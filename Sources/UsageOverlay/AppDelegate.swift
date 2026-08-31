import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: OverlayPanel!
    private let store = UsageStore()
    private var cancellables = Set<AnyCancellable>()

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
        statusItem.button?.image = StatusBarImage.make([])
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.updateStatusTitle(snapshot) }
            .store(in: &cancellables)

        store.start()
    }

    /// 메뉴바에는 각 공급자의 최대 사용률만 짧게. 예) 버스트 54%  노트 21%
    private func updateStatusTitle(_ snapshot: Snapshot) {
        var parts: [(NSImage, String)] = []
        if let peak = snapshot.claude?.peak { parts.append((Icons.claude, "\(Int(peak.rounded()))%")) }
        if let peak = snapshot.codex?.peak { parts.append((Icons.codex, "\(Int(peak.rounded()))%")) }
        statusItem.button?.image = StatusBarImage.make(parts)
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(to: menu, "Show Overlay", #selector(toggleOverlay), state: Prefs.overlayVisible)
        add(to: menu, "Click Through", #selector(toggleClickThrough), state: Prefs.clickThrough)

        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [1.0, 0.85, 0.7, 0.5] {
            let item = NSMenuItem(title: "\(Int(value * 100))%",
                                  action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(Prefs.opacity - value) < 0.01 ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for seconds in [5, 10, 30, 60, 600] {
            let item = NSMenuItem(title: Self.intervalLabel(seconds), action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = Prefs.refreshSeconds == seconds ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

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
