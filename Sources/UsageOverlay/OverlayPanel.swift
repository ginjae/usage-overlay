import AppKit
import ObjectiveC.runtime
import SwiftUI

/// 모든 스페이스·전체화면 위에 떠 있는 테두리 없는 HUD 패널.
final class OverlayPanel: NSPanel {
    /// 우리가 옮기는 중에는 위치를 저장하지 않는다.
    /// 안 그러면 내용 크기가 확정되기 전의 임시 좌표가 저장돼 버린다.
    private var isPositioning = false
    private let store: UsageStore
    /// 띄워 둔 상태. 다른 Space 에 가 있으면 `isVisible` 이 거짓이라 따로 센다.
    private var shown = false
    private var keepsGlassActive = false

    private static let activeAppearanceSelector = NSSelectorFromString("_hasActiveAppearance")
    private typealias ActiveAppearance = @convention(c) (NSWindow, Selector) -> Bool
    private static let systemActiveAppearance: ActiveAppearance? = {
        guard let method = class_getInstanceMethod(NSPanel.self, activeAppearanceSelector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: ActiveAppearance.self)
    }()

    /// AppKit 의 비공개 외형 판정. SwiftUI 의 appearsActive 는 유리의 비활성 재질을 막지 못한다.
    /// Liquid Glass 에서만 활성 외형을 유지하고, 실제 key/main 상태와 입력 포커스는 바꾸지 않는다.
    /// 다른 바탕은 원래 NSPanel 구현을 따른다. macOS 가 이 판정을 없애면 시스템 재질로 돌아간다.
    @objc(_hasActiveAppearance) private dynamic func activeAppearance() -> Bool {
        keepsGlassActive || Self.systemActiveAppearance?(self, Self.activeAppearanceSelector) == true
    }

    init(store: UsageStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 244, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

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

    /// 창의 성질을 설정에 맞춘다. 내용은 OverlayView 가 설정을 직접 따라 그린다.
    func apply(_ settings: Settings) {
        keepsGlassActive = settings.overlayBackground.usesLiquidGlass
        ignoresMouseEvents = settings.overlayClickThrough
        level = settings.overlayAlwaysOnTop ? .floating : .normal
        collectionBehavior = settings.overlayAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            : [.ignoresCycle]
        // macOS 27 부터는 OverlayView 의 WindowDragGesture 가 끈다. 둘 다 켜 두면 한 번 끌 때 두 번 움직일 수 있다.
        if #unavailable(macOS 27) {
            isMovableByWindowBackground = !settings.overlayLocked
        }
        if settings.overlayVisible != shown { setVisible(settings.overlayVisible) }
        // SwiftUI 에서 유리를 자르면 반사까지 사라질 수 있어 창의 합성 경계에서 자른다.
        // 효과가 사각 창 끝까지 새어 둥근 모서리 바깥에 남지 않도록 한다.
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = settings.overlayCornerRadius
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.masksToBounds = true
    }

    /// 숨긴 패널이 시계와 스냅샷을 구독하며 레이아웃을 계산하지 않도록 뷰도 해제한다.
    private func setVisible(_ visible: Bool) {
        shown = visible
        if visible {
            if contentViewController == nil {
                let hosting = NSHostingController(rootView: OverlayView(store: store))
                hosting.sizingOptions = [.preferredContentSize]
                contentViewController = hosting
            }
            applyStoredPosition()
            orderFrontRegardless()
            DispatchQueue.main.async { self.applyStoredPosition() }
        } else {
            orderOut(nil)
            contentViewController = nil
            contentView = nil
        }
    }

    func applyStoredPosition() {
        isPositioning = true
        setFrameTopLeftPoint(Prefs.topLeft ?? defaultTopLeft())
        DispatchQueue.main.async { self.isPositioning = false }
    }

    func resetPosition() {
        Prefs.topLeft = nil
        setFrameTopLeftPoint(defaultTopLeft())
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
