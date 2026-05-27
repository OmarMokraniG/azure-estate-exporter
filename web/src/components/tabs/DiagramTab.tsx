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
import { Download, ExternalLink } from 'lucide-react';
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
      labelStyle: { fontSize: 10, fill: '#94a3b8' },
      labelBgPadding: [4, 2],
      labelBgStyle: { fill: 'transparent', stroke: 'none' },
      style: { stroke: '#94a3b8', strokeWidth: 1.4 },
      markerEnd: { type: MarkerType.ArrowClosed, color: '#94a3b8' },
    }));
    return layoutGraph(rfNodes, rfEdges);
  }, [resources, inferred]);

  if (loading) {
    return (
      <div className="grid h-[70vh] place-items-center text-sm text-subtle">
        <div className="flex flex-col items-center gap-3">
          <div className="skeleton h-32 w-32 rounded-full" />
          <span>Loading resources…</span>
        </div>
      </div>
    );
  }
  if (!resources.length) {
    return (
      <div className="grid h-[70vh] place-items-center text-sm text-subtle">
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
      const slug = (
        scope.resourceGroup ??
        scope.subscriptionName ??
        scope.subscriptionId ??
        'estate'
      ).replace(/[^a-z0-9-_]+/gi, '-');
      downloadDrawio(xml, `${slug}.drawio`);
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="relative h-[70vh] w-full">
      {/* Floating toolbar */}
      <div className="absolute left-4 top-4 z-10 flex items-center gap-2 rounded-xl border border-default bg-surface/90 px-3 py-1.5 shadow-soft backdrop-blur">
        <span className="text-xs text-subtle">
          <strong className="text-fg">{resources.length}</strong> resources ·{' '}
          <strong className="text-fg">{inferred.length}</strong> edges
        </span>
      </div>
      <div className="absolute right-4 top-4 z-10 flex items-center gap-2 rounded-xl border border-default bg-surface/90 p-1 shadow-soft backdrop-blur">
        <button
          type="button"
          className="btn-ghost !py-1 !text-xs"
          onClick={exportDrawio}
          disabled={exporting}
          title="Download an Azure-styled .drawio file. Opens in app.diagrams.net or VS Code."
        >
          <Download className="h-3.5 w-3.5" />
          {exporting ? 'Generating…' : 'Export drawio'}
        </button>
        <a
          className="btn-ghost !py-1 !text-xs"
          href="https://app.diagrams.net/?splash=0"
          target="_blank"
          rel="noreferrer"
          title="Open diagrams.net to drop the downloaded file"
        >
          diagrams.net <ExternalLink className="h-3 w-3" />
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
        <Background gap={20} color="rgb(148 163 184 / 0.18)" />
        <Controls showInteractive={false} />
        <MiniMap pannable zoomable nodeStrokeWidth={3} maskColor="rgb(0 0 0 / 0.45)" />
      </ReactFlow>
    </div>
  );
}
