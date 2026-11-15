import AppKit
import SwiftUI

/// SwiftUI 내용이 줄거나 늘면 메뉴 항목의 프레임도 함께 맞춘다.
final class DetailsMenuItem: NSMenuItem {
    init(store: UsageStore) {
        super.init(title: "", action: nil, keyEquivalent: "")
        let content = DetailsView(store: store)
            // 이전 메뉴 높이에 맞춰 압축되거나 남은 공간 가운데에 놓이지 않도록 한다.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                self?.resize(to: size)
            }
        let hosting = NSHostingView(rootView: content)
        view = hosting
        sizeToFit()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sizeToFit() {
        guard let view else { return }
        resize(to: view.fittingSize)
    }

    private func resize(to size: NSSize) {
        guard let view else { return }
        let rounded = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard view.frame.size != rounded else { return }
        view.setFrameSize(rounded)
        menu?.update()
    }
}
