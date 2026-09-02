import AppKit

/// 메뉴바에 넣을 "아이콘 + 퍼센트" 합성 이미지.
///
/// NSTextAttachment로 붙인 이미지는 템플릿 처리가 되지 않아 다크/라이트 메뉴바에서
/// 색이 어긋난다. 그래서 아이콘과 글자를 하나의 이미지에 검정으로 그린 뒤
/// `isTemplate` 을 켜서 시스템이 알아서 색을 맞추게 한다.
enum StatusBarImage {
    private static let iconSize: CGFloat = 13
    private static let height: CGFloat = 16
    private static let iconTextGap: CGFloat = 3
    /// 공급자 사이. 같은 공급자의 창 사이보다 넓어야 어디서 갈리는지 보인다.
    private static let providerGap: CGFloat = 9
    /// 가운뎃점 양옆.
    private static let windowGap: CGFloat = 4
    private static let dot = "·"
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)

    static func make(_ parts: [MenuBarPart]) -> NSImage {
        let parts = parts.isEmpty ? [MenuBarPart(icon: nil, text: "–")] : parts
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

        let dotWidth = (dot as NSString).size(withAttributes: attributes).width
        /// 앞 조각과의 이음매가 차지하는 폭. 첫 조각은 0.
        func seamWidth(_ part: MenuBarPart) -> CGFloat {
            part.seam == .window ? windowGap * 2 + dotWidth : providerGap
        }

        let widths = parts.map { part -> CGFloat in
            let text = (part.text as NSString).size(withAttributes: attributes).width
            return part.icon == nil ? text : iconSize + iconTextGap + text
        }
        let total = widths.reduce(0, +) + parts.dropFirst().map(seamWidth).reduce(0, +)

        let image = NSImage(size: NSSize(width: max(1, ceil(total)), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    if part.seam == .window {
                        x += windowGap
                        let dot = dot as NSString
                        let size = dot.size(withAttributes: attributes)
                        dot.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
                        x += dotWidth + windowGap
                    } else {
                        x += providerGap
                    }
                }
                if let icon = part.icon {
                    icon.draw(in: NSRect(x: x, y: (height - iconSize) / 2,
                                         width: iconSize, height: iconSize))
                    x += iconSize + iconTextGap
                }
                let text = part.text as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
                x += size.width
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
