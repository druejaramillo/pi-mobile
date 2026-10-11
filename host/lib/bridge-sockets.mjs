import { lstat, mkdir, realpath, chmod, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { BridgeFailure } from './bridge-records.mjs';

/** Socket metadata is a basename, never a phone-supplied filesystem path. */
export const MOBILE_SOCKET_TOKEN = 'pi_mobile';

/** Use one private, non-symlink directory owned by the current POSIX uid. */
export async function privateBridgeDirectory(/** @type {boolean} */ create = false) {
  if (!process.getuid) throw new BridgeFailure('unsupported_host', 'POSIX uid support is required.');
  const directory = `/tmp/pi-mobile-${process.getuid()}`;
  if (create) await mkdir(directory, { mode: 0o700 }).catch((error) => { if (error.code !== 'EEXIST') throw error; });
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o700 || await realpath(directory) !== directory) throw new BridgeFailure('unsafe_socket', 'bridge socket directory is not private and owned.');
  return directory;
}

/** Allocate a unique socket basename so old shutdown cannot unlink a replacement. */
export async function allocateBridgeSocket() {
  const directory = await privateBridgeDirectory(true);
  const token = `m1-${randomBytes(16).toString('hex')}.sock`;
  return { token, path: join(directory, token) };
}

/** Resolve advertised sockets only under the owned private directory. */
export async function resolveBridgeSocket(/** @type {unknown} */ token) {
  if (typeof token !== 'string' || !/^m1-[a-f0-9]{32}\.sock$/.test(token)) throw new BridgeFailure('bridge_unavailable', 'pane has no compatible Pi Mobile advertisement.');
  const path = join(await privateBridgeDirectory(), token);
  const stat = await lstat(path);
  if (!stat.isSocket() || stat.isSymbolicLink() || stat.uid !== process.getuid?.() || (stat.mode & 0o077) !== 0 || await realpath(path) !== path) throw new BridgeFailure('unsafe_socket', 'advertised socket is not private and owned.');
  return path;
}

/** Restrict a just-created Unix socket before publishing its metadata. */
export async function secureBridgeSocket(/** @type {string} */ path) { await chmod(path, 0o600); }

/** Remove only this runtime's unique Unix socket; never recursively remove its parent. */
export async function removeBridgeSocket(/** @type {string} */ token) {
  try { await unlink(await resolveBridgeSocket(token)); } catch { /* Absent or unsafe sockets are not touched. */ }
}
