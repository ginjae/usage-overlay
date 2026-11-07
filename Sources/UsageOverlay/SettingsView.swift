import AppKit
import SwiftUI

/// 뷰 안에서만 쓰는 상태. `@State` 와 똑같다.
/// macOS 27 SDK 는 `@State` 를 매크로로 먼저 찾는데, Command Line Tools 에는 그 매크로 플러그인이 없어 빌드가 멈춘다.
/// 다른 이름을 거치면 예전처럼 속성 래퍼로 쓰이고, Xcode 에서도 그대로 빌드된다.
typealias ViewState<Value> = SwiftUI.State<Value>

/// 앱이 Liquid Glass 로 그려지는지. macOS 26 이상에서, 26 SDK 이상으로 빌드했을 때만 그렇다.
let drawsLiquidGlass: Bool = {
    #if compiler(>=6.2)
    if #available(macOS 26, *) { return true }
    #endif
    return false
}()

/// 설정 창. 열려 있는 동안에는 Dock 과 ⌘-Tab 에 나타나 다른 앱처럼 오갈 수 있고, 닫으면 메뉴바로만 돌아간다.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let navigation = SettingsNavigation()

    init(store: UsageStore, updater: Updater, actions: SettingsActions) {
        let hosting = NSHostingController(rootView: SettingsView(store: store, updater: updater,
                                                                 navigation: navigation, actions: actions))
        hosting.sizingOptions = [.minSize]
        // 뒤로 · 앞으로 단추를 SwiftUI 가 창 도구 막대에 올린다.
        hosting.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Usage Overlay Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        // 시스템 설정처럼 쪽 이름은 각 쪽 맨 위 머리에 크게 쓴다.
        // Liquid Glass 에서는 머리가 도구 막대 밑으로 올라가면 막대에도 띄우므로 SettingsView 가 제목을 다룬다.
        if !drawsLiquidGlass {
            // 도구 막대 띠를 따로 칠하지 않고 사이드바와 본문 배경을 맨 위까지 잇는다.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 680))
        window.center()
        window.setFrameAutosaveName("Settings")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// 설정 창이 앱 쪽에 부탁하는 일. 알림창을 띄우거나 창을 옮기는 일은 AppDelegate 가 한다.
struct SettingsActions {
    var refresh: () -> Void
    var checkForUpdates: () -> Void
    var installUpdate: (Release) -> Void
    var openReleaseNotes: () -> Void
    var resetOverlayPosition: () -> Void
}

/// 지금 보는 쪽과 오간 기록. 시스템 설정처럼 뒤로 · 앞으로(⌘[ · ⌘])로 되짚는다.
/// 창을 닫았다 열어도 보던 쪽에서 다시 시작한다.
final class SettingsNavigation: ObservableObject {
    @Published private(set) var pane: SettingsView.Pane = .menuBar
    @Published private(set) var back: [SettingsView.Pane] = []
    @Published private(set) var forward: [SettingsView.Pane] = []

    func open(_ next: SettingsView.Pane) {
        guard next != pane else { return }
        back.append(pane)
        forward.removeAll()
        pane = next
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(pane)
        pane = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(pane)
        pane = next
    }
}

/// 시스템 설정과 같은 짜임. 왼쪽 위에서 찾고 앱 정보를 본 뒤 쪽을 고르고, 오른쪽에서 고친다.
/// 고치는 대로 메뉴바와 오버레이에 바로 보인다.
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater
    @ObservedObject var navigation: SettingsNavigation
    let actions: SettingsActions
    @ViewState private var query = ""

    enum Pane: CaseIterable, Identifiable {
        case general, updates, menuBar, details, overlay, colors

        /// 사이드바의 묶음. 묶음 사이는 시스템 설정처럼 한 칸 띄운다.
        static let groups: [[Pane]] = [[.general, .updates], [.menuBar, .details, .overlay, .colors]]

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return "General"
            case .updates: return "Updates"
            case .menuBar: return "Menu Bar"
            case .details: return "Details"
            case .overlay: return "Overlay"
            case .colors: return "Colors"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .updates: return "arrow.down.circle.fill"
            case .menuBar: return "rectangle.topthird.inset.filled"
            case .details: return "list.bullet"
            case .overlay: return "rectangle.on.rectangle"
            case .colors: return "paintpalette.fill"
            }
        }

        /// 기호를 칠하는 그라데이션. 왼쪽 위가 밝고 오른쪽 아래가 짙다.
        /// 앱 아이콘의 주황 말풍선 · 초록 막대 · 연보라 바탕과 같은 결의 색만 쓴다.
        var tint: [Color] {
            switch self {
            case .general: return [Color(hex: 0xAFB5C0), Color(hex: 0x626876)]
            case .updates: return [Color(hex: 0x74EBB8), Color(hex: 0x12B091)]
            case .menuBar: return [Color(hex: 0xFFD84D), Color(hex: 0xFF8A3D)]
            case .details: return [Color(hex: 0x7CC8FF), Color(hex: 0x3A82F2)]
            case .overlay: return [Color(hex: 0xBBAFFF), Color(hex: 0x7462EC)]
            case .colors: return [Color(hex: 0xFFC94A), Color(hex: 0xFF6F8E), Color(hex: 0x8D6FF2)]
            }
        }

        /// 쪽 맨 위 머리에 쓰는 한두 줄 설명.
        var summary: String {
            switch self {
            case .general:
                return "Choose when Usage Overlay starts, how often it checks your usage, and where it finds the Claude and Codex CLIs."
            case .updates:
                return "Get new versions of Usage Overlay from GitHub. Nothing is installed until you choose to update."
            case .menuBar:
                return "Choose which usage appears in the menu bar and how it looks."
            case .details:
                return "Choose what the menu shows when you click Usage Overlay in the menu bar."
            case .overlay:
                return "Set up the floating panel that keeps your usage on screen above other windows."
            case .colors:
                return "Choose the colors for each usage level and for the provider logos."
            }
        }

        /// 사이드바 검색이 쪽 이름 말고도 찾아 주는 말. 각 쪽에 있는 줄 이름을 따른다.
        private var keywords: String {
            switch self {
            case .general:
                return "launch at login startup refresh every interval providers order command-line tools cli path claude codex"
            case .updates:
                return "software update version installed release notes check now automatically download install"
            case .menuBar:
                return "preview providers windows text show percent left used window label percent sign between windows separator reset time countdown logo clock ring lit unlit logo size font weight fixed-width digits color spacing hover tooltip"
            case .details:
                return "menu preview providers windows selected percent left used plan bar time to reset reset time pace last updated width"
            case .overlay:
                return "floating panel visibility show overlay opacity click through lock position reset position providers windows selected provider name plan window name bar percent time to reset last updated refresh button width text size bar thickness background material liquid glass corner radius border every space keep above other windows"
            case .colors:
                return "levels plenty left running low almost out level colors provider logos text color"
            }
        }

        /// 검색어의 낱말마다 이 쪽 이름이나 줄 이름의 어느 낱말 첫머리와 맞는지.
        /// 낱말 중간은 보지 않는다. "pace" 로 찾을 때 "space" 가 걸리지 않게.
        func matches(_ query: String) -> Bool {
            let words = Self.words(in: title + " " + keywords)
            return Self.words(in: query).allSatisfy { term in
                words.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
            }
        }

        private static func words(in text: String) -> [Substring] {
            text.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        }
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationSplitView {
            sidebar
                // 시스템 설정처럼 사이드바 폭은 고정이다. 이 창은 AppKit 이 띄워 열 폭 지정만으로는 따르지 않아 틀로 묶는다.
                .frame(width: 220)
                .navigationSplitViewColumnWidth(220)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(navigation.pane)
                .toolbar {
                    ToolbarItem(placement: .navigation) { HistoryButtons(navigation: navigation) }
                }
                .modifier(ScrollEdgeToolbar(title: navigation.pane.title))
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
        .frame(minWidth: 700, minHeight: 480)
    }

    private var sidebar: some View {
        List(selection: Binding(get: { navigation.pane }, set: { if let pane = $0 { navigation.open(pane) } })) {
            if !searching {
                Section {
                    AppRow(updater: updater) { navigation.open(.updates) }
                    if updater.pending != nil {
                        UpdateAvailableRow { navigation.open(.updates) }
                    }
                }
            }
            ForEach(Pane.groups.indices, id: \.self) { index in
                let panes = Pane.groups[index].filter { $0.matches(query) }
                if !panes.isEmpty {
                    Section {
                        ForEach(panes) { pane in
                            PaneRow(pane: pane, badge: pane == .updates && updater.pending != nil)
                                .tag(pane)
                        }
                    }
                }
            }
            if searching && !Pane.allCases.contains(where: { $0.matches(query) }) {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private func detail(_ pane: Pane) -> some View {
        switch pane {
        case .general: GeneralPane(store: store, actions: actions)
        case .updates: UpdatesPane(updater: updater, actions: actions)
        case .menuBar: MenuBarPane(store: store)
        case .details: DetailsPane(store: store)
        case .overlay: OverlayPane(store: store, actions: actions)
        case .colors: ColorsPane()
        }
    }
}

// MARK: - 사이드바

/// 시스템 설정의 Apple 계정 줄 자리. 앱 아이콘과 지금 버전을 보여 주고, 누르면 Updates 로 간다.
private struct AppRow: View {
    @ObservedObject var updater: Updater
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage Overlay")
                        .font(.headline)
                    Text(updater.currentVersion.map { "Version \($0.description)" } ?? "Development build")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows updates")
    }
}

/// 시스템 설정의 "Software Update Available" 줄. 새 버전이 있을 때만 앱 정보 바로 아래에 붙는다.
private struct UpdateAvailableRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Update Available")
                Spacer(minLength: 4)
                CountBadge()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PaneRow: View {
    let pane: SettingsView.Pane
    let badge: Bool

    var body: some View {
        HStack {
            Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
            if badge {
                Spacer(minLength: 4)
                CountBadge()
                    .accessibilityLabel("Update available")
            }
        }
    }
}

/// 빨간 동그라미 숫자. 시스템 설정이 받을 업데이트를 알리는 모양을 따른다.
private struct CountBadge: View {
    var count = 1

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 18, minHeight: 18)
            .background(Circle().fill(Color.red))
    }
}

/// 쪽 아이콘. 앱 아이콘처럼 흰 타일 위에 그라데이션 기호를 얹는다. 어두운 화면에서는 타일만 어둡게 바꾼다.
struct PaneIcon: View {
    let pane: SettingsView.Pane
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
        shape
            .fill(LinearGradient(colors: dark ? [Color(white: 0.31), Color(white: 0.23)]
                                              : [.white, Color(hex: 0xF0F1F6)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.14 : 0.09), lineWidth: max(0.5, size / 60)))
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: pane.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(dark ? 0.35 : 0.10), radius: size * 0.06, y: size * 0.03)
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 도구 막대의 뒤로 · 앞으로 단추.
private struct HistoryButtons: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        ControlGroup {
            Button(action: navigation.goBack) { Label("Back", systemImage: "chevron.left") }
                .disabled(navigation.back.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back")
            Button(action: navigation.goForward) { Label("Forward", systemImage: "chevron.right") }
                .disabled(navigation.forward.isEmpty)
                .keyboardShortcut("]", modifiers: .command)
                .help("Forward")
        }
        .controlGroupStyle(.navigation)
    }
}

/// 쪽 맨 위의 큰 머리. 아이콘 · 이름 · 무엇을 하는 쪽인지 한두 줄.
struct PaneHeader: View {
    let pane: SettingsView.Pane
    @Environment(\.reportPaneTitleTop) private var reportTitleTop

    init(_ pane: SettingsView.Pane) { self.pane = pane }

    var body: some View {
        Section {
            VStack(spacing: 6) {
                PaneIcon(pane: pane, size: 52)
                    .padding(.bottom, 4)
                Text(pane.title)
                    .font(.title.bold())
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { reportTitleTop($0) }
                Text(pane.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

/// 쪽 머리의 큰 제목 윗변이 도구 막대 아래 끝에서 얼마나 떨어져 있는지 알린다. 막대에 가려지기 시작하면 음수다.
/// 스크롤 뷰 좌표는 막대 아래 끝이 0 이다. 도구 막대가 쪽 이름을 띄울 때를 정한다.
private struct PaneTitleTopKey: EnvironmentKey {
    static let defaultValue: (CGFloat) -> Void = { _ in }
}

extension EnvironmentValues {
    var reportPaneTitleTop: (CGFloat) -> Void {
        get { self[PaneTitleTopKey.self] }
        set { self[PaneTitleTopKey.self] = newValue }
    }
}

/// 시스템 설정처럼, 맨 위에서는 도구 막대가 내용과 이어져 보이다가
/// 내용이 막대 밑으로 들어가면 경계선을 긋고, 큰 제목이 막대에 닿으면 막대에 쪽 이름을 띄운다.
/// Liquid Glass 에서만 그렇게 하고, 그 전 macOS 에서는 늘 막대를 비워 둔다.
private struct ScrollEdgeToolbar: ViewModifier {
    let title: String
    /// 맨 위에서 조금이라도 내려왔는지.
    @ViewState private var scrolled = false
    @ViewState private var titleTop = CGFloat.infinity

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content
                // .hard 는 맨 위에서도 경계선을 그어서, 내려왔을 때만 켠다. 기본 효과는 아무것도 긋지 않는다.
                .scrollEdgeEffectStyle(scrolled ? .hard : nil, for: .top)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in
                    scrolled = now
                }
                .environment(\.reportPaneTitleTop) { titleTop = $0 }
                .navigationTitle(title)
                // 시스템 설정처럼 큰 제목 윗변이 막대 아래 끝에 닿으면.
                .toolbar(removing: titleTop <= 4 ? nil : .title)
                // 다른 쪽으로 가면 그 쪽은 맨 위에서 시작한다.
                .onChange(of: title) {
                    scrolled = false
                    titleTop = .infinity
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - 여러 쪽이 같이 쓰는 줄

/// 슬라이더 한 줄. 이름 옆에 지금 값을 숫자로 보여 준다.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = SliderRow.points

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                // `step` 을 Slider 에 넘기면 칸마다 눈금이 찍혀 촘촘한 점선이 된다. 값만 칸에 맞춘다.
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .frame(minWidth: 180)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    static func points(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) pt" : String(format: "%.1f pt", value)
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func whole(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}

/// 고르는 값 한 줄. 선택지 이름은 각 값의 title 을 쓴다.
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices, id: \.self) { choice in
                Text(label(choice)).tag(choice)
            }
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: RGBA

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color.color }, set: { color = RGBA($0) }),
                    supportsOpacity: false)
    }
}

/// 공급자 켜고 끄기. 메뉴바에서는 단일 창 선택도 붙인다.
struct ProviderRows: View {
    @ObservedObject var settings = Settings.shared
    let provider: Provider
    let shown: ReferenceWritableKeyPath<Settings, Bool>
    var window: ReferenceWritableKeyPath<Settings, WindowChoice>?

    var body: some View {
        Toggle(isOn: $settings[dynamicMember: shown]) {
            HStack(spacing: 6) {
                Image(nsImage: provider.icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(settings[keyPath: provider.accent].color)
                Text(provider.name)
            }
        }
        if let window {
            ChoiceRow(title: "\(provider.name) windows", selection: $settings[dynamicMember: window],
                      choices: provider.windowChoices, label: \.title)
                .disabled(!settings[keyPath: shown])
        }
    }
}

/// 상세 창과 오버레이에서 공급자별로 여러 창을 켜고 끈다.
struct ProviderWindowRows: View {
    @ObservedObject var settings = Settings.shared
    let provider: Provider
    let shown: ReferenceWritableKeyPath<Settings, Bool>
    let window: ReferenceWritableKeyPath<Settings, WindowSelection>
    let gauges: [Gauge]

    private var selection: WindowSelection { settings[keyPath: window] }
    private var labels: [String] { provider.windowLabels(from: gauges, selection: selection) }

    var body: some View {
        ProviderRows(provider: provider, shown: shown)
        Group {
            ChoiceRow(title: "\(provider.name) windows", selection: Binding(
                get: { selection.mode },
                set: { mode in
                    switch mode {
                    case .all: settings[keyPath: window] = .all
                    case .tightest: settings[keyPath: window] = .tightest
                    case .selected:
                        if selection.mode != .selected {
                            settings[keyPath: window] = .selected(Set(labels))
                        }
                    }
                }), choices: WindowSelection.Mode.allCases, label: \.title)
            if selection.mode == .selected {
                // Form은 중첩된 행을 펼친다. 이름만 ID로 쓰면 Codex 행이 Claude의
                // 바인딩을 재사용하므로 화면·공급자를 가리키는 설정 키 경로도 포함한다.
                ForEach(labels.map { WindowToggleID(preference: window, label: $0) }, id: \.self) { row in
                    let label = row.label
                    Toggle(label, isOn: Binding(
                        get: { selection.selectedLabels.contains(label) },
                        set: { enabled in
                            var selected = selection.selectedLabels
                            if enabled { selected.insert(label) } else { selected.remove(label) }
                            settings[keyPath: window] = .selected(selected)
                        }))
                        .accessibilityLabel("\(provider.name) \(label)")
                }
            }
        }
        .disabled(!settings[keyPath: shown])
    }
}

/// 쪽 맨 아래 되돌리기 단추. 그 쪽 값만 기본으로 돌린다.
struct RestoreDefaults: View {
    let section: Settings.Section

    var body: some View {
        Section {
            HStack {
                Spacer()
                Button("Restore Defaults") { Settings.shared.reset(section) }
            }
        }
    }
}

/// 설명 한 줄. 무엇을 바꾸는지 이름만으로 모호할 때 붙인다.
struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension Snapshot {
    /// 아직 읽은 값이 없을 때 미리보기에 쓰는 본보기.
    static func sample(now: Date) -> Snapshot {
        func gauge(_ label: String, used: Double, minutes: Double, resetsIn: TimeInterval) -> Gauge {
            Gauge(id: label, label: label, percent: used,
                  resetsAt: now.addingTimeInterval(resetsIn), windowMinutes: minutes)
        }
        return Snapshot(
            claude: ProviderUsage(name: "Claude",
                                  gauges: [gauge("5-hour", used: 61, minutes: 300, resetsIn: 7800),
                                           gauge("Weekly", used: 38, minutes: 10080, resetsIn: 302_400)],
                                  plan: "Max", updatedAt: now),
            codex: ProviderUsage(name: "Codex",
                                 gauges: [gauge("5-hour", used: 18, minutes: 300, resetsIn: 12_600),
                                          gauge("Weekly", used: 83, minutes: 10080, resetsIn: 86_400)],
                                 plan: "Plus", updatedAt: now))
    }
}
