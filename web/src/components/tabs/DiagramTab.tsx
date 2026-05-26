import { useMemo } from 'react';
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  type Node,
  type Edge as RfEdge,
  MarkerType,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import type { ArgResource } from '@/api/arm';
import { inferEdges } from '@/lib/inferEdges';
import { layoutGraph } from '@/lib/layout';
import { useUi } from '@/state/store';
import { ResourceNode } from '../icons/ResourceNode';

const nodeTypes = { resource: ResourceNode };

export function DiagramTab({ resources, loading }: { resources: ArgResource[]; loading: boolean }) {
  const selectResource = useUi((s) => s.selectResource);

  const { nodes, edges } = useMemo(() => {
    if (!resources.length) return { nodes: [] as Node[], edges: [] as RfEdge[] };
    const rfNodes: Node[] = resources.map((r) => ({
      id: r.id,
      type: 'resource',
      data: { resource: r },
      position: { x: 0, y: 0 },
    }));
    const inferred = inferEdges(resources);
    const rfEdges: RfEdge[] = inferred.map((e, i) => ({
      id: `e${i}`,
      source: e.from,
      target: e.to,
      label: e.relation,
      labelStyle: { fontSize: 10, fill: '#475569' },
      labelBgPadding: [4, 2],
      labelBgStyle: { fill: '#f8fafc', stroke: '#e2e8f0' },
      style: { stroke: '#94a3b8', strokeWidth: 1.5 },
      markerEnd: { type: MarkerType.ArrowClosed, color: '#94a3b8' },
    }));
    return layoutGraph(rfNodes, rfEdges);
  }, [resources]);

  if (loading) {
    return <div className="grid h-[60vh] place-items-center text-slate-500">Loading resources…</div>;
  }
  if (!resources.length) {
    return (
      <div className="grid h-[60vh] place-items-center text-slate-500">
        No resources in this scope.
      </div>
    );
  }

  return (
    <div className="h-[70vh] w-full">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        fitView
        proOptions={{ hideAttribution: true }}
        onNodeClick={(_e, n) => selectResource(n.id)}
      >
        <Background gap={20} color="#e2e8f0" />
        <Controls showInteractive={false} />
        <MiniMap pannable zoomable nodeStrokeWidth={3} className="!bg-white" />
      </ReactFlow>
    </div>
  );
}
