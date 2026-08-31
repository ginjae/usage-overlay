import AppKit
import SwiftUI

/// 모든 스페이스·전체화면 위에 떠 있는 테두리 없는 HUD 패널.
final class OverlayPanel: NSPanel {
    /// 우리가 옮기는 중에는 위치를 저장하지 않는다.
    /// 안 그러면 내용 크기가 확정되기 전의 임시 좌표가 저장돼 버린다.
    private var isPositioning = false

    init(store: UsageStore) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 244, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = Prefs.clickThrough

        let hosting = NSHostingController(rootView: OverlayView(store: store))
        hosting.sizingOptions = [.preferredContentSize]  // 내용 높이에 맞춰 창이 따라온다
        contentViewController = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(didMove),
                                               name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(didResize),
                                               name: NSWindow.didResizeNotification, object: self)

        applyStoredPosition()
    }

    /// 새로고침 버튼이 클릭을 받으려면 패널이 key가 될 수 있어야 한다.
    /// `.nonactivatingPanel` 이라 key가 되어도 앱이 전면으로 튀어나오지는 않는다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applyStoredPosition() {
        isPositioning = true
        setFrameTopLeftPoint(Prefs.topLeft ?? defaultTopLeft())
        DispatchQueue.main.async { self.isPositioning = false }
    }

    func resetPosition() {
        Prefs.topLeft = nil
        setFrameTopLeftPoint(defaultTopLeft())
    }

    func setClickThrough(_ on: Bool) {
        Prefs.clickThrough = on
        ignoresMouseEvents = on
    }

    /// 주 화면(메뉴바가 있는 화면) 오른쪽 위 모서리.
    /// `NSScreen.main` 은 키 윈도우가 있는 화면이라 액세서리 앱에서는 어느 모니터가 될지 알 수 없다.
    /// `screens.first` 는 항상 원점(0,0)을 가진 주 화면이라 기본 위치가 예측 가능해진다.
    private func defaultTopLeft() -> NSPoint {
        guard let visible = NSScreen.screens.first?.visibleFrame else {
            return NSPoint(x: 40, y: 400)
        }
        return NSPoint(x: visible.maxX - frame.width - 16, y: visible.maxY - 16)
    }

    @objc private func didMove() {
        guard isVisible, !isPositioning else { return }
        Prefs.topLeft = NSPoint(x: frame.minX, y: frame.maxY)
    }

    /// 내용 높이가 바뀌어도 좌상단이 제자리에 남도록.
    @objc private func didResize() {
        guard !isPositioning, let topLeft = Prefs.topLeft else { return }
        if frame.minX != topLeft.x || frame.maxY != topLeft.y {
            setFrameTopLeftPoint(topLeft)
        }
    }
}
