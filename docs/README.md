# Screenshots

Captured on November 8, 2026 (Asia/Seoul) from **Usage Overlay 1.3.0, local build 102**, built with the macOS 27.2 SDK and running on macOS 27.0.1.

- The app ran unmodified with default settings and fresh preferences, with the overlay shown.
- Usage values are sample data. **Settings → General → Command-line tools** pointed at two stand-in scripts that answer like the `claude` and `codex` CLIs, with reset times a few hours to days away so each logo clock is clearly lit.
- Each image has a light and a `-dark` version, captured with the app's appearance set to light or dark.
- The overlay and the details menu were captured with `screencapture` over a plain gradient backdrop, with 28 pt of backdrop on every side. Their glass shows that backdrop instead of a desktop, and their native shadows are included.
- The details menu is the menu bar item's menu, opened in the middle of the screen so it has the same margin on every side.
- `menubar.png` and `menubar-dark.png` are cropped from **Settings → Menu Bar → Preview**, which draws the menu bar item on a light and a dark menu bar.
- `settings.png` and `settings-dark.png` are the Settings window with its shadow, sized to end after the Providers section.

| File | Content | Native size |
|---|---|---|
| [overlay.png](overlay.png), [overlay-dark.png](overlay-dark.png) | Floating overlay with Claude and Codex usage | 600 × 388 |
| [menubar.png](menubar.png), [menubar-dark.png](menubar-dark.png) | Menu bar item with logo clocks and what's left | 284 × 120 |
| [details.png](details.png), [details-dark.png](details-dark.png) | Details menu with each window's bar and reset times, then the app's commands | 712 × 974 |
| [settings.png](settings.png), [settings-dark.png](settings-dark.png) | Settings window on the Menu Bar pane | 1744 × 1460 |

[icon.png](icon.png) is the app icon, `Resources/AppIcon.png` scaled to 256 × 256.

The main README shows these at half their pixel size for Retina sharpness, except the Settings window, which is shown smaller. Capture the app again after changing the interface, and update this page with the images.
