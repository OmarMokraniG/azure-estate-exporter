import { describe, it, expect } from 'vitest';
import { analyzeFinOps } from './finops';
import type { ArgResource } from '@/api/arm';

function mk(over: Partial<ArgResource>): ArgResource {
  return {
    id: '/subscriptions/s/resourceGroups/rg1/providers/X',
    name: 'r',
    type: 'X',
    kind: null,
    location: 'westeurope',
    resourceGroup: 'rg1',
    subscriptionId: 's',
    sku: null,
    identity: null,
    tags: null,
    properties: {},
    managedBy: null,
    ...over,
  };
}

describe('analyzeFinOps', () => {
  it('flags an unattached disk as a Low (no cost data) finding', () => {
    const r = mk({
      type: 'Microsoft.Compute/disks',
      name: 'disk-orphan',
      sku: { name: 'Premium_LRS' },
      properties: { diskSizeGB: 128 },
      managedBy: null,
    });
    const f = analyzeFinOps([r]);
    const finding = f.findings.find((x) => x.type === 'UnattachedDisk');
    expect(finding).toBeDefined();
    expect(finding!.severity).toBe('Low');
  });

  it('flags an unattached disk as High when monthly cost > $50', () => {
    const r = mk({
      type: 'Microsoft.Compute/disks',
      name: 'disk-pricey',
      sku: { name: 'Premium_LRS' },
      properties: { diskSizeGB: 4096 },
      managedBy: null,
    });
    const f = analyzeFinOps([r], [{ resourceId: r.id, cost: 200, currency: 'USD' }]);
    const finding = f.findings.find((x) => x.type === 'UnattachedDisk')!;
    expect(finding.severity).toBe('High');
    expect(finding.estimatedMonthlySavings).toBe(200);
  });

  it('does NOT flag a disk that has a managedBy reference', () => {
    const r = mk({
      type: 'Microsoft.Compute/disks',
      managedBy:
        '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm1',
    });
    expect(analyzeFinOps([r]).findings.filter((x) => x.type === 'UnattachedDisk')).toHaveLength(0);
  });

  it('flags GRS storage on a dev RG', () => {
    const r = mk({
      type: 'Microsoft.Storage/storageAccounts',
      name: 'stdev',
      resourceGroup: 'rg-dev-foo',
      sku: { name: 'Standard_GRS' },
    });
    const f = analyzeFinOps([r], [{ resourceId: r.id, cost: 100, currency: 'USD' }]);
    const finding = f.findings.find((x) => x.type === 'GrsStorageOnNonProd')!;
    expect(finding).toBeDefined();
    expect(finding.estimatedMonthlySavings).toBe(50);
  });

  it('does NOT flag GRS storage on a prod-named RG', () => {
    const r = mk({
      type: 'Microsoft.Storage/storageAccounts',
      resourceGroup: 'rg-prod-foo',
      sku: { name: 'Standard_GRS' },
    });
    expect(
      analyzeFinOps([r]).findings.filter((x) => x.type === 'GrsStorageOnNonProd'),
    ).toHaveLength(0);
  });

  it('flags an empty App Service plan', () => {
    const plan = mk({
      id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Web/serverFarms/plan1',
      type: 'Microsoft.Web/serverFarms',
      name: 'plan1',
      sku: { name: 'P1v3', tier: 'PremiumV3' },
    });
    expect(analyzeFinOps([plan]).findings.some((f) => f.type === 'EmptyAppServicePlan')).toBe(true);
  });

  it('aggregates top spenders and service mix', () => {
    const r1 = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1',
      type: 'Microsoft.Compute/virtualMachines',
      name: 'vm1',
    });
    const r2 = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st1',
      type: 'Microsoft.Storage/storageAccounts',
      name: 'st1',
      sku: { name: 'Standard_LRS' },
    });
    const f = analyzeFinOps(
      [r1, r2],
      [
        { resourceId: r1.id, cost: 100, currency: 'USD' },
        { resourceId: r2.id, cost: 25, currency: 'USD' },
      ],
    );
    expect(f.topSpenders[0].name).toBe('vm1');
    expect(f.serviceMix[0].serviceType).toBe('Microsoft.Compute/virtualMachines');
    expect(f.headline.totalMonthlyCost).toBe(125);
  });
});
