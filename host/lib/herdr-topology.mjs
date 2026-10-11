import { callHerdrSnapshot } from './herdr-transport.mjs';
import { requireBridgeObject, requireBridgeString, BridgeFailure } from './bridge-records.mjs';
import { resolveBridgeSocket } from './bridge-sockets.mjs';

function topologyArray(/** @type {unknown} */ value) {
  if (!Array.isArray(value) || value.length > 2000) throw new BridgeFailure('host_incompatible', 'Herdr snapshot has incompatible topology.');
  return value.map(requireBridgeObject);
}
function topologyText(/** @type {unknown} */ value, /** @type {string} */ fallback = '') { return typeof value === 'string' ? value.slice(0, 4096) : fallback; }

/** Accept only existing Plannotator HTTP loopback metadata with an explicit port. */
export function collectPaneReviews(/** @type {Record<string, unknown>} */ tokens) {
  /** @type {{id: string, url: string}[]} */ const reviews = [];
  for (const [id, raw] of Object.entries(tokens)) {
    if (!/^plannotator_[a-f0-9]+$/.test(id) || typeof raw !== 'string' || raw.length > 1024 || /[\x00-\x20\x7f]/.test(raw)) continue;
    try {
      const url = new URL(raw);
      if (url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) && url.port && !url.username && !url.password) reviews.push({ id, url: raw });
    } catch { /* Untrusted unrelated metadata is ignored. */ }
  }
  return reviews;
}

/** Normalize Herdr 0.9.1's actual session.snapshot schema without focus changes. */
export async function loadHerdrTopology(/** @type {string} */ session, /** @type {AbortSignal | undefined} */ signal = undefined) {
  const result = await callHerdrSnapshot(session, signal);
  const snapshot = requireBridgeObject(result.snapshot);
  const workspaces = topologyArray(snapshot.workspaces).map((w) => ({ id: requireBridgeString(w.workspace_id), name: topologyText(w.label) }));
  const tabs = topologyArray(snapshot.tabs).map((t) => ({ id: requireBridgeString(t.tab_id), workspaceId: requireBridgeString(t.workspace_id), name: topologyText(t.label) }));
  const rawPanes = topologyArray(snapshot.panes);
  const terminalIds = new Set();
  const panes = await Promise.all(rawPanes.map(async (pane) => {
    const terminalId = requireBridgeString(pane.terminal_id);
    if (terminalIds.has(terminalId)) throw new BridgeFailure('host_incompatible', 'Herdr returned duplicate terminal identities.');
    terminalIds.add(terminalId);
    const tokens = pane.tokens ? requireBridgeObject(pane.tokens) : {};
    let mobileAvailable = false;
    try { await resolveBridgeSocket(tokens.pi_mobile); mobileAvailable = true; } catch { /* Terminal remains usable. */ }
    return { id: requireBridgeString(pane.pane_id), terminalId, workspaceId: requireBridgeString(pane.workspace_id), tabId: requireBridgeString(pane.tab_id),
      title: typeof pane.name === 'string' && pane.name.trim() ? topologyText(pane.name) : topologyText(pane.title, topologyText(pane.label, topologyText(pane.terminal_title_stripped))), cwd: topologyText(pane.foreground_cwd, topologyText(pane.cwd)),
      agent: typeof pane.agent === 'string' ? pane.agent.slice(0, 256) : null, state: topologyText(pane.agent_status, 'unknown'), mobileAvailable, reviews: collectPaneReviews(tokens) };
  }));
  return { topology: { workspaces, tabs, panes }, rawPanes };
}

/** Resolve a pane by stable terminal identity, not its focus or previous pane id. */
export async function resolveHerdrTerminal(/** @type {string} */ session, /** @type {string} */ terminalId, /** @type {AbortSignal | undefined} */ signal = undefined) {
  const { rawPanes } = await loadHerdrTopology(session, signal);
  const pane = rawPanes.find((candidate) => candidate.terminal_id === terminalId);
  if (!pane) throw new BridgeFailure('terminal_not_found', 'terminal no longer exists in the configured session.');
  return pane;
}
