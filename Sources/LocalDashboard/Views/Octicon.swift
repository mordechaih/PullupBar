import SwiftUI
import AppKit

/// Path data for the Octicons we render. Each entry is the list of `<path d="…">` strings from
/// the icon's SVG (most icons are one path; some, like tab-external, ship two). Sourced from
/// https://primer.style/octicons.
enum Octicons {
    static let gitBranchCheck = ["M15.26 10a.741.741 0 0 1 .414.133.75.75 0 0 1 .1 1.154l-4.557 4.45a.753.753 0 0 1-1.055-.008l-1.943-1.95a.755.755 0 0 1 .024-1.038.753.753 0 0 1 1.038-.022l1.42 1.427 4.026-3.933A.752.752 0 0 1 15.26 10Zm-3.51-9a2.252 2.252 0 0 1 1.942 3.389 2.252 2.252 0 0 1-1.192.983V6A2.5 2.5 0 0 1 10 8.5H6a.997.997 0 0 0-1 1v1.128a2.256 2.256 0 0 1 1.469 2.503A2.252 2.252 0 1 1 3.5 10.628V5.372a2.255 2.255 0 0 1-1.469-2.503A2.252 2.252 0 1 1 5 5.372v1.836A2.493 2.493 0 0 1 6 7h4a.997.997 0 0 0 1-1v-.628A2.252 2.252 0 0 1 11.75 1Zm-7.5 1.5a.747.747 0 0 0-.53.22.747.747 0 0 0 0 1.06.747.747 0 0 0 1.06 0 .747.747 0 0 0 0-1.06.747.747 0 0 0-.53-.22Zm0 9.5a.747.747 0 0 0-.53.22.747.747 0 0 0 0 1.06.747.747 0 0 0 1.06 0 .747.747 0 0 0 0-1.06.747.747 0 0 0-.53-.22Zm7.5-9.5a.747.747 0 0 0-.53.22.747.747 0 0 0 0 1.06.747.747 0 0 0 1.06 0 .747.747 0 0 0 0-1.06.747.747 0 0 0-.53-.22Z"]

    static let tabExternal = [
        "M3.25 4a.25.25 0 0 0-.25.25v9a.75.75 0 0 1-.75.75H.75a.75.75 0 0 1 0-1.5h.75V4.25c0-.966.784-1.75 1.75-1.75h9.5c.966 0 1.75.784 1.75 1.75v8.25h.75a.75.75 0 0 1 0 1.5h-1.5a.75.75 0 0 1-.75-.75v-9a.25.25 0 0 0-.25-.25h-9.5Z",
        "m7.97 7.97-2.75 2.75a.75.75 0 1 0 1.06 1.06l2.75-2.75 1.543 1.543a.25.25 0 0 0 .427-.177V6.25a.25.25 0 0 0-.25-.25H6.604a.25.25 0 0 0-.177.427L7.97 7.97Z"
    ]

    static let link = ["m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z"]
}

/// Renders an Octicon as a scalable, fillable SwiftUI shape. Octicons ship as one or more
/// `<path>` elements on a square viewBox; each is parsed from a fresh origin and combined,
/// then scaled to fit the frame. Fill uses the non-zero winding rule (the Octicon/SVG default)
/// so node rings and counters render with proper holes.
struct OcticonShape: Shape {
    let paths: [String]
    var viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var combined = Path()
        for d in paths { combined.addPath(SVGPath.parse(d)) }
        let scale = min(rect.width, rect.height) / viewBox
        let dx = (rect.width - viewBox * scale) / 2
        let dy = (rect.height - viewBox * scale) / 2
        let transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        return combined.applying(transform)
    }
}

/// Renders an Octicon as a template `NSImage`, so it's tinted by `foregroundStyle` and picks up
/// the same vibrancy blending as SF Symbols over material — a raw `Shape` fill skips vibrancy and
/// reads noticeably darker/heavier next to real symbols.
struct OcticonImage: View {
    let paths: [String]
    var viewBox: CGFloat = 16
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: Self.render(paths: paths, viewBox: viewBox, size: size))
            .renderingMode(.template)
    }

    private static func render(paths: [String], viewBox: CGFloat, size: CGFloat) -> NSImage {
        // flipped: true so the drawing origin is top-left (y-down), matching SVG coordinates.
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var combined = Path()
            for d in paths { combined.addPath(SVGPath.parse(d)) }
            let scale = size / viewBox
            let scaled = combined.applying(CGAffineTransform(scaleX: scale, y: scale))
            ctx.addPath(scaled.cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// A minimal SVG path-data parser producing a SwiftUI `Path`. Handles the full command set
/// (M/L/H/V/C/S/Q/T/A/Z, absolute and relative) including elliptical arcs, which are split
/// into ≤90° segments and approximated with cubic Béziers.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let chars = Array(d)
        var i = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint? = nil
        var lastCmd: Character = " "
        var prevWasCurve = false

        func skipSep() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" {
                i += 1
            }
        }
        func readNumber() -> CGFloat {
            skipSep()
            var s = ""
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == "." {
                    if seenDot { break }
                    seenDot = true; s.append(c); i += 1
                } else if c == "e" || c == "E" {
                    s.append(c); i += 1
                    if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }
        func readFlag() -> Bool {
            skipSep()
            guard i < chars.count else { return false }
            let c = chars[i]; i += 1
            return c == "1"
        }
        func readPoint(_ relative: Bool) -> CGPoint {
            let x = readNumber(); let y = readNumber()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        func isCommand(_ c: Character) -> Bool { "MmLlHhVvCcSsQqTtAaZz".contains(c) }

        while i < chars.count {
            skipSep()
            guard i < chars.count else { break }
            var cmd = chars[i]
            if isCommand(cmd) { i += 1 } else { cmd = lastCmd }
            guard cmd != " " else { break }

            let rel = cmd.isLowercase
            switch Character(cmd.uppercased()) {
            case "M":
                let pt = readPoint(rel)
                path.move(to: pt); current = pt; start = pt
                lastCmd = rel ? "l" : "L"; lastControl = nil; prevWasCurve = false
            case "L":
                let pt = readPoint(rel)
                path.addLine(to: pt); current = pt; lastCmd = cmd; lastControl = nil; prevWasCurve = false
            case "H":
                let x = readNumber(); let pt = CGPoint(x: rel ? current.x + x : x, y: current.y)
                path.addLine(to: pt); current = pt; lastCmd = cmd; lastControl = nil; prevWasCurve = false
            case "V":
                let y = readNumber(); let pt = CGPoint(x: current.x, y: rel ? current.y + y : y)
                path.addLine(to: pt); current = pt; lastCmd = cmd; lastControl = nil; prevWasCurve = false
            case "C":
                let c1 = readPoint(rel), c2 = readPoint(rel), end = readPoint(rel)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastControl = c2; lastCmd = cmd; prevWasCurve = true
            case "S":
                let c1 = prevWasCurve ? CGPoint(x: 2 * current.x - (lastControl?.x ?? current.x),
                                                y: 2 * current.y - (lastControl?.y ?? current.y)) : current
                let c2 = readPoint(rel), end = readPoint(rel)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastControl = c2; lastCmd = cmd; prevWasCurve = true
            case "Q":
                let c = readPoint(rel), end = readPoint(rel)
                path.addQuadCurve(to: end, control: c)
                current = end; lastControl = c; lastCmd = cmd; prevWasCurve = true
            case "T":
                let c = prevWasCurve ? CGPoint(x: 2 * current.x - (lastControl?.x ?? current.x),
                                               y: 2 * current.y - (lastControl?.y ?? current.y)) : current
                let end = readPoint(rel)
                path.addQuadCurve(to: end, control: c)
                current = end; lastControl = c; lastCmd = cmd; prevWasCurve = true
            case "A":
                let rx = readNumber(), ry = readNumber(), rot = readNumber()
                let large = readFlag(), sweep = readFlag()
                let end = readPoint(rel)
                addArc(&path, from: current, to: end, rx: rx, ry: ry, rotationDeg: rot, largeArc: large, sweep: sweep)
                current = end; lastControl = nil; lastCmd = cmd; prevWasCurve = false
            case "Z":
                path.closeSubpath(); current = start; lastCmd = cmd; lastControl = nil; prevWasCurve = false
            default:
                return path
            }
        }
        return path
    }

    /// Appends an SVG elliptical arc (endpoint parameterization) to `path`, approximated with
    /// cubic Béziers per the SVG implementation notes (F.6).
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDeg: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        if rxIn == 0 || ryIn == 0 || (p0.x == p1.x && p0.y == p1.y) { path.addLine(to: p1); return }
        var rx = abs(rxIn), ry = abs(ryIn)
        let phi = rotationDeg * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = sign * sqrt(max(0, num / den))
        let cxp = co * (rx * y1p / ry)
        let cyp = co * (-ry * x1p / rx)
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var dtheta = angle(ux, uy, vx, vy)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / CGFloat(segments)
        let alpha = (4.0 / 3.0) * tan(delta / 4)

        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cosP * cos(a) - ry * sinP * sin(a),
                    y: cy + rx * sinP * cos(a) + ry * cosP * sin(a))
        }
        func deriv(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * cosP * sin(a) - ry * sinP * cos(a),
                    y: -rx * sinP * sin(a) + ry * cosP * cos(a))
        }
        var theta = theta1
        for _ in 0..<segments {
            let next = theta + delta
            let s = point(theta), e = point(next)
            let d1 = deriv(theta), d2 = deriv(next)
            let c1 = CGPoint(x: s.x + alpha * d1.x, y: s.y + alpha * d1.y)
            let c2 = CGPoint(x: e.x - alpha * d2.x, y: e.y - alpha * d2.y)
            path.addCurve(to: e, control1: c1, control2: c2)
            theta = next
        }
    }
}
