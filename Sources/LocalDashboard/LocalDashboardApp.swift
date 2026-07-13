import SwiftUI
import AppKit

@main
struct LocalDashboardApp: App {
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardPanelView(store: store)
        } label: {
            Group {
                if store.badgeCount > 0 {
                    Image(nsImage: renderBadgeIcon(count: store.badgeCount))
                        .renderingMode(.original)
                } else {
                    Image(systemName: "gauge.medium")
                }
            }
            .task { store.startPolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

func renderBadgeIcon(count: Int) -> NSImage {
    let logicalSize = 18
    let scale = 3
    let pixelSize = logicalSize * scale
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return NSImage(size: CGSize(width: logicalSize, height: logicalSize))
    }

    let scaleFactor = CGFloat(scale)
    let rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let path = CGPath(ellipseIn: rect, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let text = "\(count)" as NSString
    let font = NSFont.systemFont(ofSize: 11 * scaleFactor, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let textSize = text.size(withAttributes: attrs)
    let textRect = CGRect(
        x: (CGFloat(pixelSize) - textSize.width) / 2,
        y: (CGFloat(pixelSize) - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    ctx.setBlendMode(.clear)
    text.draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else {
        return NSImage(size: CGSize(width: logicalSize, height: logicalSize))
    }
    let image = NSImage(cgImage: cgImage, size: CGSize(width: logicalSize, height: logicalSize))
    image.isTemplate = false
    return image
}
