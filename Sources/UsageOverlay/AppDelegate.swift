import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: OverlayPanel!
    private let store = UsageStore()
    private var cancellables = Set<AnyCancellable>()
    /// 지금 메뉴바에 그려져 있는 내용. 같은 그림을 1초마다 다시 합성하지 않으려고 들고 있다.
    private var renderedParts: [MenuBarPart] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        panel = OverlayPanel(store: store)
        if Prefs.overlayVisible {
            panel.orderFrontRegardless()
            // 내용 크기가 정해진 뒤에 자리를 잡아야 우상단 기본 위치가 제대로 나온다.
            DispatchQueue.main.async { self.panel.applyStoredPosition() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()

        // 스냅샷이 바뀔 때뿐 아니라 1초 시계에도 반응한다.
        // 남은 시간을 메뉴바에 띄운 경우 값이 그대로여도 카운트다운은 흘러야 한다.
        store.$snapshot.map { _ in () }
            .merge(with: store.$now.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)

        store.start()
    }

    /// 메뉴바 그림과 툴팁을 현재 설정에 맞춰 다시 만든다.
    private func updateStatusItem() {
        let parts = MenuBarText.parts(for: store.snapshot, now: store.now)
        if parts != renderedParts {
            renderedParts = parts
            statusItem.button?.image = StatusBarImage.make(parts)
        }
        statusItem.button?.toolTip = MenuBarText.tooltip(for: store.snapshot, now: store.now)
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(to: menu, "Show Overlay", #selector(toggleOverlay), state: Prefs.overlayVisible)
        add(to: menu, "Click Through", #selector(toggleClickThrough), state: Prefs.clickThrough)

        addSubmenu(to: menu, "Opacity") { submenu in
            for value in [1.0, 0.85, 0.7, 0.5] {
                addChoice(to: submenu, "\(Int(value * 100))%", #selector(setOpacity(_:)),
                          value: value, selected: abs(Prefs.opacity - value) < 0.01)
            }
        }

        addSubmenu(to: menu, "Refresh Interval") { submenu in
            for seconds in [5, 10, 30, 60, 600] {
                addChoice(to: submenu, Self.intervalLabel(seconds), #selector(setInterval(_:)),
                          value: seconds, selected: Prefs.refreshSeconds == seconds)
            }
        }

        addSubmenu(to: menu, "Menu Bar") { submenu in
            add(to: submenu, "Show Claude", #selector(toggleMenuBarClaude), state: Prefs.menuBarClaude)
            add(to: submenu, "Show Codex", #selector(toggleMenuBarCodex), state: Prefs.menuBarCodex)
            submenu.addItem(.separator())
            for window in MenuBarWindow.allCases {
                addChoice(to: submenu, window.title, #selector(setMenuBarWindow(_:)),
                          value: window.rawValue, selected: Prefs.menuBarWindow == window)
            }
            submenu.addItem(.separator())
            for value in MenuBarValue.allCases {
                addChoice(to: submenu, value.title, #selector(setMenuBarValue(_:)),
                          value: value.rawValue, selected: Prefs.menuBarValue == value)
            }
            submenu.addItem(.separator())
            add(to: submenu, "Window Label", #selector(toggleMenuBarLabel), state: Prefs.menuBarLabel)
            add(to: submenu, "Provider Icon", #selector(toggleMenuBarIcon), state: Prefs.menuBarIcon)
            add(to: submenu, "Reset Time", #selector(toggleMenuBarReset), state: Prefs.menuBarReset)
        }

        menu.addItem(.separator())
        add(to: menu, "Read from Chrome", #selector(toggleBrowser), state: Prefs.browserEnabled)
        if Prefs.browserEnabled {
            add(to: menu, "Hide Chrome Window", #selector(toggleHide), state: Prefs.hideWindow)
            add(to: menu, "Reopen Usage Tabs", #selector(reopenTabs))
        }

        menu.addItem(.separator())
        add(to: menu, "Refresh Now", #selector(refreshNow), key: "r")
        add(to: menu, "Reset Position", #selector(resetPosition))
        add(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin),
            state: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add(to: menu, "Quit", #selector(quit), key: "q")
    }

    private static func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60) min"
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector,
                     key: String = "", state: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let state { item.state = state ? .on : .off }
        menu.addItem(item)
        return item
    }

    /// 값 하나를 고르는 줄. 고른 값은 representedObject 로 실어 보낸다.
    private func addChoice(to menu: NSMenu, _ title: String, _ action: Selector,
                           value: Any, selected: Bool) {
        add(to: menu, title, action, state: selected).representedObject = value
    }

    private func addSubmenu(to menu: NSMenu, _ title: String, _ build: (NSMenu) -> Void) {
        let submenu = NSMenu()
        build(submenu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func toggleOverlay() {
        Prefs.overlayVisible.toggle()
        if Prefs.overlayVisible {
            panel.applyStoredPosition()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    @objc private func toggleClickThrough() {
        panel.setClickThrough(!Prefs.clickThrough)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Prefs.opacity = value
        panel.alphaValue = value
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        Prefs.refreshSeconds = seconds
        store.refresh()
    }

    // MARK: - 메뉴바 표시 설정

    @objc private func toggleMenuBarClaude() {
        Prefs.menuBarClaude.toggle()
        updateStatusItem()
    }

    @objc private func toggleMenuBarCodex() {
        Prefs.menuBarCodex.toggle()
        updateStatusItem()
    }

    @objc private func setMenuBarWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let window = MenuBarWindow(rawValue: raw) else { return }
        Prefs.menuBarWindow = window
        updateStatusItem()
    }

    @objc private func setMenuBarValue(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let value = MenuBarValue(rawValue: raw) else { return }
        Prefs.menuBarValue = value
        updateStatusItem()
    }

    @objc private func toggleMenuBarLabel() {
        Prefs.menuBarLabel.toggle()
        updateStatusItem()
    }

    @objc private func toggleMenuBarIcon() {
        Prefs.menuBarIcon.toggle()
        updateStatusItem()
    }

    @objc private func toggleMenuBarReset() {
        Prefs.menuBarReset.toggle()
        updateStatusItem()
    }

    // MARK: - 읽기

    @objc private func toggleBrowser() {
        Prefs.browserEnabled.toggle()
        store.refresh()
    }

    @objc private func toggleHide() {
        Prefs.hideWindow.toggle()
        store.refresh()  // 다음 확인에서 창 상태가 바로 맞춰진다
    }

    @objc private func reopenTabs() {
        store.claudeBrowser.closeTab()
        store.codexBrowser.closeTab()
        store.refresh()
    }

    @objc private func refreshNow() { store.refresh() }

    @objc private func resetPosition() {
        panel.resetPosition()
        if !Prefs.overlayVisible { toggleOverlay() }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\nTry moving the app to /Applications first."
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
