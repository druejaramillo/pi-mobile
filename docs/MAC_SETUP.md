# Build on your Mac

## Prerequisites

- **Xcode 26 or newer with Swift 6.2+** (required by pinned SwiftTerm); app language mode is Swift 5.
- iPhone running iOS 17 or newer. Physical-device Parakeet inference is a required verification step, not proven by the platform minimum.
- XcodeGen installed on the Mac (`brew install xcodegen` if you choose Homebrew).
- Tailscale connected on the iPhone and each host.

## Pull and compile

```sh
gh repo clone druejaramillo/pi-mobile
cd pi-mobile
./tools/build-ios.sh
```

This generates `ios/PiMobile.xcodeproj`, resolves pinned library revisions and builds an unsigned Simulator target. The script neither installs tools nor changes provisioning. Open the generated project in Xcode, select your development team in Signing & Capabilities, connect your iPhone, choose it as destination and Run. The default bundle id is `com.druejaramillo.pi-mobile`; change it locally if your team requires another id. No Push Notifications or background modes are needed.

To get subsequent checkpoints:

```sh
git pull --ff-only
./tools/build-ios.sh
```

## Run the approved tests

Host protocol tests run with `npm --prefix host test`. The app-hosted XCTest target requires the Mac:

```sh
xcrun simctl list devices available
./tools/test-ios.sh 'platform=iOS Simulator,id=<chosen-UDID>'
```

Choose a fresh Simulator with no saved machines. The script runs Core package tests plus the app-hosted session/dictation suite and saves `.xcresult` evidence under `ios/TestResults/`. Thirteen Core XCTest methods have compiled/passed on Linux; the eighteen app-hosted tests remain uncompiled/unrun. Successful SSH/audio/review paths still need the device checklist. A parallel [Linux xtool lane](LINUX_SETUP.md) is available for device builds after supplying Apple's SDK. See [TESTING.md](TESTING.md).

## Add machines

Install the host bridge following [HOST_SETUP.md](HOST_SETUP.md). Add each machine using its Tailscale DNS name/IP, SSH username, Herdr session and a verified `ssh-ed25519` host public key. Obtain that public key directly on a trusted host from `/etc/ssh/ssh_host_ed25519_key.pub`; do not trust a network scan automatically. Choose SSH key and use **Private key → Paste** or **Import OpenSSH private key**. After the key is ready, enter or use **Paste** for its passphrase if encrypted. The private key is never displayed; the passphrase remains masked. Alternatively, provide an SSH password. Credentials are stored in device-only Keychain. Encrypted key support is described in [IOS_TRANSPORT.md](IOS_TRANSPORT.md).

Tailscale networking alone does not replace SSH credentials. [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh) is a separate host feature that can authenticate without client SSH keys; the app does not yet expose a keyless setup option. Tailscale SSH also uses its own host key, not the OpenSSH host key at `/etc/ssh/ssh_host_ed25519_key.pub`. Never substitute a different server's key or bypass host verification.

The global Agents tab is the launch screen. Refresh checks every configured machine independently. An offline host retains explicitly stale locations cached during this app process; the directory never treats an unreachable host as verified empty. Tap any agent to open its pane directly. Machines remains available for workspaces/tabs and ordinary shell panes.

## Parakeet

Settings → Download and prepare Parakeet explicitly fetches the model. Allow microphone access, then use Dictate in the composer. Stop returns an editable draft; nothing is sent automatically. VoxType command aliases and punctuation are local. The desktop OpenAI cleanup script and its credentials are not copied. See [DICTATION.md](DICTATION.md).

## Required device verification

The Linux authoring environment cannot run these checks:

1. Connect to all three machines, see their running agents, jump to a specific workspace/tab/pane.
2. Attach to a Pi process already running at your desk. Send a normal prompt and an extension command; verify the desktop sees the same conversation.
3. Resolve a permission request, including the existing double-confirm behavior, denial reason and session-scope steps; make a desktop choice while a phone view is stale and verify the phone cannot approve a different request.
4. Observe a terminal without changing desktop input ownership; request control explicitly, type, resize, release, navigate back and verify the desktop can regain control.
5. Open a local and a remote Plannotator review, annotate/submit, return to the same Pi agent. External links must not escape the SSH-forwarded review origin inside the web view.
6. Download Parakeet once, disconnect internet and dictate speech plus a Pi command. Verify no upload, accurate 16 kHz conversion, stop/cancel, audio interruptions and five-minute cap on hardware.
7. Lock the iPhone/kill the app/switch networks. Host processes survive; drafts survive; reopening refreshes read state without replaying prompts or permission decisions.
8. Inspect portrait/landscape, large Dynamic Type, VoiceOver and both appearances. Capture actual Simulator/device screenshots, not browser mockups.

Source and parser checks are not substitutes for this pass. Record results in BUILD_STATUS.md before calling the app device-verified.
