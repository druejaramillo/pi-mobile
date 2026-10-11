import { spawnHerdrBridge } from './herdr-transport.mjs';
import { consumeBridgeRecords, BridgeFailure, requireBridgeObject, requireTerminalBase64, requireTerminalDimensions } from './bridge-records.mjs';

/** A terminal stream owns only its Herdr observer/controller child, never its pane. */
export class HerdrTerminalStream {
  closed = false;
  /** @type {NodeJS.Timeout | undefined} */ startupTimer;
  /** @type {(error: unknown) => void} */ rejectReady = () => {};
  /** @param {string} session @param {string} terminalId @param {boolean} control @param {boolean} takeover @param {{cols: number, rows: number}} dimensions @param {(event: string, data: unknown) => void} emit */
  constructor(session, terminalId, control, takeover, dimensions, emit) {
    this.terminalId = terminalId; this.control = control; this.emit = emit;
    this.child = spawnHerdrBridge(session, ['terminal', 'session', control ? 'control' : 'observe', terminalId, '--cols', String(dimensions.cols), '--rows', String(dimensions.rows), ...(takeover ? ['--takeover'] : [])]);
    /** @type {Promise<void>} */
    this.ready = new Promise((resolve, reject) => {
      this.rejectReady = reject;
      const timer = setTimeout(() => { reject(new BridgeFailure('terminal_unavailable', 'Herdr terminal stream did not produce a frame.')); this.close(); }, 8000);
      this.startupTimer = timer;
      this.stopRecords = consumeBridgeRecords(this.child.stdout, (value) => {
        try {
          const frame = requireBridgeObject(value);
          if (frame.type === 'terminal.closed') { this.close(); return; }
          if (frame.type !== 'terminal.frame' || frame.encoding !== 'ansi') throw new BridgeFailure('host_incompatible', 'Herdr terminal stream format is unsupported.');
          const size = requireTerminalDimensions({ cols: frame.width, rows: frame.height });
          const data = requireTerminalBase64(frame.bytes, 900 * 1024);
          clearTimeout(timer); resolve();
          if (!this.closed) emit('terminal.frame', { terminalId, data, ...size });
        } catch (error) { reject(error); this.close(); }
      }, (error) => { reject(error); this.close(); });
      this.child.on('error', () => { reject(new BridgeFailure('terminal_unavailable', 'Herdr terminal stream could not start.')); this.close(); });
      this.child.stdout.on('end', () => { clearTimeout(timer); reject(new BridgeFailure('terminal_unavailable', 'Herdr terminal stream ended.')); this.close(); });
      this.child.on('exit', () => { clearTimeout(timer); this.close(); });
    });
  }
  /** Write one explicit terminal action; Herdr's stream has no mutation acknowledgement. */
  write(/** @type {Record<string, unknown>} */ command) {
    if (this.closed || !this.control || !this.child.stdin.writable) throw new BridgeFailure('terminal_read_only', 'a live writable terminal attachment is required.');
    if (this.child.stdin.writableLength > 1024 * 1024) { this.close(); throw new BridgeFailure('delivery_uncertain', 'terminal input queue is full; do not retry automatically.'); }
    this.child.stdin.write(`${JSON.stringify(command)}\n`);
  }
  /** Release this stream only; SIGTERM targets the bridge child, never a Herdr server. */
  close() {
    if (this.closed) return;
    this.closed = true; clearTimeout(this.startupTimer); this.rejectReady(new BridgeFailure('terminal_unavailable', 'terminal attachment ended.')); this.stopRecords?.();
    if (this.control && this.child.stdin.writable) this.child.stdin.end(`${JSON.stringify({ type: 'terminal.release' })}\n`);
    this.child.kill(); this.emit('terminal.closed', { terminalId: this.terminalId });
  }
}
