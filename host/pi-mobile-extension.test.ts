import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { PiTestWorld, attachTestAgent, testAgentIdentity, type TestAgentSnapshot } from './test-support/pi-test-world.ts';

test('duplicate prompt submissions stay single across phone reconnects', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const firstPhone = world.phone();
  const snapshot = await attachTestAgent(firstPhone, world.terminalId);
  const id = randomUUID();
  const params = { ...testAgentIdentity(snapshot), message: 'Review the existing project.' };
  assert.deepEqual((await firstPhone.request('agent.prompt', params, { id })).result, { accepted: true });
  await firstPhone.close();
  const secondPhone = world.phone();
  const reattached = await attachTestAgent(secondPhone, world.terminalId);
  assert.equal(reattached.generation, snapshot.generation);
  assert.deepEqual((await secondPhone.request('agent.prompt', params, { id })).result, { accepted: true });
  const current = await attachTestAgent(secondPhone, world.terminalId);
  assert.deepEqual(current.messages.map((message) => message.text), ['Review the existing project.']);
});

test('a stale phone dialog reply cannot override desktop interaction', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  const originalAnswer = world.desktop.request<string>('dialog.select');
  const opened = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (state) => state.dialog?.kind === 'select');
  assert.ok(opened.dialog);
  await world.desktop.request('desktop.input', { data: '\u001b[B' });
  const reply = await phone.request('dialog.respond', { ...testAgentIdentity(opened),
    dialogId: opened.dialog.dialogId, revision: opened.dialog.revision, action: 'select.1' });
  assert.equal(reply.error?.code, 'stale_dialog');
  await world.desktop.request('desktop.answer', { value: 'Keep' });
  assert.equal((await originalAnswer).result, 'Keep');
});

test('a prompt id cannot be reused with a different payload', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const state = await attachTestAgent(phone, world.terminalId);
  const id = randomUUID(); const identity = testAgentIdentity(state);
  await phone.request('agent.prompt', { ...identity, message: 'First instruction.' }, { id });
  const conflict = await phone.request('agent.prompt', { ...identity, message: 'A different instruction.' }, { id });
  assert.equal(conflict.error?.code, 'duplicate_conflict');
  assert.deepEqual((await attachTestAgent(phone, world.terminalId)).messages.map((message) => message.text), ['First instruction.']);
});

test('reload rejects a previously accepted mutation instead of replaying its success', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const before = await attachTestAgent(phone, world.terminalId);
  const id = randomUUID(); const params = { ...testAgentIdentity(before), message: 'Keep this once.' };
  await phone.request('agent.prompt', params, { id });
  await world.desktop.request('session.reload');
  const rejected = await phone.request('agent.prompt', params, { id });
  assert.equal(rejected.error?.code, 'stale_generation');
  const after = await attachTestAgent(phone, world.terminalId);
  assert.notEqual(after.generation, before.generation);
  assert.deepEqual(after.messages.map((message) => message.text), ['Keep this once.']);
});

test('session replacement rejects old identity even before a fresh lifecycle event', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const before = await attachTestAgent(phone, world.terminalId);
  await world.desktop.request('session.replace', { sessionId: 'session-two' });
  const result = await phone.request('agent.abort', testAgentIdentity(before));
  assert.equal(result.error?.code, 'stale_generation');
});

test('phone EOF leaves working Pi state alive for another connection', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const before = await attachTestAgent(phone, world.terminalId);
  await world.desktop.request('agent.working', { value: true }); await phone.close();
  const after = await attachTestAgent(world.phone(), world.terminalId);
  assert.equal(after.generation, before.generation);
  assert.equal(after.status, 'working');
});

test('mobile selection completes the original Pi UI promise', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  const answer = world.desktop.request<string>('dialog.select');
  const state = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'select');
  assert.ok(state.dialog);
  const reply = await phone.request('dialog.respond', { ...testAgentIdentity(state),
    dialogId: state.dialog.dialogId, revision: state.dialog.revision, action: 'select.0' });
  assert.deepEqual(reply.result, { accepted: true });
  assert.equal((await answer).result, 'Keep');
  assert.equal((await attachTestAgent(phone, world.terminalId)).dialog, null);
});

test('replacing a dialog invalidates its old id without completing the replacement', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  const first = world.desktop.request('dialog.select');
  const old = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'select');
  assert.ok(old.dialog);
  await world.desktop.request('desktop.answer', { value: 'Keep' }); await first;
  const replacement = world.desktop.request<string>('dialog.input');
  const current = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'input');
  assert.ok(current.dialog);
  const stale = await phone.request('dialog.respond', { ...testAgentIdentity(old),
    dialogId: old.dialog.dialogId, revision: old.dialog.revision, action: 'select.1' });
  assert.equal(stale.error?.code, 'stale_dialog');
  assert.equal((await attachTestAgent(phone, world.terminalId)).dialog?.dialogId, current.dialog.dialogId);
  await world.desktop.request('desktop.answer', { value: 'Desktop response' });
  assert.equal((await replacement).result, 'Desktop response');
});

test('only a text-taking action can submit input; rejected cancel text leaves the dialog open', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  const answer = world.desktop.request<string>('dialog.input');
  const state = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'input');
  assert.ok(state.dialog);
  assert.equal(state.dialog.options.find((option) => option.id === 'submit')?.acceptsValue, true);
  assert.notEqual(state.dialog.options.find((option) => option.id === 'cancel')?.acceptsValue, true);
  const identity = { ...testAgentIdentity(state), dialogId: state.dialog.dialogId, revision: state.dialog.revision };
  assert.equal((await phone.request('dialog.respond', { ...identity, action: 'cancel', value: 'Hidden text' })).error?.code, 'invalid_request');
  assert.equal((await phone.request('dialog.respond', { ...identity, action: 'submit', value: 'Editable response' })).result !== undefined, true);
  assert.equal((await answer).result, 'Editable response');
});

test('unsupported custom UI advertises no native approval actions', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  const answer = world.desktop.request('dialog.custom');
  const state = await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'terminal');
  assert.ok(state.dialog); assert.deepEqual(state.dialog.options, []);
  const reply = await phone.request('dialog.respond', { ...testAgentIdentity(state),
    dialogId: state.dialog.dialogId, revision: state.dialog.revision, action: 'approve' });
  assert.equal(reply.error?.code, 'unknown_option');
  await world.desktop.request('desktop.answer', { value: 'Desktop handled custom UI' });
  assert.equal((await answer).result, 'Desktop handled custom UI');
});

test('desktop draft and active dialog prevent phone prompt submission', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const state = await attachTestAgent(phone, world.terminalId);
  const params = { ...testAgentIdentity(state), message: 'Do not overwrite desktop work.' };
  await world.desktop.request('desktop.draft', { text: 'Unsent desktop instruction' });
  assert.equal((await phone.request('agent.prompt', params)).error?.code, 'desktop_input_active');
  await world.desktop.request('desktop.draft', { text: '' });
  const answer = world.desktop.request('dialog.confirm');
  await phone.nextEvent<TestAgentSnapshot>('agent.snapshot', (value) => value.dialog?.kind === 'confirm');
  assert.equal((await phone.request('agent.prompt', params)).error?.code, 'dialog_active');
  await world.desktop.request('desktop.answer', { value: false }); await answer;
  assert.deepEqual((await attachTestAgent(phone, world.terminalId)).messages, []);
});

test('working agents require an explicit delivery choice and accept explicit abort', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const state = await attachTestAgent(phone, world.terminalId);
  const identity = testAgentIdentity(state);
  await world.desktop.request('agent.working', { value: true });
  const params = { ...identity, message: 'Check this after current work.' };
  assert.equal((await phone.request('agent.prompt', params)).error?.code, 'delivery_required');
  assert.deepEqual((await phone.request('agent.prompt', { ...params, delivery: 'followUp' })).result, { accepted: true });
  assert.deepEqual((await phone.request('agent.abort', identity)).result, { accepted: true });
  assert.equal((await attachTestAgent(phone, world.terminalId)).status, 'idle');
});

test('unknown slash commands stay out of conversation while templates use normal Pi expansion', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); const state = await attachTestAgent(phone, world.terminalId);
  const identity = testAgentIdentity(state);
  assert.equal((await phone.request('agent.prompt', { ...identity, message: '/new' })).error?.code, 'terminal_fallback');
  assert.deepEqual((await attachTestAgent(phone, world.terminalId)).messages, []);
  await phone.request('agent.prompt', { ...identity, message: '/explain' });
  assert.deepEqual((await attachTestAgent(phone, world.terminalId)).messages.map((message) => message.text), ['Explain the project.']);
});

test('transcript snapshots omit thinking, image bytes and raw tool payloads', async (t) => {
  const world = await PiTestWorld.start(); t.after(() => world.close());
  const phone = world.phone(); await attachTestAgent(phone, world.terminalId);
  await world.desktop.request('session.seed', { entries: [
    { id: 'assistant', type: 'message', message: { role: 'assistant', timestamp: 10, content: [
      { type: 'thinking', thinking: 'PRIVATE_THINKING_MARKER' },
      { type: 'toolCall', name: 'read', arguments: { token: 'PRIVATE_TOOL_ARGUMENT_MARKER' } },
      { type: 'image', data: 'PRIVATE_IMAGE_MARKER', mimeType: 'image/png' },
      { type: 'text', text: 'Visible reply' },
    ] } },
    { id: 'tool', type: 'message', message: { role: 'toolResult', timestamp: 11, toolName: 'read',
      content: [{ type: 'text', text: 'PRIVATE_TOOL_RESULT_MARKER' }] } },
  ] });
  const state = await attachTestAgent(phone, world.terminalId);
  const wire = JSON.stringify(state.messages);
  assert.ok(wire.includes('Visible reply'));
  assert.ok(!wire.includes('PRIVATE_'));
  assert.ok(wire.includes('details in terminal'));
});
