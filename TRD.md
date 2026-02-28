# Technical Requirements Document

## 🧭 System Context
Forge is a single-process macOS-native code editor targeting macOS 15+ on Apple Silicon. Built entirely on Apple frameworks: SwiftUI 6 for presentation, Metal shaders for GPU-accelerated 120fps rendering, CoreML and NaturalLanguage for on-device semantic indexing, SwiftData over local SQLite for persistence, and Swift Structured Concurrency for parallel subsystem orchestration. No server component exists — all logic runs locally. Distribution is via signed/notarized .app bundle. The architecture is a layered monolith: Presentation → State → Domain → Persistence, with actor-isolated services communicating through Swift protocols and AsyncStream channels.

## 🔌 API Contracts
### LSPCoordinator JSON-RPC
- **Method:** STDIN/STDOUT
- **Path:** Process pipe to external language server binary
- **Auth:** None — local child process communication
- **Request:** JSON-RPC 2.0 request envelope: {jsonrpc: '2.0', id: Int, method: String, params: Codable}. Methods include textDocument/completion, textDocument/definition, textDocument/hover, textDocument/diagnostics, initialize, shutdown. Serialized via JSONEncoder to AsyncBytes written to Process.standardInput pipe.
- **Response:** JSON-RPC 2.0 response envelope: {jsonrpc: '2.0', id: Int, result: Codable?, error: {code: Int, message: String}?}. Streamed from Process.standardOutput via AsyncBytes, deserialized by JSONDecoder. Notifications (no id) arrive as server-initiated diagnostics and progress events.
- **Errors:** LSP server process crash — detect via Process.terminationHandler, attempt automatic restart up to 3 times with exponential backoff (1s, 2s, 4s), JSON-RPC parse error (code -32700) — log malformed payload, skip response, surface diagnostic timeout to user, Method not found (code -32601) — degrade gracefully, disable unsupported feature in editor UI, Request timeout — cancel pending Task after 10 seconds, surface 'Language server not responding' in status bar, Server initialization failure — show alert with stderr output, offer manual language server path configuration

### SemanticIndexer Query Interface
- **Method:** ASYNC
- **Path:** Actor method call: SemanticIndexer.query(_ text: String, limit: Int) async throws -> [SemanticMatch]
- **Auth:** None — in-process actor isolation
- **Request:** Query text as String, maximum result count as Int. Internally tokenized via NaturalLanguage NLTokenizer, embedded via CoreML model inference on MLModel.prediction(from:), then compared against stored embeddings using cosine similarity.
- **Response:** Array of SemanticMatch: {filePath: String, symbolName: String, lineRange: Range<Int>, score: Float, snippet: String}. Results sorted by descending cosine similarity score. Empty array if index is not yet built or query yields no matches above 0.3 threshold.
- **Errors:** CoreML model not loaded — return empty results, log error, trigger background model reload, Index not yet built — return empty results with IndexStatus.building metadata so UI can show progress indicator, SwiftData fetch failure — return empty results, log ModelContext error, do not crash, Task cancellation during inference — propagate CancellationError cleanly, release MLModel prediction resources

### FileWatcher Event Stream
- **Method:** ASYNC_STREAM
- **Path:** FileWatcher.events: AsyncStream<FileChangeEvent>
- **Auth:** None — local file system access via sandbox entitlements
- **Request:** Consumer calls `for await event in fileWatcher.events`. FileWatcher internally monitors directory tree via FSEvents (DispatchSource.makeFileSystemObjectSource for individual files, FSEventStream for recursive directory monitoring). Events are debounced with 200ms coalesce window to batch rapid saves.
- **Response:** FileChangeEvent: {path: String, kind: FileChangeKind (.created, .modified, .deleted, .renamed), timestamp: Date}. Emitted after debounce window closes. Rename events include both old and new paths when detectable via FSEvents kFSEventStreamEventFlagItemRenamed.
- **Errors:** FSEvents stream creation failure — fall back to polling directory every 2 seconds, log degraded mode, File permission denied — emit event with .permissionError kind, UI shows lock icon on file, Watch descriptor limit reached — prioritize open file directories, drop monitoring of deeply nested node_modules/vendor paths, Symbolic link cycle detected — skip cyclic paths, log warning, do not follow symlinks beyond 10 levels

### PersistenceManager Workspace Operations
- **Method:** ASYNC
- **Path:** PersistenceManager.saveWorkspaceState(_ state: WorkspaceState) async throws
- **Auth:** None — local SwiftData ModelContainer at ~/Library/Application Support/Forge/
- **Request:** WorkspaceState model object containing openTabs: [OpenDocument], sidebarWidth: CGFloat, activeDocumentID: PersistentIdentifier?, windowFrame: CGRect, lastOpenedDate: Date. Called on workspace close, app background, and periodically every 30 seconds during active editing.
- **Response:** Void on success. Save executes on a background ModelContext off the main actor. Background context is created per-save via ModelContainer.mainContext peer to avoid thread contention.
- **Errors:** SwiftData save conflict — retry once with fresh ModelContext fetch, log conflict details, Disk full — surface alert to user 'Unable to save workspace state — disk space low', do not crash, Schema migration failure on launch — delete local store, recreate empty, log migration error, inform user preferences were reset, CloudKit sync failure (preferences only) — continue with local-only operation, retry sync on next app launch

### MetalRenderingEngine Frame Submission
- **Method:** SYNC_CALLBACK
- **Path:** TimelineView(.animation) schedule with MTLCommandBuffer submission per frame
- **Auth:** None — GPU access via Metal device
- **Request:** Each frame: EditorViewport provides visible line range, cursor position, selection ranges, and syntax-highlighted AttributedString spans. MetalRenderingEngine builds glyph atlas via Core Text CTFont/CTLine, uploads dirty glyph textures to MTLTexture, constructs vertex buffer for visible glyphs, submits MTLRenderCommandEncoder draw calls for text layer, selection highlight layer, cursor blink layer, and minimap layer.
- **Response:** MTLCommandBuffer.commit() presents to CAMetalLayer drawable. Target 120fps on ProMotion (8.33ms frame budget). Frame scheduling adapts to display refresh rate via CADisplayLink/TimelineView cadence.
- **Errors:** MTLDevice creation failure — fall back to Core Text software rendering in standard SwiftUI Text views, log GPU unavailable, Texture atlas overflow (>4096x4096) — evict least-recently-used glyph pages, rebuild atlas subset, Command buffer error — skip frame, log GPU error status, reset pipeline state on next frame, Drawable acquisition timeout — drop frame, continue on next vsync, do not block main thread

## 🧱 Modules
### ForgeApp (App Entry)
- **Responsibilities:**
- Define @main App struct with WindowGroup and Settings scenes
- Configure ModelContainer with all three schema domains and inject via .modelContainer modifier
- Initialize root WorkspaceManager and inject into SwiftUI Environment
- Register SwiftUI Commands for menu bar integration (File, Edit, View, Navigate, Help)
- Configure NSWindow appearance on launch via NSApplication delegate for titlebar styling and .ultraThinMaterial
- **Interfaces:**
- App protocol conformance with body: some Scene
- NSApplicationDelegate for window customization hooks
- **Dependencies:**
- WorkspaceManager
- PersistenceManager
- ForgeEditorEngine

### WorkspaceManager
- **Responsibilities:**
- Maintain @Observable state for active workspace: file tree, open tabs, active document, sidebar configuration
- Coordinate workspace open/close lifecycle — trigger file watcher start/stop, index build/teardown, state save/restore
- Manage TabGroup model: open, close, reorder, pin tabs with undo support
- Provide file tree model built from FileWatcher events and initial directory enumeration
- Serve as root environment object injected into all SwiftUI views
- **Interfaces:**
- @Observable class WorkspaceManager
- func openWorkspace(at url: URL) async throws
- func closeWorkspace() async
- func openDocument(_ url: URL) async throws -> OpenDocument
- func closeDocument(_ id: OpenDocument.ID)
- var fileTree: FileTreeNode { get }
- var tabGroup: TabGroup { get }
- var activeDocument: OpenDocument? { get set }
- **Dependencies:**
- FileWatcher
- PersistenceManager
- SemanticIndexer

### ForgeEditorEngine
- **Responsibilities:**
- Manage text buffer state: rope or gap-buffer data structure for efficient insert/delete at cursor
- Track cursor position, selection ranges, multi-cursor state
- Apply text edits from user input, LSP completions, and undo/redo stack
- Produce AttributedString spans with syntax highlighting tokens for the rendering engine
- Expose document-level operations: save, revert, detect external modification
- **Interfaces:**
- @Observable class EditorBuffer
- func insert(_ text: String, at position: TextPosition)
- func delete(range: TextRange)
- var attributedContent: AttributedString { get }
- var cursorPosition: TextPosition { get set }
- var selections: [TextRange] { get set }
- func undo()
- func redo()
- func save() async throws
- **Dependencies:**
- SyntaxHighlighter
- LSPCoordinator
- PersistenceManager

### MetalRenderingEngine
- **Responsibilities:**
- Build and maintain glyph atlas textures via Core Text CTFont glyph rasterization
- Construct per-frame vertex buffers for visible text lines, selection highlights, and cursor
- Submit Metal render command buffers within TimelineView frame callback at display refresh rate
- Handle glyph cache eviction and atlas growth for large character sets (CJK, emoji)
- Provide minimap rendering as downscaled text overview via separate Metal render pass
- **Interfaces:**
- class MetalRenderingEngine
- func render(viewport: EditorViewport, content: AttributedString, selections: [TextRange], cursor: TextPosition)
- func invalidateGlyphCache(for font: NSFont)
- func resize(to size: CGSize)
- var metalLayer: CAMetalLayer { get }
- **Dependencies:**
- ForgeEditorEngine

### SyntaxHighlighter
- **Responsibilities:**
- Parse source files into syntax tokens using tree-sitter grammars bundled as SPM resources
- Incrementally re-parse on text edits using tree-sitter edit API for sub-millisecond updates
- Map syntax token types to theme colors and font traits, producing AttributedString attributes
- Support language detection from file extension and shebang line
- Provide bracket matching and indent guide information derived from parse tree
- **Interfaces:**
- actor SyntaxHighlighter
- func highlight(_ text: String, language: Language) async -> [SyntaxToken]
- func applyEdit(_ edit: TextEdit, to tree: SyntaxTree) async -> [SyntaxToken]
- func detectLanguage(for url: URL) -> Language

### SemanticIndexer
- **Responsibilities:**
- Build semantic embeddings for source files using CoreML model inference on the Neural Engine
- Tokenize source code symbols via NaturalLanguage NLTokenizer with .word unit
- Store and query embeddings in SwiftData SemanticIndex schema via background ModelContext
- Process file changes incrementally — index only modified files based on content hash comparison
- Support semantic search queries returning ranked file/symbol matches by cosine similarity
- **Interfaces:**
- actor SemanticIndexer
- func buildIndex(for workspace: URL) async throws
- func updateIndex(for changedFiles: [FileChangeEvent]) async throws
- func query(_ text: String, limit: Int) async throws -> [SemanticMatch]
- var indexStatus: IndexStatus { get }
- nonisolated var statusStream: AsyncStream<IndexStatus> { get }
- **Dependencies:**
- FileWatcher
- PersistenceManager

### LSPCoordinator
- **Responsibilities:**
- Manage lifecycle of external language server processes as child Tasks within a TaskGroup
- Serialize/deserialize JSON-RPC 2.0 messages over Process stdin/stdout AsyncBytes streams
- Route LSP responses and notifications to the correct requesting editor buffer
- Provide completions, diagnostics, hover info, go-to-definition, and symbol search to editor layer
- Handle server crash detection and automatic restart with exponential backoff
- **Interfaces:**
- actor LSPCoordinator
- func start(serverPath: String, language: Language, rootURI: URL) async throws
- func requestCompletion(at position: TextPosition, in document: URL) async throws -> [CompletionItem]
- func requestDefinition(at position: TextPosition, in document: URL) async throws -> Location?
- func requestHover(at position: TextPosition, in document: URL) async throws -> HoverInfo?
- func didOpen(document: URL, content: String, language: Language) async
- func didChange(document: URL, changes: [TextEdit]) async
- func shutdown() async

### FileWatcher
- **Responsibilities:**
- Monitor workspace directory tree for file system changes via FSEvents API
- Emit debounced FileChangeEvent values through an AsyncStream (200ms coalesce window)
- Detect file creation, modification, deletion, and rename events
- Respect .gitignore and .forgeignore patterns to skip irrelevant directories (node_modules, .git, build)
- Provide initial directory enumeration on workspace open for file tree construction
- **Interfaces:**
- actor FileWatcher
- func watch(directory: URL) async throws
- func stop()
- nonisolated var events: AsyncStream<FileChangeEvent> { get }
- func enumerateDirectory(_ url: URL) async throws -> FileTreeNode

### PersistenceManager
- **Responsibilities:**
- Configure and own the SwiftData ModelContainer with all three schema domains
- Provide background ModelContext instances for off-main-actor writes
- Save and restore WorkspaceState on workspace open/close and periodic autosave
- Manage SemanticIndex CRUD operations for the indexer service
- Handle schema migration via VersionedSchema and SchemaMigrationPlan
- Optionally sync EditorPreferences via CloudKit-enabled ModelConfiguration
- **Interfaces:**
- actor PersistenceManager
- var modelContainer: ModelContainer { get }
- func saveWorkspaceState(_ state: WorkspaceState) async throws
- func loadWorkspaceState(for url: URL) async throws -> WorkspaceState?
- func saveSemanticEntries(_ entries: [SemanticEntry]) async throws
- func fetchSemanticEntries(matching hashes: [String]) async throws -> [SemanticEntry]
- func deleteSemanticEntries(for paths: [String]) async throws
- func savePreferences(_ prefs: EditorPreferences) async throws
- func loadPreferences() async throws -> EditorPreferences

### CommandPalette
- **Responsibilities:**
- Present searchable command list as ZStack overlay with matched geometry transitions
- Fuzzy-match user input against registered commands, recent files, and semantic search results
- Execute selected command actions through a CommandRegistry pattern
- Animate appearance/dismissal with PhaseAnimator spring animations
- Support keyboard-driven navigation (arrow keys, enter, escape) via .onKeyPress
- **Interfaces:**
- @Observable class CommandPaletteModel
- var isPresented: Bool { get set }
- var query: String { get set }
- var results: [CommandPaletteItem] { get }
- func execute(_ item: CommandPaletteItem) async
- func register(_ command: ForgeCommand)
- **Dependencies:**
- WorkspaceManager
- SemanticIndexer
- LSPCoordinator

## 🗃 Data Model Notes
- WorkspaceState (@Model): id: UUID, workspacePath: String (indexed, unique), openTabs: [OpenDocument] (cascade delete), sidebarWidth: Double, activeDocumentID: UUID?, windowFrame: CodableRect, lastOpenedDate: Date. Persisted on close and every 30s autosave.

- OpenDocument (@Model): id: UUID, filePath: String, cursorLine: Int, cursorColumn: Int, scrollOffset: Double, isPinned: Bool, openedAt: Date. Belongs to WorkspaceState via @Relationship(deleteRule: .cascade) inverse.

- SemanticEntry (@Model): id: UUID, filePath: String (indexed), contentHash: String (indexed), embedding: Data (serialized [Float] vector), symbols: [String] (encoded as JSON Data), lastIndexedDate: Date. Content hash is SHA256 of file contents for change detection.

- EditorPreferences (@Model): id: UUID, category: String (indexed, unique — values: 'theme', 'keybindings', 'editor', 'fonts'), jsonPayload: Data (flexible JSON storage for each category), lastModifiedDate: Date. Singleton per category. CloudKit-synced via separate ModelConfiguration.

- All Date fields use Date type (Swift Foundation), stored as Double (timeIntervalSinceReferenceDate) in SQLite by SwiftData.

- CodableRect is a Codable struct wrapping CGRect for SwiftData compatibility: {x: Double, y: Double, width: Double, height: Double}.

- Embedding vectors are stored as Data (binary [Float] array) rather than a separate vector database — cosine similarity computed in-memory after fetch. Acceptable for codebases up to ~100K files with 256-dimensional embeddings (~100MB index).

- File paths are stored as POSIX strings relative to workspace root where possible, absolute only for workspace root itself. Enables workspace relocation without index rebuild.

- No cross-domain @Relationship links between WorkspaceState, SemanticEntry, and EditorPreferences. Domains are isolated intentionally for independent background processing and migration.

## 🔐 Validation & Security
- App Sandbox entitlement enabled: com.apple.security.app-sandbox = true. File access granted via NSOpenPanel user-initiated security-scoped bookmarks stored in UserDefaults for workspace persistence across launches.
- Hardened Runtime enabled: com.apple.security.cs.allow-jit disabled, com.apple.security.cs.allow-unsigned-executable-memory disabled. Language server child processes launched within sandbox via com.apple.security.temporary-exception.mach-lookup for Process() API.
- All file paths validated against sandbox security-scoped bookmark before access. Reject path traversal attempts (.. components) outside workspace root.
- Language server binary paths validated: must exist, must be executable, must not be a symlink outside /usr/local or ~/.local. User-configurable paths stored in EditorPreferences and validated on each launch.
- SwiftData ModelContainer uses default encryption-at-rest via macOS FileVault. No additional application-level encryption for local index data.
- No network access entitlement required. com.apple.security.network.client is NOT included — enforces the zero-network-call guarantee. If CloudKit sync is enabled for preferences, the com.apple.security.network.client entitlement is added only to that build variant.
- CoreML model files (.mlmodelc) are bundled in the app signature and verified by Gatekeeper. No runtime model downloading.
- Input validation on editor buffer: reject single paste operations exceeding 10MB, reject files exceeding 100MB from opening in the editor (offer hex view fallback).
- JSON-RPC messages from language servers validated against size limit (16MB per message) and well-formedness before deserialization to prevent memory exhaustion from malicious or buggy servers.
- FSEvents watcher rejects symlink cycles (max 10 levels) and skips known dangerous directories (.git/objects, node_modules/.cache) by default.

## 🧯 Error Handling Strategy
Swift structured error handling with typed errors per module. Each actor service defines a module-specific error enum conforming to LocalizedError (e.g., LSPError, IndexerError, PersistenceError, RenderingError). Errors propagate via async throws through the actor call chain. Non-recoverable errors (GPU device loss, ModelContainer creation failure) surface as user-facing alerts via an @Observable ErrorPresenter model injected into the SwiftUI environment. Recoverable errors (LSP timeout, single file index failure, save conflict) are logged via os.Logger with appropriate log levels and retried where idempotent. Task cancellation (CancellationError) is always propagated cleanly — every long-running Task checks Task.isCancelled or uses withTaskCancellationHandler. Crash-level faults in actor-isolated services are contained by actor isolation boundaries; the faulting subsystem is restarted while the editor remains responsive. An ErrorRecoveryCoordinator actor tracks failure counts per subsystem and escalates repeated failures (3+ in 60 seconds) from silent retry to user notification.

## 🔭 Observability
- **Logging:** Unified Logging via os.Logger with subsystem 'com.forge.editor' and per-module categories: 'rendering', 'lsp', 'indexer', 'persistence', 'filewatcher', 'workspace'. Log levels: .debug for frame timing and cache stats (stripped in release), .info for lifecycle events (workspace open/close, index build start/complete), .error for recoverable failures, .fault for non-recoverable states. Logs viewable in Console.app filtered by subsystem. No third-party logging framework.
- **Tracing:** os.Signpost with custom intervals for all cross-module async operations. Signpost names match module boundaries: 'LSPRequest', 'IndexFile', 'SaveWorkspace', 'RenderFrame'. Compatible with Instruments for profiling. Signpost IDs correlate related operations (e.g., file change → re-index → re-highlight → re-render). No distributed tracing needed — single process.
- **Metrics:**
- Frame render time (ms) per frame via Metal GPU timestamp queries — alert if p99 exceeds 8.33ms (120fps budget)
- Keystroke-to-render latency (ms) via signpost intervals from NSEvent keyDown to MTLCommandBuffer.commit
- Semantic index build time (seconds) and file count via os.Signpost for Instruments Time Profiler
- LSP response latency (ms) per request type via os.Signpost intervals
- SwiftData save duration (ms) via os.Signpost on background ModelContext.save()
- Memory footprint (MB) via task_info mach API, logged every 60 seconds at .debug level
- File watcher event throughput (events/second) for debounce tuning

## ⚡ Performance Notes
- Metal glyph atlas uses a 2048x2048 RGBA8 texture initially, growing to 4096x4096 on demand. LRU eviction of least-used glyph pages. ASCII glyphs for the active font are pre-warmed on launch.
- Text buffer uses a gap buffer (contiguous array with gap at cursor) for O(1) insert/delete at cursor position. Rope data structure considered but gap buffer is simpler and sufficient for single-file buffers up to 100MB.
- SemanticIndexer uses TaskGroup with maxConcurrentTasks capped at ProcessInfo.processInfo.activeProcessorCount to avoid oversubscription. Each file indexing task is independently cancellable.
- SwiftData queries for SemanticEntry use #Predicate with indexed contentHash field for O(log n) lookup. Batch inserts use a single background ModelContext.save() per batch of 100 entries to amortize SQLite transaction overhead.
- FileWatcher debounce window of 200ms groups rapid file saves (e.g., git checkout modifying many files) into single batch events, preventing redundant index updates and UI refreshes.
- Tree-sitter incremental parsing re-parses only the edited range of the syntax tree, typically completing in under 1ms for single-character edits. Full reparse required only on file open.
- Main actor work is minimized: rendering computation happens on the render thread, SwiftData saves on background contexts, LSP I/O on dedicated Tasks. Only view state updates and user input handling run on MainActor.
- CoreML inference specifies MLComputeUnits.all to prefer Neural Engine when available, falling back to GPU, then CPU. Neural Engine inference for a single file embedding (~256 tokens) targets under 5ms.
- Cold launch optimized by deferring semantic index load until after first frame render. Workspace state restore (tabs, sidebar) happens synchronously from SwiftData on launch; index build is backgrounded.
- ProMotion display support via TimelineView(.animation) which automatically matches the display refresh rate. On 60Hz displays, the frame budget relaxes to 16.67ms.

## 🧪 Testing Strategy
### Unit
- EditorBuffer: insert, delete, undo, redo operations on gap buffer with verification of content and cursor position after each operation. Test multi-cursor edits. Test paste size validation (reject >10MB).
- SyntaxHighlighter: verify token spans for known Swift, Python, TypeScript source snippets. Test incremental re-parse after single character edit produces correct diff. Test language detection from file extension and shebang.
- SemanticIndexer: mock CoreML model returning fixed embeddings, verify cosine similarity ranking produces correct ordering. Test content hash change detection triggers re-index. Test cancellation mid-indexing releases resources.
- LSPCoordinator: mock Process stdin/stdout with canned JSON-RPC responses. Verify correct serialization of initialize, completion, definition requests. Test timeout handling and restart logic. Test shutdown propagation.
- FileWatcher: use temporary directory with programmatic file creation/deletion. Verify event debouncing coalesces rapid changes. Test .gitignore pattern filtering. Test symlink cycle detection at 10 levels.
- PersistenceManager: in-memory ModelConfiguration for test isolation. Verify WorkspaceState round-trip save/load. Test schema migration plan with VersionedSchema transitions. Test concurrent background saves do not deadlock.
- CommandPalette: verify fuzzy matching algorithm ranks exact prefix matches above substring matches. Test keyboard navigation state transitions. Test command registration and execution.
- ErrorRecoveryCoordinator: verify failure count tracking per subsystem, escalation after 3 failures in 60 seconds, and count reset after recovery window.
### Integration
- WorkspaceManager + FileWatcher + SemanticIndexer: open a test workspace directory, create/modify/delete files, verify file tree updates, index rebuilds, and state consistency across the pipeline.
- EditorBuffer + SyntaxHighlighter + MetalRenderingEngine: open a source file, type characters, verify attributed content updates flow from buffer through highlighter to render viewport without frame drops (mock Metal layer).
- LSPCoordinator + EditorBuffer: start a real language server (sourcekit-lsp for Swift), open a file, request completions, verify results appear in editor state. Test server crash and automatic restart.
- PersistenceManager + WorkspaceManager: open workspace, modify tabs and sidebar, close workspace, reopen, verify state restored identically from SwiftData.
- FileWatcher + PersistenceManager: verify that file changes trigger index updates that persist correctly to SwiftData and survive app restart.
- CommandPalette + SemanticIndexer: verify semantic search results appear in command palette results alongside file matches and registered commands.
### E2E
- Cold launch to editable state: launch app, open a 10K-line Swift workspace, verify editor is interactive within 2 seconds on M1 hardware. Measure via XCTest metrics.
- Full editing session: open workspace, navigate file tree, open 5 files in tabs, edit code, trigger completions via LSP, use go-to-definition, save all files, close and reopen workspace, verify state restored.
- Semantic search workflow: open large workspace (50K+ lines), wait for index build, use command palette semantic search, verify relevant results returned within 200ms.
- Performance stress test: open 100 tabs, rapidly switch between them, verify no frame drops below 60fps and memory stays under 500MB. Profile with Instruments.
- Offline operation: disable network (Flight mode equivalent), verify all features function identically — editing, syntax highlighting, LSP (local server), semantic search, workspace persistence.
- Graceful degradation: kill language server process externally during active editing session, verify editor remains responsive, LSP features degrade to 'unavailable' state, server auto-restarts within 10 seconds.

## 🚀 Rollout Plan
- Phase 0 — Project Scaffold (Week 1): Initialize SwiftPM package with target structure: ForgeApp, ForgeEditorEngine, ForgeRendering, ForgeLSP, ForgeIndexer, ForgePersistence, ForgeShared. Configure Package.swift with dependencies (none external initially). Set up GitHub repository, CI with GitHub Actions macOS runner, SwiftLint SPM plugin. Verify swift build and swift test pass on empty targets.

- Phase 1 — Core Editor Engine (Weeks 2-4): Implement gap buffer EditorBuffer with insert/delete/undo/redo. Build SyntaxHighlighter with tree-sitter Swift grammar. Create basic SwiftUI editor view with standard Text rendering (no Metal yet). Implement basic file open/save. Unit tests for buffer operations and syntax highlighting. Milestone: can open, edit, and save a Swift file with syntax highlighting.

- Phase 2 — Metal Rendering (Weeks 5-7): Implement MetalRenderingEngine with glyph atlas, Core Text layout, and MTLRenderCommandEncoder pipeline. Integrate with TimelineView for frame scheduling. Replace standard Text rendering with Metal path. Implement cursor rendering, selection highlighting, and scrolling. Performance target: 120fps on ProMotion displays. Milestone: smooth GPU-accelerated text editing.

- Phase 3 — Workspace & Persistence (Weeks 8-9): Implement SwiftData models (WorkspaceState, OpenDocument, EditorPreferences). Build PersistenceManager with background save. Implement WorkspaceManager with file tree and tab management. Build NavigationSplitView layout with sidebar file tree and tab bar. Implement FileWatcher with FSEvents and debouncing. Milestone: multi-file workspace with state persistence across launches.

- Phase 4 — LSP Integration (Weeks 10-12): Implement LSPCoordinator with JSON-RPC over Process pipes. Integrate sourcekit-lsp for Swift language support. Wire completions, diagnostics, go-to-definition, and hover into editor UI. Implement error recovery and auto-restart. Milestone: full Swift language intelligence in the editor.

- Phase 5 — Semantic Indexing (Weeks 13-15): Bundle CoreML embedding model (distilled code search model, <50MB). Implement SemanticIndexer actor with NaturalLanguage tokenization and CoreML inference. Build SwiftData SemanticEntry storage with content-hash invalidation. Implement incremental indexing via FileWatcher events. Milestone: semantic code search returns relevant results for 100K-line workspace.

- Phase 6 — Command Palette & Polish (Weeks 16-17): Build CommandPalette with fuzzy matching, semantic search integration, and matchedGeometryEffect animations. Implement PhaseAnimator transitions for sidebar and palette. Apply .ultraThinMaterial and NSWindow titlebar customization. Build Settings scene for preferences. Implement EditorPreferences CloudKit sync. Milestone: polished editor chrome matching the premium native design target.

- Phase 7 — Performance Validation & Beta (Weeks 18-20): Profile all NFR targets with Instruments (Metal System Trace, Time Profiler, Allocations). Optimize to hit: <2s cold launch, <8ms keystroke latency, 120fps rendering, <500MB memory for 50K files, <30s index build for 100K lines. Code sign with Developer ID, notarize. Create DMG installer. Begin TestFlight / direct download beta. Milestone: beta-quality release meeting all NFR thresholds.

## ❓ Open Questions
- Which CoreML model architecture to use for code embeddings — fine-tuned distilbert-base, a custom encoder trained on code search datasets, or Apple's built-in NLEmbedding (limited to natural language, may underperform on code)?
- Tree-sitter grammar bundling strategy — bundle pre-compiled .dylib grammars as SPM binary targets or compile grammars from source as part of the build? Binary targets are faster but harder to update; source compilation adds build time.
- Gap buffer vs. rope for EditorBuffer — gap buffer is simpler and faster for typical editing, but rope handles very large files (>10MB) more efficiently for split/join operations. Decision depends on whether large file support is a launch priority.
- Mac App Store distribution constraints — sandbox restrictions may limit language server process launching (com.apple.security.temporary-exception.mach-lookup). Need to verify whether LSP subprocess spawning is feasible under App Store review or if direct download is the only viable distribution channel.
- CloudKit sync scope — currently scoped to EditorPreferences only. Should workspace bookmarks (recently opened projects) also sync across devices? This affects the CloudKit schema and requires careful conflict resolution for workspace paths that differ per machine.
- Minimap rendering approach — render as downscaled Metal texture of full document (memory intensive for large files) or generate abstract representation with colored blocks per syntax token type (less accurate but constant memory)?
- Plugin/extension API timeline — the ARD defers this, but the internal Swift protocol boundaries between modules are designed to support future plugin exposure. When should the protocol stability contract begin?