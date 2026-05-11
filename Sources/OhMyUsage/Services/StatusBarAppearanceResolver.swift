import AppKit
import CoreImage

enum StatusBarAppearanceResolver {
    static let wallpaperLuminanceThreshold: Double = 0.58

    private static let defaultSampleWidth = 64
    private static let defaultSampleHeight = 16
    private static let defaultTopStripRows = 4
    private static let defaultSampleSpanRatio: Double = 0.16

    static func resolvedForegroundStyle(
        mode: StatusBarAppearanceMode,
        wallpaperLuminance: Double?
    ) -> StatusBarForegroundStyle {
        switch mode {
        case .dark:
            // "Dark" means dark menubar background, so use light foreground.
            return .light
        case .light:
            // "Light" means light menubar background, so use dark foreground.
            return .dark
        case .followWallpaper:
            guard let wallpaperLuminance else {
                // Keep current behavior when wallpaper data is unavailable.
                return .light
            }
            return wallpaperLuminance >= wallpaperLuminanceThreshold ? .dark : .light
        }
    }

    static func wallpaperTopStripLuminance(
        from image: NSImage,
        sampleWidth: Int = defaultSampleWidth,
        sampleHeight: Int = defaultSampleHeight,
        topStripRows: Int = defaultTopStripRows,
        horizontalCenterRatio: Double = 0.5,
        sampleSpanRatio: Double = defaultSampleSpanRatio
    ) -> Double? {
        guard
            sampleWidth > 0,
            sampleHeight > 0,
            topStripRows > 0,
            image.size.width > 0,
            image.size.height > 0,
            sampleSpanRatio > 0
        else {
            return nil
        }

        let cgImage: CGImage?
        if let directImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cgImage = directImage
        } else if
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff) {
            cgImage = bitmap.cgImage
        } else {
            cgImage = nil
        }
        guard let cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let centerRatio = min(max(horizontalCenterRatio, 0), 1)
        let spanRatio = min(max(sampleSpanRatio, 1.0 / Double(width)), 1.0)
        let stripWidth = max(1, Int(round(Double(width) * spanRatio)))
        let centerX = Int(round(Double(width - 1) * centerRatio))
        let stripMinX = max(0, min(width - stripWidth, centerX - (stripWidth / 2)))
        let stripRatio = min(1.0, max(Double(topStripRows) / Double(sampleHeight), 1.0 / Double(height)))
        let stripHeight = max(1, Int(round(Double(height) * stripRatio)))
        let stripRect = CGRect(
            x: stripMinX,
            y: max(0, height - stripHeight),
            width: stripWidth,
            height: stripHeight
        )
        return averageLuminance(in: cgImage, stripRect: stripRect)
    }

    private static func averageLuminance(in cgImage: CGImage, stripRect: CGRect) -> Double? {
        let ciImage = CIImage(cgImage: cgImage).cropped(to: stripRect)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let red = Double(pixel[0]) / 255.0
        let green = Double(pixel[1]) / 255.0
        let blue = Double(pixel[2]) / 255.0
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
