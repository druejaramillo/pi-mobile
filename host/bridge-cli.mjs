#!/usr/bin/env node
import { createConnection } from 'node:net';
import { BridgeFailure, BridgeCommandLedger, consumeBridgeRecords, createBridgeWriter, parseBridgeRequest, bridgeErrorReply, requireBridgeString, requireBridgeObject, requireTerminalDimensions, requireTerminalBase64 } from './lib/bridge-records.mjs';
import { validateHerdrSession, BridgeRpcConnection } from './lib/herdr-transport.mjs';
import { loadHerdrTopology, resolveHerdrTerminal } from './lib/herdr-topology.mjs';
import { resolveBridgeSocket } from './lib/bridge-sockets.mjs';
import { HerdrTerminalStream } from './lib/herdr-terminal-stream.mjs';

const version = process.versions.node.split('.').map(Number);
if (version[0] < 22 || (version[0] === 22 && version[1] < 19) || process.stdin.isTTY || process.stdout.isTTY) {
  process.stderr.write('Pi Mobile: Node 22.19+ and SSH exec without a PTY are required.\n'); process.exit(1);
}
const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--session') { process.stderr.write('Pi Mobile: usage: node host/bridge-cli.mjs --session <herdr-session>\n'); process.exit(1); }
const session = validateHerdrSession(args[1]);
const ledger = new BridgeCommandLedger();
const lifetime = new AbortController();
/** @type {BridgeRpcConnection | undefined} */ let agent;
/** @type {HerdrTerminalStream | undefined} */ let terminal;
/** @type {{ sessionId: string, generation: string } | undefined} */ let agentIdentity;
/** @type {string | undefined} */ let observedTerminalId;
/** @type {string | undefined} */ let controlAttemptTerminalId;
let closed = false;
let queued = 0;
let chain = Promise.resolve();
const write = createBridgeWriter(process.stdout, closeConnection);
const emit = (/** @type {string} */ event, /** @type {unknown} */ data) => { if (!closed) write({ event, data }); };
const stopRecords = consumeBridgeRecords(process.stdin, (value) => {
  if (closed) return;
  if (++queued > 16) { closeConnection(); return; }
  chain = chain.then(async () => {
    if (closed) return;
    let id = null;
    try {
      const request = parseBridgeRequest(value); id = request.id; ledger.remember(request);
      if (['agent.prompt', 'agent.abort', 'dialog.respond'].includes(request.method) && (!agent || agent.closed || !agentIdentity || request.params.sessionId !== agentIdentity.sessionId || request.params.generation !== agentIdentity.generation)) throw new BridgeFailure('stale_generation', 'attach to the current live Pi generation before another action.');
      const result = ['hello', 'snapshot', 'agent.attach'].includes(request.method) ? await dispatchBridgeRequest(request) : await ledger.run(request, () => dispatchBridgeRequest(request));
      if (!closed) write({ id, result });
    } catch (error) { if (!closed) write({ id, error: bridgeErrorReply(error) }); }
    finally { queued--; }
  });
}, () => closeConnection());

async function dispatchBridgeRequest(/** @type {ReturnType<typeof parseBridgeRequest>} */ request) {
  const { method, params, id } = request;
  switch (method) {
    case 'hello': return { protocol: 1, name: 'pi-mobile', capabilities: ['topology', 'agent', 'dialogs', 'terminal.observe', 'terminal.control', 'reviews'] };
    case 'snapshot': return (await loadHerdrTopology(session, lifetime.signal)).topology;
    case 'agent.attach': {
      agent?.close(); agent = undefined; agentIdentity = undefined;
      const terminalId = requireBridgeString(params.terminalId);
      const pane = await resolveHerdrTerminal(session, terminalId, lifetime.signal);
      const token = requireBridgeObject(pane.tokens ?? {}).pi_mobile;
      const socketPath = await resolveBridgeSocket(token);
      if (closed) throw new BridgeFailure('bridge_unavailable', 'SSH connection ended before attach.');
      const socket = createConnection(socketPath);
      const attached = new BridgeRpcConnection(socket, socket, () => socket.destroy(), (event) => {
        if (agent === attached && event.event === 'agent.snapshot') emit('agent.snapshot', event.data);
      });
      agent = attached;
      try { const result = requireBridgeObject(await attached.request('agent.attach', { terminalId }, id)); agentIdentity = { sessionId: requireBridgeString(result.sessionId), generation: requireBridgeString(result.generation) }; return result; } catch (error) { attached.close(); if (agent === attached) agent = undefined; throw error; }
    }
    case 'agent.detach': agent?.close(); agent = undefined; agentIdentity = undefined; return { detached: true };
    case 'agent.prompt': case 'agent.abort': case 'dialog.respond': {
      if (!agent) throw new BridgeFailure('bridge_unavailable', 'attach to a live Pi extension first.');
      return agent.request(method, params, id);
    }
    case 'terminal.attach': {
      const terminalId = requireBridgeString(params.terminalId);
      if (typeof params.control !== 'boolean' || typeof params.takeover !== 'boolean' || (params.takeover && !params.control)) throw new BridgeFailure('invalid_request', 'control and takeover must be explicit booleans.');
      if (params.control && observedTerminalId !== terminalId) throw new BridgeFailure('observe_first', 'observe this terminal before requesting input control.');
      if (params.takeover && controlAttemptTerminalId !== terminalId) throw new BridgeFailure('takeover_confirmation', 'request control without takeover first; takeover requires a separate explicit action.');
      const dimensions = requireTerminalDimensions(params);
      await resolveHerdrTerminal(session, terminalId, lifetime.signal);
      if (closed) throw new BridgeFailure('bridge_unavailable', 'SSH connection ended before terminal attach.');
      terminal?.close();
      if (params.control) controlAttemptTerminalId = terminalId;
      const attached = new HerdrTerminalStream(session, terminalId, params.control, params.takeover, dimensions, emit);
      terminal = attached;
      await attached.ready;
      if (attached.closed || closed) throw new BridgeFailure('terminal_unavailable', 'terminal attachment ended before acknowledgement.');
      if (!params.control) observedTerminalId = terminalId;
      return { attached: true };
    }
    case 'terminal.input': if (!terminal) throw new BridgeFailure('terminal_read_only', 'attach with input control first.'); terminal.write({ type: 'terminal.input', bytes: requireTerminalBase64(params.data) }); return { accepted: true };
    case 'terminal.resize': if (!terminal) throw new BridgeFailure('terminal_read_only', 'attach with input control first.'); terminal.write({ type: 'terminal.resize', ...requireTerminalDimensions(params) }); return { accepted: true };
    case 'terminal.detach': terminal?.close(); terminal = undefined; observedTerminalId = undefined; controlAttemptTerminalId = undefined; return { detached: true };
    default: throw new BridgeFailure('unknown_method', 'unsupported bridge method.');
  }
}
function closeConnection() {
  if (closed) return;
  closed = true; lifetime.abort(); stopRecords?.(); agent?.close(); terminal?.close();
  process.stdin.destroy(); process.stdout.end();
}
process.stdin.on('end', closeConnection); process.stdout.on('error', closeConnection);
process.on('SIGTERM', closeConnection); process.on('SIGHUP', closeConnection); process.on('SIGINT', closeConnection);
