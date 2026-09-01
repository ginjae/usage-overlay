# Usage Overlay

A macOS menu bar app that keeps your **Claude** and **Codex** rate-limit usage on screen at all times.

<img src="docs/overlay.png" width="290" alt="The overlay panel showing how much of each Claude and Codex rate-limit window is left.">

Each row is one rate-limit window: **how much of it is left**, and when it resets. Percentages count down, not up — 39% means you have 39% of that window still available. The bar drains and turns amber below 50%, red below 20%.

The footer shows the age of the numbers once they go stale, plus a refresh button. Where each provider's numbers came from is in the menu bar tooltip.

Your tightest remaining headroom per provider also sits in the menu bar, tagged with the window it came from — `5h 39%` means 39% of the 5-hour window is left, `7d 62%` means the weekly one:

<img src="docs/menubar.png" width="100" alt="Menu bar showing the Claude and OpenAI icons with the remaining percentage next to each.">

Which window it follows, which providers appear, and how much detail is shown are all configurable — see [Menu bar](#menu-bar). Hovering the item lists **every** window of both providers with plan, source and reset time, whatever the menu bar itself is set to.

---

## How it works

The app never talks to Anthropic or OpenAI itself. It gets numbers from two places, in order.

### 1. Chrome (reported as `Web`)

It opens a **dedicated, hidden Chrome window** holding two tabs, and runs JavaScript inside them via AppleScript. The JavaScript calls each site's own usage API using the session you are **already logged into** — no API keys, no tokens to configure.

| | Tab | API called from inside the tab |
|---|---|---|
| Claude | `https://claude.ai/new#settings/usage` | `GET /api/organizations` → uuid → `GET /api/organizations/{uuid}/usage` |
| Codex | `https://chatgpt.com/sites#settings/Usage` | `GET /api/auth/session` → accessToken → `GET /backend-api/codex/usage` |

- claude.ai works with **cookies alone**. The organization uuid is discovered inside the page, so it works on any account.
- chatgpt.com returns 401 for cookies alone, so the page grabs its own session accessToken and sends it as a Bearer header. **That token never leaves the browser tab** — see [Privacy](#privacy).

These are undocumented endpoints, found by observing what the pages actually request. They can change without notice; see [Limitations](#limitations).

**Why not the DevTools protocol?** Since Chrome 136, `--remote-debugging-port` is ignored for the default profile. Using a separate `--user-data-dir` would work but loses your logged-in session, which defeats the purpose. AppleScript is the remaining option.

**Why not scrape the page?** An earlier version read percentages off the rendered page and got them wrong — it read a promo banner ("weekly limit is **50%** higher") as 50% usage, and ChatGPT's "**80%** remaining" as 80% used. Showing a wrong number is worse than showing a stale one, so DOM scraping was removed entirely.

### 2. Local CLI cache (reported as `Local`)

If Chrome is closed or the integration is blocked, the app falls back to files the two CLIs already write:

| | File | Field |
|---|---|---|
| Claude | `~/.claude.json` | `cachedUsageUtilization` |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | last `token_count` event → `rate_limits` |

These are values the CLIs cached from their own last request, so they go stale if you haven't used the CLI recently. When that happens the overlay footer shows how old the numbers are (`3m ago`).

### Parsing

The four sources use different field names for the same thing — `window_minutes` vs `limit_window_seconds`, `resets_at` vs `reset_at`, `primary` vs `primary_window`. Instead of hardcoding paths, the app walks the JSON recursively and accepts only three shapes as a gauge:

- `used_percent` (Codex, web and CLI)
- `kind` + `percent` (Claude `limits[]`)
- `utilization` under a known key such as `five_hour` / `seven_day`

Anything else is ignored, so unknown codename fields are filtered out and one source changing shape doesn't break the others.

---

## Requirements

- macOS 14 or later
- Google Chrome, signed in to both claude.ai and chatgpt.com
- Xcode Command Line Tools (Swift 6) **only if you build from source**

### Permissions the app needs

| Permission | Why | How it's granted |
|---|---|---|
| **Automation → Google Chrome** | To create tabs and run JavaScript in them | macOS prompts on first run: *"Usage Overlay wants to control Google Chrome."* Click **OK**. Later changes: System Settings → Privacy & Security → Automation |

That is the only macOS permission. The app does **not** request or use Accessibility, Screen Recording, Full Disk Access, Camera, Microphone, or Location.

### Chrome setting you must enable manually

> Chrome menu → **View → Developer → Allow JavaScript from Apple Events**

This is off by default and **cannot be enabled programmatically** — it's a security setting, and Chrome deliberately requires a human to flip it. Without it the app silently stays on the `Local` fallback and never creates tabs.

⚠️ **Understand what this opens.** Once enabled, *any* application that has Automation permission for Chrome can execute JavaScript in your logged-in browsing sessions — not just this app. That includes reading page content and making authenticated requests as you. Turn it off in the same menu when you no longer want that.

### Files the app reads

Read-only, and only when falling back to `Local`:

- `~/.claude.json` — only `cachedUsageUtilization` and `oauthAccount.organizationType` (the plan name) are used
- `~/.codex/sessions/**/rollout-*.jsonl` — only the tail of the most recent files, looking for `rate_limits`

The app never writes to either location.

---

## Privacy

- **The app makes no network requests of its own.** Every HTTP call happens inside a Chrome tab, from the origin it belongs to, using cookies already in your browser.
- **Nothing is sent anywhere.** No telemetry, no analytics, no remote logging.
- **The ChatGPT session token stays in the page.** The injected script keeps it in a page-local variable to build the Bearer header. What comes back to the app is only `{href, ready, endpoint, resultAt, err, result}` — the token is not among them.
- The only things stored on disk are your preferences (`io.github.ginjae.usage-overlay`): window position, opacity, refresh interval, and the Chrome tab ids being tracked.

---

## Install

### Download the app (recommended)

Download `Usage-Overlay-v*.zip` from the [latest GitHub Release](https://github.com/ginjae/usage-overlay/releases/latest), unzip it, and move **Usage Overlay.app** to `/Applications`.

The release is a Universal app, so it runs natively on both Apple Silicon and Intel Macs. It only links macOS system frameworks; Swift, Xcode, Homebrew, and other build dependencies are not required on the destination Mac.

Releases are currently ad-hoc signed, not Apple-notarized. On first launch, macOS may block the app because it cannot verify the developer. After trying to open it once, go to **System Settings → Privacy & Security → Security → Open Anyway**. A future Developer ID-signed and notarized release would remove this extra step.

### Build from source

Install Apple's Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

Then clone the repository and build the app:

```bash
./scripts/bundle.sh              # release build → build/Usage Overlay.app (ad-hoc signed)
open "build/Usage Overlay.app"
```

Pass `--universal` to build for both Apple Silicon and Intel instead of only the current Mac. Release builds also accept `APP_VERSION=1.2.3` and `BUILD_NUMBER=123`.

The app icon is generated during bundling: `sips` and `iconutil` slice `Resources/AppIcon.png` into every size macOS asks for. Replace that one 1024×1024 PNG to change the icon; `Resources/AppIcon-source.png` is the original artwork it was cut from, kept so the icon can be re-cropped later. If either tool is missing the build still finishes, just with the generic icon.

For everyday use, move `build/Usage Overlay.app` to `/Applications` and turn on **Launch at Login** from the menu. If the required Apple build tools are missing, the script now stops with an installation hint instead of an opaque compiler error.

Maintainers can publish a prebuilt release by pushing a three-part version tag. For example:

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions builds the Universal app, creates a zip and SHA-256 checksum, and attaches both to a new GitHub Release.

To confirm the Chrome integration is working, hover the menu bar item: the tooltip names each provider's source — `Web` means it's live, `Local` means it fell back to the CLI cache. The overlay itself stays out of it, since one badge for two providers can't say which is which.

---

## Menu bar

Clicking the menu bar item opens:

| Item | What it does |
|---|---|
| **Show Overlay** | Toggle the floating panel |
| **Click Through** | Let mouse events pass to the window underneath (you can't drag the overlay while this is on, so position it first) |
| **Opacity** | 100 / 85 / 70 / 50% |
| **Refresh Interval** | 5s / 10s / 30s / 1 min / 10 min |
| **Menu Bar** | What the status item itself shows — see below |
| **Read from Chrome** | Turn off to use only the local CLI cache |
| **Hide Chrome Window** | Turn **off** when you need to see the window — for example to sign in again |
| **Reopen Usage Tabs** | Close and recreate the tracked tabs if they get into a bad state |
| **Refresh Now** / **Reset Position** / **Launch at Login** / **Quit** | |

The overlay is dragged by its background, floats above other windows on every Space including full screen, and remembers its position by top-left corner.

### Menu Bar submenu

| Option | What it does |
|---|---|
| **Show Claude** / **Show Codex** | Which providers appear. Turn one off if you only use the other, or to save width |
| **Tightest Window** | Follow whichever window has the least left — the default, and why the number can jump between windows |
| **5-hour Window** / **Weekly Window** | Pin one window instead. A provider that doesn't report it falls back to its tightest, so the item never goes blank |
| **All Windows** | Every window of every provider, with the icon on the first one only |
| **Percent Left** / **Percent Used** | Count down (default, matching the overlay) or up |
| **Window Label** | Prefix the window length: `5h 39%` instead of `39%` |
| **Provider Icon** | The Claude / OpenAI mark before each provider |
| **Reset Time** | Append the countdown: `5h 39% · 2h 10m` |

Turning both providers off leaves a plain `Usage` label, so the menu is still reachable. The tooltip ignores all of these and always shows everything.

---

## How it treats your Chrome

Deliberate rules, because an early version made a mess of it:

- **Tabs you opened yourself are never touched.** The app tracks only tabs it created, by tab id. If a tracked tab is gone it will adopt an existing tab only when the URL matches **exactly**, hash included.
- **Tab creation is rate limited to one per minute.** An early bug recreated a window on every poll; this cap means no bug can ever pile up windows again.
- **Windows are hidden, not minimized.** `visible of window` is set to false, which leaves no Dock thumbnail and nothing drawn on screen, while the tab stays alive and JavaScript keeps working (`document.hidden` is simply true). Pushing the window off-screen doesn't work — macOS drags it back into view.
- **If the JavaScript setting is off, no tabs are created at all.** There's no point opening a tab that can't be read. Flip the Chrome setting and it attaches within 60 seconds.
- **If Chrome isn't running, it is not launched.** The app quietly uses the local cache instead.

The URLs are configurable without rebuilding:

```bash
defaults write io.github.ginjae.usage-overlay url.claude 'https://claude.ai/new#settings/usage'
defaults write io.github.ginjae.usage-overlay url.codex  'https://chatgpt.com/#settings/Usage'
```

---

## Limitations

- The Chrome JavaScript setting must be enabled by hand, and it survives restarts but not a profile reset.
- Because the usage windows are hidden, you can't see a sign-in prompt if a session expires. Turn off **Hide Chrome Window** to bring it back.
- A refresh waits up to 6 seconds per provider for the response, so it isn't instant.
- If an endpoint changes, the app falls back to `Local` silently. The tooltip switching to `Local` is the only signal.
- Screen capture tools will include the overlay.
- Chrome tab ids do not compare equal to integer literals in AppleScript — `(id of t) as text` gives the same digits, but `(id of t) is 1546029274` is false. Every tab lookup compares strings. This cost hours; it's noted here so it doesn't again.

---

## Project layout

| File | Role |
|---|---|
| `ChromeBridge.swift` | Drives Chrome through `osascript` — tab creation, tracking, adoption, JS execution, and the pre-flight check for the JS setting |
| `PageScript.swift` | The JavaScript injected into each tab; resolves and calls the per-site usage endpoint |
| `BrowserReader.swift` | Per-site polling, tab creation rate limit, response interpretation |
| `UsageScan.swift` | Recursively extracts gauge-shaped objects from arbitrary JSON |
| `ClaudeReader.swift` / `CodexReader.swift` | Local CLI cache fallbacks |
| `UsageStore.swift` | 1-second clock, N-second refresh, Web→Local fallback, plan-name backfill |
| `OverlayPanel.swift` / `OverlayView.swift` | The floating HUD |
| `AppDelegate.swift` | Menu bar item and menu |
| `MenuBarText.swift` | Turns a snapshot into the menu bar text and tooltip, per the Menu Bar settings |
| `Icons.swift` | Provider icons as embedded template images |
| `Resources/AppIcon.png` | 1024px app icon master — the artwork cropped to its body and masked to the macOS icon shape, with the transparent margins the Dock expects. `bundle.sh` turns it into `AppIcon.icns` at build time |
| `Resources/AppIcon-source.png` | The original square artwork, before cropping and masking |
| `StatusBarImage.swift` | Composites icon + percentage into one menu bar image |
