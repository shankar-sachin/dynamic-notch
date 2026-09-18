import OSLog

/// `make logs` streams these.
enum Log {
    static let app = Logger(subsystem: "com.sachi.DynamicNotch", category: "app")
    static let media = Logger(subsystem: "com.sachi.DynamicNotch", category: "media")
    static let window = Logger(subsystem: "com.sachi.DynamicNotch", category: "window")
    static let system = Logger(subsystem: "com.sachi.DynamicNotch", category: "system")
}
