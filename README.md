# Usage Overlay

A macOS menu bar app that keeps your **Claude** and **Codex** rate-limit usage on screen at all times.

<img src="docs/overlay.png" width="290" alt="The overlay panel showing how much of each Claude and Codex rate-limit window is left.">

Each row is one rate-limit window: **how much of it is left**, and when it resets. Percentages count down, not up — 39% means you have 39% of that window still available. The bar drains and turns amber below 50%, red below 20%. Both points and all three colors can be changed.

Your tightest remaining headroom also sits in the menu bar, tagged with the window it came from — `5h 39%` means 39% of the 5-hour window is left, `7d 62%` means the weekly one. Click it for the details of every window:

<img src="docs/menubar.png" width="100" alt="Menu bar showing the Claude and OpenAI icons with the remaining percentage next to each.">

The numbers come from the CLIs you already have, refreshed every 5 minutes. Checking your usage never spends any of it.

## Install

Download `Usage-Overlay-v*.zip` from the [latest release](https://github.com/ginjae/usage-overlay/releases/latest), unzip it, and move **Usage Overlay.app** to `/Applications`.

You need macOS 14 or later and both CLIs signed in — check with `claude auth status` and `codex login status`. Only use one of them? Turn the other off in **Settings** under **Menu Bar**, **Details**, and **Overlay**, and it is never run at all.

Releases are ad-hoc signed rather than notarized, so macOS may block the first launch. After trying to open it once, go to **System Settings → Privacy & Security → Security → Open Anyway**. Only the first launch needs this.

## Details and settings

Click the menu bar item for the details: every window's usage and when it resets, both the time left and the time on the clock. Turn on **Pace** under **Details** to also see where your current rate leaves you by then. Show or hide the overlay there, or put it back in its default spot with **Reset Position**. The gear at the bottom opens **Settings**. Right-click the item to refresh, open Settings, or quit without opening the details.

Everything on screen can be changed in Settings, and each change shows up as you make it:

| Pane | What you can change |
|---|---|
| **General** | Launch at login, refresh interval, provider order, where the CLIs are, updates |
| **Menu Bar** | Providers and windows, percent left or used, window label, percent sign, separator, reset time as a countdown or a clock on the logo, logo and text size, font weight, level colors, spacing, the hover tooltip |
| **Details** | Providers, percent left or used, each line (plan, bar, time to reset, reset time, pace, last updated), width |
| **Overlay** | Visibility, opacity, click-through, locked position, providers and windows, each column, width, text size, bar thickness, background, corners, border, Spaces, staying on top |
| **Colors** | The three level colors and where each starts, and the provider logo colors |

Each pane has **Restore Defaults** for that pane alone.

With **Menu Bar → Reset time → Logo Clock** or **Ring Clock**, the provider logo becomes a clock for the window next to it. Logo Clock lights up part of the logo itself; Ring Clock draws a ring around a smaller logo. The lit part is the time left in the window (or the time gone, with **Percent Used**), so you can check your pace against the number: `39%` next to a half-lit clock means the limit is draining faster than time.

By default the overlay floats above other windows on every Space, including full screen. Drag it by its background; it remembers where you left it.

## Updates

The app checks for a new version once a day and asks before installing one — **Update**, **Later**, or **Skip This Version**. It verifies the download against the checksum published with the release, then replaces itself and reopens, so **Open Anyway** never comes back. Run a check yourself, or turn the daily one off, under **Settings → General**.

## Privacy

The app makes no network requests except that update check, which carries nothing identifying and can be turned off. Your usage is fetched by each CLI with its own credentials, exactly as when you run it in a terminal: the app never sees your tokens, and sends nothing anywhere.

## If something looks wrong

- **A row says the CLI wasn't found.** It is installed somewhere unusual. Point at it under **Settings → General → Command-line tools**; the line under each path shows which file is in use.
- **An update won't install.** The app can only replace itself where it can write, and not while macOS runs it from a read-only copy. Move it to `/Applications` and open it again.
- **The numbers look old.** The details window and the overlay footer show their age, and both have a refresh button. Right-clicking the menu bar item refreshes too.

## Build from source

```bash
xcode-select --install     # if the build tools are missing
./scripts/bundle.sh        # → build/Usage Overlay.app
```
