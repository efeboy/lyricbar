import AppKit
import OSLog

enum FitLog {

    private static let subsystem = "net.local.lyricbar"

    static let render = Logger(subsystem: subsystem, category: "render")

    static func points(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }

    static func geometry(_ frame: CGRect) -> String {
        "minX=\(points(frame.minX)) maxX=\(points(frame.maxX)) width=\(points(frame.width))"
    }

    static func geometry(_ frame: CGRect?) -> String {
        frame.map(geometry) ?? "frame=unreadable"
    }
}
