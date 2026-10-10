# Pi Mobile bridge protocol v1

Authoritative shared contract for the iOS client and host implementation. Changes require coordinator agreement. This is a private SSH stdio service, not HTTP. A connection launches `node <installation>/host/bridge-cli.mjs --session <herdr-session>` through an SSH exec channel **without a PTY**. One JSON object per LF, UTF-8; never split at Unicode line separators. Max input record: 1 MiB. stdout contains records only, stderr diagnostics. EOF releases only this connection's streams, never Pi or Herdr.

## Envelopes

Client: `{ "id": "unique UUID", "method": "snapshot", "params": {} }`.
Server success: `{ "id": "...", "result": <JSON> }`.
Server failure: `{ "id": "...", "error": { "code": "stale_dialog", "message": "..." } }`.
Event: `{ "event": "agent.snapshot", "data": <JSON> }`.

Every mutation uses the command id for duplicate suppression. Reuse of an id with different parameters is an error. The app must never automatically retry a mutation after uncertain delivery. Agent commands carry both sessionId and generation from the live attach response. A generation changes on reload/session replacement; a stale generation is rejected, never retargeted. The host CLI owns a connection, not the agent.

## Methods

- `hello` → `{protocol:1, name:"pi-mobile", capabilities:[...]}`.
- `snapshot` → topology below. Read only; no focus changes. Use the explicit configured Herdr session. Missing/incompatible host software is an error, never an auto-install/restart.
- `agent.attach` `{terminalId}` → AgentSnapshot and subscribe to `agent.snapshot`. Resolve pane by stable terminal identity, then read its Pi Mobile socket metadata. Never use current UI focus or session-file contents as a control interface. If the extension is absent, return `bridge_unavailable`; the terminal remains usable.
- `agent.detach` `{}` → `{detached:true}`; disconnect only the mobile subscription.
- `agent.prompt` `{sessionId,generation,message,delivery?:"steer"|"followUp"}` → `{accepted:true}`. Preserve extension commands, skills and prompt templates via Pi's normal expansion pipeline. Built-in TUI-only commands fail with a terminal fallback, never become model prose. Empty prompts, an active dialog, stale identities and unspecified delivery while working are rejected. Success means accepted, not completed.
- `agent.abort` `{sessionId,generation}` → `{accepted:true}`.
- `dialog.respond` `{sessionId,generation,dialogId,revision,action,value?:string}` → `{accepted:true}`. Only advertised actions allowed. Stale revision/id, unknown option, closed/replaced dialog and control characters in free text are rejected. Never synthesize policy verdicts or widen grants.
- `terminal.attach` `{terminalId,control:bool,takeover:bool,cols:int,rows:int}` → `{attached:true}`. Observe first; obtaining input control is an explicit user action. Takeover requires another explicit action. Use Herdr's actual terminal session observe/control JSONL API, **no PTY**. Stream `terminal.frame` and `terminal.closed`.
- `terminal.input` `{data:string}` → `{accepted:true}`; data is base64 terminal bytes. Writable attachment required.
- `terminal.resize` `{cols:int,rows:int}` → `{accepted:true}`; writable attachment required.
- `terminal.detach` `{}` → `{detached:true}`.

## Topology

```
{
  workspaces:[{id:string,name:string}],
  tabs:[{id:string,workspaceId:string,name:string}],
  panes:[{id:string,terminalId:string,workspaceId:string,tabId:string,
    title:string,cwd:string,agent:string|null,state:string,
    mobileAvailable:bool,reviews:[{id:string,url:string}]}]
}
```

All ids are opaque. The app adds the saved machine UUID to local identity; two machines can have identical Herdr ids. A pane move may change paneId but not terminalId. Reviews originate only from existing `plannotator_<hex>` pane metadata; accept http loopback URLs with an explicit port, no credentials. The iOS transport opens a local loopback-only ephemeral listener and forwards connections through SSH direct-tcpip to **127.0.0.1 and that advertised port**. It does not open a general remote URL proxy. Review dismissal closes owned forwarding connections, not the review server or agent. Token disappearance means the review has ended.

## AgentSnapshot

```
{
  sessionId:string,generation:string,terminalId:string,
  name:string,cwd:string,status:"idle"|"working"|"blocked",
  messages:[{id:string,role:string,text:string,toolName?:string,isError?:bool}],
  commands:[{name:string,description:string}],
  dialog:DialogSnapshot|null,
  truncated:bool
}
```

Use the live Pi session manager's active branch and message events. Do not create a second Pi process. Send bounded transcript snapshots, including a live streaming message, with explicit truncation. Tool/image data is rendered as text descriptors; do not expose credential stores, raw image payloads or system prompts.

DialogSnapshot:
```
{dialogId:string,revision:int,kind:"permission"|"select"|"confirm"|"input"|"editor"|"terminal",
 title:string,text:string,options:[{id:string,label:string}],acceptsText:bool}
```

Generic dialogs must complete the original Pi UI promise and dismiss only that dialog. For pi-permission-system's custom TUI, reuse the **actual active component's public render/handleInput interface**, version/shape gated. Publish its currently rendered options/confirmation/scope steps. Apply one advertised action at a time to that same component; do not call a fabricated permission resolver or introspect private policy state. Mobile must preserve double confirmation, reason entry and subagent/session scope steps. A component update increments revision; late phone replies cannot act on a newer desktop selection. Unsupported components produce kind `terminal` and no native approval action. Document the compatibility boundary explicitly.

Terminal event data: `{terminalId:string,data:string,cols:int,rows:int}` (base64 ANSI bytes). Actual Herdr frame fields are translated at the CLI boundary.

## Security/lifecycle

Pi extension exposes a per-process Unix socket in an owned private directory, published under pane metadata token `pi_mobile`. No TCP listener. The CLI resolves only owned, non-symlink socket paths under that directory, never arbitrary paths supplied by the phone. Extension shutdown removes its own socket/metadata and invalidates callbacks. Reload must not let an old shutdown clear a new extension's advertisement. Slow subscribers are disconnected rather than blocking Pi's turn. No notifications or idle/background polling from the app.
