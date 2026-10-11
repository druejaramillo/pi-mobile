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

The arm64 app compile/link/package passed and source review resolved both named findings; neither is visual proof. No refresh screenshots or runtime test exist. Native finish-review disposition: **recapture — screenshots required; no visual verdict**. Light/dark, keyboard, landscape and accessibility-size inspection remain required.

Frontmatter records native points and SwiftUI text styles, not CSS rendering values. Dynamic color roles and material APIs live in `.impeccable/design.json` native extensions; there are intentionally no fixed CSS/hex palette substitutes.

## Colors

### Primary
The app's interactive tint is SwiftUI `.blue`, also used for working status.

### Secondary
Semantic `.orange` means input needed; `.green` means ready/finished; `.red` marks errors and active recording. These are state roles, not additional brand accents.

### Neutral
Use `.primary` text and `.secondary` context/offline/unknown foregrounds. UIKit `.systemBackground` backs the transcript; `.secondarySystemBackground` backs transcript containers, permission explanations and detail notices; `.secondarySystemGroupedBackground` is the accessible opaque glass-surface fallback. Status capsules use their semantic state color at low opacity, increased under higher contrast.

**The Semantic State Rule.** Status always has text and an SF Symbol, never color alone; cached/unknown agents cannot appear ready. Appearance follows the system. The icon's fixed colors are artwork, not UI palette tokens.

## Typography

Use San Francisco through Dynamic Type system styles, not fixed display sizes. Native navigation owns large directory titles and inline detail titles. Frontmatter records row/dialog headlines, body conversation and draft text, subheadline context, footnote notices/tool output and caption metadata. Status captions use medium weight; transcript speaker labels use semibold captions; the Send SF Symbol uses semibold title3. Commands use monospaced body, terminal keys monospaced subheadline and tool output monospaced footnote; host-key input also stays monospaced.

**The Native Type Rule.** Keep system text styles and SF Symbols; no custom display face. Accessibility-size rows stack title/status and remove title truncation. Draft lines and delivery-menu placement adapt to text size; actual clipping remains unverified.

## Layout

Use native navigation stacks, inset-grouped lists and forms; retain safe areas, standard back gestures and inline detail titles. The observed spacing tokens distinguish compact/group gaps, neighboring controls, panel padding, transcript side insets and conversation/list-section separation; they are native points, not a universal web grid. Directory rows use group spacing and vertical padding; status internals use a 5pt symbol/text gap.

The composer and separate Send sit bottom-aligned in one glass container. iOS 26 uses `safeAreaBar(edge: .bottom, spacing: 0)`; earlier iOS uses `safeAreaInset`. A viewport-bounded scrollable accessory holds dialogs and the dock above the keyboard; permission text remains independently scrollable. No fixed screen breakpoint is authored.

Controls require at least 44pt touch targets. Explicit minimum sizing exists on draft, Send, command, follow-output, cancellation, permission and terminal-key controls; native controls still require on-device target, keyboard and accessibility-size checks.

## Elevation & Depth

**The Controls-Only Glass Rule.** Apple's iOS 26 `.glassEffect(.regular, in:)`, `.glass` and `.glassProminent` belong to controls; transcript, directory content and permission explanations stay opaque. System navigation/tab bars adopt native glass without custom replacements. `GlassEffectContainer(spacing: 8)` shares rendering across adjacent controls without merging their resting shapes.

Earlier iOS uses `.regularMaterial` surfaces and `.bordered`/`.borderedProminent` buttons. The authored surface modifier switches to an opaque grouped surface under Reduce Transparency or increased contrast, with a primary-opacity outline (0.2 opacity, 0.5pt stroke). Native button styles retain system accessibility, disabled, pressed and destructive-role behavior. No decorative shadow or imitation CSS glass is authored.

**The State-Only Motion Rule.** Dictation changes use `.smooth(duration: 0.25)` unless Reduce Motion is enabled; status/dictation symbol bounces are state-triggered and suppressed under Reduce Motion. Selection haptics follow native tab/pane changes; success feedback follows the host acknowledgment. Navigation pushes/sheets remain system transitions. Streaming text is not animated; no ambient loops or custom entrance choreography.

## Shapes

System lists, forms, sheets and rounded-border dialog fields own their shapes. Status is a text-and-symbol capsule, not a status dot. Actions and terminal keys use native capsules; Send uses a circle. Frontmatter corners are component-specific observations: continuous composer, softer user message, tighter tool disclosure and clipped permission panel. Do not generalize those content containers into nested cards for platform sections.

## Components

- **Buttons:** native glass/prominent variants with earlier-iOS bordered fallbacks. Primary setup actions use large capsules; Send is a separate prominent circle. Inner composer commands/dictation remain borderless. Preserve native disabled/pressed/focus behavior, not invented web states.
- **Directory rows / status:** headline and readable location context on opaque list rows; semantic text-and-symbol capsules, with cached locations explicitly marked and status stacked at accessibility sizes.
- **Machine forms:** grouped native sections, secure password/passphrase fields and a file importer for keys.
- **Composer:** plain multiline body field inside the continuous glass surface, command picker, editable dictation and explicit Send. Recording/errors stay near the draft; progress replaces the Send arrow while pending. Disable Send for empty draft, dialog, pending send or disconnected host. Clear only the submitted draft after acknowledgment, not newly typed text.
- **Transcript containers:** selectable opaque body text; user messages on a secondary surface, assistant text directly on the transcript, monospaced tool output inside a disclosure. Speaker labels identify actual roles, not decorative eyebrows.
- **Dialogs:** original prompt disclosure and supported native response field on an opaque panel; only the advertised action buttons use glass capsules. Keep host-owned labels, grant widths and confirmation steps.
- **Terminal:** read-only first, explicit input control and separate takeover confirmation. Horizontal glass key controls use SF Symbols and text; SwiftTerm retains its own renderer.
- **Navigation / reviews:** unchanged Agents/Machines/Settings tabs and navigation stacks, segmented Agent/Terminal detail, standard sheets and back gestures. Reviews contain the real Plannotator page with a return-to-agent action.

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

Source: `ios/PiMobile/App/PiMobileApp.swift` and `ios/PiMobile/Views`, especially `MobileGlassStyle.swift`, `AgentStatusLabel.swift`, `AgentConversationView.swift`, `GlobalAgentsView.swift` and `PaneDetailView.swift`; form/dictation patterns sampled in `MachineEditorView.swift` and `MobileSettingsView.swift`. Raster provenance remains [docs/ASSETS.md](docs/ASSETS.md); icon appearance is not verified.
