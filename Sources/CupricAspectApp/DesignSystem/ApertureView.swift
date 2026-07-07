import SwiftUI

/// The CupricAspect brand mark and working indicator: eight copper aperture
/// blades over a green iris "eye". Port of the design bundle's Aperture.jsx;
/// geometry, colors, and timing are specified in
/// agent_docs/07-cupricaspect-gui-design.md Section 5.
///
/// Idle (`running == false`): blades held fully open, no rotation.
/// Running: a 3.8 s breathing close/open cycle; with `spin` the blade group
/// additionally rotates at 26°/s. Under system reduce-motion the idle frame
/// is drawn regardless of `running` (FR4-043).
struct ApertureView: View {
    var size: CGFloat
    var running: Bool = false
    var spin: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animating: Bool { running && !reduceMotion }

    var body: some View {
        TimelineView(.animation(paused: !animating)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let closeFactor = animating ? Self.closeFactor(phase: elapsed.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle) : 0
                let rotation = (animating && spin) ? elapsed * 26 : 0
                Self.draw(in: &context, canvasSize: canvasSize, closeFactor: closeFactor, rotationDegrees: rotation)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Geometry constants (160×160 design space)

    private static let designSpace: CGFloat = 160
    private static let center = CGPoint(x: 80, y: 80)
    private static let outerRadius: CGFloat = 72
    private static let innerOpen: CGFloat = 46
    private static let innerClosed: CGFloat = 2.5
    private static let bladeCount = 8
    private static let spacing: CGFloat = 360 / 8
    private static let outerHalf: CGFloat = 180 / 8
    private static let innerLead: CGFloat = 360 / 8 - 3
    /// Breathing cycle length in seconds.
    private static let cycle: Double = 3.8

    /// Outer→inner gradient stops by *world* position, from Aperture.jsx
    /// COLORS. The palette encodes a fixed light source (brightest entries
    /// around the upper-left, matching the specular highlight): blades sample
    /// it by their current world angle, so the lighting stays put while the
    /// blades rotate underneath it.
    private static let bladeColors: [(outer: UInt32, inner: UInt32)] = [
        (0xF0AA40, 0x9C5018),
        (0xB87A26, 0x4E3220),
        (0xA86C1E, 0x42281A),
        (0xBA7620, 0x503018),
        (0xD08830, 0x743610),
        (0xFFD060, 0xB05E20),
        (0xF8BC50, 0xA85820),
        (0xECA034, 0x8A4414),
    ]

    /// Palette colors for a blade whose world angle is `degrees`, blending
    /// adjacent slots so rotation never pops between palette entries.
    private static func litColors(worldAngleDegrees degrees: CGFloat) -> (outer: Color, inner: Color) {
        let slots = CGFloat(bladeColors.count)
        var position = (degrees / spacing).truncatingRemainder(dividingBy: slots)
        if position < 0 { position += slots }
        let lower = Int(position) % bladeColors.count
        let upper = (lower + 1) % bladeColors.count
        let fraction = Double(position - position.rounded(.down))
        return (
            outer: lerp(bladeColors[lower].outer, bladeColors[upper].outer, fraction),
            inner: lerp(bladeColors[lower].inner, bladeColors[upper].inner, fraction)
        )
    }

    private static func lerp(_ from: UInt32, _ to: UInt32, _ t: Double) -> Color {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF)
        }
        return Color(
            .sRGB,
            red: (channel(from, 16) + (channel(to, 16) - channel(from, 16)) * t) / 255.0,
            green: (channel(from, 8) + (channel(to, 8) - channel(from, 8)) * t) / 255.0,
            blue: (channel(from, 0) + (channel(to, 0) - channel(from, 0)) * t) / 255.0
        )
    }

    /// Blade closure over one breathing cycle: hold open, ease-in close,
    /// hold closed, ease-out reopen. Phase boundaries from Aperture.jsx.
    private static func closeFactor(phase: Double) -> Double {
        func easeIn(_ t: Double) -> Double { t * t * t }
        func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
        if phase < 0.26 { return 0 }
        if phase < 0.66 { return easeIn((phase - 0.26) / 0.40) }
        if phase < 0.79 { return 1 }
        return 1 - easeOut((phase - 0.79) / 0.21)
    }

    private static func point(radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    // MARK: - Drawing

    private static func draw(in context: inout GraphicsContext, canvasSize: CGSize, closeFactor: Double, rotationDegrees: Double) {
        let scale = min(canvasSize.width, canvasSize.height) / designSpace
        context.scaleBy(x: scale, y: scale)
        context.clip(to: Path(ellipseIn: CGRect(x: center.x - 74, y: center.y - 74, width: 148, height: 148)))

        drawDisc(in: &context)
        drawEye(in: &context)
        drawBlades(in: &context, closeFactor: closeFactor, rotationDegrees: rotationDegrees)
    }

    private static func drawDisc(in context: inout GraphicsContext) {
        let discRect = CGRect(x: center.x - 74, y: center.y - 74, width: 148, height: 148)
        context.fill(
            Path(ellipseIn: discRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x2A1408), Color(hex: 0x0A0500)]),
                center: center, startRadius: 0, endRadius: 74
            )
        )
        context.stroke(
            Path(ellipseIn: discRect.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(Color(hex: 0x1E0C04, opacity: 0.85)),
            lineWidth: 1.5
        )
    }

    /// The green iris, limbus vignette, pupil, and specular highlight.
    /// Elliptical gradients are drawn as circular gradients inside a
    /// y-scaled context (ry/rx = 34/43).
    private static func drawEye(in context: inout GraphicsContext) {
        let irisRx: CGFloat = 43
        let irisRy: CGFloat = 34

        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.scaleBy(x: 1, y: irisRy / irisRx)
            let irisCircle = Path(ellipseIn: CGRect(x: -irisRx, y: -irisRx, width: irisRx * 2, height: irisRx * 2))
            // Focal point offset toward upper-left (42%,37% in the SVG gradient).
            let focus = CGPoint(x: -irisRx * 0.16, y: -irisRx * 0.26)
            layer.fill(
                irisCircle,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0xC8F0A0), location: 0),
                        .init(color: Color(hex: 0x68CE64), location: 0.14),
                        .init(color: Color(hex: 0x389050), location: 0.32),
                        .init(color: Color(hex: 0x256040), location: 0.56),
                        .init(color: Color(hex: 0x184A2C), location: 0.77),
                        .init(color: Color(hex: 0x2E3C1C), location: 0.90),
                        .init(color: Color(hex: 0x060A04), location: 1),
                    ]),
                    center: focus, startRadius: 0, endRadius: irisRx * 1.28
                )
            )
            // Limbus: darken the iris rim.
            layer.fill(
                irisCircle,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.black.opacity(0), location: 0.68),
                        .init(color: Color.black.opacity(0.94), location: 1),
                    ]),
                    center: .zero, startRadius: 0, endRadius: irisRx
                )
            )
        }

        let pupilRect = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        context.fill(
            Path(ellipseIn: pupilRect),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x1A1A1A), Color(hex: 0x010101)]),
                center: CGPoint(x: center.x - 5, y: center.y - 6), startRadius: 0, endRadius: 23
            )
        )

        context.drawLayer { layer in
            layer.translateBy(x: 73.5, y: 73.5)
            layer.rotate(by: .degrees(-40))
            layer.fill(
                Path(ellipseIn: CGRect(x: -5.5, y: -3.8, width: 11, height: 7.6)),
                with: .color(.white.opacity(0.88))
            )
        }
    }

    private static func drawBlades(in context: inout GraphicsContext, closeFactor: Double, rotationDegrees: Double) {
        let innerRadius = innerOpen + (innerClosed - innerOpen) * closeFactor
        let twist = 24 * closeFactor + rotationDegrees

        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(twist))
            layer.translateBy(x: -center.x, y: -center.y)

            for index in 0..<bladeCount {
                let theta = CGFloat(index) * spacing
                var blade = Path()
                blade.addArc(
                    center: center, radius: outerRadius,
                    startAngle: .degrees(theta - outerHalf), endAngle: .degrees(theta + outerHalf),
                    clockwise: false
                )
                blade.addLine(to: point(radius: innerRadius, degrees: theta + innerLead))
                blade.addLine(to: point(radius: innerRadius, degrees: theta - 3))
                blade.closeSubpath()

                // The layer is rotated by `twist`, so this blade's world
                // angle is theta + twist: sample the fixed-light palette there.
                let colors = litColors(worldAngleDegrees: theta + CGFloat(twist))
                layer.fill(
                    blade,
                    with: .linearGradient(
                        Gradient(colors: [colors.outer, colors.inner]),
                        startPoint: point(radius: outerRadius, degrees: theta),
                        endPoint: point(radius: innerOpen, degrees: theta)
                    )
                )
                layer.stroke(blade, with: .color(Color(hex: 0x1A0A04)), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
            }

            var opening = Path()
            let openingPoints = (0..<bladeCount).map { point(radius: innerRadius, degrees: CGFloat($0) * spacing + innerLead) }
            opening.addLines(openingPoints)
            opening.closeSubpath()
            layer.stroke(opening, with: .color(Color(hex: 0xD89030, opacity: 0.35)), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
        }
    }
}
