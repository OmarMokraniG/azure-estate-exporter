import { Handle, Position, type NodeProps } from '@xyflow/react';
import type { ArgResource } from '@/api/arm';
import { metaForType, colorForCategory } from '@/lib/resourceTypes';

export interface ResourceNodeData {
  resource: ArgResource;
}

export function ResourceNode({ data }: NodeProps) {
  const { resource } = data as unknown as ResourceNodeData;
  const meta = metaForType(resource.type);
  const color = colorForCategory(meta.category);
  const iconUrl = `/icons/${meta.icon}.svg`;

  return (
    <div
      className="flex w-[200px] items-center gap-2 rounded-lg border border-default bg-surface px-2 py-1.5 shadow-soft"
      style={{ borderLeft: `4px solid ${color}` }}
      title={`${resource.type}\n${resource.id}`}
    >
      <Handle type="target" position={Position.Left} className="!h-2 !w-2 !bg-slate-400" />
      <img
        src={iconUrl}
        alt=""
        aria-hidden
        width={28}
        height={28}
        onError={(e) => {
          (e.currentTarget as HTMLImageElement).src = '/icons/_default.svg';
        }}
      />
      <div className="min-w-0 flex-1">
        <div className="truncate text-xs font-semibold leading-tight text-fg">{resource.name}</div>
        <div className="truncate text-[10px] uppercase tracking-wider text-subtle">
          {meta.label}
        </div>
      </div>
      <Handle type="source" position={Position.Right} className="!h-2 !w-2 !bg-slate-400" />
    </div>
  );
}
