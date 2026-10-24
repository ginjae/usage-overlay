import AppKit

/// 메뉴바에 넣을 "아이콘 + 퍼센트" 합성 이미지.
///
/// NSTextAttachment로 붙인 이미지는 템플릿 처리가 되지 않아 다크/라이트 메뉴바에서
/// 색이 어긋난다. 그래서 아이콘과 글자를 하나의 이미지에 검정으로 그린 뒤
/// `isTemplate` 을 켜서 시스템이 알아서 색을 맞추게 한다.
/// 단계 색을 입히면 시스템이 대신 칠해 주지 않는다. 그때만 템플릿을 끄고,
/// 나머지는 메뉴바 모양에 맞춘 글자색으로 직접 칠한다. 치수는 모두 설정에서 온다.
///
/// 그 글자색은 그림을 만들 때가 아니라 그릴 때 고른다. 화면이 여럿이면 macOS 가 화면마다
/// 메뉴바 모양을 바꿔 가며 같은 그림을 다시 그리므로, 그때그때 그 화면에 맞는 색이 나온다.
/// 모양이 바뀔 때마다 그림을 새로 끼우면 그 끼움이 또 다시 그리기를 불러 끝없이 돈다.
enum StatusBarImage {
    /// `appearance` 를 주면 그 모양으로 고정해 그린다. 설정 창 미리보기처럼 메뉴바 밖에 놓을 때 쓴다.
    static func make(_ parts: [MenuBarPart], appearance: NSAppearance? = nil) -> NSImage {
        let settings = Settings.shared
        let parts = parts.isEmpty ? [MenuBarPart(icon: nil, text: "–")] : parts
        let metrics = Metrics(settings)
        let colored = parts.contains { $0.level != nil }
        func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: metrics.font, .foregroundColor: color]
        }

        let separatorWidth = metrics.separator.map { ($0 as NSString).size(withAttributes: attributes(.black)).width } ?? 0
        /// 앞 조각과의 이음매가 차지하는 폭. 첫 조각은 0.
        func seamWidth(_ part: MenuBarPart) -> CGFloat {
            part.seam == .window ? metrics.windowGap * 2 + separatorWidth : metrics.providerGap
        }

        let widths = parts.map { part -> CGFloat in
            let text = (part.text as NSString).size(withAttributes: attributes(.black)).width
            return part.icon == nil ? text : metrics.iconWidth(part.clock) + metrics.iconTextGap + text
        }
        let total = widths.reduce(0, +) + parts.dropFirst().map(seamWidth).reduce(0, +)
        let height = metrics.height

        let image = NSImage(size: NSSize(width: max(1, ceil(total)), height: height), flipped: false) { _ in
            let neutral = colored ? labelColor(in: appearance) : .black
            func ink(_ part: MenuBarPart) -> NSColor {
                part.level.map { settings.color(for: $0).nsColor } ?? neutral
            }
            var x: CGFloat = 0
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    if part.seam == .window {
                        x += metrics.windowGap
                        if let mark = metrics.separator.map({ $0 as NSString }) {
                            let size = mark.size(withAttributes: attributes(neutral))
                            mark.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes(neutral))
                        }
                        x += separatorWidth + metrics.windowGap
                    } else {
                        x += metrics.providerGap
                    }
                }
                let color = ink(part)
                if let icon = part.icon {
                    drawIcon(icon, clock: part.clock, x: x, ink: color, metrics: metrics)
                    x += metrics.iconWidth(part.clock) + metrics.iconTextGap
                }
                let text = part.text as NSString
                let size = text.size(withAttributes: attributes(color))
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes(color))
                x += size.width
            }
            return true
        }
        image.isTemplate = !colored
        // 그려 둔 결과를 재사용하면 다른 화면에도 처음 고른 색이 그대로 남는다.
        if colored { image.cacheMode = .never }
        return image
    }

    /// 그리는 데 쓰는 치수. 모두 설정에서 온다.
    private struct Metrics {
        let font: NSFont
        let iconSize: CGFloat
        let iconTextGap: CGFloat
        let providerGap: CGFloat
        let windowGap: CGFloat
        let separator: String?
        let ringDiameter: CGFloat
        let ringLineWidth: CGFloat
        let ringIconSize: CGFloat
        /// 시계에서 칠하지 않는 쪽. 템플릿 이미지는 알파만 남으므로 옅게 칠해 칠한 쪽과 가른다.
        let dimAlpha: CGFloat
        let height: CGFloat

        init(_ settings: Settings) {
            let size = CGFloat(settings.menuBarFontSize)
            let weight = settings.menuBarFontWeight.nsWeight
            font = settings.menuBarMonospacedDigits
                ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                : .systemFont(ofSize: size, weight: weight)
            iconSize = CGFloat(settings.menuBarIconSize)
            iconTextGap = CGFloat(settings.menuBarIconGap)
            providerGap = CGFloat(settings.menuBarProviderGap)
            windowGap = CGFloat(settings.menuBarWindowGap)
            separator = settings.menuBarSeparator.mark
            // 고리는 로고 칸보다 조금 크게 두르고, 로고는 고리 안쪽에 들어가도록 줄인다.
            ringLineWidth = CGFloat(settings.menuBarRingWidth)
            ringDiameter = iconSize + 2
            ringIconSize = (ringDiameter - ringLineWidth * 2) * 0.7
            dimAlpha = CGFloat(settings.menuBarClockDim)
            // 메뉴바는 22pt 남짓이다. 글자나 로고를 키운 만큼만 높인다.
            height = max(16, ceil(max(ringDiameter, font.ascender - font.descender)))
        }

        func iconWidth(_ clock: LogoClock?) -> CGFloat {
            clock?.face == .ring ? ringDiameter : iconSize
        }
    }

    /// 템플릿을 끈 그림에서 시스템 대신 고르는 글자색. 밝은 메뉴바엔 검정 쪽, 어두운 메뉴바엔 흰색 쪽이 된다.
    /// 그리는 중에 부르면 지금 그리는 화면의 메뉴바 모양을 따른다.
    private static func labelColor(in appearance: NSAppearance?) -> NSColor {
        var color = NSColor.black
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        return color
    }

    private static func drawIcon(_ icon: NSImage, clock: LogoClock?, x: CGFloat, ink: NSColor, metrics m: Metrics) {
        let icon = tinted(icon, ink)
        let rect = NSRect(x: x, y: (m.height - m.iconSize) / 2, width: m.iconSize, height: m.iconSize)
        guard let clock else {
            icon.draw(in: rect)
            return
        }
        let lit = clock.lit

        switch clock.face {
        case .sweep:
            // 로고 전체를 옅게 깐 뒤 칠할 부채꼴 안에만 진한 로고를 다시 찍는다.
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: m.dimAlpha)
            if let wedge = arc(around: NSPoint(x: rect.midX, y: rect.midY), radius: m.iconSize,
                               from: lit.from, to: lit.to, wedge: true) {
                NSGraphicsContext.saveGraphicsState()
                wedge.addClip()
                icon.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }

        case .ring:
            let center = NSPoint(x: x + m.ringDiameter / 2, y: m.height / 2)
            let radius = (m.ringDiameter - m.ringLineWidth) / 2
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
            track.lineWidth = m.ringLineWidth
            ink.withAlphaComponent(ink.alphaComponent * m.dimAlpha).setStroke()
            track.stroke()
            if let hand = arc(around: center, radius: radius, from: lit.from, to: lit.to, wedge: false) {
                hand.lineWidth = m.ringLineWidth
                hand.lineCapStyle = .round
                ink.setStroke()
                hand.stroke()
            }
            icon.draw(in: NSRect(x: center.x - m.ringIconSize / 2, y: center.y - m.ringIconSize / 2,
                                 width: m.ringIconSize, height: m.ringIconSize))
        }
    }

    /// 템플릿 로고는 검정 실루엣이다. 템플릿을 끈 그림에서는 직접 색을 입혀야 한다.
    private static func tinted(_ icon: NSImage, _ ink: NSColor) -> NSImage {
        guard ink != .black else { return icon }
        return NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// 12시를 0 으로 시계 방향으로 잰 구간의 호. `wedge` 면 중심까지 닫은 부채꼴.
    /// 구간이 비면 nil, 한 바퀴면 원 하나다. 한 바퀴를 호로 그리면 시작과 끝이 겹쳐 빈 경로가 된다.
    private static func arc(around center: NSPoint, radius: CGFloat,
                            from start: Double, to end: Double, wedge: Bool) -> NSBezierPath? {
        guard end > start else { return nil }
        if end - start >= 1 {
            return NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        }
        let path = NSBezierPath()
        if wedge { path.move(to: center) }
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: 90 - 360 * start, endAngle: 90 - 360 * end, clockwise: true)
        if wedge { path.close() }
        return path
    }
}
