// External Herdr/Pi SDK peer. The product CLI, extension, sockets and dialog wrappers stay real.
import { createServer } from 'node:net';
import { createInterface } from 'node:readline';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import piMobileExtension from '../pi-mobile-extension.ts';

const root = await mkdtemp(join(tmpdir(), 'pi-mobile-tests-'));
const herdrSocket = join(root, 'herdr.sock');
process.env.HERDR_ENV = '1';
process.env.HERDR_SOCKET_PATH = herdrSocket;
process.env.HERDR_PANE_ID = 'w1:p1';
process.env.PI_MOBILE_PERMISSION_PACKAGE = join(root, 'no-permission-package');
const terminalId = 'term_live';
const pane = { pane_id: 'w1:p1', terminal_id: terminalId, workspace_id: 'w1', tab_id: 'w1:t1',
  name: 'Existing agent', title: 'Pi', foreground_cwd: '/project', agent: 'pi', agent_status: 'idle', tokens: {} };
const peers = new Set();
const herdr = createServer((socket) => {
  peers.add(socket); socket.on('close', () => peers.delete(socket)); socket.on('error', () => {});
  createInterface({ input: socket }).on('line', (line) => {
    const request = JSON.parse(line);
    let result;
    if (request.method === 'session.snapshot') {
      result = { snapshot: {
        workspaces: [{ workspace_id: pane.workspace_id, label: 'Project workspace' }],
        tabs: [{ tab_id: pane.tab_id, workspace_id: pane.workspace_id, label: 'Build tab' }],
        panes: [{ pane_id: 'other:p2', terminal_id: 'term_other', workspace_id: pane.workspace_id,
          tab_id: pane.tab_id, title: 'Focused elsewhere', agent: null, agent_status: 'unknown', tokens: {} }, pane],
      } };
    } else if (request.method === 'pane.current') {
      result = { pane };
    } else if (request.method === 'pane.report_metadata') {
      for (const [key, value] of Object.entries(request.params.tokens)) {
        if (value === null) delete pane.tokens[key]; else pane.tokens[key] = value;
      }
      result = {};
    } else {
      socket.write(JSON.stringify({ id: request.id, error: { code: 'unknown_method', message: 'Only fixture Herdr APIs are allowed.' } }) + '\n');
      return;
    }
    socket.write(JSON.stringify({ id: request.id, result }) + '\n');
  });
});
await new Promise((resolve, reject) => { herdr.once('error', reject); herdr.listen(herdrSocket, resolve); });

const handlers = new Map();
const terminalInput = new Set();
let sessionId = 'session-one';
let branch = [];
let editorText = '';
let idle = true;
let messageSequence = 0;
let desktopDialog;
async function emit(event, data = {}) {
  for (const handler of handlers.get(event) ?? []) await handler(data, ctx);
}
function finishDesktopDialog(value) {
  if (!desktopDialog) throw new Error('Fixture desktop has no pending dialog.');
  const active = desktopDialog; desktopDialog = undefined; active.resolve(value);
}
function originalDialog(options = {}, cancelled = undefined) {
  void emit('ui_prompt_start');
  return new Promise((resolve) => {
    const finish = (value) => { options.signal?.removeEventListener('abort', abort); resolve(value); };
    const abort = () => { if (desktopDialog?.resolve === finish) desktopDialog = undefined; finish(cancelled); };
    desktopDialog = { resolve: finish };
    if (options.signal?.aborted) abort(); else options.signal?.addEventListener('abort', abort, { once: true });
  }).finally(() => emit('ui_prompt_end'));
}
const ui = {
  onTerminalInput(callback) { terminalInput.add(callback); return () => terminalInput.delete(callback); },
  getEditorText() { return editorText; },
  notify() {},
  select(_title, _options, options) { return originalDialog(options); },
  confirm(_title, _text, options) { return originalDialog(options, false); },
  input(_title, _placeholder, options) { return originalDialog(options); },
  editor() { return originalDialog(); },
  async custom(factory) {
    const answer = originalDialog();
    const component = await factory({}, {}, {}, (value) => finishDesktopDialog(value));
    component.render(80);
    return answer;
  },
};
const ctx = {
  mode: 'tui', hasUI: true, cwd: '/project', ui,
  sessionManager: { getSessionId: () => sessionId, getSessionName: () => 'Existing agent', getBranch: () => branch },
  isIdle: () => idle, hasPendingMessages: () => false,
  abort() { idle = true; void emit('agent_settled'); },
};
const pi = {
  on(event, handler) { const registered = handlers.get(event) ?? []; registered.push(handler); handlers.set(event, registered); },
  getCommands: () => [{ name: 'skill:check', description: 'Check the project' }, { name: 'explain', description: 'Explain template' }],
  sendUserMessage(text, options) {
    const expanded = text === '/explain' && options?.expandPromptTemplates ? 'Explain the project.' : text;
    const message = { role: 'user', content: expanded, timestamp: ++messageSequence };
    branch.push({ id: `message-${messageSequence}`, type: 'message', message });
    void emit('message_end', { message });
  },
};
piMobileExtension(pi);
await emit('session_start');
if (!pane.tokens.pi_mobile) throw new Error('Fixture startup failed to advertise the actual extension.');

let stopping;
function shutdown() {
  stopping ??= (async () => {
    if (desktopDialog) finishDesktopDialog(undefined);
    await emit('session_shutdown');
    for (const socket of peers) socket.destroy();
    await new Promise((resolve) => herdr.close(resolve));
    await rm(root, { recursive: true, force: true });
  })();
  return stopping;
}
async function control(method, params) {
  switch (method) {
    case 'ready': return { herdrSocket, terminalId };
    case 'dialog.select': return ui.select('Choose an option', ['Keep', 'Delete']);
    case 'dialog.confirm': return ui.confirm('Confirm', 'Proceed with this action?');
    case 'dialog.input': return ui.input('Enter text', 'Response');
    case 'dialog.custom': return ui.custom(() => ({ render: () => ['Unknown custom interface'], handleInput() {} }));
    case 'desktop.answer': finishDesktopDialog(params.value); return {};
    case 'desktop.input': for (const listener of terminalInput) listener(params.data); return {};
    case 'desktop.draft': editorText = params.text; return {};
    case 'agent.working': idle = !params.value; await emit(params.value ? 'agent_start' : 'agent_settled'); return {};
    case 'session.reload': await emit('session_start'); return {};
    case 'session.replace': sessionId = params.sessionId; return {};
    case 'session.seed': branch = params.entries; await emit('session_tree'); return {};
    case 'pane.move': pane.pane_id = 'w2:p9'; pane.workspace_id = 'w2'; pane.tab_id = 'w2:t9'; return {};
    case 'pane.tokens': Object.assign(pane.tokens, params.tokens); return {};
    default: throw new Error('Unknown fixture control request.');
  }
}
const commands = createInterface({ input: process.stdin, terminal: false });
commands.on('line', (line) => {
  const request = JSON.parse(line);
  void control(request.method, request.params).then((result) => {
    process.stdout.write(JSON.stringify({ id: request.id, result: result ?? null }) + '\n');
  }, (error) => {
    process.stdout.write(JSON.stringify({ id: request.id, error: { code: 'fixture_failure', message: error.message } }) + '\n');
  });
});
commands.on('close', () => { void shutdown(); });
process.on('SIGTERM', () => { void shutdown(); });
