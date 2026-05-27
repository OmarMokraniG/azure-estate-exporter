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

  it('places resources into bands by category (Internet/Edge, Network, Compute, Data, Observability)', async () => {
    const xml = await generateDrawioXml({
      resources: [
        mk({ type: 'Microsoft.Network/publicIPAddresses', name: 'pip' }),
        mk({ type: 'Microsoft.Compute/virtualMachines', name: 'vm' }),
        mk({ type: 'Microsoft.KeyVault/vaults', name: 'kv' }),
        mk({ type: 'Microsoft.Insights/components', name: 'ai' }),
      ],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('Internet / Edge');
    expect(xml).toContain('Compute &amp; Web');
    expect(xml).toContain('Data &amp; Security');
    expect(xml).toContain('Observability &amp; Integration');
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

  it('emits an edge cell when from + to are both in scope', async () => {
    const a = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet1',
      type: 'Microsoft.Network/virtualNetworks',
      name: 'vnet1',
    });
    const b = mk({
      id: '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/nic1',
      type: 'Microsoft.Network/networkInterfaces',
      name: 'nic1',
    });
    const xml = await generateDrawioXml({
      resources: [a, b],
      edges: [{ from: b.id, to: a.id, relation: 'in-vnet' }],
      fetcher: async () => '<svg/>',
    });
    expect(xml).toContain('edge="1"');
    expect(xml).toContain('in-vnet');
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
