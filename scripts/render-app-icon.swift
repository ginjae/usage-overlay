import AppKit
import ImageIO
import UniformTypeIdentifiers

// xcrun swiftc Sources/UsageOverlay/Icons.swift scripts/render-app-icon.swift -o /tmp/render-app-icon
// /tmp/render-app-icon Resources/AppIcon-source.png build
@main
enum RenderAppIcon {
    static func main() {
        do {
            try render()
        } catch {
            FileHandle.standardError.write(Data("render-app-icon: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func render() throws {
        guard CommandLine.arguments.count == 3 else {
            throw CocoaError(.executableLoad, userInfo: [
                NSLocalizedDescriptionKey: "Usage: render-app-icon <blank-panel.png> <output-directory>"
            ])
        }

        let panelURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard let source = CGImageSourceCreateWithURL(panelURL as CFURL, nil),
              let panel = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let logo = makeSplitLogo() else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try writePNG(logo, to: output.appendingPathComponent("provider-logos.png"))
        guard let icon = composite(logo, over: panel) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writePNG(icon, to: output.appendingPathComponent("app-icon.png"))
    }

    private static func composite(_ logo: CGImage, over panel: CGImage) -> CGImage? {
        guard let canvas = makeCanvas(width: panel.width, height: panel.height) else { return nil }
        let width = CGFloat(panel.width)
        let height = CGFloat(panel.height)
        canvas.draw(panel, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The glass face is a symmetric trapezoid with a horizontal top and bottom.
        let bottom = Int((height * 0.296).rounded())
        let top = Int((height * 0.731).rounded())
        let bottomWidth = width * 0.764
        let topWidth = width * 0.648
        let projectedHeight = CGFloat(top - bottom)
        canvas.interpolationQuality = .high
        for row in bottom..<top {
            let y = CGFloat(row)
            let t = (y + 0.5 - CGFloat(bottom)) / projectedHeight
            let rowWidth = bottomWidth + (topWidth - bottomWidth) * t
            // Invert the plane's projective transform at this scanline. The local height
            // provides the vertical scale used to sample the logo texture at that point.
            let textureY = t * topWidth / rowWidth
            let localHeight = projectedHeight * rowWidth * rowWidth / (bottomWidth * topWidth)
            canvas.saveGState()
            canvas.clip(to: CGRect(x: 0, y: y, width: width, height: 1))
            canvas.draw(logo, in: CGRect(
                x: (width - rowWidth) / 2, y: y + 0.5 - textureY * localHeight,
                width: rowWidth, height: localHeight
            ))
            canvas.restoreGState()
        }
        return canvas.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
    }

    private static func makeSplitLogo() -> CGImage? {
        guard let canvas = makeCanvas(width: 1024, height: 704),
              let claude = Icons.claude.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let gpt = Icons.codex.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let centerX = CGFloat(canvas.width) / 2
        let centerY = CGFloat(canvas.height) / 2
        let visibleDiameter: CGFloat = 560
        // The centered 64 px templates have 60 px and 54 px of visible artwork.
        let marks = [
            (claude, visibleDiameter * 64 / 60, CGFloat.zero,
             CGColor(red: 0.85, green: 0.45, blue: 0.28, alpha: 1)),
            (gpt, visibleDiameter * 64 / 54, centerX,
             CGColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1))
        ]
        canvas.interpolationQuality = .high
        for (image, size, halfX, color) in marks {
            let bounds = CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
            canvas.saveGState()
            canvas.clip(to: CGRect(x: halfX, y: 0, width: centerX, height: CGFloat(canvas.height)))
            canvas.draw(image, in: bounds)
            canvas.setBlendMode(.sourceIn)
            canvas.setFillColor(color)
            canvas.fill(bounds)
            canvas.restoreGState()
        }
        return canvas.makeImage()
    }

    private static func makeCanvas(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
