import { resolve, join } from 'node:path';
import { writeFile, unlink, access } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';

// Typecheck against the actual installed Pi declarations, without installing a second Pi.
const root = process.env.PI_MOBILE_PI_ROOT;
if (!root) throw new Error('Pi Mobile typecheck: set PI_MOBILE_PI_ROOT to the installed pi-coding-agent package directory.');
await access(join(root, 'dist/core/extensions/types.d.ts'));
const config = new URL('./.host-typecheck.json', import.meta.url);
await writeFile(config, JSON.stringify({ extends: './tsconfig.json', compilerOptions: {
  paths: { '@earendil-works/pi-coding-agent': [resolve(root, 'dist/index.d.ts')] },
} }));
try {
  const result = spawnSync(process.execPath, [new URL('./node_modules/typescript/bin/tsc', import.meta.url).pathname, '-p', config.pathname], { stdio: 'inherit' });
  process.exitCode = result.status ?? 1;
} finally { await unlink(config); }
