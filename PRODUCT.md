# Pi Mobile

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI app, SwiftTerm terminal rendering, Citadel SSH over the user's always-available Tailscale network, FluidAudio/Core ML Parakeet TDT v3. Node.js host bridge and TypeScript Pi extension. XcodeGen produces the Xcode project on a Mac. These are implementation choices within the approved native build, not existing infrastructure.

## Users

Drue, checking and directing existing coding agents from an iPhone while away from the laptop or desktop. This is a personal tool, not a multi-user hosted service.

## Product Purpose

Access existing Herdr workspaces, tabs and panes across an Omarchy laptop, Omarchy desktop and Hetzner VPS. Continue the same running Pi conversations, give instructions by voice, answer permission requests and review plans without creating another agent environment.

## Operating Context

Herdr owns terminal processes and topology. Pi owns each conversation, commands, skills and permission decisions. Tailscale is installed on every machine and is a required dependency. The user has access to a Mac, Xcode and Apple Developer membership.

## Capabilities and Constraints

- Native iOS controls and navigation, one pane at a time.
- A first-class global Agents screen lists recognized running agents across every configured machine with status and machine/workspace/tab context. Tapping an agent goes directly to its native conversation or terminal. Unreachable machines and cached/stale state remain explicit; an offline machine must not look empty.
- Direct SSH connections; no central terminal gateway or public HTTP service.
- SSH keys stored in Keychain, explicit host-key verification.
- A native conversation surface backed by the same live Pi process; unsupported custom interfaces remain accessible in the terminal.
- Permission requests must retain the existing policy, grant widths, confirmation steps and audit trail. No automatic approvals.
- Actual Plannotator web pages inside the app, forwarded through SSH; return to the originating pane.
- On-device Parakeet TDT v3, editable transcription before sending. Port deterministic VoxType speech settings, not the OpenAI cleanup script or credentials.
- No notifications, APNs, background monitoring, notification entitlements, or push sender. The user chooses when to check agents.
- Phone suspension/disconnection never stops host agents. Reconnect reloads live state; mutations are never blindly replayed.
- iPhone is the initial device target. No multi-pane layout or full IDE.

## Evidence on Hand

Inspected local Herdr 0.9.1 terminal stream/API schema, Pi 1.1.0 extension API, pi-permission-system 40.1.3 dialog implementation and local Plannotator metadata publisher. VoxType configuration was inspected read-only. No Mac/device builds have been run in this Linux environment.

## Product Principles

- Existing sessions remain authoritative.
- Make frequent phone interactions native; retain the terminal as an escape hatch.
- Keep audio and control traffic private.
- Prefer explicit action and fresh state over automatic retries or interruptions.
- State verification gaps honestly; a Linux syntax check is not an iPhone test.
