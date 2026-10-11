import { randomUUID } from 'node:crypto';
import { createServer, type Socket } from 'node:net';
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';
import { BridgeFailure, BridgeCommandLedger, bridgeErrorReply, consumeBridgeRecords, createBridgeWriter, parseBridgeRequest, requireBridgeObject, requireBridgeString } from './bridge-records.mjs';
import { allocateBridgeSocket, secureBridgeSocket, removeBridgeSocket, resolveBridgeSocket } from './bridge-sockets.mjs';
import { callInheritedHerdr } from './herdr-transport.mjs';
import { AgentDialogBridge } from './agent-dialogs.ts';
import { buildMobileAgentSnapshot, liveMessageIdentity, type MobileDialogSnapshot } from './agent-snapshot.ts';

/** An agent runtime belongs to exactly one live Pi session generation. */
export interface MobileAgentRuntime {
  stop(): Promise<void>;
  message(value: unknown): void;
  working(value: boolean): void;
  changed(): void;
  branchChanged(): void;
  uiPrompt(waiting: boolean): void;
}

/** Start the per-generation Unix socket only from Pi's session_start lifecycle. */
export async function startMobileAgentBridge(pi: ExtensionAPI, ctx: ExtensionContext): Promise<MobileAgentRuntime> {
  const herdrSocket = process.env.HERDR_SOCKET_PATH;
  const callerPane = process.env.HERDR_PANE_ID;
  if (ctx.mode !== 'tui' || !ctx.hasUI || process.env.HERDR_ENV !== '1' || !herdrSocket || !callerPane) throw new BridgeFailure('bridge_unavailable', 'Pi Mobile requires an interactive Pi in a managed Herdr pane.');
  const paneResult = await callInheritedHerdr(herdrSocket, 'pane.current', { caller_pane_id: callerPane });
  const initialPane = requireBridgeObject(paneResult.pane);
  const terminalId = requireBridgeString(initialPane.terminal_id);
  const existing = requireBridgeObject(initialPane.tokens ?? {}).pi_mobile;
  if (existing) {
    try { await resolveBridgeSocket(existing); throw new BridgeFailure('already_attached', 'another Pi Mobile runtime already owns this terminal.'); }
    catch (error) { if (error instanceof BridgeFailure && error.code === 'already_attached') throw error; }
  }
  const sessionId = ctx.sessionManager.getSessionId();
  const generation = randomUUID();
  const socket = await allocateBridgeSocket();
  const clients = new Map<Socket, { subscribed: boolean; write: (value: unknown) => boolean }>();
  const ledger = new BridgeCommandLedger();
  const liveMessages = new Map<string, unknown>();
  let stopped = false;
  let working = !ctx.isIdle();
  let uiWaiting = false;
  const uncapturedDialog: MobileDialogSnapshot = { dialogId: randomUUID(), revision: 1, kind: 'terminal', title: 'Pi dialog', text: 'Use the terminal for this existing or unsupported dialog.', options: [], acceptsText: false };
  let publishTimer: NodeJS.Timeout | undefined;
  let snapshotTimer: NodeJS.Timeout | undefined;
  let metadataChain = Promise.resolve();
  let stopPromise: Promise<void> | undefined;
  let publishing = false;
  const dialogs = new AgentDialogBridge(ctx.ui, changed);

  function snapshot() { return buildMobileAgentSnapshot(pi, ctx, generation, terminalId, dialogs.snapshot() ?? (uiWaiting ? uncapturedDialog : null), liveMessages, working); }
  function changed(): void {
    if (stopped || snapshotTimer) return;
    snapshotTimer = setTimeout(() => {
      snapshotTimer = undefined;
      if (stopped) return;
      try { const data = snapshot(); for (const client of clients.values()) if (client.subscribed) client.write({ event: 'agent.snapshot', data }); }
      catch { for (const client of clients.keys()) client.destroy(); }
    }, 60);
    snapshotTimer.unref();
  }
  function verifyAgentIdentity(params: Record<string, unknown>): void {
    if (stopped || params.sessionId !== sessionId || params.generation !== generation || ctx.sessionManager.getSessionId() !== sessionId) throw new BridgeFailure('stale_generation', 'agent session or generation changed; reattach before another action.');
  }
  async function dispatch(request: ReturnType<typeof parseBridgeRequest>, client: { subscribed: boolean }): Promise<unknown> {
    const { method, params } = request;
    if (stopped) throw new BridgeFailure('stale_generation', 'this Pi extension generation has ended.');
    if (method === 'agent.attach') {
      if (params.terminalId !== terminalId) throw new BridgeFailure('terminal_not_found', 'advertised socket belongs to a different terminal.');
      client.subscribed = true; return snapshot();
    }
    if (!client.subscribed) throw new BridgeFailure('bridge_unavailable', 'attach to this Pi generation before issuing actions.');
    verifyAgentIdentity(params);
    if (method === 'dialog.respond') { dialogs.respond(params); return { accepted: true }; }
    if (method === 'agent.abort') { ctx.abort(); changed(); return { accepted: true }; }
    if (method !== 'agent.prompt') throw new BridgeFailure('unknown_method', 'unsupported agent bridge method.');
    const message = params.message;
    if (typeof message !== 'string' || !message.trim() || Buffer.byteLength(message) > 256 * 1024 || /[\x00-\x08\x0b-\x1f\x7f-\x9f]/u.test(message)) throw new BridgeFailure('invalid_prompt', 'prompt is empty, oversized or contains control characters.');
    if (uiWaiting || dialogs.snapshot()) throw new BridgeFailure('dialog_active', 'answer or close the active dialog before sending a prompt.');
    if (ctx.ui.getEditorText().trim()) throw new BridgeFailure('desktop_input_active', 'desktop draft is authoritative; finish it in the terminal first.');
    const delivery = params.delivery;
    if (delivery !== undefined && delivery !== 'steer' && delivery !== 'followUp') throw new BridgeFailure('invalid_request', 'delivery must be steer or followUp.');
    if ((working || !ctx.isIdle() || ctx.hasPendingMessages()) && delivery === undefined) throw new BridgeFailure('delivery_required', 'choose steer or followUp while the agent is working.');
    if (message.trimStart().startsWith('/')) {
      if (!message.startsWith('/')) throw new BridgeFailure('invalid_prompt', 'slash commands must begin at the first character.');
      const name = message.slice(1).split(/\s/, 1)[0];
      if (!pi.getCommands().some((command) => command.name === name)) throw new BridgeFailure('terminal_fallback', 'built-in TUI-only or unavailable slash commands must be used in the terminal.');
    }
    // Pi's normal pipeline retains extension commands, skill gates and template expansion.
    // The public API returns void: accepted means submitted, not completed or policy-approved.
    pi.sendUserMessage(message, { expandPromptTemplates: true, ...(delivery ? { deliverAs: delivery } : {}) });
    changed(); return { accepted: true };
  }
  const server = createServer((connection) => {
    if (stopped || clients.size >= 8) { connection.destroy(); return; }
    connection.on('error', () => {});
    const client = { subscribed: false, write: createBridgeWriter(connection, () => connection.destroy()) };
    clients.set(connection, client);
    let queued = 0;
    let chain = Promise.resolve();
    const stopRecords = consumeBridgeRecords(connection, (value) => {
      if (++queued > 16) { connection.destroy(); return; }
      chain = chain.then(async () => {
        if (connection.destroyed || stopped) return;
        let id: string | null = null;
        try {
          const request = parseBridgeRequest(value); id = request.id; ledger.remember(request);
          // Check generation before replaying a duplicate result, never retarget stale commands.
          if (request.method !== 'agent.attach') verifyAgentIdentity(request.params);
          const result = request.method === 'agent.attach' ? await dispatch(request, client) : await ledger.run(request, () => dispatch(request, client));
          client.write({ id, result });
        } catch (error) { client.write({ id, error: bridgeErrorReply(error) }); }
        finally { queued--; }
      });
    }, () => connection.destroy());
    connection.on('close', () => { stopRecords(); clients.delete(connection); });
  });
  // Metadata operations are serialized and drained before a reload publishes its new token.
  function reportMetadata(clear = false): Promise<void> {
    const operation = metadataChain.then(async () => {
      if (stopped && !clear) return;
      const current = requireBridgeObject((await callInheritedHerdr(herdrSocket!, 'pane.current', { caller_pane_id: callerPane })).pane);
      if (current.terminal_id !== terminalId || (stopped && !clear)) return;
      if (clear && requireBridgeObject(current.tokens ?? {}).pi_mobile !== socket.token) return;
      await callInheritedHerdr(herdrSocket!, 'pane.report_metadata', { pane_id: current.pane_id, source: 'pi:mobile', tokens: { pi_mobile: clear ? null : socket.token }, ttl_ms: 15000 });
    });
    metadataChain = operation.catch(() => {}); return operation;
  }
  const runtime: MobileAgentRuntime = {
    changed,
    branchChanged() { liveMessages.clear(); changed(); },
    uiPrompt(waiting) { if (!stopped) { uiWaiting = waiting; uncapturedDialog.revision++; changed(); } },
    message(value) { if (stopped) return; liveMessages.set(liveMessageIdentity(value), value); while (liveMessages.size > 16) liveMessages.delete(liveMessages.keys().next().value!); changed(); },
    working(value) { if (!stopped) { working = value; changed(); } },
    stop() {
      if (stopPromise) return stopPromise;
      stopped = true; clearInterval(publishTimer); clearTimeout(snapshotTimer); dialogs.stop();
      for (const connection of clients.keys()) connection.destroy(); clients.clear();
      stopPromise = (async () => { await new Promise<void>((resolve) => { if (!server.listening) resolve(); else server.close(() => resolve()); }); await metadataChain; await reportMetadata(true).catch(() => {}); await removeBridgeSocket(socket.token); })();
      return stopPromise;
    },
  };
  try {
    await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(socket.path, resolve); });
    await secureBridgeSocket(socket.path);
    await reportMetadata();
    publishTimer = setInterval(() => { if (publishing || stopped) return; publishing = true; void reportMetadata().catch(() => {}).finally(() => { publishing = false; }); }, 5000); publishTimer.unref();
    return runtime;
  } catch (error) { await runtime.stop(); throw error; }
}
