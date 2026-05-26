import { describe, it, expect } from 'vitest';
import {
  generateTerraformRepo,
  isFullySupported,
  sanitizeName,
  type GeneratedFile,
} from './terraformGenerator';
import type { ArgResource } from '@/api/arm';

function mkResource(over: Partial<ArgResource>): ArgResource {
  return {
    id: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg1/providers/X',
    name: 'r',
    type: 'X',
    kind: null,
    location: 'westeurope',
    resourceGroup: 'rg1',
    subscriptionId: '00000000-0000-0000-0000-000000000000',
    sku: null,
    identity: null,
    tags: null,
    properties: {},
    managedBy: null,
    ...over,
  };
}

function fileMap(files: GeneratedFile[]): Map<string, GeneratedFile> {
  return new Map(files.map((f) => [f.path, f]));
}

describe('sanitizeName', () => {
  it('lowercases and collapses runs of invalid chars to a single _', () => {
    expect(sanitizeName('My-Storage Account #1')).toBe('my-storage_account_1');
  });
  it('prefixes digits-only names', () => {
    expect(sanitizeName('123')).toBe('r_123');
  });
});

describe('generateTerraformRepo — file structure', () => {
  it('emits the root scaffolding files', () => {
    const r = mkResource({
      id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stx',
      name: 'stx',
      type: 'Microsoft.Storage/storageAccounts',
      sku: { name: 'Standard_LRS' },
    });
    const files = generateTerraformRepo({ subscriptionId: 's', resources: [r] });
    const m = fileMap(files);
    expect(m.has('README.md')).toBe(true);
    expect(m.has('.gitignore')).toBe(true);
    expect(m.has('backend.tf.example')).toBe(true);
    expect(m.has('infra/rg1/main.tf')).toBe(true);
    expect(m.has('infra/rg1/provider.tf')).toBe(true);
    expect(m.has('infra/rg1/variables.tf')).toBe(true);
    expect(m.has('infra/rg1/terraform.tfvars.example')).toBe(true);
    expect(m.has('infra/rg1/outputs.tf')).toBe(true);
    expect(m.has('infra/rg1/README.md')).toBe(true);
  });

  it('groups resources into one infra/<rg>/ folder per resource group', () => {
    const files = generateTerraformRepo({
      subscriptionId: 's',
      resources: [
        mkResource({ resourceGroup: 'rg-a', type: 'Microsoft.Storage/storageAccounts', name: 'sta' }),
        mkResource({ resourceGroup: 'rg-b', type: 'Microsoft.Storage/storageAccounts', name: 'stb' }),
      ],
    });
    const m = fileMap(files);
    expect(m.has('infra/rg-a/main.tf')).toBe(true);
    expect(m.has('infra/rg-b/main.tf')).toBe(true);
  });
});

describe('generateTerraformRepo — HCL content', () => {
  it('renders a storage account block with sku split + flags', () => {
    const r = mkResource({
      id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stcontoso',
      name: 'stcontoso',
      type: 'Microsoft.Storage/storageAccounts',
      sku: { name: 'Standard_ZRS' },
      kind: 'StorageV2',
      properties: {
        minimumTlsVersion: 'TLS1_2',
        allowBlobPublicAccess: false,
        publicNetworkAccess: 'Disabled',
      },
    });
    const files = generateTerraformRepo({ subscriptionId: 's', resources: [r] });
    const main = files.find((f) => f.path === 'infra/rg1/main.tf')!.content;
    expect(main).toContain('resource "azurerm_storage_account" "stcontoso"');
    expect(main).toContain('account_tier             = "Standard"');
    expect(main).toContain('account_replication_type = "ZRS"');
    expect(main).toContain('public_network_access_enabled   = false');
    expect(main).toContain('allow_nested_items_to_be_public = false');
  });

  it('emits a synthetic RG block referenced by name from child resources', () => {
    const r = mkResource({
      id: '/subscriptions/s/resourceGroups/rg-named/providers/Microsoft.Storage/storageAccounts/stx',
      name: 'stx',
      type: 'Microsoft.Storage/storageAccounts',
      resourceGroup: 'rg-named',
      sku: { name: 'Standard_LRS' },
    });
    const files = generateTerraformRepo({ subscriptionId: 's', resources: [r] });
    const main = files.find((f) => f.path === 'infra/rg-named/main.tf')!.content;
    expect(main).toContain('resource "azurerm_resource_group" "rg-named"');
    expect(main).toContain('resource_group_name      = azurerm_resource_group.rg-named.name');
  });

  it('emits a commented stub for unsupported types instead of throwing', () => {
    const r = mkResource({
      type: 'Microsoft.UnsupportedThing/widgets',
      name: 'wid1',
      id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.UnsupportedThing/widgets/wid1',
    });
    const files = generateTerraformRepo({ subscriptionId: 's', resources: [r] });
    const main = files.find((f) => f.path === 'infra/rg1/main.tf')!.content;
    expect(main).toContain('# ─ Unsupported type: Microsoft.UnsupportedThing/widgets');
    expect(main).toContain('Run the PowerShell module locally');
  });

  it('outputs.tf has one output per supported resource only', () => {
    const files = generateTerraformRepo({
      subscriptionId: 's',
      resources: [
        mkResource({
          type: 'Microsoft.Storage/storageAccounts',
          name: 'stx',
          id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/stx',
          sku: { name: 'Standard_LRS' },
        }),
        mkResource({
          type: 'Microsoft.UnsupportedThing/widgets',
          name: 'wid1',
          id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.UnsupportedThing/widgets/wid1',
        }),
      ],
    });
    const outputs = files.find((f) => f.path === 'infra/rg1/outputs.tf')!.content;
    expect(outputs).toContain('output "stx_id"');
    expect(outputs).not.toContain('wid1');
  });

  it('resolves a subnet id reference to an in-scope tf address', () => {
    const subnetId =
      '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Network/virtualNetworks/vnet1/subnets/sub1';
    const resources: ArgResource[] = [
      mkResource({
        type: 'Microsoft.Network/virtualNetworks',
        name: 'vnet1',
        id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Network/virtualNetworks/vnet1',
        properties: { addressSpace: { addressPrefixes: ['10.0.0.0/16'] } },
      }),
      mkResource({
        type: 'Microsoft.Network/virtualNetworks/subnets',
        name: 'vnet1/sub1',
        id: subnetId,
        properties: { addressPrefix: '10.0.1.0/24' },
      }),
      mkResource({
        type: 'Microsoft.Network/networkInterfaces',
        name: 'nic1',
        id: '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Network/networkInterfaces/nic1',
        properties: {
          ipConfigurations: [
            {
              name: 'ipconfig1',
              properties: {
                subnet: { id: subnetId },
                privateIPAllocationMethod: 'Dynamic',
              },
            },
          ],
        },
      }),
    ];
    const files = generateTerraformRepo({ subscriptionId: 's', resources });
    const main = files.find((f) => f.path === 'infra/rg1/main.tf')!.content;
    expect(main).toContain('subnet_id                     = azurerm_subnet.sub1.id');
  });
});

describe('isFullySupported', () => {
  it('returns true for known types and false otherwise', () => {
    expect(isFullySupported('Microsoft.Storage/storageAccounts')).toBe(true);
    expect(isFullySupported('Microsoft.UnsupportedThing/widgets')).toBe(false);
  });
});
