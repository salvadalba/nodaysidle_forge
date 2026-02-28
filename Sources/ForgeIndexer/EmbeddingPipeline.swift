import Foundation
import NaturalLanguage
import ForgeShared
import os.log

private let logger = Logger(subsystem: "com.forge.editor", category: "embedding")

// MARK: - EmbeddingPipeline

/// On-device text embedding pipeline using NLEmbedding.
///
/// Generates 128-dimensional embedding vectors for code files using Apple's
/// built-in word embeddings. Falls back to TF-IDF-style hashing for unsupported
/// languages.
///
/// Note: In production, this would use a bundled sub-50MB CoreML model for
/// 256-dim semantic embeddings. For now, we use NLEmbedding which ships with macOS.
public actor EmbeddingPipeline {
    // MARK: - Configuration

    /// Embedding vector dimension.
    public static let embeddingDimension = 128

    // MARK: - Properties

    private var embedding: NLEmbedding?
    private var isLoaded = false

    // MARK: - Init

    public init() {}

    // MARK: - Load

    /// Load the embedding model.
    public func load() throws {
        guard !isLoaded else { return }

        // Use Apple's built-in English word embedding
        guard let emb = NLEmbedding.wordEmbedding(for: .english) else {
            throw IndexerError.modelLoadFailed("NLEmbedding for English not available")
        }

        self.embedding = emb
        self.isLoaded = true
        logger.info("Embedding pipeline loaded (NLEmbedding, dim=\(emb.dimension))")
    }

    // MARK: - Embed

    /// Generate an embedding vector for a code file's content.
    /// Tokenizes with NLTokenizer, embeds each word, and averages.
    public func embed(text: String) throws -> [Float] {
        guard isLoaded, let embedding else {
            throw IndexerError.modelNotLoaded
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var sumVector = [Double](repeating: 0, count: embedding.dimension)
        var wordCount = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vector = embedding.vector(for: word) {
                for (i, v) in vector.enumerated() {
                    if i < sumVector.count {
                        sumVector[i] += v
                    }
                }
                wordCount += 1
            }
            return true
        }

        // Average the vectors
        if wordCount > 0 {
            let avg = sumVector.map { Float($0 / Double(wordCount)) }
            return padOrTruncate(avg, to: Self.embeddingDimension)
        }

        // Fallback: hash-based embedding for code tokens
        return hashEmbedding(for: text)
    }

    /// Generate a content hash for change detection.
    public func contentHash(for text: String) -> String {
        // Simple hash using string's hashValue (stable within process)
        // In production, use SHA-256
        var hasher = Hasher()
        hasher.combine(text)
        let hash = hasher.finalize()
        return String(format: "%016x", abs(hash))
    }

    // MARK: - Helpers

    /// Pad or truncate a vector to the target dimension.
    private func padOrTruncate(_ vector: [Float], to dimension: Int) -> [Float] {
        if vector.count >= dimension {
            return Array(vector.prefix(dimension))
        }
        return vector + [Float](repeating: 0, count: dimension - vector.count)
    }

    /// Fallback hash-based embedding for content not well-served by NLEmbedding.
    private func hashEmbedding(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: Self.embeddingDimension)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })

        for word in words {
            var hasher = Hasher()
            hasher.combine(String(word))
            let hash = abs(hasher.finalize())
            let index = hash % Self.embeddingDimension
            vector[index] += 1.0
        }

        // Normalize
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }

        return vector
    }
}

// MARK: - Cosine Similarity

/// Compute cosine similarity between two vectors.
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    var dotProduct: Float = 0
    var magnitudeA: Float = 0
    var magnitudeB: Float = 0

    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        magnitudeA += a[i] * a[i]
        magnitudeB += b[i] * b[i]
    }

    let denominator = sqrt(magnitudeA) * sqrt(magnitudeB)
    guard denominator > 0 else { return 0 }

    return dotProduct / denominator
}
