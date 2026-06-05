# penpal

> ## ⚠️ Before you start — what YOU (the human) must do
>
> An AI agent can run every command in this README, but a few things require **you**, because macOS and Apple security won't let any script do them. Read this first.
>
> **You need installed first:**
> - **Xcode** (to build the iPad app)
>
> **Steps only a human can do (your AI agent will pause and ask for these):**
> - Open in Xcode, set **your own Apple Team ID**, and build to a **physical iPad** (needs Apple Pencil + on-device frameworks).
> - Trust the developer cert on the iPad: Settings → General → VPN & Device Management.
> - Paste an **Anthropic API key (billing enabled)** into the app's Settings — the notebook does nothing without it.
> - *(Optional)* add your own Spotify client ID for the Spotify integration.

> **Experimental software. This project is a personal research prototype — it is unstable, under active development, and likely has bugs. Use at your own risk.**

**Write on your iPad. Claude writes back.** penpal is an iPadOS app where you write with Apple Pencil on a canvas, and an AI reads your handwriting and responds — by animating handwritten text back onto the same page.

There are no buttons. Every action — opening settings, switching notebooks, toggling debug, sending a text, dimming the lights, creating a calendar event — is triggered by what you write.

---

## What It Does

- **Handwriting in, handwriting out** — Write anything in your own hand. Claude sees the canvas, replies in a hand-drawn style that matches yours.
- **Buttonless interface** — No UI chrome. Write `settings`, `clear`, or `debug` to toggle panels. Write `thicker pen` or `make background white` to change appearance. The app interprets your intent.
- **Persistent notebooks** — Each notebook is a separate page that auto-saves. Switch between them from the gallery view.
- **Integrations** — Trigger real-world actions by writing them:
  - "lights off" / "dim to 50%" / "make it blue" → Philips Hue
  - "text mom I'm on my way" → iMessage compose
  - "remind me to call dentist tomorrow" → Apple Reminders
  - "todo: milk, eggs, bread" → Reminders list
  - "meeting with Sarah Thursday 2pm" → Calendar event
  - "play some jazz" → Spotify
- **Games** — Draw a tic-tac-toe grid and an X. Claude draws an O back.

---

## Requirements

- iPadOS 17.0+
- An iPad with Apple Pencil support
- An [Anthropic API key](https://console.anthropic.com/) (you provide your own — stored in iOS Keychain, never sent anywhere except Anthropic)
- A Mac with Xcode 15+ to build and install
- Either a **free Apple ID** (sideloading works, see "About signing" below) or a paid Apple Developer account

---

## Privacy

- **Your handwriting and canvas screenshots** are sent to the Anthropic API for transcription and response. Nothing is sent to any server operated by this project.
- **Your API key** is stored only in the iOS Keychain on your device.
- **Integrations are local-first** where possible: Hue talks directly to your bridge over your LAN; Reminders and Calendar use Apple's on-device EventKit.
- **No telemetry, no analytics, no crash reporting.**

---

## About signing (free vs. paid Apple Developer)

You don't need a paid Apple Developer account to run penpal on your own iPad — a free Apple ID works. The tradeoffs:

| | Free Apple ID | Paid Developer Program ($99/yr) |
|---|---|---|
| Install on personal devices | ✅ | ✅ |
| Re-sign required every | **7 days** | 1 year |
| Active app IDs at once | 3 | unlimited |
| TestFlight / App Store | ❌ | ✅ |

For just trying penpal on your own iPad, the free path is fine — you'll just need to rebuild and reinstall once a week.

---

## Setup

### 1. Clone

```bash
git clone https://github.com/brianharms/penpal
cd penpal
```

### 2. Open in Xcode and set your team

```bash
open penpal.xcodeproj
```

The project's bundle ID is `com.magicnotebook.penpal` and the committed `DEVELOPMENT_TEAM` is the original author's. **You'll need to change both** before the project will build for you:

1. Select the `penpal` target → **Signing & Capabilities**
2. Pick **your team** from the dropdown (sign in with your Apple ID if it isn't listed)
3. Change the **Bundle Identifier** to something unique (e.g. `com.YOURNAME.penpal`) — Apple won't let two developers share the same one

### 3. Build & install on your iPad

The easiest path is to just hit **Run** in Xcode with your iPad selected as the target. That handles signing, install, and launch automatically.

If you'd rather use the command line, this repo includes a `deploy.sh` script. Open it and read the comment block at the top — it walks through exactly which two values to fill in (`DEVICE_ID` and `SIGN_ID`), and which `xcrun` / `security` commands to run to discover them. Then:

```bash
./deploy.sh
```

> **Tip:** if you're using Claude Code, just paste the comment block from `deploy.sh` into your terminal and Claude will run the discovery commands and fill in the placeholders for you.

### 4. First launch — paste your Anthropic API key

Open the app, tap to open the Settings panel (or just write `settings` on the canvas), and paste in your key from [console.anthropic.com](https://console.anthropic.com/). The key is stored in the iOS Keychain. Optionally add a [Resend](https://resend.com/) key if you want the email integration.

### 5. Optional integrations

- **Philips Hue** — write `connect hue` on the canvas. The app discovers your bridge; press the bridge button when prompted, then write `pair hue`.
- **Spotify** — requires a Spotify Premium account and the Spotify iOS app installed. The app uses [SpotifyiOS SPM](https://github.com/spotify/ios-sdk) to talk to the running Spotify app over IPC.
- **Reminders / Calendar / Contacts / iMessage** — granted via system permission prompts on first use.

---

## How handwriting commands work

penpal sends a screenshot of the visible canvas plus a system prompt to Claude on every "stroke pause." Claude replies with structured JSON that can include:

- `text` — handwritten reply animated stroke-by-stroke onto the canvas
- `command` — a verb (`settings`, `clear`, `debug`, `notebooks`, `share`, …)
- `settings` — partial setting changes (`{"strokeWidth": 9}`, `{"backgroundColor": "white"}`)
- One of the integration payloads (`hue`, `message`, `reminder`, `todo`, `calendar_event`, `game_move`)

The viewmodel routes each one to the right service and writes a confirmation back onto the canvas in your handwriting style.

Examples that just work:

| You write | What happens |
|---|---|
| `Hi` | Claude writes `Hi! :)` back |
| `clear` | Canvas wipes |
| `settings` | Settings panel slides in |
| `thicker pen` | Stroke width increases |
| `make it dark` | Theme switches to dark canvas |
| `lights off` | Hue lights turn off |
| `text Sarah running 10 late` | iMessage compose sheet opens, prefilled |
| `remind me to call dentist tomorrow at 3` | Reminder created |
| Draws a tic-tac-toe grid + X | Claude draws an O |

---

## Architecture

```
Apple Pencil → PKCanvasView → screenshot on stroke pause → Claude API
                                                              ↓
canvas ← stroke-by-stroke animation ← parse JSON response ← {text, command, settings, integration}
                                                              ↓
                                                        HueService / ReminderService /
                                                        CalendarService / ContactService /
                                                        SpotifyService / EmailService
```

### Key Files

| Area | File | Purpose |
|---|---|---|
| App entry | `penpalApp.swift` | App entry, URL routing for OAuth callbacks |
| Main view | `ContentView.swift` | ZStack of canvas + overlays + settings panel + debug overlay |
| Canvas | `CanvasView.swift` | UIViewRepresentable wrapping `PKCanvasView` |
| Logic | `CanvasViewModel.swift` | Stroke tracking, API calls, response animation, command dispatch |
| Claude | `ClaudeService.swift` | Sends screenshots, parses structured JSON responses |
| Handwriting | `HandwritingGenerator.swift` | Converts text into `PKStroke` arrays that look hand-drawn |
| Style | `HandwritingStyle.swift` | Detects/applies styles (friendly, neat, casual, energetic) |
| Single-stroke font | `SingleLineFont.swift` | Custom single-stroke font data |
| Glow overlay | `MagicGlowOverlay.swift` | Animated glow on user strokes while AI is thinking |
| Notebook model | `Notebook.swift` | Data model + `NotebookStore` (UserDefaults JSON persistence) |
| Notebook UI | `NotebookGalleryView.swift` | Notebook selection screen |
| Integrations | `HueService.swift` | Philips Hue bridge discovery, auth, light control |
| Integrations | `ContactService.swift` | Contacts framework lookup for iMessage |
| Integrations | `ReminderService.swift` | EventKit reminders + todo lists |
| Integrations | `CalendarService.swift` | EventKit calendar events |
| Integrations | `SpotifyService.swift` | Spotify Web API + SPTAppRemote IPC control |
| Integrations | `EmailService.swift` | Resend API for outbound email |
| Theming | `CanvasTheme.swift` | Light/dark canvas themes, paper textures |
| Sharing | `ShareSheet.swift` | Canvas export via UIActivityViewController |
| Keychain | `KeychainHelper.swift` | Secure API key storage |

---

## Troubleshooting

**Build fails with "No matching profiles found"** — You're hitting the committed bundle ID / development team. Change both as described in setup step 2.

**App launches but nothing happens when I write** — Open Settings (write `settings`), check that your Anthropic API key is filled in. Check that you have credits on your Anthropic account.

**Reminders / Calendar / Contacts integrations don't fire** — Make sure you granted the permissions when iOS first prompted. If you denied, you can re-enable them in Settings → Privacy & Security on the iPad.

**Spotify "no devices found"** — Make sure the Spotify app is installed on the iPad and that you're signed in with a Premium account. The integration uses SPTAppRemote IPC, which requires the Spotify app to be running.

**Hue bridge not discovered** — Make sure your iPad and your Hue bridge are on the same Wi-Fi network. Discovery uses the [meethue.com discovery service](https://discovery.meethue.com/).

---

## License

MIT — [Ritual.Industries](https://ritual.industries)

## For AI coding agents

This is a native iPadOS/SwiftUI app (no package manager beyond Swift Package Manager, no build script generation). Read the files before changing them; the app's whole control flow runs through one viewmodel and one service.

### Repo layout (top level)
- `penpal.xcodeproj/` — the Xcode project. `project.pbxproj` holds build settings, signing, and the one SPM dependency.
- `penpal/` — all Swift source plus `Assets.xcassets`, `Preview Content/`, and `Info.plist`.
- `deploy.sh` — optional CLI build/sign/install/launch path for a physical iPad. Has a `DEVICE_ID` / `SIGN_ID` placeholder block at the top.
- `generate_icon.swift`, `generate_mockups.swift` — standalone helper scripts (app icon + marketing mockups); not part of the app target.
- `README.md`, `LICENSE` (MIT), `.gitignore`.

### Key files (read these first, in order)
1. `penpal/CanvasViewModel.swift` — the brain. Stroke tracking, debounced API calls, response animation, and dispatch of every parsed command to the right service. Start here to understand any behavior.
2. `penpal/ClaudeService.swift` — drives the Anthropic API. Builds the system prompt (the entire command grammar lives in this prompt string), sends a base64 canvas screenshot + conversation history to `https://api.anthropic.com/v1/messages`, and brace-counts the response into the `AIResponse` Codable. The `AIResponse` struct and its JSON `CodingKeys` are the contract between the prompt and the rest of the app.
3. `penpal/penpalApp.swift` — `@main` entry; `onOpenURL` routes the `penpal://` callback to Spotify PKCE vs. App Remote handling.
4. `penpal/ContentView.swift` / `penpal/CanvasView.swift` — the SwiftUI shell and the `PKCanvasView` (PencilKit) wrapper.
5. Integration services, each self-contained and called by the viewmodel: `HueService`, `ContactService`, `ReminderService`, `CalendarService`, `SpotifyService`, `EmailService`, plus `MusicService`. Support files: `HandwritingGenerator`, `HandwritingStyle`, `SingleLineFont`, `MagicGlowOverlay`, `CanvasTheme`, `Notebook` (+`NotebookStore`), `NotebookGalleryView`, `ShareSheet`, `KeychainHelper`.

### Build / run / test
- Open `penpal.xcodeproj` in Xcode 15+, select the `penpal` scheme, set your own team (see invariants), pick a physical iPad (iPadOS 17.0+; requires a real device for Pencil + EventKit/Hue/Spotify), and Run.
- CLI alternative: fill in `DEVICE_ID` and `SIGN_ID` in `deploy.sh`, then `./deploy.sh`. Discover them with `xcrun devicectl list devices` and `security find-identity -v -p codesigning`. The script builds with `-allowProvisioningUpdates`, strips iCloud xattrs, re-signs, installs, and launches.
- There is no test target and no CI. "Verification" means building and exercising handwriting commands on a device. Do not claim a behavior change works without a build.
- The only third-party dependency is the Spotify iOS SDK via SPM (`https://github.com/spotify/ios-sdk`, product `SpotifyiOS`). Xcode resolves it on first build.

### Invariants — do NOT break these
- **`DEVELOPMENT_TEAM` must stay blank.** It appears empty (`DEVELOPMENT_TEAM = "";`) in both build configs in `project.pbxproj`. Never commit a real team ID — each user sets their own.
- **`SpotifyService` client ID must stay a placeholder.** `penpal/SpotifyService.swift` init falls back to `"YOUR_SPOTIFY_CLIENT_ID"` when nothing is in the Keychain. Keep that literal; do not hardcode a real Spotify client ID. The user supplies theirs at runtime (persisted via `KeychainHelper` under `spotify_client_id`).
- **`deploy.sh` device/cert values must stay parameterized** as `YOUR_DEVICE_UDID_HERE` and `YOUR_SIGNING_CERT_SHA1_HERE`, with the guard that exits if they're unedited. Don't bake in real UDIDs/hashes.
- **No secrets in source — ever.** The Anthropic API key, Resend API key (`resend_api_key`) and from-address (`resend_from_email`), and all Spotify tokens are read only from the iOS Keychain via `KeychainHelper` at runtime. `EmailService`/`ClaudeService`/`SpotifyService` must keep reading them from Keychain (or injected init), never from a constant or a checked-in file. `.gitignore` already blocks `.env`, `*.pem`, `*.key`, `*.p12`, `credentials.json`, etc. — keep it that way and don't add real keys anywhere.
- **`.gitignore` excludes internal dev notes** (`CLAUDE.md`, `SESSION_LOG.md`, `.claude/`, `docs/superpowers/`, …). Don't commit those into the public repo.
- **Protocol/scheme tokens are load-bearing — keep them consistent across all three places:** the URL scheme `penpal` (declared in `Info.plist` `CFBundleURLSchemes`), the Spotify `redirectURI = "penpal://callback"`, the PKCE `callbackURLScheme: "penpal"`, and the `onOpenURL` router in `penpalApp.swift`. Changing one without the others silently breaks Spotify auth.
- **The `AIResponse` Codable ↔ system-prompt contract.** The command grammar in `ClaudeService.swift`'s system prompt (commands, `settings` keys, integration payloads, snake_case `CodingKeys` like `calendar_event`, `pen_thickness`, `theme_name`) must stay in sync with the `AIResponse` struct and the viewmodel's dispatch. If you add a command, update the prompt, the struct/`CodingKeys`, and the dispatch together.
- **Bundle ID `com.magicnotebook.penpal`** is the committed default and is wired to the Keychain/permissions; users are expected to change it to their own (e.g. `com.YOURNAME.penpal`) for signing, but don't rename it in committed source on their behalf.
- **`Info.plist` privacy usage strings** (Contacts, Reminders full access, Calendars full access, local network for Hue, media playback, Photos) and `LSApplicationQueriesSchemes` (`spotify`) are required for the integrations to function — don't remove them.

### Where personal/config values were placeholdered
Keep these generic; they are intentionally blanked for the public repo:
- `DEVELOPMENT_TEAM = "";` (both configs in `project.pbxproj`)
- `"YOUR_SPOTIFY_CLIENT_ID"` fallback in `SpotifyService.swift`
- `DEVICE_ID="YOUR_DEVICE_UDID_HERE"` and `SIGN_ID="YOUR_SIGNING_CERT_SHA1_HERE"` in `deploy.sh`
- All API keys, tokens, and the Resend from-address are runtime-only (Keychain) and have no committed values — leave it that way.
