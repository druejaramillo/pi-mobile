import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';

/** A dialog snapshot advertises only actions currently supported by its original UI. */
export interface MobileDialogSnapshot {
  dialogId: string;
  revision: number;
  kind: 'permission' | 'select' | 'confirm' | 'input' | 'editor' | 'terminal';
  title: string;
  text: string;
  options: { id: string; label: string; acceptsValue?: boolean }[];
  acceptsText: boolean;
}

/** Transcript text omits control sequences, system prompts and non-text payloads. */
export function boundedMobileText(text: string, limit = 8192): string {
  const clean = text.replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, '').replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '').replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/g, '');
  const bytes = Buffer.from(clean);
  return bytes.length <= limit ? clean : `${bytes.subarray(0, limit).toString('utf8').replace(/\ufffd$/, '')}\n[truncated]`;
}

interface MobileMessage { id: string; role: string; text: string; toolName?: string; isError?: boolean }

function describeLiveMessage(id: string, value: unknown): MobileMessage | null {
  if (!value || typeof value !== 'object') return null;
  const message = value as Record<string, unknown>;
  const role = message.role;
  if (typeof role !== 'string' || role === 'system' || (role === 'custom' && message.display !== true)) return null;
  if (role === 'toolResult') return { id, role, text: message.isError ? '[Tool failed; details in terminal]' : '[Tool completed; details in terminal]', toolName: typeof message.toolName === 'string' ? boundedMobileText(message.toolName, 128) : 'tool', isError: message.isError === true };
  if (role === 'bashExecution') return { id, role, text: '[Shell execution; details in terminal]' };
  if (!['user', 'assistant', 'custom', 'branchSummary', 'compactionSummary'].includes(role)) return null;
  const content = message.content ?? message.summary;
  let text = '';
  if (typeof content === 'string') text = content;
  else if (Array.isArray(content)) {
    for (const raw of content) {
      if (!raw || typeof raw !== 'object') continue;
      const block = raw as Record<string, unknown>;
      if (block.type === 'text' && typeof block.text === 'string') text += `${boundedMobileText(block.text)}\n`;
      else if (block.type === 'image') text += '[Image; available in terminal]\n';
      else if (block.type === 'toolCall') text += `[Tool: ${typeof block.name === 'string' ? boundedMobileText(block.name, 128) : 'tool'}]\n`;
      if (Buffer.byteLength(text) > 8192) break;
    }
  }
  return { id, role, text: boundedMobileText(text) };
}

/** Rebuild the active branch from the live session manager; never read session files. */
export function buildMobileAgentSnapshot(pi: ExtensionAPI, ctx: ExtensionContext, generation: string, terminalId: string, dialog: MobileDialogSnapshot | null, liveMessages: Map<string, unknown>, working: boolean) {
  const branch = ctx.sessionManager.getBranch();
  const messages: MobileMessage[] = [];
  const persisted = new Set<string>();
  let truncated = false;
  for (let index = branch.length - 1; index >= 0; index--) {
    const entry = branch[index];
    if (entry.type !== 'message') continue;
    const described = describeLiveMessage(entry.id, entry.message);
    if (!described) continue;
    persisted.add(liveMessageIdentity(entry.message));
    if (messages.length >= 64) { truncated = true; break; }
    messages.unshift(described);
  }
  for (const [id, value] of liveMessages) {
    if (persisted.has(id)) continue;
    const described = describeLiveMessage(`live:${id}`, value);
    if (described) messages.push(described);
  }
  let bytes = messages.reduce((total, message) => total + Buffer.byteLength(message.text), 0);
  while (messages.length > 64 || bytes > 128 * 1024) { const removed = messages.shift(); if (removed) bytes -= Buffer.byteLength(removed.text); truncated = true; }
  if (messages.some((message) => message.text.includes('[truncated]'))) truncated = true;
  const allCommands = pi.getCommands();
  const commands = allCommands.slice(0, 128).map((command) => ({ name: boundedMobileText(command.name, 128), description: boundedMobileText(command.description ?? '', 256) }));
  return { sessionId: ctx.sessionManager.getSessionId(), generation, terminalId, name: boundedMobileText(ctx.sessionManager.getSessionName() ?? 'Pi', 1024), cwd: boundedMobileText(ctx.cwd, 4096),
    status: dialog ? 'blocked' : working || !ctx.isIdle() || ctx.hasPendingMessages() ? 'working' : 'idle', messages, commands, dialog, truncated: truncated || allCommands.length > 128 };
}

/** Message event identities reconcile live streaming content with persisted branch entries. */
export function liveMessageIdentity(value: unknown): string {
  const message = value as { role?: unknown; timestamp?: unknown; toolCallId?: unknown };
  return `${String(message.role)}:${String(message.timestamp)}:${String(message.toolCallId ?? '')}`;
}
