<img src="docs/icon.png" width="128" alt="Usage Overlay app icon">

# Usage Overlay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/overlay-dark.png">
  <img src="docs/overlay.png" width="244" alt="The floating overlay showing Claude and Codex usage bars, percentages left, and time until reset.">
</picture>

## Overview

Usage Overlay is a macOS menu bar app that keeps your **Claude** and **Codex** rate-limit usage in view. For each rate-limit window it shows how much is left and when the window resets, in three places:

- **Menu bar**: each provider's logo and what's left. The logo doubles as a clock for the time until reset.
- **Details menu**: every window with a bar, its reset time, and your plan.
- **Overlay**: an optional floating panel that stays above other windows.

Bars turn amber below 50% left and red below 20% left.

## Quick start

1. Install and sign in to the CLI for each provider you use. Check with `claude auth status` and `codex login status`.
2. Download `Usage-Overlay-v*.zip` from the [latest release](https://github.com/ginjae/usage-overlay/releases/latest), unzip it, and move **Usage Overlay.app** to `/Applications`.
3. Open the app. Releases are ad-hoc signed rather than notarized, so macOS may block the first launch. If it does, go to **System Settings → Privacy & Security** and choose **Open Anyway**.
4. Your usage appears in the menu bar. Click it and choose **Show Overlay** to float the panel.

Requires macOS 14 or later, on Apple Silicon or Intel. Which windows you see depends on your account.

## How it works

### Where the numbers come from

The app runs the CLIs you're already signed in to and reads what they print. It finds them in their usual install locations, or at the paths you set in **Settings → General → Command-line tools**.

```bash
claude -p "/usage" --session-id <new UUID>   # Claude Code: usage
claude auth status                           # Claude Code: plan name, once per launch
codex app-server                             # Codex: usage and plan, over JSON-RPC
```

`/usage` is built into Claude Code, so no prompt goes to a model. The app deletes the transcript that the one-off session leaves in `~/.claude/projects`.

Codex has no usage subcommand, so the app starts the same app server the Codex TUI uses and writes these lines to its stdin:

```json
{"id":0,"method":"initialize","params":{"clientInfo":{"name":"usage-overlay","version":"1.0.0"}}}
{"method":"initialized"}
{"id":1,"method":"account/rateLimits/read"}
```

It refreshes every 5 minutes (**Settings → General**) and pauses while the Mac or display sleeps. A provider's CLI runs while the provider is enabled in **Settings → General → Providers** and shown in the menu bar, the details menu, or a visible overlay.

### Menu bar and details

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/menubar-dark.png">
  <img src="docs/menubar.png" width="196" alt="Menu bar previews showing logo clocks and the remaining percentages for Claude and Codex.">
</picture>

By default the menu bar shows every window for each provider. In **Settings → Menu Bar** you can check individual windows or choose **Tightest** to show the window with the least left. You can also add labels such as `5h 39%` or switch to **Percent Used**.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/details-dark.png">
  <img src="docs/details.png" width="320" alt="The Details settings preview, showing plan names, 5-hour and weekly usage bars, and reset times for Claude and Codex.">
</picture>

Click the menu bar item for the details menu. It lists each window's time to reset and the weekday and time it resets. Turn on **Pace** in **Settings → Details** to see whether your current rate will use up a window before it resets. Codex plans **Pro 100**, **Pro 200**, and **Pro 500** are the [ChatGPT Pro tiers](https://learn.chatgpt.com/docs/pricing) at $100, $200, and $500 a month.

### Overlay

The overlay starts hidden and shows **5-hour** and **Weekly** for each provider. It floats above other windows on every Space, including full screen, and stays where you drag it. Set its opacity, click-through, columns, size, and background in **Settings → Overlay**. Choose **Glass**, **Solid**, or, on macOS 26 and later, **Liquid Glass** with a clear, reflective surface that responds to pointer interactions. Liquid Glass keeps its active appearance while you work in other apps and is the default on supported Macs. Your first launch after updating to v1.5.0 selects Liquid Glass once; any background you choose afterward is kept. Earlier Clear Glass, Light Glass, and Frosted Glass selections now use Glass.

### Settings

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/settings-dark.png">
  <img src="docs/settings.png" width="720" alt="The General settings pane with startup, refresh interval, provider switches, and provider order.">
</picture>

Settings is laid out like System Settings. Search the sidebar to find the pane for any setting, and press ⌘[ and ⌘] to go back and forward. Changes apply right away, and every pane except **Updates** has its own **Restore Defaults**.

| Pane | What you can change |
|---|---|
| **General** | Launch at login, refresh interval, provider switches and order, CLI locations |
| **Updates** | Installed version, release notes, automatic checks |
| **Menu Bar** | Windows, percent left or used, reset time, appearance, tooltip |
| **Details** | Windows, percent left or used, which lines to show, width |
| **Overlay** | Visibility, opacity, click-through, position lock, windows and columns, size, background, Spaces |
| **Colors** | Level colors and where each starts, provider logo colors |

In **Menu Bar**, **Details**, and **Overlay**, select the windows you want under Claude and Codex. Right-click the **Windows** row for **All** or **Tightest**.

**Codex reset status** shows the latest reset, scheduled announcements, and AI forecasts from [Codex Resets](https://codex-resets.com) in compact rows in the details menu. This experimental feature is on by default; you can turn it off in **Settings → Details → Experimental**. It reads the site's [public status API](https://codex-resets.com/api/docs) with each usage refresh and **Refresh Now**. Click the ↗ line in a row to open the original post, or hover the row to read its text. Forecasts come from this community service and are not confirmed resets; a scheduled time passing does not mean your account has been reset.

### Updates

Once a day the app checks GitHub for a new version and asks before installing it. It verifies the download against its SHA-256 checksum when one is published, checks the app identifier and version, then replaces itself and reopens. Your settings are kept. A red badge in the Settings sidebar marks a new version, and **Settings → Updates** shows what's new. To check right away, choose **Check for Updates…** in the details menu. The app has to be in a folder it can write to, such as `/Applications`.

### Privacy

The app's own network requests are GitHub release checks and update downloads, plus the public codex-resets.com status API when its experimental feature is enabled. These requests carry no usage data or credentials. Usage is queried by the CLIs with their own sign-in; the app reads their output and never reads stored credentials. There is no telemetry. You can turn off update checks in **Settings → Updates** and Codex reset status in **Settings → Details**.

## Troubleshooting

- **A provider says its CLI wasn't found.** Point to it in **Settings → General → Command-line tools**.
- **The numbers look old.** The details menu and the overlay show when they were updated. Use **Refresh Now** or the overlay's refresh button.
- **The overlay won't move.** Turn off **Click through** and **Lock position** in **Settings → Overlay**, or use **Reset Overlay Position** in the menu.
- **An update won't install.** Move the app to `/Applications` and open it again.

## Build from source

Requires Swift 6 or later, from Xcode or its Command Line Tools. Build with Xcode 26 or later to get the Liquid Glass look on macOS 26 and later. With an older SDK the app keeps the previous look, and the script warns about it.

Keeping Liquid Glass active without keyboard focus relies on AppKit's private `_hasActiveAppearance` selector, scoped to the overlay's Liquid Glass background. If a future macOS stops using that selector, the system's normal inactive appearance returns.

```bash
./scripts/bundle.sh               # → build/Usage Overlay.app
./scripts/bundle.sh --universal   # Apple Silicon and Intel
./scripts/bundle.sh --install     # also replaces the installed app
swift test
```

Set `APP_VERSION` and `BUILD_NUMBER` for the bundle's version (defaults: `0.1.0` and `1`; with `--install`, the latest release's version, so the app still offers the next release). The tests run against a small local CLI fixture and never query your accounts.

[About the screenshots](docs/README.md)

## License

The project’s original code is available under the [MIT License](LICENSE). The Claude and Codex logos shown in the app, app icon, and screenshots belong to their respective owners.
