import Foundation
import ForgeShared
import ForgePersistence
import os.log

private let logger = Logger(subsystem: "com.forge.editor", category: "indexer")

/// Cosine similarity threshold for search results.
private let similarityThreshold: Float = 0.3

// MARK: - SemanticIndexer

/// Actor-isolated semantic indexer using embeddings and SwiftData storage.
///
/// Incrementally indexes files by content hash, embeds via EmbeddingPipeline,
/// stores SemanticEntry in SwiftData. Query by cosine similarity with 0.3 threshold.
/// Concurrency capped at activeProcessorCount via TaskGroup.
public actor SemanticIndexer {
    // MARK: - Properties

    private let embeddingPipeline = EmbeddingPipeline()
    private let persistence: PersistenceManager

    private var isIndexing = false
    private var statusContinuation: AsyncStream<IndexStatus>.Continuation?

    /// AsyncStream of indexing status updates.
    public nonisolated let statusStream: AsyncStream<IndexStatus>
    private let _statusContinuation: AsyncStream<IndexStatus>.Continuation

    // MARK: - Init

    public init(persistence: PersistenceManager) {
        self.persistence = persistence
        let (stream, continuation) = AsyncStream<IndexStatus>.makeStream()
        self.statusStream = stream
        self._statusContinuation = continuation
    }

    // MARK: - Index

    /// Index a list of file URLs. Only re-indexes files with changed content hashes.
    public func indexFiles(_ urls: [URL]) async {
        guard !isIndexing else {
            logger.info("Indexing already in progress, skipping")
            return
        }

        isIndexing = true
        _statusContinuation.yield(.building(filesProcessed: 0, totalFiles: urls.count))
        logger.info("Starting indexing of \(urls.count) files")

        // Load embedding model
        do {
            try await embeddingPipeline.load()
        } catch {
            logger.error("Failed to load embedding pipeline: \(error.localizedDescription)")
            _statusContinuation.yield(.error(error.localizedDescription))
            isIndexing = false
            return
        }

        // Fetch existing entries for content-hash comparison
        let existingSnapshots: [SemanticEntrySnapshot]
        do {
            existingSnapshots = try await persistence.fetchAllSemanticSnapshots()
        } catch {
            existingSnapshots = []
        }
        let existingHashes = Dictionary(
            uniqueKeysWithValues: existingSnapshots.map { ($0.filePath, $0.contentHash) }
        )

        let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
        var processed = 0

        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for url in urls {
                // Cap concurrency
                if activeCount >= maxConcurrent {
                    await group.next()
                    activeCount -= 1
                }

                activeCount += 1
                group.addTask { [self] in
                    await self.indexSingleFile(url, existingHashes: existingHashes)
                }

                processed += 1
                _statusContinuation.yield(.building(filesProcessed: processed, totalFiles: urls.count))
            }

            // Wait for remaining tasks
            await group.waitForAll()
        }

        _statusContinuation.yield(.completed(totalFiles: urls.count))
        isIndexing = false
        logger.info("Indexing completed: \(urls.count) files")
    }

    /// Index files triggered by file change events.
    public func handleFileChanges(_ events: [FileChangeEvent]) async {
        var filesToIndex: [URL] = []
        var filesToDelete: [String] = []

        for event in events {
            switch event.kind {
            case .created, .modified, .renamed:
                // Only index text files
                let lang = Language.detect(from: event.path)
                if lang != .unknown {
                    filesToIndex.append(event.path)
                }
            case .deleted:
                filesToDelete.append(event.path.path)
            case .permissionError:
                break
            }
        }

        // Delete entries for removed files
        if !filesToDelete.isEmpty {
            do {
                try await persistence.deleteSemanticEntries(for: filesToDelete)
                logger.debug("Deleted \(filesToDelete.count) semantic entries")
            } catch {
                logger.error("Failed to delete semantic entries: \(error.localizedDescription)")
            }
        }

        // Index new/modified files
        if !filesToIndex.isEmpty {
            await indexFiles(filesToIndex)
        }
    }

    // MARK: - Search

    /// Search for files semantically similar to a query string.
    public func search(query: String, limit: Int = 10) async throws -> [SemanticMatch] {
        try await embeddingPipeline.load()
        let queryEmbedding = try await embeddingPipeline.embed(text: query)

        let allSnapshots = try await persistence.fetchAllSemanticSnapshots()
        var results: [SemanticMatch] = []

        for snapshot in allSnapshots {
            let similarity = cosineSimilarity(queryEmbedding, snapshot.embeddingVector)
            guard similarity >= similarityThreshold else { continue }

            results.append(SemanticMatch(
                filePath: snapshot.filePath,
                symbolName: snapshot.symbols.first ?? snapshot.filePath,
                lineRange: 0..<1,
                score: similarity,
                snippet: ""
            ))
        }

        // Sort by score descending
        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    // MARK: - Private

    private func indexSingleFile(_ url: URL, existingHashes: [String: String]) async {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let hash = await embeddingPipeline.contentHash(for: text)

            // Skip if content hash hasn't changed
            if existingHashes[url.path] == hash {
                return
            }

            let embedding = try await embeddingPipeline.embed(text: text)

            // Extract symbol names (simple regex for functions/types)
            let symbols = extractSymbols(from: text, language: Language.detect(from: url))

            let entry = SemanticEntry(
                filePath: url.path,
                contentHash: hash,
                embedding: embedding,
                symbols: symbols
            )

            try await persistence.saveSemanticEntries([entry])
        } catch {
            logger.error("Failed to index \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Extract top-level symbol names from source code.
    private func extractSymbols(from text: String, language: Language) -> [String] {
        var symbols: [String] = []
        let lines = text.components(separatedBy: .newlines)

        let patterns: [(String, String)] = switch language {
        case .swift:
            [
                ("func\\s+(\\w+)", "func"),
                ("class\\s+(\\w+)", "class"),
                ("struct\\s+(\\w+)", "struct"),
                ("enum\\s+(\\w+)", "enum"),
                ("protocol\\s+(\\w+)", "protocol"),
            ]
        case .python:
            [
                ("def\\s+(\\w+)", "def"),
                ("class\\s+(\\w+)", "class"),
            ]
        case .typescript, .javascript:
            [
                ("function\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class"),
                ("const\\s+(\\w+)\\s*=", "const"),
            ]
        default:
            [
                ("func(?:tion)?\\s+(\\w+)", "function"),
                ("class\\s+(\\w+)", "class"),
            ]
        }

        for line in lines {
            for (pattern, _) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: line) {
                    symbols.append(String(line[range]))
                }
            }
        }

        return symbols
    }
}
