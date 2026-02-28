import Foundation
import Observation
import ForgeShared

/// Maximum paste size: 10MB
private let maxPasteSize = 10 * 1_048_576

/// Maximum undo stack depth
private let maxUndoStackSize = 500

// MARK: - Undo Entry

/// Records a single undoable/redoable edit operation.
struct UndoEntry: Sendable {
    let deletedText: String
    let insertedText: String
    let position: Int // byte offset in the buffer
    let cursorBefore: TextPosition
    let cursorAfter: TextPosition
}

// MARK: - Gap Buffer

/// A gap buffer: contiguous array with a gap at the cursor for O(1) insert/delete.
///
/// The buffer is laid out as: [prefix content] [gap ...] [suffix content]
/// Moving the gap to the cursor position is O(k) where k is the distance moved,
/// but inserts and deletes at the gap are O(1).
@Observable
@MainActor
public final class EditorBuffer {
    // MARK: - Storage

    /// The raw backing storage with embedded gap.
    private var storage: ContiguousArray<UInt8>

    /// Start index of the gap in storage.
    private var gapStart: Int

    /// End index of the gap in storage (exclusive).
    private var gapEnd: Int

    // MARK: - State

    /// Current cursor position in document coordinates.
    public var cursorPosition: TextPosition

    /// Active selection ranges (empty array = no selection).
    public var selections: [TextRange]

    /// All cursor positions for multi-cursor editing.
    public var cursors: [TextPosition]

    /// Whether the buffer has unsaved modifications.
    public private(set) var isModified: Bool

    /// The file URL this buffer is associated with, if any.
    public var fileURL: URL?

    // MARK: - Undo/Redo

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []

    // MARK: - Line Cache

    /// Cached line start offsets for fast line/column ↔ byte offset conversion.
    /// Each entry is the byte offset where that line begins in the logical content.
    private var lineStarts: [Int] = [0]

    // MARK: - Init

    public init(content: String = "") {
        let bytes = ContiguousArray(content.utf8)
        let initialGapSize = max(256, bytes.count / 4)
        var buffer = ContiguousArray<UInt8>()
        buffer.reserveCapacity(bytes.count + initialGapSize)
        buffer.append(contentsOf: bytes)
        buffer.append(contentsOf: ContiguousArray(repeating: 0, count: initialGapSize))

        self.storage = buffer
        self.gapStart = bytes.count
        self.gapEnd = bytes.count + initialGapSize
        self.cursorPosition = TextPosition(line: 0, column: 0)
        self.selections = []
        self.cursors = [TextPosition(line: 0, column: 0)]
        self.isModified = false

        rebuildLineCache()
    }

    // MARK: - Content Access

    /// The total number of logical bytes (excluding the gap).
    public var count: Int {
        storage.count - gapSize
    }

    /// The size of the gap.
    private var gapSize: Int {
        gapEnd - gapStart
    }

    /// Returns the full document content as a String.
    public var text: String {
        var bytes = ContiguousArray<UInt8>()
        bytes.reserveCapacity(count)
        bytes.append(contentsOf: storage[0..<gapStart])
        bytes.append(contentsOf: storage[gapEnd..<storage.count])
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Number of lines in the document.
    public var lineCount: Int {
        lineStarts.count
    }

    /// Returns the text for a specific line (without trailing newline).
    public func lineText(_ lineIndex: Int) -> String {
        guard lineIndex >= 0 && lineIndex < lineStarts.count else { return "" }
        let startOffset = lineStarts[lineIndex]
        let endOffset: Int
        if lineIndex + 1 < lineStarts.count {
            // End is just before the newline that starts the next line
            endOffset = lineStarts[lineIndex + 1] - 1
        } else {
            endOffset = count
        }
        guard endOffset > startOffset else { return "" }

        var bytes = ContiguousArray<UInt8>()
        bytes.reserveCapacity(endOffset - startOffset)
        for i in startOffset..<endOffset {
            bytes.append(logicalByte(at: i))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Insert

    /// Insert text at a given document position.
    public func insert(_ text: String, at position: TextPosition) throws {
        let bytes = ContiguousArray(text.utf8)
        guard bytes.count <= maxPasteSize else {
            throw EditorError.pasteTooLarge(size: bytes.count)
        }

        let offset = offsetFromPosition(position)
        moveGap(to: offset)
        ensureGapCapacity(bytes.count)

        let cursorBefore = cursorPosition

        for byte in bytes {
            storage[gapStart] = byte
            gapStart += 1
        }

        rebuildLineCache()
        cursorPosition = positionFromOffset(offset + bytes.count)
        cursors = [cursorPosition]
        isModified = true

        let entry = UndoEntry(
            deletedText: "",
            insertedText: text,
            position: offset,
            cursorBefore: cursorBefore,
            cursorAfter: cursorPosition
        )
        pushUndo(entry)
    }

    /// Insert text at the current cursor position.
    public func insertAtCursor(_ text: String) throws {
        if cursors.count > 1 {
            // Multi-cursor: insert at all cursor positions (reverse order to maintain offsets)
            let sorted = cursors.sorted(by: >)
            for cursor in sorted {
                try insert(text, at: cursor)
            }
        } else {
            try insert(text, at: cursorPosition)
        }
    }

    // MARK: - Delete

    /// Delete text in the given range.
    public func delete(range: TextRange) {
        let startOffset = offsetFromPosition(range.start)
        let endOffset = offsetFromPosition(range.end)
        guard endOffset > startOffset else { return }

        let deletedText = textInRange(startOffset: startOffset, endOffset: endOffset)
        let cursorBefore = cursorPosition

        moveGap(to: startOffset)
        gapEnd += (endOffset - startOffset)

        rebuildLineCache()
        cursorPosition = range.start
        cursors = [cursorPosition]
        isModified = true

        let entry = UndoEntry(
            deletedText: deletedText,
            insertedText: "",
            position: startOffset,
            cursorBefore: cursorBefore,
            cursorAfter: cursorPosition
        )
        pushUndo(entry)
    }

    /// Delete the character before the cursor (backspace).
    public func deleteBackward() {
        guard cursorPosition != TextPosition(line: 0, column: 0) else { return }
        let offset = offsetFromPosition(cursorPosition)
        guard offset > 0 else { return }

        let prevPos = positionFromOffset(offset - 1)
        delete(range: TextRange(start: prevPos, end: cursorPosition))
    }

    /// Delete the character after the cursor (forward delete).
    public func deleteForward() {
        let offset = offsetFromPosition(cursorPosition)
        guard offset < count else { return }

        let nextPos = positionFromOffset(offset + 1)
        delete(range: TextRange(start: cursorPosition, end: nextPos))
    }

    // MARK: - Undo / Redo

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func undo() {
        guard let entry = undoStack.popLast() else { return }

        // Reverse the operation
        if !entry.insertedText.isEmpty {
            // Undo an insert → delete the inserted text
            let bytes = ContiguousArray(entry.insertedText.utf8)
            moveGap(to: entry.position)
            gapEnd += bytes.count
        }

        if !entry.deletedText.isEmpty {
            // Undo a delete → re-insert the deleted text
            let bytes = ContiguousArray(entry.deletedText.utf8)
            moveGap(to: entry.position)
            ensureGapCapacity(bytes.count)
            for byte in bytes {
                storage[gapStart] = byte
                gapStart += 1
            }
        }

        rebuildLineCache()
        cursorPosition = entry.cursorBefore
        cursors = [cursorPosition]
        isModified = true

        redoStack.append(entry)
    }

    public func redo() {
        guard let entry = redoStack.popLast() else { return }

        // Re-apply the operation
        if !entry.deletedText.isEmpty {
            // Redo a delete
            let bytes = ContiguousArray(entry.deletedText.utf8)
            moveGap(to: entry.position)
            gapEnd += bytes.count
        }

        if !entry.insertedText.isEmpty {
            // Redo an insert
            let bytes = ContiguousArray(entry.insertedText.utf8)
            moveGap(to: entry.position)
            ensureGapCapacity(bytes.count)
            for byte in bytes {
                storage[gapStart] = byte
                gapStart += 1
            }
        }

        rebuildLineCache()
        cursorPosition = entry.cursorAfter
        cursors = [cursorPosition]
        isModified = true

        undoStack.append(entry)
    }

    // MARK: - File I/O

    /// Load content from a file URL. Rejects files > 100MB.
    public func load(from url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        guard fileSize <= 100 * 1_048_576 else {
            throw EditorError.fileTooLarge(size: fileSize)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EditorError.fileReadFailed(url, error.localizedDescription)
        }

        let content = String(decoding: data, as: UTF8.self)
        replaceAll(with: content)
        fileURL = url
        isModified = false
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Save the current content to the associated file URL.
    public func save() async throws {
        guard let url = fileURL else { return }
        let content = text
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EditorError.fileWriteFailed(url, error.localizedDescription)
        }
        isModified = false
    }

    /// Save to a specific URL.
    public func save(to url: URL) async throws {
        let content = text
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EditorError.fileWriteFailed(url, error.localizedDescription)
        }
        fileURL = url
        isModified = false
    }

    // MARK: - Replace All

    /// Replace entire buffer content (used for file load).
    public func replaceAll(with content: String) {
        let bytes = ContiguousArray(content.utf8)
        let gapSize = max(256, bytes.count / 4)
        var buffer = ContiguousArray<UInt8>()
        buffer.reserveCapacity(bytes.count + gapSize)
        buffer.append(contentsOf: bytes)
        buffer.append(contentsOf: ContiguousArray(repeating: 0, count: gapSize))

        storage = buffer
        gapStart = bytes.count
        gapEnd = bytes.count + gapSize
        cursorPosition = TextPosition(line: 0, column: 0)
        cursors = [cursorPosition]
        selections = []
        rebuildLineCache()
    }

    // MARK: - Private Helpers

    /// Read a logical byte at the given logical offset (accounting for the gap).
    private func logicalByte(at offset: Int) -> UInt8 {
        if offset < gapStart {
            return storage[offset]
        } else {
            return storage[offset + gapSize]
        }
    }

    /// Extract text from a logical byte range.
    private func textInRange(startOffset: Int, endOffset: Int) -> String {
        var bytes = ContiguousArray<UInt8>()
        bytes.reserveCapacity(endOffset - startOffset)
        for i in startOffset..<endOffset {
            bytes.append(logicalByte(at: i))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Move the gap so it starts at the given logical offset.
    private func moveGap(to offset: Int) {
        if offset == gapStart { return }

        if offset < gapStart {
            // Move gap left: shift bytes from before gap to after gap
            let moveCount = gapStart - offset
            storage.withUnsafeMutableBufferPointer { ptr in
                let src = ptr.baseAddress! + offset
                let dst = ptr.baseAddress! + gapEnd - moveCount
                dst.update(from: src, count: moveCount)
            }
            gapEnd -= moveCount
            gapStart = offset
        } else {
            // Move gap right: shift bytes from after gap to before gap
            let moveCount = offset - gapStart
            storage.withUnsafeMutableBufferPointer { ptr in
                let src = ptr.baseAddress! + gapEnd
                let dst = ptr.baseAddress! + gapStart
                dst.update(from: src, count: moveCount)
            }
            gapStart += moveCount
            gapEnd += moveCount
        }
    }

    /// Ensure the gap has at least `needed` bytes of capacity, growing if necessary.
    private func ensureGapCapacity(_ needed: Int) {
        guard gapSize < needed else { return }

        let growth = max(needed - gapSize, max(256, count / 4))
        var newStorage = ContiguousArray<UInt8>()
        newStorage.reserveCapacity(storage.count + growth)
        newStorage.append(contentsOf: storage[0..<gapStart])
        newStorage.append(contentsOf: ContiguousArray(repeating: 0, count: gapSize + growth))
        newStorage.append(contentsOf: storage[gapEnd..<storage.count])

        gapEnd = gapStart + gapSize + growth
        storage = newStorage
    }

    /// Convert a TextPosition (line, column) to a logical byte offset.
    private func offsetFromPosition(_ pos: TextPosition) -> Int {
        guard pos.line >= 0 && pos.line < lineStarts.count else {
            return count
        }
        return min(lineStarts[pos.line] + pos.column, count)
    }

    /// Convert a logical byte offset to a TextPosition (line, column).
    private func positionFromOffset(_ offset: Int) -> TextPosition {
        let clampedOffset = min(max(offset, 0), count)

        // Binary search for the line
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= clampedOffset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return TextPosition(line: lo, column: clampedOffset - lineStarts[lo])
    }

    /// Rebuild the line start offset cache from the current buffer content.
    private func rebuildLineCache() {
        lineStarts = [0]
        let total = count
        for i in 0..<total {
            if logicalByte(at: i) == UInt8(ascii: "\n") {
                lineStarts.append(i + 1)
            }
        }
    }

    private func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }
}
