import dagre from 'dagre';
import type { Node, Edge as RfEdge } from '@xyflow/react';

const NODE_W = 200;
const NODE_H = 70;

/**
 * Apply a left-to-right dagre layout to React Flow nodes/edges.
 * Returns the same nodes/edges with `position` mutated.
 */
export function layoutGraph(nodes: Node[], edges: RfEdge[]): { nodes: Node[]; edges: RfEdge[] } {
  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: 'LR', nodesep: 40, ranksep: 80, marginx: 20, marginy: 20 });
  g.setDefaultEdgeLabel(() => ({}));

  nodes.forEach((n) => g.setNode(n.id, { width: NODE_W, height: NODE_H }));
  edges.forEach((e) => g.setEdge(e.source, e.target));

  dagre.layout(g);

  return {
    nodes: nodes.map((n) => {
      const pos = g.node(n.id);
      return { ...n, position: { x: pos.x - NODE_W / 2, y: pos.y - NODE_H / 2 } };
    }),
    edges,
  };
}
