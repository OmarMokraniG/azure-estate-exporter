import { useQuery } from '@tanstack/react-query';
import { listResources } from '@/api/arm';
import { useUi } from '@/state/store';
import { DiagramTab } from './tabs/DiagramTab';
import { ResourcesTab } from './tabs/ResourcesTab';
import { TerraformTab } from './tabs/TerraformTab';
import { ResourceDetail } from './ResourceDetail';

export function EstateView({ onChangeScope }: { onChangeScope: () => void }) {
  const scope = useUi((s) => s.scope);
  const tab = useUi((s) => s.activeTab);
  const setTab = useUi((s) => s.setTab);

  const resources = useQuery({
    queryKey: ['resources', scope.subscriptionId, scope.resourceGroup],
    queryFn: () => listResources(scope.subscriptionId!, scope.resourceGroup),
    enabled: Boolean(scope.subscriptionId),
  });

  return (
    <section className="flex flex-1 flex-col gap-4">
      <div className="card flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="text-sm text-slate-700">
          <span className="text-slate-500">Scope:</span>{' '}
          <span className="font-medium">{scope.subscriptionName ?? scope.subscriptionId}</span>
          {scope.resourceGroup && (
            <>
              {' '}
              <span className="text-slate-400">/</span>{' '}
              <span className="font-medium">{scope.resourceGroup}</span>
            </>
          )}
          <span className="ml-3 pill">
            {resources.isLoading
              ? 'Loading…'
              : `${resources.data?.length ?? 0} resources`}
          </span>
        </div>
        <button type="button" className="btn-ghost" onClick={onChangeScope}>
          Change scope
        </button>
      </div>

      <div className="card overflow-hidden">
        <nav className="flex border-b border-slate-200" role="tablist">
          {(
            [
              ['diagram', 'Diagram'],
              ['resources', 'Resources'],
              ['terraform', 'Terraform'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={tab === id}
              className={`px-4 py-2 text-sm font-medium ${
                tab === id
                  ? 'border-b-2 border-azure-600 text-azure-700'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
              onClick={() => setTab(id)}
            >
              {label}
            </button>
          ))}
        </nav>
        <div className="relative min-h-[60vh]">
          {resources.error && (
            <div className="p-4 text-sm text-red-600">
              {(resources.error as Error).message}
            </div>
          )}
          {tab === 'diagram' && <DiagramTab resources={resources.data ?? []} loading={resources.isLoading} />}
          {tab === 'resources' && <ResourcesTab resources={resources.data ?? []} />}
          {tab === 'terraform' && <TerraformTab />}
        </div>
      </div>

      <ResourceDetail resources={resources.data ?? []} />
    </section>
  );
}
