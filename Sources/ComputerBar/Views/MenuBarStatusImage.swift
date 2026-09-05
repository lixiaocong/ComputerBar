import AppKit

enum MenuBarStatusImage {
    struct Bar: Equatable {
        let label: String
        let cpuPercent: Double?
        let memoryPercent: Double?
        let virtualMemoryPercent: Double?
        let diskPercent: Double?
        let isError: Bool

        init(
            label: String,
            cpuPercent: Double? = nil,
            memoryPercent: Double? = nil,
            virtualMemoryPercent: Double? = nil,
            diskPercent: Double? = nil,
            isError: Bool = false
        ) {
            self.label = label
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
            self.virtualMemoryPercent = virtualMemoryPercent
            self.diskPercent = diskPercent
            self.isError = isError
        }

        var percents: [Double?] {
            if virtualMemoryPercent != nil {
                return [cpuPercent, memoryPercent, virtualMemoryPercent, diskPercent]
            }

            return [cpuPercent, memoryPercent, diskPercent]
        }
    }

    static let placeholderBars = [
        Bar(label: "--"),
    ]

    static func make(bars: [Bar]) -> NSImage {
        let values = normalizedBars(bars)
        let size = imageSize(for: values.count)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        for (index, value) in values.enumerated() {
            let groupX = horizontalPadding + CGFloat(index) * (machineElementWidth + machineGap)
            let labelRect = NSRect(
                x: groupX,
                y: verticalInset,
                width: labelWidth,
                height: size.height - verticalInset * 2
            )
            let stackRect = NSRect(
                x: groupX + labelWidth + labelGap,
                y: 0,
                width: stackWidth,
                height: size.height
            )

            drawLabel(for: value, in: labelRect)
            drawStackedBars(in: stackRect, bar: value)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func normalizedBars(_ bars: [Bar]) -> [Bar] {
        let values = bars.isEmpty ? placeholderBars : bars
        return Array(values.prefix(3))
    }

    private static func imageSize(for machineCount: Int) -> NSSize {
        let count = max(1, min(machineCount, 3))
        let width = horizontalPadding * 2
            + machineElementWidth * CGFloat(count)
            + machineGap * CGFloat(count - 1)
        return NSSize(width: width, height: 18)
    }

    private static var horizontalPadding: CGFloat {
        2
    }

    private static var machineElementWidth: CGFloat {
        labelWidth + labelGap + agentBarProgressBarWidth
    }

    private static var machineGap: CGFloat {
        3
    }

    private static var labelWidth: CGFloat {
        8
    }

    private static var labelGap: CGFloat {
        2
    }

    private static var stackWidth: CGFloat {
        agentBarProgressBarWidth
    }

    private static var agentBarProgressBarWidth: CGFloat {
        38
    }

    private static var verticalInset: CGFloat {
        1
    }

    private static var metricBarHeight: CGFloat {
        4
    }

    private static var metricBarGap: CGFloat {
        2
    }

    private static func drawLabel(
        for bar: Bar,
        in rect: NSRect
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let fontSize: CGFloat = bar.label.count > 3 ? 6.4 : 7.4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(
                ofSize: fontSize,
                weight: .heavy
            ),
            .foregroundColor: labelColor(for: bar),
            .paragraphStyle: paragraphStyle
        ]

        guard let context = NSGraphicsContext.current else {
            bar.label.draw(in: rect, withAttributes: attributes)
            return
        }

        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: -90)
        transform.translateX(by: -rect.height / 2, yBy: -rect.width / 2)
        transform.concat()

        bar.label.draw(
            in: NSRect(x: 0, y: 0, width: rect.height, height: rect.width),
            withAttributes: attributes
        )
        context.restoreGraphicsState()
    }

    private static func drawStackedBars(
        in rect: NSRect,
        bar: Bar
    ) {
        let percents = bar.percents
        let barHeight = metricBarHeight(for: percents.count)
        let barGap = metricBarGap(for: percents.count)
        let stackHeight = barHeight * CGFloat(percents.count)
            + barGap * CGFloat(max(0, percents.count - 1))
        let startY = (rect.height - stackHeight) / 2

        for (index, percent) in percents.enumerated() {
            let y = startY + CGFloat(percents.count - 1 - index) * (barHeight + barGap)
            let metricRect = NSRect(
                x: rect.minX,
                y: y,
                width: rect.width,
                height: barHeight
            )
            drawBar(in: metricRect, percent: percent, isError: bar.isError)
        }
    }

    private static func metricBarHeight(for metricCount: Int) -> CGFloat {
        metricCount > 3 ? 3 : metricBarHeight
    }

    private static func metricBarGap(for metricCount: Int) -> CGFloat {
        metricCount > 3 ? 1 : metricBarGap
    }

    private static func drawBar(
        in rect: NSRect,
        percent: Double?,
        isError: Bool
    ) {
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6)
        trackColor(percent: percent, isError: isError).setFill()
        trackPath.fill()

        guard let percent else {
            if isError {
                drawUnavailableMarker(in: rect)
            }
            return
        }

        let fillFraction = fillFraction(for: percent)
        let fillRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(2, rect.width * fillFraction),
            height: rect.height
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.6, yRadius: 1.6)
        fillColor(percent: percent, isError: isError).setFill()
        fillPath.fill()
    }

    private static func drawUnavailableMarker(in rect: NSRect) {
        let markerRect = rect.insetBy(dx: 1.4, dy: max(0.5, rect.height * 0.18))
        let markerPath = NSBezierPath()
        markerPath.lineWidth = max(1, min(1.4, rect.height * 0.35))
        markerPath.lineCapStyle = .round
        markerPath.move(to: NSPoint(x: markerRect.minX, y: markerRect.minY))
        markerPath.line(to: NSPoint(x: markerRect.maxX, y: markerRect.maxY))
        markerPath.move(to: NSPoint(x: markerRect.minX, y: markerRect.maxY))
        markerPath.line(to: NSPoint(x: markerRect.maxX, y: markerRect.minY))
        NSColor.systemRed.withAlphaComponent(0.9).setStroke()
        markerPath.stroke()
    }

    private static func fillFraction(for percent: Double) -> CGFloat {
        return max(0, min(1, CGFloat(percent / 100)))
    }

    private static func trackColor(percent: Double?, isError: Bool) -> NSColor {
        if isError {
            return NSColor.systemRed.withAlphaComponent(0.22)
        }

        return NSColor.labelColor.withAlphaComponent(percent == nil ? 0.18 : 0.22)
    }

    private static func labelColor(for bar: Bar) -> NSColor {
        if bar.isError {
            return NSColor.systemRed.withAlphaComponent(0.9)
        }

        guard let highestPercent = bar.percents.compactMap({ $0 }).max() else {
            return .labelColor.withAlphaComponent(0.5)
        }

        return progressColor(for: highestPercent)
    }

    private static func fillColor(percent: Double?, isError: Bool) -> NSColor {
        if isError {
            return NSColor.systemRed.withAlphaComponent(0.9)
        }

        guard let percent else {
            return .labelColor.withAlphaComponent(0.5)
        }

        return progressColor(for: percent)
    }

    private static func progressColor(for percent: Double) -> NSColor {
        switch percent {
        case 95...:
            return .systemRed
        case 80...:
            return .systemOrange
        default:
            return .systemGreen
        }
    }
}
