import { useMemo } from 'react';
import type { GeneratedFile } from '@/lib/terraformGenerator';

/**
 * A FileTree node — either a folder containing children or a leaf pointing
 * at a `GeneratedFile`.
 */
interface TreeNode {
  name: string;
  path: string;
  isDir: boolean;
  children: TreeNode[];
  file?: GeneratedFile;
}

function buildTree(files: GeneratedFile[]): TreeNode {
  const root: TreeNode = { name: '/', path: '', isDir: true, children: [] };
  for (const f of files) {
    const parts = f.path.split('/');
    let cur = root;
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const isLeaf = i === parts.length - 1;
      let child = cur.children.find((c) => c.name === part);
      if (!child) {
        child = {
          name: part,
          path: parts.slice(0, i + 1).join('/'),
          isDir: !isLeaf,
          children: [],
        };
        cur.children.push(child);
      }
      if (isLeaf) child.file = f;
      cur = child;
    }
  }
  sortRecursive(root);
  return root;
}

function sortRecursive(n: TreeNode) {
  n.children.sort((a, b) => {
    if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  for (const c of n.children) sortRecursive(c);
}

function iconFor(file?: GeneratedFile): string {
  if (!file) return '📁';
  switch (file.language) {
    case 'hcl':
      return '🌍';
    case 'markdown':
      return '📝';
    case 'json':
      return '📄';
    default:
      return '📄';
  }
}

function Node({
  node,
  depth,
  selectedPath,
  onSelect,
}: {
  node: TreeNode;
  depth: number;
  selectedPath: string | null;
  onSelect: (path: string) => void;
}) {
  const isSelected = node.file && node.path === selectedPath;
  return (
    <>
      <div
        className={`flex cursor-pointer items-center gap-1 truncate px-2 py-0.5 text-xs ${
          isSelected ? 'bg-azure-100 font-semibold text-azure-800' : 'hover:bg-slate-50'
        }`}
        style={{ paddingLeft: 8 + depth * 14 }}
        onClick={() => node.file && onSelect(node.path)}
        role={node.file ? 'button' : 'presentation'}
        tabIndex={node.file ? 0 : -1}
      >
        <span className="shrink-0">{node.isDir ? '📁' : iconFor(node.file)}</span>
        <span className="truncate">{node.name || 'repo'}</span>
      </div>
      {node.children.map((c) => (
        <Node key={c.path} node={c} depth={depth + 1} selectedPath={selectedPath} onSelect={onSelect} />
      ))}
    </>
  );
}

export function FileTree({
  files,
  selectedPath,
  onSelect,
}: {
  files: GeneratedFile[];
  selectedPath: string | null;
  onSelect: (path: string) => void;
}) {
  const root = useMemo(() => buildTree(files), [files]);

  return (
    <div className="h-full overflow-auto rounded border border-slate-200 bg-white py-2">
      {root.children.map((c) => (
        <Node key={c.path} node={c} depth={0} selectedPath={selectedPath} onSelect={onSelect} />
      ))}
    </div>
  );
}
