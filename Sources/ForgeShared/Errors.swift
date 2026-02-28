import Foundation

// MARK: - LSP Errors

/// Errors from the Language Server Protocol coordinator.
public enum LSPError: LocalizedError, Sendable {
    case serverNotRunning
    case serverBinaryNotFound(String)
    case serverBinaryNotExecutable(String)
    case serverBinaryUntrusted(String)
    case initializationFailed(stderr: String)
    case timeout(String)
    case messageTooLarge(Int)
    case parseError(String)
    case serverCrashed
    case maxRestartsExceeded
    case processSpawnFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Language server is not running"
        case .serverBinaryNotFound(let path):
            return "Language server not found at: \(path)"
        case .serverBinaryNotExecutable(let path):
            return "Language server is not executable: \(path)"
        case .serverBinaryUntrusted(let path):
            return "Language server binary outside allowed directories: \(path)"
        case .initializationFailed(let stderr):
            return "Language server initialization failed: \(stderr)"
        case .timeout(let method):
            return "Language server request timed out: \(method)"
        case .messageTooLarge(let size):
            return "Language server message exceeds 16MB limit: \(size) bytes"
        case .parseError(let detail):
            return "Failed to parse language server response: \(detail)"
        case .serverCrashed:
            return "Language server crashed unexpectedly"
        case .maxRestartsExceeded:
            return "Language server exceeded maximum restart attempts"
        case .processSpawnFailed(let detail):
            return "Failed to spawn language server process: \(detail)"
        }
    }
}

// MARK: - Indexer Errors

/// Errors from the semantic indexer.
public enum IndexerError: LocalizedError, Sendable {
    case modelNotLoaded
    case modelLoadFailed(String)
    case inferenceFailure(String)
    case indexNotBuilt
    case fetchFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "CoreML embedding model is not loaded"
        case .modelLoadFailed(let detail):
            return "Failed to load CoreML model: \(detail)"
        case .inferenceFailure(let detail):
            return "CoreML inference failed: \(detail)"
        case .indexNotBuilt:
            return "Semantic index has not been built yet"
        case .fetchFailed(let detail):
            return "Failed to fetch semantic entries: \(detail)"
        case .cancelled:
            return "Indexing operation was cancelled"
        }
    }
}

// MARK: - Persistence Errors

/// Errors from the SwiftData persistence layer.
public enum PersistenceError: LocalizedError, Sendable {
    case containerCreationFailed(String)
    case saveFailed(String)
    case saveConflict(String)
    case fetchFailed(String)
    case migrationFailed(String)
    case diskFull

    public var errorDescription: String? {
        switch self {
        case .containerCreationFailed(let detail):
            return "Failed to create data container: \(detail)"
        case .saveFailed(let detail):
            return "Failed to save data: \(detail)"
        case .saveConflict(let detail):
            return "Data save conflict: \(detail)"
        case .fetchFailed(let detail):
            return "Failed to fetch data: \(detail)"
        case .migrationFailed(let detail):
            return "Schema migration failed: \(detail)"
        case .diskFull:
            return "Unable to save — disk space is low"
        }
    }
}

// MARK: - Rendering Errors

/// Errors from the Metal rendering engine.
public enum RenderingError: LocalizedError, Sendable {
    case deviceCreationFailed
    case pipelineCreationFailed(String)
    case textureAtlasOverflow
    case commandBufferError(String)
    case drawableAcquisitionTimeout
    case shaderCompilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceCreationFailed:
            return "Failed to create Metal GPU device — falling back to software rendering"
        case .pipelineCreationFailed(let detail):
            return "Failed to create Metal render pipeline: \(detail)"
        case .textureAtlasOverflow:
            return "Glyph texture atlas exceeded maximum size"
        case .commandBufferError(let detail):
            return "Metal command buffer error: \(detail)"
        case .drawableAcquisitionTimeout:
            return "Failed to acquire drawable from Metal layer"
        case .shaderCompilationFailed(let detail):
            return "Metal shader compilation failed: \(detail)"
        }
    }
}

// MARK: - Editor Errors

/// Errors from the editor engine.
public enum EditorError: LocalizedError, Sendable {
    case fileTooLarge(size: Int64)
    case pasteTooLarge(size: Int)
    case fileReadFailed(URL, String)
    case fileWriteFailed(URL, String)
    case bookmarkCreationFailed(URL)
    case bookmarkResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            return "File exceeds 100MB limit (\(size / 1_048_576)MB) — consider hex view"
        case .pasteTooLarge(let size):
            return "Paste operation exceeds 10MB limit (\(size / 1_048_576)MB)"
        case .fileReadFailed(let url, let detail):
            return "Failed to read \(url.lastPathComponent): \(detail)"
        case .fileWriteFailed(let url, let detail):
            return "Failed to save \(url.lastPathComponent): \(detail)"
        case .bookmarkCreationFailed(let url):
            return "Failed to create security bookmark for: \(url.path)"
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        }
    }
}
