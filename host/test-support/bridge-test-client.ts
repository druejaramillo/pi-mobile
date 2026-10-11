import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { once, EventEmitter } from 'node:events';
import { createInterface } from 'node:readline';

/** Test peers speak the public JSONL protocol; no production parser or private helper is imported. */
export interface BridgeTestReply<T = unknown> {
  id: string;
  result?: T;
  error?: { code: string; message: string };
}

/** Observable stream events are consumed once, including repeated identical terminal frames. */
export interface BridgeTestEvent { event: string; data: unknown }

/** An owned pipe client bounds waits and kills only the child created by this test. */
export class BridgeTestClient {
  readonly child: ChildProcessWithoutNullStreams;
  readonly closed: Promise<void>;
  private readonly pending = new Map<string, {
    resolve(reply: BridgeTestReply): void; reject(error: Error): void; timer: NodeJS.Timeout;
  }>();
  private readonly events: BridgeTestEvent[] = [];
  private readonly received = new EventEmitter();
  private ended = false;

  constructor(args: string[], env: NodeJS.ProcessEnv = process.env) {
    this.child = spawn(process.execPath, args, { env, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stderr.resume();
    const lines = createInterface({ input: this.child.stdout, terminal: false });
    lines.on('line', (line) => {
      const record = JSON.parse(line) as BridgeTestReply & Partial<BridgeTestEvent>;
      if (record.event) {
        this.events.push({ event: record.event, data: record.data });
        this.received.emit('event');
      } else {
        const waiting = this.pending.get(record.id);
        if (waiting) {
          this.pending.delete(record.id); clearTimeout(waiting.timer); waiting.resolve(record);
        }
      }
    });
    const ended = () => {
      this.ended = true;
      for (const waiting of this.pending.values()) {
        clearTimeout(waiting.timer); waiting.reject(new Error('Bridge test peer closed before its reply.'));
      }
      this.pending.clear(); this.received.emit('event');
    };
    this.child.stdin.on('error', ended);
    this.child.on('error', ended);
    this.closed = new Promise((resolve) => this.child.once('close', () => { ended(); lines.close(); resolve(); }));
  }

  async request<T = unknown>(method: string, params: Record<string, unknown> = {},
                            options: { id?: string; chunkBytes?: number } = {}): Promise<BridgeTestReply<T>> {
    if (this.ended) throw new Error('Bridge test peer is closed.');
    const id = options.id ?? randomUUID();
    const response = new Promise<BridgeTestReply>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id); reject(new Error(`Bridge test reply deadline: ${method}`));
      }, 5000);
      this.pending.set(id, { resolve, reject, timer });
    });
    // A peer can reject while a large stdin write is still draining; observe both failure paths.
    void response.catch(() => {});
    const bytes = Buffer.from(JSON.stringify({ id, method, params }) + '\n');
    const chunkBytes = options.chunkBytes ?? bytes.length;
    try {
      for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
        if (!this.child.stdin.write(bytes.subarray(offset, offset + chunkBytes))) await once(this.child.stdin, 'drain');
      }
    } catch (error) {
      const waiting = this.pending.get(id);
      if (waiting) {
        this.pending.delete(id); clearTimeout(waiting.timer);
        waiting.reject(error instanceof Error ? error : new Error(String(error)));
      }
    }
    return response as Promise<BridgeTestReply<T>>;
  }

  async nextEvent<T>(name: string, matches: (data: T) => boolean = () => true): Promise<T> {
    const deadline = AbortSignal.timeout(5000);
    for (;;) {
      const index = this.events.findIndex((event) => event.event === name && matches(event.data as T));
      if (index !== -1) return this.events.splice(index, 1)[0].data as T;
      if (this.ended) throw new Error('Bridge test peer closed before its event.');
      await once(this.received, 'event', { signal: deadline });
    }
  }

  async close(): Promise<void> {
    if (!this.ended) this.child.stdin.end();
    const timer = setTimeout(() => this.child.kill(), 1000);
    try { await this.closed; } finally { clearTimeout(timer); }
  }
}
