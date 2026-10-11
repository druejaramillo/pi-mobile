# Native iPhone surface

Mode: Operate. The user-approved native platform grammar and explicit global-agent directory take precedence over decorative world exploration. Code-first native implementation; no paid image generation is authorized or needed for this utility surface.

## Direction contract

THESIS: The first screen is the user's live agent directory, not a terminal squeezed into a phone or a disconnected chat environment. Every row has an opaque stable destination and readable location context.

OWN-WORLD: SwiftUI system surfaces, San Francisco text styles, semantic colors and one system-blue interactive tint. SF Symbols, native navigation/back gestures, inset lists, platform-adaptive Agent/Terminal choices and self-contained review sheets. Light/dark follows the user's appearance because this app is used indoors and outdoors. Dynamic Type and 44pt controls remain native.

STORY: Open Agents, see which live agent needs input, recognize its machine/workspace/tab, tap directly into it, dictate a draft, decide a live request and review an actual plan. Hosts stay authoritative and disconnected hosts stay visible as unavailable rather than empty.

FIRST VIEWPORT: Agents navigation title with refresh/add controls, readable agent rows carrying status and location. Empty state offers machine setup; connection errors are listed by machine. No fabricated agents, dashboard metrics or notification controls.

FORM: User-pinned native iOS activity directory with Machines and Settings as peer tab sections. The design seed was run (4a51cd93, assigned index 3); the explicit native/agent-index constraints govern rather than a literal foreign visual metaphor. Signature interaction: tapping a location-bearing agent row takes you to that exact running terminal, with Agent/Terminal as views of the same process.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Liquid Glass refresh

The user requested native Liquid Glass, a prettier interface and a more magical feel. This is a material and craft refresh of the same Operate surface, not a new navigation model or product identity. The existing user-pinned native direction and code-first build path remain authoritative.

- Keep system navigation, tab bars, forms, back gestures, San Francisco, semantic colors and the blue interactive tint. The user specifically rejected incomplete glass coverage on navigation/menu/header actions: comprehensive controls, not composer-only glass, are required.
- Use Apple's iOS 26 glass APIs on floating controls, with native material/button fallbacks on iOS 17–25. Directory rows, transcript content and permission explanations stay nonglass and legible.
- Saved implementation `649628b` uses `mobileGlassHeaderControl`: minimum 44pt circle icons and minimum 44pt-high capsule text actions. `mobileGlassHeaderItem` hides iOS 26 shared toolbar backgrounds only for explicit glass controls, not native back navigation. Header refresh/add/edit/review/Stop and sheet Done/Cancel/Save/Back actions are covered, as are inline reconnect/refresh/edit and key import/remove/paste styles. Native PasteButtons retain system paste authorization.
- Agents/Machines/Settings use native `Tab` on iOS 18+, `.tabItem` fallback on iOS 17 and scroll-down tab minimization on iOS 26. Agent/Terminal uses two glass choices on iOS 26, selected prominence and accessibility trait, minimum 44pt height and Reduce Motion-aware smooth selection animation; iOS 17–25 retains the segmented picker. This changes neither destinations nor terminal ownership/request semantics.
- Give agent status a text-and-symbol capsule and generous row rhythm; stack status and title at accessibility text sizes.
- Signature interaction: the editable composer floats above the conversation beside a separate glass Send control. Dictation stays editable and explicit; send feedback follows the host's acknowledgment, never an optimistic approval or delivery claim.
- Keep motion brief and state-driven. Honor Reduce Motion, Reduce Transparency and increased contrast. Never animate streaming text or add ambient effect loops.
- Preserve cached/offline visibility, exact pane destinations, terminal control/takeover confirmations, permission action labels, grant widths and every host-owned decision.

## Keyless machine setup simplification

Machine setup now serves only the new Tailscale SSH path: name, Tailscale address, host username and **verified public host identity**, with port 22 automatic. Private-key import/paste, passwords, passphrases and the authentication picker are removed. The public identity key stays because the app cannot read the system Tailscale app's coordination data; it is not a private login credential. Host bridge session/path defaults move under a native disclosure.

Existing saved SSH logins remain unchanged. Their editor offers a deliberate **Switch to Tailscale SSH** action, which clears the draft pin and requires the verified Tailscale-advertised key before Save. Cancel retains saved state; legacy Keychain items are not erased by migration. Switch/remove keep minimum 44pt native glass controls; the system form, semantic type/colors and navigation remain unchanged. Tailscale SSH must be enabled and allowed by an `accept` rule; interactive `check` sign-in is unsupported.

This form compiles in the real arm64 app (`ios/TestResults/xtool-build-20261011T090542Z.log`). Sixteen Core tests and the keyless/legacy loopback transport regression pass. The simplified build (`440e66d`) was subsequently signed and successfully installed in place over USB after explicit user authorization (`ios/TestResults/deploy-keyless-tailscale-20261011T090750Z.log`). No uninstall or data reset was performed. No launch verification or native screenshots exist for the simplified form; native finish disposition is **recapture**, not visual approval. See [the keyless checklist](TESTING.md#tailscale-ssh-setup--required-native-verification).

## Verification state (Liquid Glass checkpoint)

The Liquid Glass checkpoint compiles, links and packages for arm64 iPhone through the Linux lane. Thirteen platform-neutral Core tests passed at that checkpoint; these do not exercise the UI. Its evidence is `ios/TestResults/xtool-build-20261011T083838Z.log` and the source-derived system in [DESIGN.md](../DESIGN.md).

An independent source review found accessory-height overflow risk and unconditional bottom anchoring that bypassed Follow output. Both named findings were scored resolved at source scope after the fixes. A subsequent source review spotted missing explicit 44pt terminal ownership and PasteButton frames; these are now resolved **at source scope only**. The subsequent keyless setup removes those PasteButtons entirely. No full-surface visual approval is implied.

Packaging fix `5aa5d6d` corrected metadata that recorded linked SDK17 despite actual SDK27. The current Mach-O records SDK 27.0.0 with deployment minimum 17.0.0; plist SDK metadata is 27.0. Six metadata CLI regressions pass. These checks do not establish runtime glass appearance.

No native render has been captured for this refresh. The finish-review disposition is **recapture**: native screenshots are required before a visual verdict. Native light/dark, keyboard, landscape, accessibility-size, Reduce Motion, Reduce Transparency and increased-contrast inspection remain required on the Mac Simulator or physical iPhone. The user authorized USB installation. The refreshed working-tree build carrying UI revision `649628b` was provisioned, signed and successfully installed on the connected iPhone running iOS 26.6.2, superseding the older `ce51440` build. The installed build also includes concurrent SSH work; it is not a pristine checkout of the UI commit alone. No launch verification or UI runtime test has been performed. USB screenshot capture was attempted, but `com.apple.mobile.screenshotr` returned `Invalid service`; there are **no native screenshots and no visual verdict**. No new assets or runtime appearances are canonized; raster provenance remains [ASSETS.md](ASSETS.md).
