import { spawn } from 'node:child_process';
import { createConnection } from 'node:net';
import { randomUUID } from 'node:crypto';
import { BridgeFailure, consumeBridgeRecords, createBridgeWriter, requireBridgeObject, requireBridgeString } from './bridge-records.mjs';

/** Explicit Herdr sessions never inherit focus or autostart a server. */
export function validateHerdrSession(/** @type {string} */ session) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(session)) throw new BridgeFailure('invalid_session', 'configure an explicit Herdr session name.');
  return session;
}

/** Launch the existing Herdr API stdio bridge without a shell, PTY or restart. */
export function spawnHerdrBridge(/** @type {string} */ session, /** @type {string[]} */ args = ['remote-api-bridge']) {
  const child = spawn(process.env.PI_MOBILE_HERDR_BIN || 'herdr', ['--session', validateHerdrSession(session), ...args], { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stderr.resume(); // Never forward possibly sensitive local diagnostics onto SSH stdout.
  child.stdin.on('error', () => {});
  return child;
}

/** A bounded JSONL RPC connection never retries a request after uncertain delivery. */
export class BridgeRpcConnection {
  /** @type {Map<string, {resolve: (result: unknown) => void, reject: (error: unknown) => void, timer: NodeJS.Timeout}>} */
  pending = new Map();
  closed = false;
  /** @param {import('node:stream').Writable} input @param {import('node:stream').Readable} output @param {() => void} closeTransport @param {(event: Record<string, unknown>) => void} onEvent */
  constructor(input, output, closeTransport, onEvent = () => {}) {
    this.input = input; this.closeTransport = closeTransport;
    this.write = createBridgeWriter(input, () => this.close());
    this.stopRecords = consumeBridgeRecords(output, (value) => {
      try {
        const reply = requireBridgeObject(value);
        if (typeof reply.event === 'string') { onEvent(reply); return; }
        if (typeof reply.id !== 'string') throw new BridgeFailure('host_incompatible', 'host RPC returned an invalid envelope.');
        const pending = this.pending.get(reply.id);
        if (!pending) return;
        this.pending.delete(reply.id); clearTimeout(pending.timer);
        if (reply.error) {
          const error = requireBridgeObject(reply.error);
          pending.reject(new BridgeFailure(requireBridgeString(error.code), 'host rejected the operation.'));
        } else if ('result' in reply) pending.resolve(reply.result);
        else pending.reject(new BridgeFailure('host_incompatible', 'host RPC returned no result.'));
      } catch (error) { this.close(error); }
    }, (error) => this.close(error));
    output.on('end', () => this.close()); output.on('close', () => this.close());
    input.on('error', (error) => this.close(error));
  }
  /** @param {string} method @param {Record<string, unknown>} params @param {string} id */
  request(method, params = {}, id = randomUUID()) {
    if (this.closed) return Promise.reject(new BridgeFailure('bridge_unavailable', 'RPC connection is closed.'));
    if (this.pending.size >= 16 || this.pending.has(id)) return Promise.reject(new BridgeFailure('busy', 'RPC request is already pending.'));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.close(new BridgeFailure('delivery_uncertain', 'host response timed out; do not automatically retry.')); }, 8000);
      this.pending.set(id, { resolve, reject, timer });
      if (!this.write({ id, method, params })) this.close();
    });
  }
  /** Close only the transport and subscriptions, never the host agents. */
  close(/** @type {unknown} */ error = new BridgeFailure('delivery_uncertain', 'RPC connection ended; reload live state before another action.')) {
    if (this.closed) return;
    this.closed = true; this.stopRecords(); this.closeTransport();
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
    this.pending.clear();
  }
}

/** One read-only topology RPC targets exactly the configured Herdr session. */
export async function callHerdrSnapshot(/** @type {string} */ session, /** @type {AbortSignal | undefined} */ signal = undefined) {
  const child = spawnHerdrBridge(session);
  const rpc = new BridgeRpcConnection(child.stdin, child.stdout, () => { child.stdin.destroy(); child.kill(); });
  child.on('error', () => rpc.close(new BridgeFailure('herdr_unavailable', 'compatible Herdr is not installed.')));
  const abort = () => rpc.close(new BridgeFailure('bridge_unavailable', 'SSH connection ended.'));
  signal?.addEventListener('abort', abort, { once: true });
  if (signal?.aborted) abort();
  try { return requireBridgeObject(await rpc.request('session.snapshot')); } finally { signal?.removeEventListener('abort', abort); rpc.close(); }
}

/** An inherited Herdr socket may only publish metadata for its own Pi pane. */
export async function callInheritedHerdr(/** @type {string} */ socketPath, /** @type {string} */ method, /** @type {Record<string, unknown>} */ params) {
  const socket = createConnection(socketPath);
  const rpc = new BridgeRpcConnection(socket, socket, () => socket.destroy());
  try { return requireBridgeObject(await rpc.request(method, params)); } finally { rpc.close(); }
}
