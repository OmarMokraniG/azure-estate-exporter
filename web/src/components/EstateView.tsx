import { useQuery } from '@tanstack/react-query';
import { listResources } from '@/api/arm';
import { useUi } from '@/state/store';
import { DiagramTab } from './tabs/DiagramTab';
import { ResourcesTab } from './tabs/ResourcesTab';
import { TerraformTab } from './tabs/TerraformTab';
import { ResourceDetail } from './ResourceDetail';
import { ArrowLeft, FileCode2, LayoutDashboard, Workflow } from 'lucide-react';
import clsx from 'clsx';

const NAV: { id: 'diagram' | 'resources' | 'terraform'; label: string; icon: typeof Workflow }[] = [
  { id: 'diagram', label: 'Diagram', icon: Workflow },
  { id: 'resources', label: 'Resources', icon: LayoutDashboard },
  { id: 'terraform', label: 'Terraform', icon: FileCode2 },
];

export function EstateView() {
  const scope = useUi((s) => s.scope);
  const clearScope = useUi((s) => s.clearScope);
  const tab = useUi((s) => s.activeTab);
  const setTab = useUi((s) => s.setTab);

  const resources = useQuery({
    queryKey: ['resources', scope.subscriptionId, scope.resourceGroup],
    queryFn: () => listResources(scope.subscriptionId!, scope.resourceGroup),
    enabled: Boolean(scope.subscriptionId),
  });

  return (
    <section className="flex flex-1 animate-fade-in flex-col gap-4">
      {/* Sub-header chip with scope summary + change-scope */}
      <div className="surface flex flex-wrap items-center justify-between gap-3 px-4 py-3">
        <button
          type="button"
          className="btn-ghost -ml-2 !px-2"
          onClick={() => clearScope()}
          title="Back to scope picker"
        >
          <ArrowLeft className="h-4 w-4" />
          <span>Change scope</span>
        </button>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="pill">
            Sub: <span className="font-medium text-fg">{scope.subscriptionName ?? scope.subscriptionId}</span>
          </span>
          {scope.resourceGroup && (
            <span className="pill">
              RG: <span className="font-mono font-medium text-fg">{scope.resourceGroup}</span>
            </span>
          )}
          <span className="pill-accent">
            {resources.isLoading ? 'Loading…' : `${resources.data?.length ?? 0} resources`}
          </span>
        </div>
      </div>

      {/* Sidebar nav + main content */}
      <div className="grid flex-1 grid-cols-[220px_1fr] gap-4">
        <nav className="surface flex flex-col gap-1 p-2" aria-label="Sections">
          {NAV.map((item) => {
            const Icon = item.icon;
            const active = tab === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setTab(item.id)}
                className={clsx(
                  'flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                  active
                    ? 'bg-accent-soft text-accent'
                    : 'text-muted hover:bg-surface-2 hover:text-fg',
                )}
                aria-current={active ? 'page' : undefined}
              >
                <Icon className="h-4 w-4" />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>

        <div className="surface relative overflow-hidden">
          {resources.error && (
            <div className="p-4 text-sm text-red-500">{(resources.error as Error).message}</div>
          )}
          {tab === 'diagram' && (
            <DiagramTab resources={resources.data ?? []} loading={resources.isLoading} />
          )}
          {tab === 'resources' && <ResourcesTab resources={resources.data ?? []} />}
          {tab === 'terraform' && <TerraformTab resources={resources.data ?? []} />}
        </div>
      </div>

      <ResourceDetail resources={resources.data ?? []} />
    </section>
  );
}
