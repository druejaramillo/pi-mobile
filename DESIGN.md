---
name: Pi Mobile
description: Native iPhone controls for an existing agent environment.
typography:
  headline:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.headline
  body:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.body
  context:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.subheadline
  notice:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.footnote
  caption:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.caption
  status:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.caption
    fontWeight: medium
  send-symbol:
    fontFamily: San Francisco
    fontSize: SwiftUI.Font.title3
    fontWeight: semibold
  tool-content:
    fontFamily: San Francisco Monospaced
    fontSize: SwiftUI.Font.footnote
rounded:
  tool-result: 18pt
  user-message: 22pt
  permission: 24pt
  composer: 28pt
spacing:
  tight: 4pt
  compact: 8pt
  group: 10pt
  controls: 12pt
  panel: 16pt
  transcript-inset: 20pt
  section: 24pt
components:
  button-primary:
    size: minimum 44pt touch target where explicitly framed
  button-secondary:
    size: minimum 44pt touch target where explicitly framed
  header-icon:
    width: minimum 44pt
    height: minimum 44pt
  header-text:
    height: minimum 44pt
  pane-choice:
    typography: "{typography.context}"
    height: minimum 44pt
  composer-input:
    typography: "{typography.body}"
    rounded: "{rounded.composer}"
    padding: "{spacing.compact}"
  status-capsule:
    typography: "{typography.status}"
    padding: 6pt vertical, 9pt horizontal
  tool-result:
    typography: "{typography.tool-content}"
    rounded: "{rounded.tool-result}"
    padding: 4pt vertical, 14pt horizontal
  user-message:
    typography: "{typography.body}"
    rounded: "{rounded.user-message}"
    padding: "{spacing.panel}"
  permission-panel:
    rounded: "{rounded.permission}"
    padding: "{spacing.panel}"
  directory-row:
    typography: "{typography.headline}"
    padding: 10pt vertical
---

# Pi Mobile native design

## Overview

This is a source-derived native system, **not a visually verified design**. The user chose native iOS rather than a browser-shaped terminal application. SwiftUI platform controls carry the interface; the actual Plannotator page and SwiftTerm renderer retain their own content presentation.

The approved Apple Liquid Glass refresh adds a prettier, more magical native control layer without replacing the Operate identity or navigation. Surface-specific direction remains in [docs/IOS_SURFACE.md](docs/IOS_SURFACE.md). **Key Characteristics:**
- System-owned navigation, semantic colors and Dynamic Type.
- Floating glass controls over opaque, readable content.
- Explicit actions and state-driven feedback, never ambient animation.

Latest arm64 compile/link/package evidence is `ios/TestResults/xtool-build-20261011T083838Z.log`; 13 Core tests and six metadata CLI regressions pass. Packaging fix `5aa5d6d` corrected the recorded linked SDK17 despite actual SDK27: current Mach-O records SDK27.0.0/minimum17.0.0 and plist SDK metadata27.0. Neither build metadata nor source fixes prove native appearance. The refreshed working-tree build carrying UI revision `649628b` was provisioned, signed and successfully installed on the connected iPhone running iOS 26.6.2; it also includes concurrent SSH work. This supersedes the older `ce51440` installation. No launch verification or UI runtime test exists. USB screenshot capture failed with `com.apple.mobile.screenshotr: Invalid service`; there are **no native screenshots**. Native finish disposition: **recapture — screenshots required; no visual verdict**. Light/dark, keyboard, landscape and accessibility-size inspection remain required.

Frontmatter records native points and SwiftUI text styles, not CSS rendering values. Dynamic color roles and material APIs live in `.impeccable/design.json` native extensions; there are intentionally no fixed CSS/hex palette substitutes.

## Colors

### Primary
The app's interactive tint is SwiftUI `.blue`, also used for working status.

### Secondary
Semantic `.orange` means input needed; `.green` means ready/finished; `.red` marks errors, active recording and the confirmed Stop action. These are state roles, not additional brand accents.

### Neutral
Use `.primary` text and `.secondary` context/offline/unknown foregrounds. UIKit `.systemBackground` backs the transcript; `.secondarySystemBackground` backs transcript containers, permission explanations and detail notices; `.secondarySystemGroupedBackground` is the accessible opaque glass-surface fallback. Status capsules use their semantic state color at low opacity, increased under higher contrast.

**The Semantic State Rule.** Status always has text and an SF Symbol, never color alone; cached/unknown agents cannot appear ready. Appearance follows the system. The icon's fixed colors are artwork, not UI palette tokens.

## Typography

Use San Francisco through Dynamic Type system styles, not fixed display sizes. Native navigation owns large directory titles and inline detail titles. Frontmatter records row/dialog headlines, body conversation and draft text, subheadline context, footnote notices/tool output and caption metadata. Status captions use medium weight; transcript speaker labels use semibold captions; the Send SF Symbol uses semibold title3. Commands use monospaced body, terminal keys monospaced subheadline and tool output monospaced footnote; host-key input also stays monospaced.

**The Native Type Rule.** Keep system text styles and SF Symbols; no custom display face. Accessibility-size rows stack title/status and remove title truncation. Draft lines and delivery-menu placement adapt to text size; actual clipping remains unverified.

## Layout

Use native navigation stacks, inset-grouped lists and forms; retain safe areas, standard back gestures and inline detail titles. The observed spacing tokens distinguish compact/group gaps, neighboring controls, panel padding, transcript side insets and conversation/list-section separation; they are native points, not a universal web grid. Directory rows use group spacing and vertical padding; status internals use a 5pt symbol/text gap.

The composer and separate Send sit bottom-aligned in one glass container. iOS 26 uses `safeAreaBar(edge: .bottom, spacing: 0)`; earlier iOS uses `safeAreaInset`. A viewport-bounded scrollable accessory holds dialogs and the dock above the keyboard; permission text remains independently scrollable. No fixed screen breakpoint is authored.

Controls require at least 44pt touch targets. Explicit minimum sizing exists on draft, Send, command, follow-output, cancellation, permission, header, pane-choice, terminal ownership/key and both PasteButton controls. The missing explicit terminal ownership and PasteButton frames are resolved at source scope only; native hit testing still requires on-device checks, especially PasteButton.

## Elevation & Depth

**The Controls-Only Glass Rule.** Apple's iOS 26 `.glassEffect(.regular, in:)`, `.glass` and `.glassProminent` belong to controls; transcript, directory content and permission explanations stay opaque. Glass coverage includes navigation/menu/header actions, as explicitly requested by the user; it is not limited to the composer. Native bars remain system-owned. Explicit glass toolbar buttons use `mobileGlassHeaderItem` to hide only their iOS 26 shared toolbar background, avoiding a second glass layer; native back navigation is not replaced. `GlassEffectContainer(spacing: 8)` shares rendering across adjacent controls without merging their resting shapes.

Earlier iOS uses `.regularMaterial` surfaces and `.bordered`/`.borderedProminent` buttons. The authored surface modifier switches to an opaque grouped surface under Reduce Transparency or increased contrast, with a primary-opacity outline (0.2 opacity, 0.5pt stroke). Native button styles retain system accessibility, disabled, pressed and destructive-role behavior. No decorative shadow or imitation CSS glass is authored.

**The State-Only Motion Rule.** Dictation and iOS 26 Agent/Terminal selection changes use `.smooth(duration: 0.25)` unless Reduce Motion is enabled; status/dictation symbol bounces are state-triggered and suppressed under Reduce Motion. Selection haptics follow native tab/pane changes; success feedback follows the host acknowledgment. Navigation pushes/sheets remain system transitions. Streaming text is not animated; no ambient loops or custom entrance choreography.

## Shapes

System lists, forms, sheets and rounded-border dialog fields own their shapes. Status is a text-and-symbol capsule, not a status dot. Text header actions, pane choices and terminal keys use native capsules; symbol-only header actions and Send use circles. Header icons are explicitly at least 44pt square; header text actions are at least 44pt high. Frontmatter corners are component-specific observations: continuous composer, softer user message, tighter tool disclosure and clipped permission panel. Do not generalize those content containers into nested cards for platform sections.

## Components

- **Buttons:** native glass/prominent variants with earlier-iOS bordered fallbacks. Primary setup actions use large capsules; Send is a separate prominent circle. Inner composer commands/dictation remain borderless. Preserve native disabled/pressed/focus behavior, not invented web states.
- **Directory rows / status:** headline and readable location context on opaque list rows; semantic text-and-symbol capsules, with cached locations explicitly marked and status stacked at accessibility sizes.
- **Headers / menus:** `mobileGlassHeaderControl` covers refresh/add/edit, review menu, Stop, Follow output and error dismissal; sheet Done/Cancel/Save/Back actions use text capsules, with Save prominent. Explicit toolbar items hide shared background only on iOS 26. Menu contents and native back gestures remain platform-owned.
- **Machine forms / inline actions:** grouped native sections and secure fields; key import/remove/paste, directory edit, machine refresh/edit and detail reconnect use native glass styles with bordered fallbacks. Both native PasteButtons retain system paste authorization and explicit 44pt minimum frames. Generic glass styling and hit testing of PasteButton remain runtime-only risks, not verified appearances.
- **Composer:** plain multiline body field inside the continuous glass surface, command picker, editable dictation and explicit Send. Recording/errors stay near the draft; progress replaces the Send arrow while pending. Disable Send for empty draft, dialog, pending send or disconnected host. Clear only the submitted draft after acknowledgment, not newly typed text.
- **Transcript containers:** selectable opaque body text; user messages on a secondary surface, assistant text directly on the transcript, monospaced tool output inside a disclosure. Speaker labels identify actual roles, not decorative eyebrows.
- **Dialogs:** original prompt disclosure and supported native response field on an opaque panel; only the advertised action buttons use glass capsules. Keep host-owned labels, grant widths and confirmation steps.
- **Terminal:** read-only first, explicit input control and separate takeover confirmation. Horizontal glass key controls use SF Symbols and text; SwiftTerm retains its own renderer.
- **Navigation / reviews:** Agents/Machines/Settings remain peer tabs with native stacks. iOS 18+ uses the native `Tab` API; iOS 17 retains `.tabItem`, and iOS 26 enables `.onScrollDown` tab minimization. Agent/Terminal uses two glass capsule choices on iOS 26 (selected choice prominent, `.isSelected` accessibility trait, medium subheadline, minimum 44pt height), with a segmented fallback on iOS 17–25. Selection changes the view, not input ownership. Reviews retain the real Plannotator page and glass return-to-agent action; sheets and back gestures remain native.

## Do's and Don'ts

### Do:
- Do preserve platform navigation, semantic colors, Dynamic Type and SF Symbols.
- Do keep glass on controls, content opaque and accessibility fallbacks native.
- Do distinguish unknown/unreachable state from a verified empty directory.
- Do tie motion to state, honor Reduce Motion and await host acknowledgment for success feedback.
- Do capture native screenshots in both appearances, keyboard/landscape and large text sizes before claiming visual readiness.

### Don't:
- Don't use browser screenshots, fake HTML/CSS glass or mock conversations as evidence of the native app.
- Don't substitute fixed hex palettes for dynamic system colors or UI tokens for icon artwork.
- Don't add decorative dashboard metrics, ambient animation, custom navigation gestures or notification controls.
- Don't treat compilation or resolved source findings as a visual verdict.

Source: `ios/PiMobile/App/PiMobileApp.swift` and `ios/PiMobile/Views`, especially `MobileGlassStyle.swift`, `MobilePaneSurfacePicker.swift`, `AgentStatusLabel.swift`, `AgentConversationView.swift`, `GlobalAgentsView.swift` and `PaneDetailView.swift`; form/dictation patterns sampled in `MachineEditorView.swift` and `MobileSettingsView.swift`. Raster provenance remains [docs/ASSETS.md](docs/ASSETS.md); icon appearance is not verified.
