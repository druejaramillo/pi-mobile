import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { startMobileAgentBridge, type MobileAgentRuntime } from './lib/agent-bridge.ts';

const ownerKey = Symbol.for('pi-mobile.runtime-owner.v1');
const owners = globalThis as typeof globalThis & { [ownerKey]?: MobileAgentRuntime };

/** Pi Mobile attaches to the existing process; it never creates another Pi or model client. */
export default function piMobileExtension(pi: ExtensionAPI): void {
  let runtime: MobileAgentRuntime | undefined;
  let uiWaiting = false;
  pi.on('ui_prompt_start', () => { uiWaiting = true; runtime?.uiPrompt(true); });
  pi.on('ui_prompt_end', () => { uiWaiting = false; runtime?.uiPrompt(false); });
  pi.on('session_start', async (_event, ctx) => {
    await owners[ownerKey]?.stop();
    runtime = undefined;
    try {
      runtime = await startMobileAgentBridge(pi, ctx);
      owners[ownerKey] = runtime;
      runtime.uiPrompt(uiWaiting);
    } catch {
      if (ctx.mode === 'tui' && process.env.HERDR_ENV === '1') ctx.ui.notify('Pi Mobile: bridge unavailable; check host setup. Terminal interaction is unchanged.', 'warning');
    }
  });
  pi.on('session_shutdown', async () => { const owned = runtime; runtime = undefined; uiWaiting = false; await owned?.stop(); if (owners[ownerKey] === owned) delete owners[ownerKey]; });
  pi.on('message_start', (event) => runtime?.message(event.message));
  pi.on('message_update', (event) => runtime?.message(event.message));
  pi.on('message_end', (event) => runtime?.message(event.message));
  pi.on('agent_start', () => runtime?.working(true));
  pi.on('agent_settled', () => runtime?.working(false));
  pi.on('session_tree', () => runtime?.branchChanged());
  pi.on('session_compact', () => runtime?.branchChanged());
  pi.on('session_info_changed', () => runtime?.changed());
}
