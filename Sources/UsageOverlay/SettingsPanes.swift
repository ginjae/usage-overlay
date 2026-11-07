import AppKit
import ServiceManagement
import SwiftUI

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var store: UsageStore
    let actions: SettingsActions
    /// 로그인 항목은 설정 저장소가 아니라 시스템이 들고 있다. 창을 열 때 한 번 묻는다.
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    private static let intervals = [30, 60, 120, 300, 600, 900, 1800, 3600]

    var body: some View {
        Form {
            PaneHeader(.general)

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError { Caption(loginError) }
            }

            Section("Refresh") {
                ChoiceRow(title: "Refresh every", selection: $settings.refreshSeconds,
                          choices: Self.intervals, label: Self.intervalLabel)
                Caption("Each refresh runs the CLIs you show. Checking your usage never spends any of it.")
            }

            Section("Providers") {
                ChoiceRow(title: "Order", selection: $settings.providerOrder,
                          choices: ProviderOrder.allCases, label: \.title)
                Caption("Used by the menu bar, the details window, and the overlay.")
            }

            Section("Command-line tools") {
                CLIPathRow(name: "claude", path: $settings.claudePath, store: store, refresh: actions.refresh)
                CLIPathRow(name: "codex", path: $settings.codexPath, store: store, refresh: actions.refresh)
                Caption("Leave a path empty to look in the usual install locations.")
            }

            RestoreDefaults(section: .general)
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "\(error.localizedDescription) Try moving the app to /Applications first."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func intervalLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        if seconds < 3600 { return seconds == 60 ? "1 minute" : "\(seconds / 60) minutes" }
        return "1 hour"
    }
}

/// CLI 경로 한 줄. 지금 어느 파일을 쓰는지 같이 보여 준다.
/// 글자를 칠 때마다 CLI 를 다시 돌리지 않도록 Return 을 누르거나 칸을 떠날 때만 저장한다.
private struct CLIPathRow: View {
    let name: String
    @Binding var path: String
    @ObservedObject var store: UsageStore
    let refresh: () -> Void
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(name, text: $draft, prompt: Text("Find automatically"))
                    .focused($focused)
                    .onSubmit(commit)
                Button("Choose…", action: choose)
            }
            Caption(status)
        }
        .onAppear { draft = path }
        .onChange(of: focused) { _, focused in if !focused { commit() } }
        .onChange(of: path) { _, path in draft = path }
    }

    private var status: String {
        // 조회가 끝날 때마다 다시 그려 방금 지정한 경로가 맞았는지 바로 보이게 한다.
        _ = store.snapshot
        let found = CommandRunner.executable(name)
        // 지정한 파일을 못 쓰면 알려진 설치 위치로 넘어간다. 그 사실을 말해 주지 않으면 지정이 먹은 줄 안다.
        if let chosen = Settings.shared.path(for: name), !FileManager.default.isExecutableFile(atPath: chosen) {
            return found.map { "Can't run that file, so \($0.path) is used instead." }
                ?? "Can't run that file, and \(name) wasn't found anywhere else."
        }
        guard let found else { return "Not found. Choose the \(name) file directly." }
        return "Using \(found.path)"
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != path else { return }
        path = trimmed
        refresh()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose the \(name) command-line tool"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft = url.path
        commit()
    }
}

// MARK: - Updates

/// 시스템 설정의 소프트웨어 업데이트처럼 지금 상태를 맨 위 한 칸에 보여 준다.
/// 직접 누른 검사의 결과도 알림창 대신 여기 뜬다.
struct UpdatesPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var updater: Updater
    let actions: SettingsActions

    var body: some View {
        Form {
            PaneHeader(.updates)

            Section { status }

            if let release = updater.available, updater.unavailableReason == nil {
                let notes = ReleaseNotes(release.notes)
                if !notes.blocks.isEmpty {
                    Section("What's New in \(release.version.description)") {
                        notes
                        Link("View on GitHub", destination: release.page)
                    }
                }
            }

            Section {
                LabeledContent("Installed",
                               value: updater.currentVersion.map { "Usage Overlay \($0.description)" } ?? "Development build")
                Toggle("Check for updates automatically", isOn: $settings.autoUpdate)
                Caption("Once a day, Usage Overlay asks GitHub whether a new version is out, and asks you before installing it.")
            } footer: {
                Button("All Release Notes", action: actions.openReleaseNotes)
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: checkIfUnknown)
    }

    /// 이번 실행에서 아직 물어본 적이 없으면 쪽을 여는 김에 물어본다. 자동 검사를 껐으면 누를 때까지 기다린다.
    private func checkIfUnknown() {
        guard settings.autoUpdate, updater.lastOutcome == nil, updater.status == .idle,
              updater.unavailableReason == nil else { return }
        actions.checkForUpdates()
    }

    @ViewBuilder private var status: some View {
        if let reason = updater.unavailableReason {
            StatusRow(symbol: "info.circle.fill", tint: .secondary,
                      title: "This copy can't update itself", detail: reason) {
                Button("Open Releases Page", action: actions.openReleaseNotes)
            }
        } else if updater.status == .checking {
            HStack {
                Text("Checking for updates…")
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else if updater.status == .downloading {
            HStack {
                Text("Downloading \(updater.available.map { "Usage Overlay \($0.version.description)" } ?? "the update")…")
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else if let release = updater.available {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage Overlay \(release.version.description)")
                        .font(.headline)
                    Text("A new version is available."
                         + (updater.currentVersion.map { " You have \($0.description)." } ?? ""))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Update Now") { actions.installUpdate(release) }
                    .buttonStyle(.borderedProminent)
            }
            Caption("Usage Overlay quits and reopens itself to finish updating.")
        } else {
            switch updater.lastOutcome {
            case .upToDate?:
                StatusRow(symbol: "checkmark.circle.fill", tint: .green,
                          title: "Usage Overlay is up to date", detail: lastChecked) { checkNow }
            case .failed(let message)?:
                StatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                          title: "Couldn't check for updates", detail: message) {
                    Button("Try Again", action: actions.checkForUpdates)
                }
            default:
                StatusRow(title: "Check for updates",
                          detail: lastChecked ?? "Automatic checks are off.") { checkNow }
            }
        }
    }

    private var checkNow: some View {
        Button("Check Now", action: actions.checkForUpdates)
    }

    private var lastChecked: String? {
        updater.lastChecked.map { "Last checked \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" }
    }
}

/// 상태 한 줄. 왼쪽에 기호와 설명, 오른쪽에 할 일 단추.
private struct StatusRow<Accessory: View>: View {
    var symbol: String?
    var tint: Color = .secondary
    let title: String
    var detail: String?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Caption(detail) }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

/// GitHub 릴리스 본문을 설정 창에 맞게 그린다.
/// 제목 · 목록 · 문단만 가르고, 굵게 · 링크 같은 줄 안 꾸밈은 Markdown 을 그대로 읽는다.
struct ReleaseNotes: View {
    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    let blocks: [Block]

    init(_ markdown: String) { blocks = Self.blocks(of: markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(Self.inline(text))
                        .font(.headline)
                        .padding(.top, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(Self.inline(text))
                    }
                case .paragraph(let text):
                    Text(Self.inline(text))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    /// 맨 위 `# Usage Overlay v1.2.1` 같은 문서 제목은 바로 위 버전 줄과 겹치니 뺀다.
    static func blocks(of markdown: String) -> [Block] {
        markdown.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("# ") { return nil }
            if line.hasPrefix("#") {
                return .heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Menu Bar

struct MenuBarPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            PaneHeader(.menuBar)

            Section("Preview") {
                MenuBarPreview(store: store)
            }

            Section("Providers") {
                ForEach(settings.providerOrder.providers, id: \.self) { provider in
                    ProviderRows(provider: provider, shown: provider.menuBarShown, window: provider.menuBarWindow)
                }
                Caption("If a provider doesn't have the window you picked, its tightest window shows instead.")
            }

            Section("Text") {
                ChoiceRow(title: "Show", selection: $settings.menuBarValue,
                          choices: PercentKind.allCases, label: \.title)
                ChoiceRow(title: "Window label", selection: $settings.menuBarLabel,
                          choices: LabelStyle.allCases, label: \.title)
                Toggle("Percent sign", isOn: $settings.menuBarPercentSign)
                ChoiceRow(title: "Between windows", selection: $settings.menuBarSeparator,
                          choices: WindowSeparator.allCases, label: \.title)
            }

            Section("Reset time") {
                ChoiceRow(title: "Show as", selection: $settings.menuBarReset,
                          choices: MenuBarReset.allCases, label: \.title)
                if settings.menuBarReset == .countdown {
                    ChoiceRow(title: "Precision", selection: $settings.menuBarCountdownUnits,
                              choices: [1, 2], label: { $0 == 1 ? "One unit (2h)" : "Two units (2h 10m)" })
                }
                if settings.menuBarReset.face != nil {
                    ForEach(settings.providerOrder.providers, id: \.self) { provider in
                        ChoiceRow(title: "\(provider.name) window", selection: $settings[dynamicMember: provider.menuBarClockWindow],
                                  choices: provider.clockWindowChoices, label: \.title)
                            .disabled(!settings[keyPath: provider.menuBarShown])
                    }
                    Caption("Choose each clock's window independently of the percentages. If that window is unavailable, its tightest window is used.")
                    ChoiceRow(title: "Lit part", selection: $settings.menuBarClockFill,
                              choices: ClockFill.allCases, label: \.title)
                    SliderRow(title: "Unlit part", value: $settings.menuBarClockDim,
                              range: 0.05...0.7, step: 0.05, format: SliderRow.percent)
                    if settings.menuBarReset == .ringClock {
                        SliderRow(title: "Ring thickness", value: $settings.menuBarRingWidth,
                                  range: 0.5...3, step: 0.25)
                    }
                    Caption("The hand turns clockwise from 12 as the selected window passes.")
                }
            }

            Section("Logo") {
                Toggle("Provider logo", isOn: Binding(
                    get: { settings.menuBarIcon || settings.menuBarReset.face != nil },
                    set: { settings.menuBarIcon = $0 }))
                    .disabled(settings.menuBarReset.face != nil)
                if settings.menuBarReset.face != nil {
                    Caption("The clock is drawn on the logo, so the logo stays while a clock is chosen.")
                }
                SliderRow(title: "Logo size", value: $settings.menuBarIconSize, range: 9...18, step: 0.5)
            }

            Section("Font") {
                SliderRow(title: "Size", value: $settings.menuBarFontSize, range: 9...15, step: 0.5)
                ChoiceRow(title: "Weight", selection: $settings.menuBarFontWeight,
                          choices: FontWeight.allCases, label: \.title)
                Toggle("Fixed-width digits", isOn: $settings.menuBarMonospacedDigits)
                Caption("Fixed-width digits keep the menu bar from shifting as the numbers change.")
            }

            Section("Color") {
                ChoiceRow(title: "Color", selection: $settings.menuBarColor,
                          choices: MenuBarColor.allCases, label: \.title)
                Caption("Level colors and where they start are set in Colors.")
            }

            Section("Spacing") {
                SliderRow(title: "Logo to text", value: $settings.menuBarIconGap, range: 0...10, step: 0.5)
                SliderRow(title: "Between windows", value: $settings.menuBarWindowGap, range: 0...12, step: 0.5)
                SliderRow(title: "Between providers", value: $settings.menuBarProviderGap, range: 0...24, step: 0.5)
            }

            Section("Hover") {
                Toggle("Show every window in a tooltip", isOn: $settings.menuBarTooltip)
            }

            RestoreDefaults(section: .menuBar)
        }
        .formStyle(.grouped)
    }
}

/// 지금 설정으로 그린 메뉴바 그림. 밝은 메뉴바와 어두운 메뉴바에 하나씩 놓아 본다.
/// 아직 읽은 값이 없으면 본보기 숫자로 그린다.
private struct MenuBarPreview: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let snapshot = store.snapshot.hasGauges ? store.snapshot : .sample(now: store.now)
        let parts = MenuBarText.parts(for: snapshot, now: store.now)
        VStack(spacing: 8) {
            strip(parts, dark: false)
            strip(parts, dark: true)
        }
    }

    private func strip(_ parts: [MenuBarPart], dark: Bool) -> some View {
        let image = StatusBarImage.make(parts, appearance: NSAppearance(named: dark ? .darkAqua : .aqua))
        return HStack {
            Spacer()
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .foregroundStyle(dark ? Color.white : Color.black)
                .padding(.horizontal, 10)
        }
        .frame(height: 26)
        .background(dark ? Color(white: 0.17) : Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Details

struct DetailsPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            PaneHeader(.details)

            Section("Preview") {
                HStack {
                    Spacer()
                    DetailsView(store: store)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                    Spacer()
                }
            }

            Section("Providers") {
                ForEach(settings.providerOrder.providers, id: \.self) { provider in
                    ProviderWindowRows(provider: provider, shown: provider.detailsShown,
                                       window: provider.detailsWindow,
                                       gauges: provider.usage(in: store.snapshot)?.gauges ?? [])
                }
            }

            Section("Content") {
                ChoiceRow(title: "Show", selection: $settings.detailsValue,
                          choices: PercentKind.allCases, label: \.title)
                Toggle("Plan", isOn: $settings.detailsPlan)
                Toggle("Bar", isOn: $settings.detailsBars)
                Toggle("Time to reset", isOn: $settings.detailsCountdown)
                Toggle("Reset time", isOn: $settings.detailsResetTime)
                Toggle("Pace", isOn: $settings.detailsPace)
                Caption("Pace projects your current rate to the end of the window: whether you'll run out first, or how much you'll have left.")
                Toggle("Last updated", isOn: $settings.detailsUpdated)
            }

            Section("Size") {
                SliderRow(title: "Width", value: $settings.detailsWidth, range: 240...460, step: 10)
            }

            RestoreDefaults(section: .details)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Overlay

struct OverlayPane: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var store: UsageStore
    let actions: SettingsActions

    var body: some View {
        Form {
            PaneHeader(.overlay)

            Section("Visibility") {
                Toggle("Show overlay", isOn: $settings.overlayVisible)
                SliderRow(title: "Opacity", value: $settings.overlayOpacity,
                          range: 0.2...1, step: 0.05, format: SliderRow.percent)
                Toggle("Click through", isOn: $settings.overlayClickThrough)
                Caption("Clicks go to the window underneath. Turn this off to drag the overlay or use its refresh button.")
                Toggle("Lock position", isOn: $settings.overlayLocked)
                LabeledContent("Position") {
                    Button("Reset Position", action: actions.resetOverlayPosition)
                }
            }

            Section("Providers") {
                ForEach(settings.providerOrder.providers, id: \.self) { provider in
                    ProviderWindowRows(provider: provider, shown: provider.overlayShown,
                                       window: provider.overlayWindow,
                                       gauges: provider.usage(in: store.snapshot)?.gauges ?? [])
                }
            }

            Section("Content") {
                ChoiceRow(title: "Show", selection: $settings.overlayValue,
                          choices: PercentKind.allCases, label: \.title)
                Toggle("Provider name", isOn: $settings.overlayHeader)
                Toggle("Plan", isOn: $settings.overlayPlan)
                    .disabled(!settings.overlayHeader)
                Toggle("Window name", isOn: $settings.overlayLabels)
                Toggle("Bar", isOn: $settings.overlayBars)
                Toggle("Percent", isOn: $settings.overlayPercent)
                Toggle("Time to reset", isOn: $settings.overlayCountdown)
                Toggle("Last updated and refresh button", isOn: $settings.overlayFooter)
            }

            Section("Size") {
                SliderRow(title: "Width", value: $settings.overlayWidth, range: 180...440, step: 2)
                SliderRow(title: "Text size", value: $settings.overlayScale,
                          range: 0.8...1.6, step: 0.05, format: SliderRow.percent)
                SliderRow(title: "Bar thickness", value: $settings.overlayBarHeight, range: 2...12, step: 0.5)
            }

            Section("Background") {
                ChoiceRow(title: "Material", selection: $settings.overlayBackground,
                          choices: OverlayBackground.choices, label: \.title)
                SliderRow(title: "Corner radius", value: $settings.overlayCornerRadius, range: 0...24, step: 1)
                Toggle("Border", isOn: $settings.overlayBorder)
            }

            Section("Window") {
                Toggle("Show on every Space", isOn: $settings.overlayAllSpaces)
                Toggle("Keep above other windows", isOn: $settings.overlayAlwaysOnTop)
            }

            RestoreDefaults(section: .overlay)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Colors

struct ColorsPane: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            PaneHeader(.colors)

            Section("Levels") {
                // 세 단계가 실제로 어떻게 보이는지. 각 단계 한가운데 값으로 막대를 채운다.
                HStack(spacing: 12) {
                    ForEach([Level.high, .mid, .low], id: \.self) { level in
                        UsageBar(fraction: sample(level) / 100, color: settings.color(for: level).color, height: 6)
                    }
                }
                ColorRow(title: "Plenty left", color: $settings.colorHigh)
                SliderRow(title: "Running low below", value: $settings.midBelow,
                          range: max(settings.lowBelow, 1)...100, step: 1, format: SliderRow.whole)
                ColorRow(title: "Running low", color: $settings.colorMid)
                SliderRow(title: "Almost out below", value: $settings.lowBelow,
                          range: 0...min(settings.midBelow, 99), step: 1, format: SliderRow.whole)
                ColorRow(title: "Almost out", color: $settings.colorLow)
                Caption("Levels go by how much is left, whichever percent you show. They color the bars in the overlay and details, and the menu bar when its color is on.")
            }

            Section("Provider logos") {
                TintRow(title: "Claude", tint: $settings.claudeAccent)
                TintRow(title: "Codex", tint: $settings.codexAccent)
                Caption("Used in the overlay, the details window, and these settings. The menu bar logo always matches the menu bar.")
            }

            RestoreDefaults(section: .colors)
        }
        .formStyle(.grouped)
    }

    private func sample(_ level: Level) -> Double {
        switch level {
        case .high: return (settings.midBelow + 100) / 2
        case .mid: return (settings.lowBelow + settings.midBelow) / 2
        case .low: return settings.lowBelow / 2
        }
    }
}

/// 로고 색 한 줄. 색을 고르면 그 색으로, "Text Color" 를 누르면 글자색을 그대로 따른다.
private struct TintRow: View {
    let title: String
    @Binding var tint: Tint

    var body: some View {
        LabeledContent(title) {
            HStack {
                if tint != .text {
                    Button("Use Text Color") { tint = .text }
                }
                ColorPicker(title, selection: Binding(get: { tint.color }, set: { tint = .custom(RGBA($0)) }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}
