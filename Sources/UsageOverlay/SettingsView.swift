import AppKit
import SwiftUI

/// 뷰 안에서만 쓰는 상태. `@State` 와 똑같다.
/// macOS 27 SDK 는 `@State` 를 매크로로 먼저 찾는데, Command Line Tools 에는 그 매크로 플러그인이 없어 빌드가 멈춘다.
/// 다른 이름을 거치면 예전처럼 속성 래퍼로 쓰이고, Xcode 에서도 그대로 빌드된다.
typealias ViewState<Value> = SwiftUI.State<Value>

/// 설정 창. 열려 있는 동안에는 Dock 과 ⌘-Tab 에 나타나 다른 앱처럼 오갈 수 있고, 닫으면 메뉴바로만 돌아간다.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(store: UsageStore, updater: Updater, actions: SettingsActions) {
        let hosting = NSHostingController(rootView: SettingsView(store: store, updater: updater, actions: actions))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Usage Overlay Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // 분할 뷰의 배경을 제목 표시줄까지 이어 경계를 하나로 맞춘다.
        // 별도 제목 표시줄 배경은 호환 레이아웃에서 사이드바보다 2pt 먼저 시작한다.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 640))
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
    var openReleaseNotes: () -> Void
    var resetOverlayPosition: () -> Void
}

/// 왼쪽에서 쪽을 고르고 오른쪽에서 고친다. 고치는 대로 메뉴바와 오버레이에 바로 보인다.
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater
    let actions: SettingsActions
    @ViewState private var pane: Pane? = .menuBar

    enum Pane: CaseIterable, Identifiable {
        case general, menuBar, details, overlay, colors

        var id: Self { self }

        var title: String {
            switch self {
            case .general: return "General"
            case .menuBar: return "Menu Bar"
            case .details: return "Details"
            case .overlay: return "Overlay"
            case .colors: return "Colors"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .menuBar: return "menubar.rectangle"
            case .details: return "list.bullet.rectangle"
            case .overlay: return "rectangle.on.rectangle"
            case .colors: return "paintpalette"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 170, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(pane ?? .general)
                .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder private func detail(_ pane: Pane) -> some View {
        switch pane {
        case .general: GeneralPane(store: store, updater: updater, actions: actions)
        case .menuBar: MenuBarPane(store: store)
        case .details: DetailsPane(store: store)
        case .overlay: OverlayPane(store: store, actions: actions)
        case .colors: ColorsPane()
        }
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
