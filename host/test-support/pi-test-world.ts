import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { BridgeTestClient } from './bridge-test-client.ts';

/** Tests control external Pi/Herdr peers, then observe the product only through bridge records. */
export class PiTestWorld {
  readonly terminalId: string;
  private readonly connections: BridgeTestClient[] = [];

  private constructor(readonly desktop: BridgeTestClient, private readonly herdrSocket: string, terminalId: string) {
    this.terminalId = terminalId;
  }

  static async start(): Promise<PiTestWorld> {
    const fixture = fileURLToPath(new URL('./pi-test-peer.mjs', import.meta.url));
    const desktop = new BridgeTestClient(['--experimental-transform-types', fixture]);
    try {
      const ready = await desktop.request<{ herdrSocket: string; terminalId: string }>('ready');
      assert.ok(ready.result, ready.error?.message);
      return new PiTestWorld(desktop, ready.result.herdrSocket, ready.result.terminalId);
    } catch (error) { await desktop.close(); throw error; }
  }

  phone(): BridgeTestClient {
    const cli = fileURLToPath(new URL('../bridge-cli.mjs', import.meta.url));
    const herdr = fileURLToPath(new URL('./herdr-test-peer.mjs', import.meta.url));
    const phone = new BridgeTestClient([cli, '--session', 'test-only'], {
      ...process.env, PI_MOBILE_HERDR_BIN: herdr, PI_MOBILE_TEST_HERDR_SOCKET: this.herdrSocket,
    });
    this.connections.push(phone);
    return phone;
  }

  async close(): Promise<void> {
    for (const phone of this.connections) await phone.close();
    await this.desktop.close();
  }
}

/** Snapshot fields used by protocol assertions, not an import from the product's internal types. */
export interface TestAgentSnapshot {
  sessionId: string; generation: string; terminalId: string; status: string;
  messages: { id: string; role: string; text: string }[];
  dialog: null | { dialogId: string; revision: number; kind: string; options: { id: string; label: string; acceptsValue?: boolean }[] };
  truncated: boolean;
}

/** Read the public attach snapshot; test setup never inspects a runtime's private state. */
export async function attachTestAgent(phone: BridgeTestClient, terminalId: string): Promise<TestAgentSnapshot> {
  const reply = await phone.request<TestAgentSnapshot>('agent.attach', { terminalId });
  assert.ok(reply.result, reply.error?.message);
  return reply.result;
}

/** Mutation identity comes only from the live attach response. */
export function testAgentIdentity(snapshot: TestAgentSnapshot): { sessionId: string; generation: string } {
  return { sessionId: snapshot.sessionId, generation: snapshot.generation };
}
