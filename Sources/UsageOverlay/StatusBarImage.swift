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
    private static let groupGap: CGFloat = 7
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)

    static func make(_ parts: [MenuBarPart]) -> NSImage {
        let parts = parts.isEmpty ? [MenuBarPart(icon: nil, text: "–")] : parts
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

        let widths = parts.map { part -> CGFloat in
            let text = (part.text as NSString).size(withAttributes: attributes).width
            return part.icon == nil ? text : iconSize + iconTextGap + text
        }
        let total = widths.reduce(0, +) + groupGap * CGFloat(parts.count - 1)

        let image = NSImage(size: NSSize(width: max(1, ceil(total)), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                if let icon = part.icon {
                    icon.draw(in: NSRect(x: x, y: (height - iconSize) / 2,
                                         width: iconSize, height: iconSize))
                    x += iconSize + iconTextGap
                }
                let text = part.text as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)
                x += size.width + groupGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
