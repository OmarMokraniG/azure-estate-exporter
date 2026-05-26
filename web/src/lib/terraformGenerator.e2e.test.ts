import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { generateTerraformRepo, isFullySupported } from './terraformGenerator';
import type { ArgResource } from '@/api/arm';

/**
 * End-to-end smoke against a real `inventory.json` produced by the
 * PowerShell module. Skipped on CI / contributor machines that don't have a
 * checked-in real inventory file — keeps the regular `npm test` reproducible.
 */
const realInventory = resolve(__dirname, '../../../out/2026-05-26T16-58-45/inventory.json');
const hasFixture = existsSync(realInventory);

describe.skipIf(!hasFixture)('generator e2e against real ARG inventory', () => {
  let resources: ArgResource[] = [];

  beforeAll(() => {
    // Read inside beforeAll so a missing file does not blow up import time.
    resources = JSON.parse(readFileSync(realInventory, 'utf8')) as ArgResource[];
  });

  it('produces the expected file tree with no exceptions', () => {
    const files = generateTerraformRepo({
      subscriptionId: 'e8941ee9-a543-4f66-9d42-5c28612e9fe0',
      subscriptionName: 'ME-MngEnvMCAP274168-omarmok-2',
      resourceGroup: 'rg-mhsql-dev-7o5cp',
      resources,
    });
    expect(files.length).toBeGreaterThan(5);
    expect(files.some((f) => f.path === 'README.md')).toBe(true);
    expect(files.some((f) => f.path.endsWith('main.tf'))).toBe(true);
  });

  it('renders all resources as either HCL or honest stub (never throws)', () => {
    const files = generateTerraformRepo({
      subscriptionId: 'e8941ee9-a543-4f66-9d42-5c28612e9fe0',
      resources,
    });
    const mainTf = files.find((f) => f.path === 'infra/rg-mhsql-dev-7o5cp/main.tf')!.content;
    for (const r of resources) {
      expect(
        mainTf.includes(r.name) || mainTf.includes(r.id),
        `resource ${r.name} (${r.type}) is absent from main.tf`,
      ).toBe(true);
    }
    const supported = resources.filter((r) => isFullySupported(r.type)).length;
    console.log(
      `[e2e] coverage: ${supported}/${resources.length} (${Math.round(
        (100 * supported) / resources.length,
      )}%) resources rendered as native HCL.`,
    );
  });

  it('every generated .tf file has balanced braces', () => {
    const files = generateTerraformRepo({
      subscriptionId: 'e8941ee9-a543-4f66-9d42-5c28612e9fe0',
      resources,
    });
    for (const f of files.filter((x) => x.path.endsWith('.tf'))) {
      const opens = (f.content.match(/\{/g) ?? []).length;
      const closes = (f.content.match(/\}/g) ?? []).length;
      expect(opens, `file ${f.path}`).toBe(closes);
    }
  });
});
