import AppKit
import SwiftUI

/// 메뉴바 항목 바로 아래에 붙어 내려오는 상세 창. 다른 메뉴바 메뉴처럼 꼭지 없이 뜬다.
/// NSPopover 는 꼭지를 늘 그려서, 테두리 없는 패널을 직접 띄운다.
/// 앱을 앞으로 끌어오지 않고 키 창만 되므로 쓰던 앱의 포커스를 빼앗지 않는다.
final class DetailsPanel: NSPanel {
    /// 메뉴바와 창 사이 틈.
    private static let gap: CGFloat = 1
    /// 화면 가장자리에서 띄우는 거리.
    private static let screenMargin: CGFloat = 6

    private var anchor: NSStatusBarButton?
    /// 바깥을 누르거나 다른 앱으로 넘어가면 닫는다. 열려 있는 동안만 지켜본다.
    private var monitors: [Any] = []
    private var activation: NSObjectProtocol?
    private var dismissedAt = Date.distantPast

    /// 방금 닫혔는지. 메뉴바 항목은 다른 프로세스가 그려서, 그걸 누르면 먼저 바깥 클릭으로 닫힌 뒤에야
    /// 항목의 동작이 온다. 그 동작이 창을 다시 열지 않도록 닫기로 받는다.
    var justDismissed: Bool { Date().timeIntervalSince(dismissedAt) < 0.35 }

    init(details: DetailsView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: DetailsSurface(details: details))
        hosting.sizingOptions = [.preferredContentSize]
        contentViewController = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(didResize),
                                               name: NSWindow.didResizeNotification, object: self)
    }

    /// 단추와 스위치가 클릭을 받고 Esc 가 닿으려면 키 창이 될 수 있어야 한다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(below button: NSStatusBarButton) {
        anchor = button
        place()
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        watchForDismissal()
    }

    func dismiss() {
        guard isVisible else { return }
        dismissedAt = Date()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// 메뉴바 항목의 왼쪽 끝에 맞춰 바로 아래에 놓는다. 화면 밖으로 넘치면 안쪽으로 당긴다.
    private func place() {
        guard let anchor, let window = anchor.window else { return }
        let item = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var x = item.minX
        if let screen = (window.screen ?? NSScreen.main)?.frame {
            x = min(max(x, screen.minX + Self.screenMargin), screen.maxX - frame.width - Self.screenMargin)
        }
        setFrameTopLeftPoint(NSPoint(x: x, y: item.minY - Self.gap))
    }

    /// 내용이 바뀌어 높이가 달라져도 위쪽은 메뉴바 아래에 붙어 있게 한다.
    @objc private func didResize() {
        guard isVisible else { return }
        place()
        invalidateShadow()
    }

    private func watchForDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.dismiss()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            // 메뉴바 항목을 누른 건 AppDelegate 가 열고 닫는다. 여기서도 닫으면 곧바로 다시 열린다.
            if let self, event.window !== self, event.window !== self.anchor?.window { self.dismiss() }
            return event
        }) {
            monitors.append(local)
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }
}

/// 상세 창의 바탕. 다른 메뉴바 메뉴처럼 뒤 화면이 흐리게 비치는 재질에 둥근 모서리, 옅은 테두리.
private struct DetailsSurface: View {
    let details: DetailsView

    private static let radius: CGFloat = 12

    var body: some View {
        details
            .background(MenuBackdrop(radius: Self.radius))
            .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// 창 뒤를 흐리게 비추는 메뉴 재질. SwiftUI 재질은 이 투명한 창에서 뒤를 비추지 않고 회색 판으로만 깔린다.
/// 창 뒤 흐림은 레이어를 잘라도 네모로 남아서, 둥근 모서리는 maskImage 로 깎는다.
private struct MenuBackdrop: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        // 앱을 앞으로 끌어오지 않는 창이라, 기본값이면 늘 비활성 모양(불투명)으로 그려진다.
        view.state = .active
        view.maskImage = roundedMask()
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// 늘려 써도 모서리는 그대로인 둥근 사각형.
    private func roundedMask() -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
