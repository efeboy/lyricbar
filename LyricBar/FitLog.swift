import AppKit
import OSLog

enum FitLog {

    private static let subsystem = "net.local.lyricbar"

    static let calibration = Logger(subsystem: subsystem, category: "calibration")
    static let drift = Logger(subsystem: subsystem, category: "drift")
    static let render = Logger(subsystem: subsystem, category: "render")

    static func points(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }

    static func points(_ value: CGFloat?) -> String {
        value.map(points) ?? "none"
    }

    static func geometry(_ frame: CGRect) -> String {
        "minX=\(points(frame.minX)) maxX=\(points(frame.maxX)) width=\(points(frame.width))"
    }

    static func geometry(_ frame: CGRect?) -> String {
        frame.map(geometry) ?? "frame=unreadable"
    }

    static func milliseconds(_ duration: Duration) -> String {
        let parts = duration.components
        return String(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}
