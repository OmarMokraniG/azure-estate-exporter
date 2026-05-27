import { describe, it, expect } from 'vitest';
import { generateDrawioXml } from './drawioGenerator';
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

describe('generateDrawioXml', () => {
  it('emits a well-formed mxfile XML envelope', async () => {
    const xml = await generateDrawioXml({
      resources: [mk({ type: 'Microsoft.Storage/storageAccounts', name: 'st1' })],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('<?xml version="1.0" encoding="UTF-8"?>');
    expect(xml).toContain('<mxfile host="azure-estate-exporter"');
    expect(xml).toContain('<diagram name="Estate"');
    expect(xml).toContain('</mxGraphModel>');
    expect(xml).toContain('</mxfile>');
  });

  it('groups resources by resource-group container', async () => {
    const xml = await generateDrawioXml({
      resources: [
        mk({ type: 'Microsoft.Storage/storageAccounts', name: 'sta', resourceGroup: 'rg-a' }),
        mk({ type: 'Microsoft.Storage/storageAccounts', name: 'stb', resourceGroup: 'rg-b' }),
      ],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('Resource group: rg-a');
    expect(xml).toContain('Resource group: rg-b');
    expect(xml).toContain('container=1');
  });

  it('emits a subscription container only when multiple subs are in scope', async () => {
    const single = await generateDrawioXml({
      resources: [mk({ name: 'st1', subscriptionId: 'subA' })],
      fetcher: async () => '<svg/>',
    });
    expect(single).not.toContain('Subscription: subA');

    const multi = await generateDrawioXml({
      resources: [
        mk({ name: 'st1', subscriptionId: 'subA' }),
        mk({ name: 'st2', subscriptionId: 'subB' }),
      ],
      fetcher: async () => '<svg/>',
    });
    expect(multi).toContain('Subscription: subA');
    expect(multi).toContain('Subscription: subB');
  });

  it('uses an embedded SVG data URI (image=data:image/svg+xml;base64,...) for known resource types', async () => {
    const xml = await generateDrawioXml({
      resources: [
        mk({ type: 'Microsoft.Compute/virtualMachines', name: 'vm1' }),
        mk({ type: 'Microsoft.KeyVault/vaults', name: 'kv1' }),
      ],
      // Stub fetcher so tests don`t need network. Returns a 1-line SVG per icon.
      fetcher: async (url: string) => `<svg data-from='${url}'/>`,
    });
    expect(xml).toContain('image=data:image/svg+xml;base64,');
    expect(xml).toContain('shape=image;html=1;');
  });

  it('places a NIC inside its subnet container (in-subnet edge)', async () => {
    const vnetId =
      '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet1';
    const subnetId = `${vnetId}/subnets/snet-foo`;
    const nic = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic1',
      type: 'Microsoft.Network/networkInterfaces',
      name: 'nic1',
      properties: { ipConfigurations: [{ name: 'ip', properties: { subnet: { id: subnetId } } }] },
    });
    const vnet = mk({
      id: vnetId,
      type: 'Microsoft.Network/virtualNetworks',
      name: 'vnet1',
      properties: { subnets: [{ id: subnetId, name: 'snet-foo', properties: {} }] },
    });
    const xml = await generateDrawioXml({
      resources: [vnet, nic],
      edges: [{ from: nic.id, to: subnetId, relation: 'in-subnet' }],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('Virtual network: vnet1');
    expect(xml).toContain('Subnet: snet-foo');
    // The NIC cell must be a child of the subnet cell.
    const snMatch = xml.match(/<mxCell id="(snet_\d+)" value="Subnet: snet-foo"/);
    expect(snMatch).toBeTruthy();
    const snId = snMatch![1];
    const nicHasSubnetParent = new RegExp(`parent="${snId}"`).test(xml);
    expect(nicHasSubnetParent).toBe(true);
  });

  it('synthesises subnets from VNet properties.subnets when no standalone subnet rows exist', async () => {
    const vnetId =
      '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet1';
    const vnet = mk({
      id: vnetId,
      type: 'Microsoft.Network/virtualNetworks',
      name: 'vnet1',
      properties: {
        subnets: [
          { id: `${vnetId}/subnets/sub-a`, name: 'sub-a', properties: {} },
          { id: `${vnetId}/subnets/sub-b`, name: 'sub-b', properties: {} },
        ],
      },
    });
    const xml = await generateDrawioXml({
      resources: [vnet],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('Subnet: sub-a');
    expect(xml).toContain('Subnet: sub-b');
  });

  it('places PaaS resources without a network home into the Platform services band', async () => {
    const xml = await generateDrawioXml({
      resources: [
        mk({ type: 'Microsoft.Storage/storageAccounts', name: 'stcontoso' }),
        mk({ type: 'Microsoft.KeyVault/vaults', name: 'kv1' }),
      ],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('Platform services');
    expect(xml).toContain('stcontoso');
    expect(xml).toContain('kv1');
  });

  it('falls back to the default icon when a fetch fails', async () => {
    const xml = await generateDrawioXml({
      resources: [mk({ type: 'Microsoft.UnknownProvider/widgets', name: 'wid' })],
      fetcher: async (url: string) => {
        if (url.endsWith('_default.svg')) return '<svg id="default"/>';
        throw new Error('not found');
      },
    });
    expect(xml).toContain('image=data:image/svg+xml;base64,');
  });

  it('emits an edge cell when from + to are both in scope (non-topology relations only)', async () => {
    const a = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sta',
      type: 'Microsoft.Storage/storageAccounts',
      name: 'sta',
    });
    const b = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Web/sites/app1',
      type: 'Microsoft.Web/sites',
      name: 'app1',
    });
    const xml = await generateDrawioXml({
      resources: [a, b],
      edges: [{ from: b.id, to: a.id, relation: 'uses-storage' }],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('edge="1"');
    expect(xml).toContain('uses-storage');
  });

  it('hides in-subnet / in-vnet edges because the container nesting expresses them', async () => {
    const vnetId =
      '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet1';
    const subnetId = `${vnetId}/subnets/sub`;
    const nic = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic',
      type: 'Microsoft.Network/networkInterfaces',
      name: 'nic',
    });
    const vnet = mk({
      id: vnetId,
      type: 'Microsoft.Network/virtualNetworks',
      name: 'vnet1',
      properties: { subnets: [{ id: subnetId, name: 'sub', properties: {} }] },
    });
    const xml = await generateDrawioXml({
      resources: [vnet, nic],
      edges: [{ from: nic.id, to: subnetId, relation: 'in-subnet' }],
      fetcher: async () => '<svg/>',
    });
    expect(xml).not.toMatch(/edge="1"[^>]*?value="in-subnet"/);
  });

  it('skips edges whose endpoints are out of scope', async () => {
    const a = mk({ name: 'a', id: '/in-scope' });
    const xml = await generateDrawioXml({
      resources: [a],
      edges: [{ from: '/in-scope', to: '/out-of-scope', relation: 'references' }],
      fetcher: async () => '<svg/>',
    });
    expect(xml).not.toContain('edge="1"');
  });

  it('escapes XML-unsafe characters in labels', async () => {
    const r = mk({ type: 'Microsoft.Storage/storageAccounts', name: 'a&b<c>"d' });
    const xml = await generateDrawioXml({ resources: [r], fetcher: async () => '<svg/>' });
    expect(xml).toContain('a&amp;b&lt;c&gt;&quot;d');
  });
});
