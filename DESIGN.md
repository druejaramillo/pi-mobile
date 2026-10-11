---
name: Pi Mobile
description: Native iPhone controls for an existing agent environment.
---

# Pi Mobile native design

## Overview

This is a source-derived native baseline, **not a visually verified design**. The user chose native iOS rather than a browser-shaped terminal application. SwiftUI platform controls carry the interface; the actual Plannotator page and SwiftTerm renderer retain their own content presentation.

No replacement visual world is being introduced. Simulator screenshots, device inspection and independent finish review are pending the Mac build. Surface-specific navigation and workflow belong in [docs/IOS_SURFACE.md](docs/IOS_SURFACE.md).

## Colors

Use semantic SwiftUI foregrounds and system surfaces, not fixed light-mode hex values. The app's interactive tint is `.blue`. Status uses orange for input needed, blue for working, green for ready/finished and secondary foreground for offline/unknown. Every status also has a text label; color is not the only signal. Errors use `.red`.

The app follows system appearance. The icon's fixed colors are artwork, not UI palette tokens.

## Typography

Use San Francisco through system text styles. Current hierarchy: navigation titles, row headlines, body conversation text, subheadline context, footnote notices and caption status. Use monospaced system text only for commands, host keys and terminal/tool content. Dynamic Type is required; actual clipping and accessibility-size layout are not yet checked.

## Layout

Use native navigation stacks, platform lists and forms. Respect safe areas and the standard back gesture. Detail screens have inline titles. Conversation entries have 24pt separation; most inline groups use 8–10pt gaps and standard horizontal padding.

Controls require at least 44pt touch targets. Explicit target sizing exists on command, cancellation and terminal-key controls; verify every remaining native/inline control on-device. Portrait, landscape, keyboard presentation and large Dynamic Type need the same native inspection pass.

## Elevation & Depth

Use platform `.bar` and `.thinMaterial` for control/error surfaces. Do not add decorative shadows or custom glass layers. Navigation pushes and sheets use system transitions; no custom entrance animation is authored.

## Shapes

System buttons, rounded text fields, list rows and sheets own their shapes. Status dots are small circles accompanied by labels. Do not turn platform sections into nested custom cards.

## Components

- **Directory rows:** headline, readable location context and text status; cached locations are explicitly marked.
- **Machine forms:** grouped native sections, secure password/passphrase fields and a file importer for keys.
- **Composer:** editable text, command picker, dictation and explicit Send. Loading/error state stays near the action.
- **Dialogs:** disclosure of the original prompt, advertised action buttons and a native field only when supported. Do not hide confirmation or grant-width steps.
- **Terminal:** read-only first, explicit input control and separate takeover confirmation. Phone key controls use SF Symbols and text.
- **Reviews:** a dismissible navigation sheet containing the real page, with a return-to-agent action.

## Do's and Don'ts

- Do preserve platform navigation, semantic colors, Dynamic Type and SF Symbols.
- Do distinguish unknown/unreachable state from a verified empty directory.
- Do inspect native screenshots in both appearances and at large text sizes before claiming visual readiness.
- Don't use browser screenshots or mock conversations as evidence of the native app.
- Don't add decorative dashboard metrics, custom navigation gestures or notification controls.

Source: `ios/PiMobile/App` and `ios/PiMobile/Views`. Raster provenance: [docs/ASSETS.md](docs/ASSETS.md).
