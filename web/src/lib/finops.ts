import type { ArgResource } from '@/api/arm';
import type { ResourceCost } from '@/api/arm';

/**
 * Browser port of `Invoke-FinOpsAnalysis`. Pure data — no network calls.
 *
 * Produces severity-graded recommendations from the inventory + optional
 * per-resource cost data, plus headline aggregates so the Resources tab can
 * surface "where the money goes" and "what to fix".
 */

export type Severity = 'High' | 'Medium' | 'Low';

export interface FinOpsFinding {
  severity: Severity;
  type: string;
  title: string;
  resourceId?: string;
  resourceName?: string;
  resourceType?: string;
  resourceGroup?: string;
  evidence: string;
  recommendation: string;
  estimatedMonthlySavings: number;
  currency: string;
}

export interface TopSpender {
  resourceId: string;
  name: string;
  type: string;
  resourceGroup: string;
  cost: number;
  currency: string;
}

export interface ServiceMixRow {
  serviceType: string;
  resourceCount: number;
  totalCost: number;
  percentOfTotal: number;
}

export interface FinOpsHeadline {
  totalMonthlyCost: number;
  currency: string;
  potentialSavings: number;
  findingCount: number;
  findingsBySeverity: { severity: Severity; count: number }[];
}

export interface FinOpsResult {
  findings: FinOpsFinding[];
  topSpenders: TopSpender[];
  serviceMix: ServiceMixRow[];
  headline: FinOpsHeadline;
}

const SEV_ORDER: Record<Severity, number> = { High: 0, Medium: 1, Low: 2 };

function asObj(v: unknown): Record<string, unknown> {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}

export function analyzeFinOps(
  inventory: ArgResource[],
  costByResource: ResourceCost[] = [],
): FinOpsResult {
  const findings: FinOpsFinding[] = [];
  const currency = costByResource[0]?.currency ?? 'USD';

  const costMap = new Map<string, ResourceCost>();
  for (const c of costByResource) {
    if (c.resourceId) costMap.set(c.resourceId.toLowerCase(), c);
  }
  const getCost = (id?: string) => (id ? costMap.get(id.toLowerCase()) : undefined);

  const byType = new Map<string, ArgResource[]>();
  for (const r of inventory) {
    const t = r.type.toLowerCase();
    const arr = byType.get(t) ?? [];
    arr.push(r);
    byType.set(t, arr);
  }

  const add = (
    severity: Severity,
    type: string,
    title: string,
    r: ArgResource | null,
    evidence: string,
    recommendation: string,
    estimatedMonthlySavings = 0,
  ) => {
    findings.push({
      severity,
      type,
      title,
      resourceId: r?.id,
      resourceName: r?.name,
      resourceType: r?.type,
      resourceGroup: r?.resourceGroup,
      evidence,
      recommendation,
      estimatedMonthlySavings,
      currency,
    });
  };

  // 1. Unattached managed disks
  for (const d of byType.get('microsoft.compute/disks') ?? []) {
    if (!d.managedBy) {
      const c = getCost(d.id);
      const monthly = c?.cost ?? 0;
      const sev: Severity = monthly > 50 ? 'High' : monthly > 5 ? 'Medium' : 'Low';
      add(
        sev,
        'UnattachedDisk',
        `Managed disk \`${d.name}\` is not attached to any VM`,
        d,
        `managedBy is empty; sku=${d.sku?.name ?? 'n/a'}; sizeGb=${
          (asObj(d.properties).diskSizeGB as number) ?? 'n/a'
        }`,
        'Delete the disk or snapshot it and delete the source. Unattached disks bill at full rate.',
        monthly,
      );
    }
  }

  // 2. Unattached Public IPs
  for (const pip of byType.get('microsoft.network/publicipaddresses') ?? []) {
    const p = asObj(pip.properties);
    const cfg = asObj(p.ipConfiguration);
    if (!cfg.id) {
      const c = getCost(pip.id);
      const monthly = c?.cost ?? 4;
      const sev: Severity = monthly > 5 ? 'Medium' : 'Low';
      add(
        sev,
        'UnattachedPublicIp',
        `Public IP \`${pip.name}\` is not associated with any resource`,
        pip,
        `sku=${pip.sku?.name ?? 'n/a'}; allocation=${(p.publicIPAllocationMethod as string) ?? 'n/a'}`,
        'Delete the Public IP or attach it. Standard SKU PIPs bill even when idle.',
        monthly,
      );
    }
  }

  // 3. App Service plans with no hosted sites
  const plans = byType.get('microsoft.web/serverfarms') ?? [];
  const sites = byType.get('microsoft.web/sites') ?? [];
  for (const plan of plans) {
    const hosted = sites.some(
      (s) =>
        (asObj(s.properties).serverFarmId as string)?.toLowerCase() === plan.id.toLowerCase(),
    );
    if (!hosted) {
      const c = getCost(plan.id);
      const monthly = c?.cost ?? 0;
      const sev: Severity = monthly > 50 ? 'High' : monthly > 10 ? 'Medium' : 'Low';
      add(
        sev,
        'EmptyAppServicePlan',
        `App Service Plan \`${plan.name}\` has no sites hosted on it`,
        plan,
        `sku=${plan.sku?.name ?? 'n/a'}; tier=${plan.sku?.tier ?? 'n/a'}`,
        'Delete the empty plan or scale to Free/Shared. Dedicated plans bill regardless of site count.',
        monthly,
      );
    }
  }

  // 4. GRS / RAGRS storage on dev/test RGs
  for (const sa of byType.get('microsoft.storage/storageaccounts') ?? []) {
    const repl = sa.sku?.name ?? '';
    if (/GRS|RAGRS/.test(repl)) {
      const rg = sa.resourceGroup.toLowerCase();
      const env = Object.values(sa.tags ?? {})
        .join('|')
        .toLowerCase();
      const nonProd =
        /dev|test|qa|staging|sandbox/.test(rg) || /dev|test|qa|staging|sandbox/.test(env);
      if (nonProd) {
        const c = getCost(sa.id);
        const monthly = c?.cost ?? 0;
        const savings = monthly > 0 ? Math.round(monthly * 0.5 * 100) / 100 : 0;
        const sev: Severity = savings > 50 ? 'Medium' : 'Low';
        add(
          sev,
          'GrsStorageOnNonProd',
          `Storage account \`${sa.name}\` uses ${repl} replication on a non-prod RG`,
          sa,
          `sku.name=${repl}; rg=${rg}`,
          'Consider LRS for non-production data. GRS roughly doubles the storage cost vs LRS.',
          savings,
        );
      }
    }
  }

  // 5. Premium / Ultra disks under 256 GB
  for (const d of byType.get('microsoft.compute/disks') ?? []) {
    const sku = d.sku?.name ?? '';
    const size = (asObj(d.properties).diskSizeGB as number) ?? 0;
    if (/Premium|UltraSSD/.test(sku) && size > 0 && size < 256) {
      const c = getCost(d.id);
      const monthly = c?.cost ?? 0;
      const savings = monthly > 0 ? Math.round(monthly * 0.5 * 100) / 100 : 0;
      add(
        'Low',
        'PremiumDiskSmall',
        `${sku} disk \`${d.name}\` is only ${size} GB`,
        d,
        `sku=${sku}; sizeGb=${size}`,
        'Evaluate StandardSSD_LRS if the workload doesn`t need >5000 IOPS or sub-ms latency.',
        savings,
      );
    }
  }

  // 6. Oversized VMs (D-/E-/M-series 32+ vCPU)
  for (const vm of byType.get('microsoft.compute/virtualmachines') ?? []) {
    const size = (asObj(asObj(vm.properties).hardwareProfile).vmSize as string) ?? '';
    if (/^Standard_[DEM]\w*_(32|48|64|96|128)/.test(size)) {
      const c = getCost(vm.id);
      const monthly = c?.cost ?? 0;
      const sev: Severity = monthly > 500 ? 'High' : 'Medium';
      add(
        sev,
        'OversizedVm',
        `VM \`${vm.name}\` is sized \`${size}\` — review utilisation`,
        vm,
        `vmSize=${size}`,
        'Pull 7–30 day CPU + memory metrics; consider B-series or smaller D/E if averages stay under 40%.',
        Math.round(monthly * 0.3 * 100) / 100,
      );
    }
  }

  // 7. Classic App Insights
  for (const ai of byType.get('microsoft.insights/components') ?? []) {
    const p = asObj(ai.properties);
    const ws = (p.WorkspaceResourceId as string) ?? (p.workspaceResourceId as string) ?? '';
    if (!ws) {
      add(
        'Low',
        'AppInsightsClassic',
        `App Insights \`${ai.name}\` is classic (no Log Analytics workspace)`,
        ai,
        'WorkspaceResourceId is empty.',
        'Migrate to workspace-based App Insights. Microsoft is retiring classic AI; workspace mode unifies billing with Log Analytics.',
        0,
      );
    }
  }

  // Cross-cuts
  const idToInv = new Map<string, ArgResource>();
  for (const r of inventory) idToInv.set(r.id.toLowerCase(), r);

  const enriched: TopSpender[] = costByResource
    .filter((c) => c.resourceId)
    .map((c) => {
      const r = idToInv.get(c.resourceId.toLowerCase());
      return {
        resourceId: c.resourceId,
        name: r?.name ?? c.resourceId.split('/').pop() ?? c.resourceId,
        type: r?.type ?? 'n/a',
        resourceGroup: r?.resourceGroup ?? c.resourceId.split('/')[4] ?? '',
        cost: c.cost,
        currency: c.currency,
      };
    });
  const topSpenders = [...enriched].sort((a, b) => b.cost - a.cost).slice(0, 10);
  const totalCost = costByResource.reduce((sum, c) => sum + c.cost, 0);

  const byTypeCost = new Map<string, { count: number; total: number }>();
  for (const e of enriched) {
    const cur = byTypeCost.get(e.type) ?? { count: 0, total: 0 };
    cur.count += 1;
    cur.total += e.cost;
    byTypeCost.set(e.type, cur);
  }
  const serviceMix: ServiceMixRow[] = [...byTypeCost.entries()]
    .map(([serviceType, v]) => ({
      serviceType,
      resourceCount: v.count,
      totalCost: Math.round(v.total * 100) / 100,
      percentOfTotal: totalCost > 0 ? Math.round((v.total / totalCost) * 1000) / 10 : 0,
    }))
    .sort((a, b) => b.totalCost - a.totalCost);

  const potentialSavings = findings.reduce((sum, f) => sum + f.estimatedMonthlySavings, 0);
  const findingsBySeverity: { severity: Severity; count: number }[] = (['High', 'Medium', 'Low'] as Severity[])
    .map((s) => ({ severity: s, count: findings.filter((f) => f.severity === s).length }))
    .filter((x) => x.count > 0);

  return {
    findings: [...findings].sort((a, b) => {
      const d = SEV_ORDER[a.severity] - SEV_ORDER[b.severity];
      if (d !== 0) return d;
      return b.estimatedMonthlySavings - a.estimatedMonthlySavings;
    }),
    topSpenders,
    serviceMix,
    headline: {
      totalMonthlyCost: Math.round(totalCost * 100) / 100,
      currency,
      potentialSavings: Math.round(potentialSavings * 100) / 100,
      findingCount: findings.length,
      findingsBySeverity,
    },
  };
}
