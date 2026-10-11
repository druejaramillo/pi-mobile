import { createHash } from 'node:crypto';
import { TextDecoder } from 'node:util';

/** Bridge record limits bound memory even when an SSH peer stops reading. */
export const BRIDGE_RECORD_LIMIT = 1024 * 1024;
const OUTPUT_QUEUE_LIMIT = 4 * BRIDGE_RECORD_LIMIT;

/** A bridge failure carries a stable wire code, never raw subprocess diagnostics. */
export class BridgeFailure extends Error {
  /** @param {string} code @param {string} message */
  constructor(code, message) { super(`Pi Mobile: ${message}`); this.code = code; }
}

/** Require a JSON object rather than an array or null at protocol boundaries. */
export function requireBridgeObject(/** @type {unknown} */ value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new BridgeFailure('invalid_request', 'expected an object.');
  return /** @type {Record<string, unknown>} */ (value);
}

/** Require a bounded string; control characters are never accepted in identifiers. */
export function requireBridgeString(/** @type {unknown} */ value, /** @type {number} */ max = 256) {
  if (typeof value !== 'string' || !value || value.length > max || /[\x00-\x1f\x7f-\x9f]/u.test(value)) throw new BridgeFailure('invalid_request', 'invalid string.');
  return value;
}

/** Validate a single request envelope before dispatch or duplicate suppression. */
export function parseBridgeRequest(/** @type {unknown} */ value) {
  const object = requireBridgeObject(value);
  const id = requireBridgeString(object.id, 64);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new BridgeFailure('invalid_request', 'request id must be a UUID.');
  return { id, method: requireBridgeString(object.method, 80), params: requireBridgeObject(object.params ?? {}) };
}

/** Convert failures to bounded public errors without leaking local paths or tool output. */
export function bridgeErrorReply(/** @type {unknown} */ error) {
  return error instanceof BridgeFailure ? { code: error.code, message: error.message } : { code: 'bridge_unavailable', message: 'Pi Mobile: host operation failed; use the terminal or inspect local setup.' };
}

/** Read LF-only JSONL with fatal UTF-8 validation and a byte cap before decoding. */
export function consumeBridgeRecords(
  /** @type {import('node:stream').Readable} */ input,
  /** @type {(value: unknown) => void} */ onRecord,
  /** @type {(error: unknown) => void} */ onFailure,
  /** @type {number} */ limit = BRIDGE_RECORD_LIMIT,
) {
  let pending = Buffer.alloc(0);
  let failed = false;
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const fail = (/** @type {unknown} */ error) => { if (!failed) { failed = true; pending = Buffer.alloc(0); onFailure(error); } };
  const data = (/** @type {Buffer} */ chunk) => {
    if (failed) return;
    let start = 0;
    try {
      while (start < chunk.length) {
        const newline = chunk.indexOf(10, start);
        const end = newline < 0 ? chunk.length : newline;
        if (pending.length + end - start > limit) throw new BridgeFailure('record_too_large', 'JSONL input exceeds its byte limit.');
        pending = Buffer.concat([pending, chunk.subarray(start, end)]);
        if (newline < 0) return;
        if (!pending.length) throw new BridgeFailure('invalid_request', 'empty JSONL record.');
        const value = JSON.parse(decoder.decode(pending));
        pending = Buffer.alloc(0);
        onRecord(value);
        start = newline + 1;
      }
    } catch (error) { fail(error); }
  };
  const end = () => { if (pending.length) fail(new BridgeFailure('invalid_request', 'unterminated JSONL record.')); };
  input.on('data', data); input.on('end', end); input.on('error', fail);
  return () => { input.off('data', data); input.off('end', end); input.off('error', fail); pending = Buffer.alloc(0); };
}

/** Emit bounded JSON records and disconnect slow subscribers instead of blocking Pi. */
export function createBridgeWriter(/** @type {import('node:stream').Writable} */ output, /** @type {() => void} */ disconnect) {
  return (/** @type {unknown} */ value) => {
    if (output.destroyed || !output.writable) return false;
    const line = `${JSON.stringify(value)}\n`;
    const bytes = Buffer.byteLength(line);
    if (bytes > BRIDGE_RECORD_LIMIT || output.writableLength + bytes > OUTPUT_QUEUE_LIMIT) { disconnect(); return false; }
    output.write(line); return true;
  };
}

/** @returns {string} */
function canonicalBridgeJson(/** @type {unknown} */ value) {
  if (Array.isArray(value)) return `[${value.map(canonicalBridgeJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const object = /** @type {Record<string, unknown>} */ (value);
    return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${canonicalBridgeJson(object[key])}`).join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

/** Duplicate suppression retains all accepted mutation ids until its generation ends. */
export class BridgeCommandLedger {
  /** @type {Map<string, {digest: string, reply: Promise<unknown>}>} */
  commands = new Map();
  cachedBytes = 0;
  /** @type {Map<string, string>} */ requestIdentities = new Map();
  /** Record even read request ids so reuse with different parameters always fails. */
  remember(/** @type {ReturnType<typeof parseBridgeRequest>} */ request) {
    const digest = createHash('sha256').update(canonicalBridgeJson({ method: request.method, params: request.params })).digest('hex');
    const previous = this.requestIdentities.get(request.id);
    if (previous && previous !== digest) throw new BridgeFailure('duplicate_conflict', 'request id was already used with different parameters.');
    if (!previous && this.requestIdentities.size >= 8192) throw new BridgeFailure('command_limit', 'request identity ledger is full; no operation was attempted.');
    this.requestIdentities.set(request.id, digest);
    return digest;
  }
  /** @param {ReturnType<typeof parseBridgeRequest>} request @param {() => Promise<unknown>} execute */
  run(request, execute) {
    const digest = this.remember(request);
    const previous = this.commands.get(request.id);
    if (previous) {
      if (previous.digest !== digest) throw new BridgeFailure('duplicate_conflict', 'command id was already used with different parameters.');
      return previous.reply;
    }
    if (this.commands.size >= 4096 || this.cachedBytes >= 8 * BRIDGE_RECORD_LIMIT) throw new BridgeFailure('command_limit', 'command ledger is full; no mutation was attempted.');
    const reply = Promise.resolve().then(execute).then((result) => { this.cachedBytes += Buffer.byteLength(JSON.stringify(result) ?? 'null'); return result; }, (error) => { this.cachedBytes += 512; throw error; });
    this.commands.set(request.id, { digest, reply });
    return reply;
  }
}

/** Validate canonical base64 terminal bytes, never silently accept malformed input. */
export function requireTerminalBase64(/** @type {unknown} */ value, /** @type {number} */ max = 256 * 1024) {
  if (typeof value !== 'string' || value.length > max || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw new BridgeFailure('invalid_request', 'invalid terminal base64 bytes.');
  return value;
}

/** Terminal dimensions are deliberately smaller than Herdr's u16 maximum. */
export function requireTerminalDimensions(/** @type {Record<string, unknown>} */ params) {
  const { cols, rows } = params;
  if (!Number.isInteger(cols) || !Number.isInteger(rows) || Number(cols) < 1 || Number(cols) > 500 || Number(rows) < 1 || Number(rows) > 300) throw new BridgeFailure('invalid_request', 'terminal dimensions must be 1–500 columns and 1–300 rows.');
  return { cols: Number(cols), rows: Number(rows) };
}
