import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { BridgeTestClient } from './test-support/bridge-test-client.ts';
import { PiTestWorld, attachTestAgent } from './test-support/pi-test-world.ts';

interface TestTopology {
  panes: { id: string; terminalId: string; title: string; mobileAvailable: boolean; reviews: { id: string; url: string }[] }[];
}
interface TestTerminalFrame { terminalId: string; data: string; cols: number; rows: number }

const cli = fileURLToPath(new URL('./bridge-cli.mjs', import.meta.url));

test('bridge JSONL preserves fragmented UTF-8 and Unicode line separators', async (t) => {
  const bridge = new BridgeTestClient([cli, '--session', 'test-only']);
  t.after(() => bridge.close());
  const unknown = await bridge.request('unknown\u2028méthode\u2029🙂', {}, { chunkBytes: 1 });
  assert.equal(unknown.error?.code, 'unknown_method');
  const hello = await bridge.request<{ protocol: number; name: string }>('hello');
  assert.equal(hello.result?.protocol, 1);
  assert.equal(hello.result?.name, 'pi-mobile');
});

test('stable terminal navigation survives a pane move without using focused location', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  await world.desktop.request('pane.move');
  const topology = (await phone.request<TestTopology>('snapshot')).result;
  assert.equal(topology?.panes.find((pane) => pane.terminalId === world.terminalId)?.id, 'w2:p9');
  assert.equal(topology?.panes.find((pane) => pane.terminalId === world.terminalId)?.title, 'Existing agent');
  assert.equal((await attachTestAgent(phone, world.terminalId)).terminalId, 'term_live');
  assert.equal((await phone.request('agent.attach', { terminalId: 'missing' })).error?.code, 'terminal_not_found');
});

test('topology admits only advertised Plannotator HTTP loopback URLs', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  await world.desktop.request('pane.tokens', { tokens: {
    plannotator_a1: 'http://localhost:43111/review?token=fixture',
    plannotator_a2: 'http://127.0.0.1:43112/review',
    plannotator_a3: 'https://127.0.0.1:43113/review',
    plannotator_a4: 'http://remote.example:43114/review',
    plannotator_a5: 'http://user:password@localhost:43115/review',
    plannotator_a6: 'http://localhost/review',
    plannotator_nothex: 'http://localhost:43116/review',
  } });
  const pane = (await phone.request<TestTopology>('snapshot')).result?.panes.find((value) => value.terminalId === world.terminalId);
  assert.deepEqual(pane?.reviews, [
    { id: 'plannotator_a1', url: 'http://localhost:43111/review?token=fixture' },
    { id: 'plannotator_a2', url: 'http://127.0.0.1:43112/review' },
  ]);
});

test('arbitrary socket metadata never becomes an agent attachment', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  await world.desktop.request('pane.tokens', { tokens: { pi_mobile: '/tmp/not-a-pi-mobile-token.sock' } });
  assert.equal((await phone.request('agent.attach', { terminalId: world.terminalId })).error?.code, 'bridge_unavailable');
});

test('terminal input needs observation, then control, then a distinct takeover choice', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  const params = { terminalId: world.terminalId, cols: 80, rows: 24 };
  assert.equal((await phone.request('terminal.attach', { ...params, control: true, takeover: false })).error?.code, 'observe_first');
  assert.deepEqual((await phone.request('terminal.attach', { ...params, control: false, takeover: false })).result, { attached: true });
  assert.equal((await phone.request('terminal.input', { data: 'eA==' })).error?.code, 'terminal_read_only');
  assert.equal((await phone.request('terminal.attach', { ...params, control: true, takeover: true })).error?.code, 'takeover_confirmation');
  assert.equal((await phone.request('terminal.attach', { ...params, control: true, takeover: false })).error?.code, 'terminal_unavailable');
  assert.deepEqual((await phone.request('terminal.attach', { ...params, control: true, takeover: true })).result, { attached: true });
  const typed = Buffer.from('typed\r').toString('base64');
  assert.deepEqual((await phone.request('terminal.input', { data: typed })).result, { accepted: true });
  assert.equal((await phone.nextEvent<TestTerminalFrame>('terminal.frame', (frame) => frame.data === typed)).terminalId, 'term_live');
  await phone.request('terminal.detach');
  assert.equal((await phone.request('terminal.input', { data: typed })).error?.code, 'terminal_read_only');
});

test('leaving a pane detaches subscriptions without taking the machine directory or Pi offline', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  const before = await attachTestAgent(phone, world.terminalId);
  await world.desktop.request('agent.working', { value: true });
  const params = { terminalId: world.terminalId, cols: 80, rows: 24 };
  assert.deepEqual((await phone.request('terminal.attach', { ...params, control: false, takeover: false })).result, { attached: true });
  assert.equal((await phone.request('terminal.attach', { ...params, control: true, takeover: false })).error?.code, 'terminal_unavailable');
  assert.deepEqual((await phone.request('terminal.attach', { ...params, control: true, takeover: true })).result, { attached: true });
  assert.deepEqual((await phone.request('terminal.detach')).result, { detached: true });
  assert.deepEqual((await phone.request('agent.detach')).result, { detached: true });
  assert.equal((await phone.request('terminal.input', { data: 'eA==' })).error?.code, 'terminal_read_only');
  assert.equal((await phone.request<{ protocol: number }>('hello')).result?.protocol, 1);
  assert.ok((await phone.request<TestTopology>('snapshot')).result?.panes.some((pane) => pane.terminalId === world.terminalId));
  const after = await attachTestAgent(phone, world.terminalId);
  assert.equal(after.generation, before.generation);
  assert.equal(after.status, 'working');
});

test('terminal frames preserve identical successive output and explicit grid changes', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone();
  const params = { terminalId: world.terminalId, cols: 80, rows: 24 };
  await phone.request('terminal.attach', { ...params, control: false, takeover: false });
  await phone.request('terminal.attach', { ...params, control: true, takeover: false });
  await phone.request('terminal.attach', { ...params, control: true, takeover: true });
  await phone.request('terminal.input', { data: 'eA==' });
  await phone.request('terminal.input', { data: 'eA==' });
  assert.equal((await phone.nextEvent<TestTerminalFrame>('terminal.frame', (frame) => frame.data === 'eA==')).data, 'eA==');
  assert.equal((await phone.nextEvent<TestTerminalFrame>('terminal.frame', (frame) => frame.data === 'eA==')).data, 'eA==');
  await phone.request('terminal.resize', { cols: 100, rows: 30 });
  const resized = await phone.nextEvent<TestTerminalFrame>('terminal.frame', (frame) => frame.cols === 100);
  assert.equal(resized.rows, 30);
  assert.equal((await phone.request('terminal.resize', { cols: 501, rows: 30 })).error?.code, 'invalid_request');
  assert.equal((await phone.request('terminal.input', { data: 'not base64!' })).error?.code, 'invalid_request');
});

test('the one-MiB input limit accepts its boundary and counts UTF-8 bytes', async (t) => {
  const exact = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => exact.close());
  const id = '11111111-1111-1111-1111-111111111111';
  const overhead = Buffer.byteLength(JSON.stringify({ id, method: 'hello', params: { blob: '' } }));
  const accepted = await exact.request<{ protocol: number }>('hello', { blob: 'a'.repeat(1024 * 1024 - overhead) }, { id });
  assert.equal(accepted.result?.protocol, 1);
  const oversized = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => oversized.close());
  await assert.rejects(oversized.request('hello', { blob: 'é'.repeat(600_000) }));
  await oversized.closed;
});

test('malformed UTF-8 and unterminated JSONL close only their bridge connection', { timeout: 5000 }, async (t) => {
  const invalid = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => invalid.close());
  invalid.child.stdin.write(Buffer.from([0x7b, 0xc3, 0x28, 0x7d, 0x0a]));
  await invalid.closed;
  const partial = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => partial.close());
  partial.child.stdin.end('{"id":"unfinished"');
  await partial.closed;
  const healthy = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => healthy.close());
  assert.equal((await healthy.request<{ protocol: number }>('hello')).result?.protocol, 1);
});

test('request identity reuse rejects changed methods even after a read', async (t) => {
  const bridge = new BridgeTestClient([cli, '--session', 'test-only']); t.after(() => bridge.close());
  const id = '22222222-2222-2222-2222-222222222222';
  await bridge.request('hello', {}, { id });
  assert.equal((await bridge.request('agent.detach', {}, { id })).error?.code, 'duplicate_conflict');
});
