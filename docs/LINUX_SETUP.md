# Linux build and iPhone deployment with xtool

This is a parallel **physical-iPhone** build lane. The XcodeGen/Mac project remains unchanged. **The real unsigned arm64 app now builds successfully, including repeat builds.** The user supplied Apple's SDK and configured signing credentials locally. No installation or iPhone runtime verification has occurred. See [BUILD_STATUS.md](BUILD_STATUS.md).

## What is ready on this machine

- Private Swift 6.4.0 compiler and xtool 1.21.0, under `~/.local/share/pi-mobile/toolchains/`.
- Compiler/xtool downloads verified; Ubuntu ncurses and Arch XML compatibility libraries are private to the compiler, not fake system-library symlinks. No shell profile or global Swift installation changed.
- `usbmuxd` 1.1.1-4 installed through desktop authorization. Existing libimobiledevice tooling remains available.
- User-supplied Xcode 27 slim SDK installed. Seven Core XCTest methods pass on native Linux; the complete iOS app and native dependencies compile/link/package successfully.
- `ios/Package.swift`, `ios/Package.resolved` and `ios/xtool.yml`; the existing microphone/local-network privacy strings, iPhone-only family, icon and VoxType profile are retained.
- Exact original SwiftTerm revision plus a small checked-in manifest patch. `SWIFTTERM_TARGET_APPLE=1` includes Apple/UIKit sources when the manifest runs on Linux; ordinary host builds keep their original exclusions. No terminal implementation or dependency revision is changed.
- FluidAudio's supported `traits: []` disables its optional **TTS** NeMo normalizer. Parakeet ASR and our deterministic VoxType cleanup remain unchanged. SwiftPM nevertheless downloaded/checksummed the declared 87 MB xcframework during resolution; disabled linkage is **not** proof that no binary was fetched. Parakeet model weights were not downloaded.

## 1. Private tool setup

```sh
./tools/setup-ios-linux.sh
source tools/xtool-environment.sh
swift --version
xtool --version
```

The bootstrap downloads about 1.2 GB and expands several GB under the private tool directory. It installs no Arch packages and does not change shell startup files. On this Arch x86_64 machine it also extracts exact compatibility libraries from pinned packages. Future Arch/ICU ABI changes may require revisiting that pin; do not create incompatible system symlinks to bypass an error.

The bootstrap checks hashes, uses owned staging files and locks, and refuses unexpected dependency-cache edits. Interrupted/diagnostic extraction receipts are retained rather than recursively deleting user paths. `PI_MOBILE_TOOLCHAIN_ROOT` can select a different private tool directory.

## 2. Supply Apple's SDK

Download **Xcode 27 `.xip`** from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode) in your browser. You must handle Apple authentication and license acceptance. xtool does not include Apple's SDK, and we do not source it from unofficial mirrors.

```sh
./tools/setup-ios-linux.sh --sdk /absolute/path/Xcode_27.xip
source tools/xtool-environment.sh
xtool sdk status
```

This extracts a slim Darwin SDK into xtool/SwiftPM's user-level SDK location. It refuses to replace an existing SDK automatically. Slim SDKs cannot be updated in place; a future replacement needs a deliberate decision, not silent deletion.

## 3. Compile the real iOS app

```sh
./tools/build-ios-linux.sh
```

The command prepares the exact patched SwiftTerm source, derives a plist without Xcode `$(...)` literals, then invokes **`xtool dev build` without signing**. It never authenticates, deploys or automatically downloads an SDK. Missing SDK/tool prerequisites fail with exit 2 rather than an interactive surprise.

Expected output after a successful build:

- `ios/xtool/PiMobile.app` — unsigned device app.
- `ios/TestResults/xtool-build-<UTC timestamp>.log` — real build evidence.

**Verified:** full and repeated builds succeed, including a source-timestamp rebuild. The output is a Mach-O arm64 executable targeting iOS 17, with the exact icon/dictation profile and FluidAudio resource bundle. No third-party dynamic framework is required by its load commands. This is compile/link/package evidence, not device execution or an app-hosted XCTest pass.

### If an earlier checkout failed at `ld.lld -version_details`

Update the checkout, then rerun:

```sh
./tools/setup-ios-linux.sh
./tools/build-ios-linux.sh
./tools/build-ios-linux.sh
```

Rerunning setup without `--sdk` preserves the installed SDK and signing credentials. Two failures were reproduced and fixed:

- The private LLVM linker could not load `libxml2.so.2`. Setup now exposes the verified compatibility library in LLVM's own RUNPATH as well as Swift's.
- Swift 6.4's cached cross-target build path probed the Linux ELF linker with a Darwin-only option. The build script uses xtool's supported custom-bin seam to pass `--disable-build-manifest-caching` to SwiftPM. The shims clear that override before invoking Swift so it cannot redirect the manifest runtime. SwiftBuild descriptions and compiled objects remain reusable; no build-directory deletion, SDK patch, compiler replacement or signing change is needed.

Use the repository build script, not bare `xtool dev build`, until this version-specific caching workaround can be removed. The unwrapped command was retained as a failing control; the fixed command passed four runs.

## 4. Configure signing yourself

You already have Apple Developer membership. The [xtool guide](https://github.com/xtool-org/xtool/blob/1.21.0/Documentation/xtool.docc/Installation-Linux.md) recommends a **Team App Store Connect API key with App Manager role**, using public APIs rather than Apple-ID password login.

Generate/download the key in App Store Connect, keep it private outside the repository, then run in your own terminal:

```sh
source tools/xtool-environment.sh
xtool auth login --mode key
```

Enter Key ID, Issuer ID and the private `.p8` file path at the prompts. **Do not paste the key/password into this conversation or Git.** xtool retains credentials in its own user storage; protect that storage and key file. We do not capture the authentication transcript.

Provisioning can create/register app IDs, certificates, profiles and the selected device in your developer account. If xtool asks to revoke existing certificates, stop and assess the impact on your Mac/other apps—do not automatically agree.

## 5. Select and deploy to your iPhone

Connect by **USB**, unlock and accept **Trust This Computer** on the phone. Enable **Settings → Privacy & Security → Developer Mode** and complete its required restart/confirmation.

```sh
source tools/xtool-environment.sh
xtool devices --usb --no-wait
idevice_id -l
./tools/deploy-ios-linux.sh <chosen-iPhone-UDID>
```

The deploy command requires one explicit USB UDID and a successfully built app. It provisions/signs a staged copy and installs once; no automatic device selection, wireless pairing setup or retry loop is added. xtool may prefix the installed bundle ID with `XTL-…`; the Mac-signed build can therefore be a separate install with separate app data. Open **Pi Mobile** manually after installation; a successful install is not proof it runs.

If USB discovery fails, first check `usbmuxd`, cable/unlock/trust and `idevicepair validate`. Pairing/Developer Mode are human/device actions; do not reset pairing records or unrelated services blindly.

## Verification and evidence

```sh
source tools/xtool-environment.sh
swift test --package-path ios/PiMobileCore --jobs 4
npm --prefix host test
```

Evidence under ignored `ios/TestResults/` includes `xtool-repro-first.log` (original failure), `linker-probe-linux.stderr`, `xtool-default-cache-contrast.log` (failing unwrapped control), `xtool-cache-fix-first-isolated.log`, `xtool-cache-fix-repeat.log`, `xtool-cache-fix-third.log` and `xtool-cache-fix-source-repeat.log` (successful real builds), plus `core-post-sdk-fix.log` (7 passing tests) and `host-post-sdk-fix.tap` (23 passing tests). The SwiftTerm manifest before/after evidence is also retained. Build evidence is not UIKit/Metal/device-runtime proof.

Once installed, run the real-device checklist in [MAC_SETUP.md](MAC_SETUP.md): same-agent prompting/dialogs, disconnect ownership, host-key rejection, control/takeover, real review assets/WebSockets, offline Parakeet capture/inference/cancellation/cap delivery, memory/thermals and light/dark/accessibility. No live host agent is installed/restarted by these build/deploy commands.

## Download provenance

Pinned SHA-256 values are in `tools/setup-ios-linux.sh`:

- xtool AppImage: GitHub 1.21.0 release asset digest.
- Swift archive: verified against the official detached signature before pinning. Signing fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`; the valid release signature was created before that key expired. Verification receipt: `~/.local/share/pi-mobile/toolchains/verification/swift-6.4.0-verification.txt`.
- Ubuntu ncurses/tinfo: exact 6.3-2ubuntu0.3 package hashes published by Ubuntu.
- Arch libxml2-legacy: exact 2.13.9-2 package, verified against the installed Arch keyring; signer fingerprint `ADC8A1FCC15E01D45310419E94657AB20F2A092B`.

No Docker, global toolchain replacement, Apple credentials, SDK archive, provisioning material or build products are committed. System change in this checkpoint is the authorized `usbmuxd` package and its normal package hooks.
