# Usage Overlay

A macOS menu bar app that keeps your **Claude** and **Codex** rate-limit usage on screen at all times.

<img src="docs/overlay.png" width="290" alt="The overlay panel showing how much of each Claude and Codex rate-limit window is left.">

By default, each row shows one rate-limit window: **how much of it is left**, and the time until it resets. For example, 39% means 39% is still available. You can switch to **Percent Used** separately for the menu bar, details, and overlay. Bars turn amber below 50% remaining and red below 20% remaining, whichever percentage you display. The thresholds and colors can be changed in **Settings → Colors**.

The menu bar defaults to each provider's **Tightest Window**, the one with the least headroom. Choose a specific window or **All Windows** for each provider in **Settings → Menu Bar**. Window labels are optional: with short labels, `5h 39%` means 39% of the 5-hour window is left, and `7d 62%` means 62% of the weekly window is left.

The **Menu Bar → Preview** shows your configuration on light and dark backgrounds:

<img src="docs/menubar.png" width="151" alt="Settings preview showing Claude and Codex usage with logo clocks on light and dark backgrounds.">

The numbers come from the CLIs you already have. The default refresh interval is 5 minutes; change it under **Settings → General**. Polling pauses while the Mac or display sleeps, or your login session is inactive, and resumes when active. Usage checks query quota information without asking a model to generate a response.

## Install

Download `Usage-Overlay-v*.zip` from the [latest release](https://github.com/ginjae/usage-overlay/releases/latest), unzip it, and move **Usage Overlay.app** to `/Applications`.

You need macOS 14 or later. Release downloads run natively on Apple Silicon and Intel Macs. Install and sign in to the CLI for each provider you use — check with `claude auth status` and `codex login status`. Only use one provider? Turn the other off in **Settings** under **Menu Bar**, **Details**, and **Overlay**, and its CLI will not be run. Available rate-limit windows depend on your account.

Releases are ad-hoc signed rather than notarized, so macOS may block opening the app. After trying to open it, go to **System Settings → Privacy & Security → Security → Open Anyway** if macOS offers that option.

This README describes the current source tree, including interface changes newer than the packaged **v1.0.3** release. [Build from source](#build-from-source) to use every option shown here. [Screenshot details](docs/README.md) record the captured build.

## Details and settings

Click the menu bar item for the details. **Refresh Now** sits at the top, followed by the last updated time and a divider, then each enabled provider's usage and reset times. Hide the timestamp with **Settings → Details → Last updated**. Turn on **Pace** in the same pane to project whether your current usage rate will exhaust a window before it resets. Below the usage are **Show Overlay**, **Reset Overlay Position**, **Settings…** and **Quit Usage Overlay**.

<img src="docs/details.png" width="346" alt="Details menu with Refresh Now first, Updated just now and a divider below it, followed by Claude and Codex usage and app controls.">

Settings apply as you change them:

| Pane | What you can change |
|---|---|
| **General** | Launch at login, refresh interval, provider order, where the CLIs are, updates |
| **Menu Bar** | Providers and windows, percent left or used, labels, percent sign, separator, reset countdown or clock, each provider's clock window, clock fill and dimming, ring thickness, logo and text size, font weight, color mode, spacing, the hover tooltip |
| **Details** | Providers, percent left or used, each line (plan, bar, time to reset, reset time, pace, last updated), width |
| **Overlay** | Visibility, opacity, click-through, locked position, providers and windows, each column, width, text size, bar thickness, background, corners, border, Spaces, staying on top |
| **Colors** | The three level colors and where each starts, and the provider logo colors |

Each pane has **Restore Defaults** for that pane alone.

Under **Menu Bar → Reset time → Show as**, choose **Off** (the default), **Countdown**, **Logo Clock**, or **Ring Clock**. Countdown adds the time until each displayed window resets, with one or two units of precision. Logo Clock lights up part of the provider logo itself; Ring Clock draws a ring around a smaller logo.

For either clock, choose **Claude window** and **Codex window** independently of the percentages. **First Shown Window** (the default) follows the first percentage shown for that provider. You can instead choose **Tightest Window**, **5-hour Window**, **Weekly Window**, or **Fable Weekly Window** for Claude. If the chosen window is unavailable, the tightest window is used. A clock needs both a known window duration and a reset time; otherwise the plain logo is shown.

<img src="docs/reset-time.png" width="585" alt="Reset time settings with Logo Clock enabled and the Claude window menu open, offering First Shown, Tightest, 5-hour, Weekly, and Fable Weekly windows.">

**Lit part → Same as Percent** lights the time left with **Percent Left**, or the time gone with **Percent Used**. Choose **Time Left** or **Time Gone** to override that behavior. When the clock and percentage follow the same window, `39%` next to a half-lit clock means the limit is draining faster than time.

By default the overlay floats above other windows on every Space, including full screen. Drag it by its background; it remembers where you left it.

## Updates

The installed app checks for a new version once a day by default and asks before installing one — **Update**, **Later**, or **Skip This Version**. It compares the archive with a SHA-256 checksum when one is available, checks the app identifier and version, then replaces itself and reopens. Run a check yourself, or turn off automatic checks, under **Settings → General**. Self-updates require write access to the app's containing folder and cannot run from a read-only, translocated copy.

## Privacy

Usage Overlay's own network requests are GitHub release checks and update downloads. Those requests do not include your usage data or CLI credentials. Usage queries are performed by the signed-in CLIs using their existing credentials; the app reads their output rather than accessing stored credentials. It does not upload usage data or telemetry. Automatic update checks can be turned off in **Settings → General**.

## If something looks wrong

- **A row says the CLI wasn't found.** It is installed somewhere unusual. Point at it under **Settings → General → Command-line tools**; the line under each path shows which file is in use.
- **An update won't install.** The app can only replace itself where it can write, and not while macOS runs it from a read-only copy. Move it to `/Applications` and open it again.
- **The numbers look old.** The details menu and the overlay footer show their age. Refresh from **Refresh Now** in the menu or the overlay's refresh button.
- **A selected window shows another window instead.** That window is not available in the current response, so the app falls back to the provider's tightest window. The reset clock has its own window selection under **Menu Bar → Reset time**.
- **The overlay won't move.** Turn off **Click through** and **Lock position** under **Settings → Overlay**. Use **Reset Overlay Position** in the menu to move it back to the primary display's top-right corner.

## Build from source

Requires macOS and Swift 6 or later, provided by Xcode or its Command Line Tools.

```bash
xcode-select --install     # if the build tools are missing
./scripts/bundle.sh        # → build/Usage Overlay.app
```

Run `./scripts/bundle.sh --universal` to build for both Apple Silicon and Intel. Open the resulting app from `build`, or copy it to `/Applications`.

Set `APP_VERSION` and `BUILD_NUMBER` when you need specific bundle version metadata; the script defaults to `0.1.0` and `1`.
