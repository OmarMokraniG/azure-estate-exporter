import { useMemo, useState } from 'react';
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
import { downloadDrawio, generateDrawioXml } from '@/lib/drawioGenerator';
import { useUi } from '@/state/store';
import { ResourceNode } from '../icons/ResourceNode';

const nodeTypes = { resource: ResourceNode };

export function DiagramTab({ resources, loading }: { resources: ArgResource[]; loading: boolean }) {
  const selectResource = useUi((s) => s.selectResource);
  const scope = useUi((s) => s.scope);
  const [exporting, setExporting] = useState(false);

  const inferred = useMemo(() => (resources.length ? inferEdges(resources) : []), [resources]);

  const { nodes, edges } = useMemo(() => {
    if (!resources.length) return { nodes: [] as Node[], edges: [] as RfEdge[] };
    const rfNodes: Node[] = resources.map((r) => ({
      id: r.id,
      type: 'resource',
      data: { resource: r },
      position: { x: 0, y: 0 },
    }));
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
  }, [resources, inferred]);

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

  const exportDrawio = async () => {
    setExporting(true);
    try {
      const xml = await generateDrawioXml({
        resources,
        edges: inferred.map((e) => ({ from: e.from, to: e.to, relation: e.relation })),
      });
      const slug =
        (scope.resourceGroup ?? scope.subscriptionName ?? scope.subscriptionId ?? 'estate')
          .replace(/[^a-z0-9-_]+/gi, '-');
      downloadDrawio(xml, `${slug}.drawio`);
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="flex h-[70vh] w-full flex-col">
      <div className="flex items-center justify-end gap-2 border-b border-slate-200 bg-white px-3 py-2">
        <span className="mr-auto text-xs text-slate-500">
          {resources.length} resources · {inferred.length} edges · auto-layout via dagre
        </span>
        <button
          type="button"
          className="btn-ghost !py-1 !text-xs"
          onClick={exportDrawio}
          disabled={exporting}
          title="Download an Azure-styled .drawio file. Opens in app.diagrams.net or VS Code."
        >
          {exporting ? 'Generating…' : 'Export as drawio'}
        </button>
        <a
          className="btn-ghost !py-1 !text-xs"
          href="https://app.diagrams.net/?splash=0"
          target="_blank"
          rel="noreferrer"
          title="After downloading the .drawio file, drop it into the diagrams.net canvas to edit."
        >
          Open diagrams.net ↗
        </a>
      </div>
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
