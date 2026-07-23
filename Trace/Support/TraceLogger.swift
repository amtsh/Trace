import OSLog

extension Logger {
    static let sessions = Logger(subsystem: "amitshinde.Trace", category: "sessions")
    static let db = Logger(subsystem: "amitshinde.Trace", category: "database")
    static let summary = Logger(subsystem: "amitshinde.Trace", category: "summary")
    static let restore = Logger(subsystem: "amitshinde.Trace", category: "restore")
    static let tracking = Logger(subsystem: "amitshinde.Trace", category: "tracking")
}
