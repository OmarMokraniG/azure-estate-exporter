#!/usr/bin/env node
// Optional helper: download Microsoft's official Azure architecture icons and
// drop them into `web/public/icons/azure-official/` so the web app's
// `ResourceNode` component can pick them up via a small CSS override.
//
// Microsoft publishes the icon archive at the URL below as a zipped Visio
// stencil + SVG bundle. The license terms (printed when you run this script)
// allow you to USE the icons in architecture diagrams; redistribution rules
// vary. By design we DO NOT bundle the icons in this repo — you opt in by
// running this script locally.
//
// Usage:
//   cd web
//   npm run fetch-icons

import { mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '..', 'public', 'icons', 'azure-official');

// Microsoft updates this URL over time; check
// https://learn.microsoft.com/en-us/azure/architecture/icons/
// for the current download. We do NOT hard-code a specific file because the
// version (and license text) can change.
const LANDING = 'https://learn.microsoft.com/en-us/azure/architecture/icons/';

async function main() {
  console.log('--------------------------------------------------------------');
  console.log('Azure architecture icons — manual download required');
  console.log('--------------------------------------------------------------');
  console.log(`Open ${LANDING} and:`);
  console.log('  1. Accept the Microsoft license terms.');
  console.log('  2. Download the latest Azure_Public_Service_Icons_*.zip.');
  console.log(`  3. Extract its SVG/ folder into:  ${OUT_DIR}`);
  console.log('');
  console.log('Why no auto-download? The license URL and asset hash change');
  console.log('regularly. Forcing a manual step keeps you in the loop on the');
  console.log('terms you accept.');
  console.log('');
  console.log('After extracting, restart `npm run dev` and the ResourceNode');
  console.log('component will prefer files in azure-official/ when present.');

  await mkdir(OUT_DIR, { recursive: true });
  await writeFile(
    join(OUT_DIR, 'README.txt'),
    [
      'This folder is intentionally empty in the repository.',
      '',
      'To populate it with the official Microsoft Azure architecture icons,',
      `follow the instructions printed by  npm run fetch-icons  or visit ${LANDING}`,
      '',
      'These icons are subject to Microsoft\'s license terms. Read them before use.',
      '',
    ].join('\n'),
  );

  // Reference: silence the unused-import lint if we ever inline downloads.
  void Readable;
  void pipeline;
  void createWriteStream;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
