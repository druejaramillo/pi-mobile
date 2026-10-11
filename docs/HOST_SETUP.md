# Pi Mobile host setup (Linux/POSIX)

## Compatibility boundary

- Node **22.19.0+**, Pi **1.1.0**, Herdr **0.9.1** with `herdr-api-bridge-v1`, `session.snapshot`, and `terminal session observe/control` JSONL. Missing software is an error; the bridge does not install, start, restart, or upgrade it.
- Native permission support is restricted to **@gotgenes/pi-permission-system 40.1.3**, an actual active `PermissionPromptComponent`, and its recognized live rendering grammar. Other versions, custom components, overlays, wrapped/missing grant labels, or oversized dialogs advertise terminal fallback with **no native approval actions**.
- Generic select/confirm/input wrap the original UI promise and use an owned AbortSignal to dismiss that exact active prompt. Desktop input increments the revision and remains authoritative. Because generic promises expose no live draft/selection handle, any local keyboard interaction makes that prompt terminal-only until it completes. Timed or oversized prompts also fall back to terminal.
- **Pi 1.1.0 `ui.editor(title, prefill)` has no AbortSignal or owned cancellation API.** Editor dialogs are terminal-only; completing a synthetic replacement would leave the original dialog active. This is a deliberate compatibility limitation, not an alternate editor implementation.
- Only dialogs opened after the UI wrappers are installed are captured. Load Pi Mobile before extensions that open startup dialogs where ordering is configurable. An already-open custom UI cannot be discovered through public Pi APIs; finish it locally and open a fresh dialog.

The supplied research checkout is older than the installed binary and lacks the terminal-session API. The implementation follows the installed 0.9.1 `herdr api schema --json` and the tagged 0.9.1 `src/client/terminal_sessions.rs`, not an invented stream format.

## Enable keyless Tailscale SSH

Tailscale must be connected on the iPhone and host. **Tailscale networking and Tailscale SSH are different:** new Pi Mobile connections use SSH's `none` authentication, with identity and authorization enforced by Tailscale. No client private key, password or passphrase is needed.

On the deliberately chosen host, enable Tailscale SSH yourself:

```sh
sudo tailscale set --ssh
```

This takes over port **22 on the host's Tailscale address only** and can interrupt existing SSH connections to that address. Review the change from a local console or another trusted access path. The app never runs this command or changes Tailscale settings.

Your tailnet policy must permit both network access to the destination's port 22 and SSH access for the phone's identity to an **existing host username**. Pi Mobile currently supports SSH `accept` rules, not interactive browser sign-in for `check` rules. Do not disable checks broadly to make the app work: review and deliberately choose the narrow access you want. Matching `check` rules take precedence over `accept`; merely adding an `accept` rule will not override them. A narrowly scoped SSH-policy excerpt for your own devices is:

```json
"ssh": [
  {
    "action": "accept",
    "src": ["you@example.com"],
    "dst": ["autogroup:self"],
    "users": ["your-host-username"]
  }
]
```

Substitute your actual identity/account and merge deliberately into your existing policy; this is not a replacement tailnet policy or a network-access grant. See [Tailscale SSH prerequisites, rules and platform limitations](https://tailscale.com/docs/features/tailscale-ssh). Linux is supported; macOS servers require the open-source `tailscaled` variant, not the App Store client.

### Verify the public host identity

The iOS app cannot read the system Tailscale app's coordination data. It therefore still requires a **verified public host key**, not a private login credential. From another trusted, authenticated Tailscale device, copy the destination's advertised Ed25519 public key:

```sh
tailscale status --json | jq -r --arg host 'your-host.your-tailnet.ts.net.' \
  '.Peer[] | select(.DNSName == $host) |
   (.sshHostKeys // .SSH_HostKeys // [])[] | select(startswith("ssh-ed25519 "))'
```

Use the exact destination MagicDNS FQDN, including the final dot. `jq` is needed only for this copy command. The field fallback accommodates Tailscale CLI versions. Copy the complete `ssh-ed25519 …` line into **Tailscale host identity** on the phone. If no key appears, check the destination name, SSH enablement and policy; never bypass verification or replace this with an unverified network scan. Tailscale can reuse a system host key or advertise a different one—use the key advertised for this node, not a guessed `/etc/ssh` file.

In Pi Mobile, enter the name, Tailscale DNS name/IP and host username. Port 22 is fixed for this setup. **Host bridge** reveals the existing session/path defaults only if they need changing. Install the bridge separately below; opening a connection never installs it.

Existing saved SSH profiles remain unchanged on upgrade. Their editor offers **Switch to Tailscale SSH**, which clears the draft host pin and requires the verified Tailscale-advertised public key. Save changes the connection mode; Cancel leaves the saved profile and credential untouched. Old Keychain items are retained on migration and removed only when you remove the saved machine.

## Install deliberately (not performed by this implementation)

Review `host/` before enabling it. In the installation checkout:

```sh
cd /path/to/pi-mobile/host
npm ci --ignore-scripts --legacy-peer-deps
```

Dependencies are exactly pinned in `host/package-lock.json`; runtime uses only Node built-ins and the Pi extension API. No second Pi package is installed or bundled.

To opt in for a **new, explicitly chosen** Pi invocation inside a Herdr pane:

```sh
pi --extension /path/to/pi-mobile/host/pi-mobile-extension.ts
```

Alternatively the user may install the local host package through Pi's normal package settings. Do not copy/reload installed extensions or alter existing sessions automatically. Pi/Herdr remain the conversation/process owners.

The extension requires inherited `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, and `HERDR_PANE_ID`. It resolves `pane.current` against the inherited caller identity, including after a pane move. There is no UI-focus fallback. Native permission version detection reads only the public package manifest at `~/.pi/agent/npm/node_modules/@gotgenes/pi-permission-system/package.json`. For another installation layout, set `PI_MOBILE_PERMISSION_PACKAGE` to that package's directory **in the Pi process environment**. It never reads permission configuration or private component state.

Configure the phone's SSH exec command with an explicit existing Herdr session:

```sh
node /path/to/pi-mobile/host/bridge-cli.mjs --session default
```

Use the real configured session name; `default` is an example. Names must be 1–64 ASCII letters/digits/underscore/hyphen, starting with a letter or digit. SSH must use **exec without a PTY** (`ssh -T` for manual use), never a shell/PTY terminal channel. The native client currently invokes `node` from the SSH account's **noninteractive PATH**; confirm that this PATH contains the required Node and Herdr before connecting. A per-profile Node executable override is not implemented. Choose any host PATH changes yourself; this repository never makes them automatically. An optional administrator-owned `PI_MOBILE_HERDR_BIN` chooses an executable; it is passed to `spawn`, not a shell. The phone cannot choose executables, socket paths, or arbitrary URLs.

Tailscale and host-key verification are client prerequisites. SSH stdout carries only LF-delimited JSON records, stderr diagnostics. No TCP listener, credentials, background agent, model client, or notification sender is installed.

## Behavior and safety

- `snapshot` is a read-only `session.snapshot` call. IDs are opaque; native attach resolves stable `terminal_id`, not focus, pane title, agent-session files, or saved conversation history.
- The extension creates a random `m1-<32 hex>.sock` in `/tmp/pi-mobile-<uid>` (0700, owned, non-symlink), chmods the socket 0600, and publishes its **basename** as pane token `pi_mobile`. Both sides reject arbitrary/symlink/foreign/public socket paths. Neither scans nor deletes unrelated sockets.
- Advertisement refresh is bounded and uses a 15-second metadata TTL. Shutdown drains its own writes before clearing its own token. Process-local reload ownership waits for old cleanup before publishing a new generation; old callbacks and wrappers are invalidated/restored. A second advertised runtime for the same terminal is refused.
- EOF/disconnect destroys only this connection's API, terminal, and UDS transports. Killing a bridge child does not stop the Herdr server, its pane process, Pi turn, or a review server.
- Every agent mutation checks session ID plus generation. Reload/session replacement requires fresh attach. Mutation IDs are retained by the agent across mobile reconnects within the same generation, and by the CLI for its own connection. Reusing an ID with different parameters fails. There are no automatic mutation retries. After uncertain delivery, reconnect/read fresh state; do not resend a prompt with a new ID as a transport retry.
- Ledgers never evict accepted IDs: new commands fail when 4096 mutations or the 8 MiB reply-cache threshold is reached; the separate read/mutation identity index is capped at 8192 request IDs. A terminal connection can be deliberately renewed; an agent-generation ledger requires a user-managed lifecycle change, not an automatic reload.
- Prompts reject empty/oversized/control-bearing text, desktop drafts, active captured dialogs, stale identities, and missing steer/followUp delivery while working. Slash commands must exist in Pi's live command list. Built-in TUI-only and unavailable slash commands return `terminal_fallback`, never model prose. `sendUserMessage(..., {expandPromptTemplates:true})` retains extension commands, skills, templates and their permission gates. Its void API means `accepted` is submission, **not completion**; downstream failure remains visible in Pi.
- Permission options and hotkeys come only from the original component's public `render(width)`. Each phone action calls that same instance's public `handleInput` once. Hotkeys are never automatically followed by Enter. Double-press confirmation, denial-reason entry and session/subagent scope steps remain separate live revisions. Reason text is appended as a bounded control-free bracketed paste; submitting it is a separate advertised action. There is no authorizer registration or fabricated permission verdict. Narrow/wrapped grant labels fail closed to terminal rather than guess a grant width.
- Generic phone replies revision-check, abort only their owned original prompt, then complete its UI wrapper to its original caller. Original desktop completions, external cancellation and replacements invalidate phone actions. Disconnect itself never answers or cancels a dialog.
- Terminal flow is **observe → explicit control request → separate explicit takeover request if needed**. `terminal.input`/resize require writable attachment. Herdr input uses `{type:"terminal.input",bytes:<base64>}`; frames translate `{type:"terminal.frame",bytes,width,height}` to bridge `{terminalId,data,cols,rows}`. Herdr does not acknowledge individual input writes: accepted means enqueued locally, not remotely executed. Neither blind focused-pane keys nor a PTY are used.
- Input records are capped at 1 MiB before decoding, UTF-8 is validated, and only LF splits records. Request queues, RPC waits, dimensions, terminal input, transcript text, commands, subscribers and output buffers are bounded. Slow UDS subscribers are disconnected rather than delaying Pi. Transcript snapshots include the active branch and live message events; abandoned-branch streaming cache is cleared on navigation. System prompts, thinking payloads, image data, tool arguments/results and credential stores are not serialized. Tool/image entries are text descriptors; snapshots explicitly mark transcript truncation.
- Reviews are only existing `plannotator_<hex>` tokens containing HTTP loopback URLs with explicit ports and no credentials. The host opens no review proxy. The client owns its SSH forwarding to **127.0.0.1 and the advertised port**, and dismissing a review must close only that forwarding.

## Static verification

Point the checker at the exact **installed** Pi package directory, not at its `dist` subdirectory:

```sh
PI_MOBILE_PI_ROOT=/path/to/node_modules/@earendil-works/pi-coding-agent npm run check
```

This performs strict TypeScript/checkJs validation against Pi's actual declarations without creating another Pi or calling a model. The temporary local typecheck configuration is removed afterward. JavaScript syntax can also be checked with `node --check` on `host/*.mjs` and `host/lib/*.mjs`.

The approved host protocol suite now passes 23 tests (`npm test`) against the real CLI/extension and isolated external Pi/Herdr peers. See [TESTING.md](TESTING.md). It exercises reconnect/duplicate/stale-dialog guards and control sequencing without touching live sessions or calling a model. It does **not** prove actual permission-component rendering or audit/scoping behavior. No live permission interaction, SSH device round-trip or iOS build has been run; use deliberately chosen dedicated sessions for those checks before daily use.
