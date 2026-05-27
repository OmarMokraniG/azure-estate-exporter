import { useMemo } from 'react';
import { ChevronRight, FileCode2, FileText, FileJson, Folder } from 'lucide-react';
import clsx from 'clsx';
import type { GeneratedFile } from '@/lib/terraformGenerator';

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

function FileIcon({ file }: { file?: GeneratedFile }) {
  if (!file) return <Folder className="h-3.5 w-3.5 text-amber-500" />;
  switch (file.language) {
    case 'hcl':
      return <FileCode2 className="h-3.5 w-3.5 text-violet-500" />;
    case 'markdown':
      return <FileText className="h-3.5 w-3.5 text-blue-500" />;
    case 'json':
      return <FileJson className="h-3.5 w-3.5 text-emerald-500" />;
    default:
      return <FileText className="h-3.5 w-3.5 text-subtle" />;
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
        className={clsx(
          'flex cursor-pointer select-none items-center gap-1.5 truncate rounded-md px-2 py-1 text-xs transition-colors',
          isSelected
            ? 'bg-accent-soft text-accent font-medium'
            : 'text-muted hover:bg-surface-2 hover:text-fg',
        )}
        style={{ paddingLeft: 8 + depth * 14 }}
        onClick={() => node.file && onSelect(node.path)}
        role={node.file ? 'button' : 'presentation'}
        tabIndex={node.file ? 0 : -1}
      >
        {node.isDir ? (
          <ChevronRight className="h-3 w-3 shrink-0 text-subtle" />
        ) : (
          <span className="w-3 shrink-0" />
        )}
        <FileIcon file={node.file} />
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
    <div className="h-full overflow-auto rounded-lg border border-default bg-surface py-2">
      {root.children.map((c) => (
        <Node key={c.path} node={c} depth={0} selectedPath={selectedPath} onSelect={onSelect} />
      ))}
    </div>
  );
}
