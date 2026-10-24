import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: OverlayPanel!
    private let store = UsageStore()
    private let updater = Updater()
    private let settings = Settings.shared
    private var cancellables = Set<AnyCancellable>()
    private lazy var details = DetailsPanel(details: DetailsView(
        store: store,
        refresh: { [weak self] in self?.store.refresh() },
        resetOverlayPosition: { [weak self] in self?.resetOverlayPosition() },
        openSettings: { [weak self] in self?.openSettings() },
        quit: { NSApp.terminate(nil) }))
    private lazy var settingsWindow = SettingsWindowController(
        store: store, updater: updater,
        actions: SettingsActions(refresh: { [weak self] in self?.store.refresh() },
                                 checkForUpdates: { [weak self] in self?.checkForUpdates() },
                                 openReleaseNotes: { [weak self] in self?.openReleasesPage() },
                                 resetOverlayPosition: { [weak self] in self?.resetOverlayPosition() }))
    /// 내용이 달라졌을 때만 메뉴바 이미지와 툴팁을 교체한다.
    private var renderedParts: [MenuBarPart] = []
    private var renderedTooltip: String?
    /// 바뀐 설정이 CLI 조회나 업데이트 검사에 닿을 때만 그쪽을 깨운다.
    private var configuration = UsageStore.Configuration.preferences
    private var autoUpdate = Settings.shared.autoUpdate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        panel = OverlayPanel(store: store)
        panel.apply(settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            // 오른쪽 클릭은 짧은 메뉴로 받는다. 상세 창을 거치지 않고 설정과 종료에 닿는다.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItem()

        // 스냅샷과 분 단위 시계에 반응한다.
        // 남은 시간을 메뉴바에 띄운 경우 값이 그대로여도 카운트다운은 흘러야 한다.
        store.$snapshot.map { _ in () }
            .merge(with: store.$now.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)

        // objectWillChange 는 값이 바뀌기 직전에 울린다. 다음 차례로 미뤄 바뀐 값을 읽는다.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.settingsChanged() }
            .store(in: &cancellables)

        observeWorkspaceActivity()
        store.start()

        updater.onCheckFinished = { [weak self] outcome, userInitiated in
            self?.checkFinished(outcome, userInitiated: userInitiated)
        }
        updater.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        updater.stop()
    }

    private func observeWorkspaceActivity() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, Notification.Name, UsageStore.SuspensionReason)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, .systemSleep),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .displaySleep),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession),
        ]
        for (sleep, wake, reason) in events {
            for (name, suspended) in [(sleep, true), (wake, false)] {
                center.publisher(for: name)
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.store.setSuspended(suspended, for: reason) }
                    .store(in: &cancellables)
            }
        }
    }

    /// 설정 창에서 무엇이든 바뀌면 불린다. 그리는 쪽은 모두 다시 그리고,
    /// 공급자나 조회 주기처럼 CLI 에 닿는 값이 바뀌었을 때만 조회 쪽을 깨운다.
    private func settingsChanged() {
        updateStatusItem(force: true)
        panel.apply(settings)
        let next = UsageStore.Configuration.preferences
        if next != configuration {
            configuration = next
            store.settingsChanged()
        }
        if settings.autoUpdate != autoUpdate {
            autoUpdate = settings.autoUpdate
            updater.settingsChanged()
        }
    }

    /// 메뉴바 그림과 툴팁을 현재 설정에 맞춰 다시 만든다.
    /// 글꼴 · 간격 · 색은 조각에 담기지 않으므로 설정이 바뀌었을 때는 조각이 같아도 다시 그린다.
    private func updateStatusItem(force: Bool = false) {
        guard let button = statusItem.button else { return }
        let parts = MenuBarText.parts(for: store.snapshot, now: store.now)
        if force || parts != renderedParts {
            renderedParts = parts
            button.image = StatusBarImage.make(parts)
        }
        let tooltip = settings.menuBarTooltip ? MenuBarText.tooltip(for: store.snapshot, now: store.now) : nil
        if tooltip != renderedTooltip {
            renderedTooltip = tooltip
            button.toolTip = tooltip
        }
    }

    // MARK: - 메뉴바 클릭

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            toggleDetails()
        }
    }

    private func toggleDetails() {
        guard let button = statusItem.button else { return }
        if details.isVisible || details.justDismissed {
            details.dismiss()
        } else {
            details.show(below: button)
        }
    }

    private func showQuickMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(item("Refresh Now", #selector(refreshNow), key: "r"))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    /// 설정 창을 띄우는 동안 보이는 메뉴. 평소엔 메뉴바 앱이라 안 보이지만,
    /// 이게 있어야 글상자에서 ⌘V 로 붙이고 ⌘W 로 창을 닫는다.
    private func makeMainMenu() -> NSMenu {
        let app = NSMenu(title: "Usage Overlay")
        app.addItem(item("Settings…", #selector(openSettings), key: ","))
        app.addItem(.separator())
        app.addItem(item("Quit Usage Overlay", #selector(quit), key: "q"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                                  keyEquivalent: "m"))
        NSApp.windowsMenu = window

        let main = NSMenu()
        for menu in [app, edit, window] {
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - 동작

    @objc private func refreshNow() { store.refresh() }

    @objc private func openSettings() {
        details.dismiss()
        settingsWindow.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func resetOverlayPosition() {
        panel.resetPosition()
        if !settings.overlayVisible { settings.overlayVisible = true }
    }

    // MARK: - 업데이트

    private func checkForUpdates() { updater.check(userInitiated: true) }

    private func openReleasesPage() { NSWorkspace.shared.open(Updater.releasesPage) }

    /// 자동 검사는 새 버전을 찾았을 때만 말을 건다. 직접 눌렀을 때는 결과가 무엇이든 답한다.
    private func checkFinished(_ outcome: Updater.Outcome, userInitiated: Bool) {
        switch outcome {
        case .found(let release):
            offerUpdate(release)
        case .upToDate:
            guard userInitiated else { return }
            let alert = NSAlert()
            alert.messageText = "You're up to date."
            alert.informativeText = updater.currentVersion.map { "Usage Overlay \($0) is the latest version." }
                ?? "Nothing newer has been released."
            run(alert)
        case .failed(let message):
            guard userInitiated else { return }
            let alert = NSAlert()
            alert.messageText = "Couldn't check for updates."
            alert.informativeText = message
            alert.addButton(withTitle: "Open Releases Page")
            alert.addButton(withTitle: "OK")
            if run(alert) == .alertFirstButtonReturn { openReleasesPage() }
        }
    }

    private func offerUpdate(_ release: Release) {
        let current = updater.currentVersion?.description ?? "?"
        let alert = NSAlert()
        alert.messageText = "Usage Overlay \(release.version) is available."
        let notes = Self.summary(of: release.notes)
        alert.informativeText = "You have \(current). Updating replaces the app and reopens it."
            + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch run(alert) {
        case .alertFirstButtonReturn:
            // 성공하면 앱이 그대로 종료되고 새 번들로 다시 뜬다. 여기 돌아오는 건 실패했을 때뿐이다.
            updater.install(release) { [weak self] message in
                guard let self else { return }
                let failure = NSAlert()
                failure.messageText = "Couldn't install the update."
                failure.informativeText = message
                failure.addButton(withTitle: "Open Releases Page")
                failure.addButton(withTitle: "OK")
                if self.run(failure) == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
            }
        case .alertThirdButtonReturn:
            Prefs.skippedVersion = release.version.description
        default:
            break
        }
    }

    /// 릴리스 노트는 길이가 정해져 있지 않다. 알림창이 화면을 다 덮지 않을 만큼만 싣는다.
    private static func summary(of notes: String) -> String {
        let limit = 600
        guard notes.count > limit else { return notes }
        return notes.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "\u{2026}"
    }

    /// 메뉴바 앱이라 늘 다른 앱이 앞에 있다. 알림창을 앞으로 끌어와야 보인다.
    @discardableResult
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
