import Foundation

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case writeFailed(String)
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Could not open the snapshot database: \(message)"
        case .prepareFailed(let message):
            "Database query preparation failed: \(message)"
        case .writeFailed(let message):
            "Database write failed: \(message)"
        case .execFailed(let message):
            "Database command failed: \(message)"
        }
    }
}

enum RestoreError: LocalizedError {
    case appNotFound(String)
    case launchFailed(String, underlying: Error)
    case openURLFailed(String, underlying: Error)
    case openFileFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            "Could not find \(name) on this Mac"
        case .launchFailed(let name, let underlying):
            "Could not launch \(name): \(underlying.localizedDescription)"
        case .openURLFailed(let url, let underlying):
            "Could not open \(url): \(underlying.localizedDescription)"
        case .openFileFailed(let path, let underlying):
            "Could not open \(path): \(underlying.localizedDescription)"
        }
    }
}

enum SummaryError: LocalizedError {
    case cacheLoadFailed(String)
    case cacheSaveFailed(String)
    case llmUnavailable
    case llmGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cacheLoadFailed(let detail):
            "Summary cache could not be loaded: \(detail)"
        case .cacheSaveFailed(let detail):
            "Summary cache could not be saved: \(detail)"
        case .llmUnavailable:
            "On-device language model is unavailable"
        case .llmGenerationFailed(let detail):
            "Summary generation failed: \(detail)"
        }
    }
}
