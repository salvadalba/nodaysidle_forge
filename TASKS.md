# Tasks Plan — Forge — macOS-Native Code Editor

## 📌 Global Assumptions
- macOS 15+ (Sequoia) on Apple Silicon is the only supported platform at launch
- No network entitlement is required; all features operate fully offline except optional CloudKit preferences sync
- sourcekit-lsp is the primary language server for Swift; additional language servers are user-configured
- Tree-sitter grammars are bundled as pre-compiled SPM binary targets for launch
- Gap buffer is used for EditorBuffer; rope data structure is deferred unless large file support becomes a launch priority
- CoreML embedding model is a pre-trained sub-50MB model bundled in the app; no runtime model downloading

## ⚠️ Risks
- **Mac App Store sandbox may block LSP subprocess spawning:** com.apple.security.temporary-exception.mach-lookup may not pass App Store review, forcing direct-download-only distribution.
- **CoreML code embedding quality may be insufficient:** Available sub-50MB models may underperform on code-specific semantic search compared to larger cloud models, degrading the semantic search value proposition.
- **Metal glyph atlas memory pressure on CJK-heavy codebases:** CJK character sets can exhaust the 4096x4096 atlas limit, causing frequent eviction and potential frame drops.
- **Tree-sitter grammar bundling increases app size:** Pre-compiled binary grammars for multiple languages may push app bundle size beyond user expectations for a code editor.
- **Gap buffer performance degrades on files exceeding 10MB:** Gap buffer O(n) move cost on cursor jumps across large files may cause noticeable latency, pushing toward rope implementation earlier than planned.

## 🧩 Epics
## Project Scaffold & Core Editor Engine
**Goal:** Initialize SwiftPM project structure and build the fundamental text editing engine with gap buffer, syntax highlighting, and basic SwiftUI editor view.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Initialize SwiftPM Package with Target Structure (2d)

Create Package.swift with targets: ForgeApp, ForgeEditorEngine, ForgeRendering, ForgeLSP, ForgeIndexer, ForgePersistence, ForgeShared. Configure macOS 15+ deployment target, SwiftLint plugin, and GitHub Actions CI.

**Acceptance Criteria**
- swift build succeeds with all empty targets
- swift test runs and passes on macOS 15+ runner
- SwiftLint SPM plugin configured and passing on empty sources

**Dependencies**
_None_

### ✅ Implement Gap Buffer EditorBuffer (4d)

Build @Observable EditorBuffer class with gap-buffer data structure supporting O(1) insert/delete at cursor, multi-cursor state, selection ranges, undo/redo stack, and 10MB paste validation.

**Acceptance Criteria**
- Unit tests pass for insert, delete, undo, redo with content and cursor verification
- Multi-cursor edits apply correctly across all cursor positions
- Paste operations exceeding 10MB are rejected with appropriate error

**Dependencies**
- Initialize SwiftPM Package with Target Structure

### ✅ Build Tree-Sitter SyntaxHighlighter Actor (4d)

Implement actor SyntaxHighlighter using tree-sitter with bundled Swift grammar. Support incremental re-parse on edits, language detection from file extension/shebang, and AttributedString token output.

**Acceptance Criteria**
- Token spans for known Swift snippets match expected highlighting
- Incremental re-parse after single char edit completes under 1ms
- Language detection resolves correctly for .swift, .py, .ts extensions

**Dependencies**
- Initialize SwiftPM Package with Target Structure

### ✅ Create Basic SwiftUI Editor View with File Open/Save (3d)

Build the initial editor view using standard SwiftUI Text rendering, wired to EditorBuffer. Implement file open via NSOpenPanel with security-scoped bookmarks and file save via async write.

**Acceptance Criteria**
- Can open a Swift file and display its contents with syntax highlighting
- Edits reflect in the buffer and can be saved back to disk
- Security-scoped bookmarks persist across app launches
- Files exceeding 100MB are rejected with hex view fallback offer

**Dependencies**
- Implement Gap Buffer EditorBuffer
- Build Tree-Sitter SyntaxHighlighter Actor

### ✅ Define Shared Types and Error Enums (2d)

Create ForgeShared target with TextPosition, TextRange, FileChangeEvent, SyntaxToken, ForgeCommand types and per-module error enums (LSPError, IndexerError, PersistenceError, RenderingError) conforming to LocalizedError.

**Acceptance Criteria**
- All shared types are Codable and Sendable
- Error enums provide localized descriptions for user-facing display
- Types compile and are importable from all module targets

**Dependencies**
- Initialize SwiftPM Package with Target Structure

## Metal Rendering Pipeline
**Goal:** Replace standard SwiftUI text rendering with GPU-accelerated Metal pipeline achieving 120fps on ProMotion displays with glyph atlas, selection highlights, and cursor rendering.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Build Metal Glyph Atlas with Core Text Rasterization (4d)

Implement glyph atlas as 2048x2048 RGBA8 MTLTexture with Core Text CTFont/CTLine rasterization, LRU eviction, growth to 4096x4096, and ASCII pre-warming on launch.

**Acceptance Criteria**
- ASCII glyphs for the active font are pre-warmed into atlas on init
- LRU eviction correctly frees least-used glyph pages when atlas is full
- Atlas grows from 2048 to 4096 when glyph demand exceeds initial capacity

**Dependencies**
- Define Shared Types and Error Enums

### ✅ Implement Metal Render Command Pipeline (5d)

Build MetalRenderingEngine with MTLRenderCommandEncoder draw calls for text layer, selection highlight layer, and cursor blink layer. Integrate with TimelineView(.animation) for ProMotion frame scheduling.

**Acceptance Criteria**
- Render pipeline submits frames at display refresh rate via TimelineView
- Selection highlights and cursor render correctly over text glyphs
- Frame drops are logged and pipeline state resets gracefully on GPU errors

**Dependencies**
- Build Metal Glyph Atlas with Core Text Rasterization

### ✅ Integrate Metal Renderer with EditorBuffer (3d)

Wire ForgeEditorEngine's attributedContent and cursor/selection state into MetalRenderingEngine viewport. Replace SwiftUI Text path with CAMetalLayer rendering. Implement smooth scrolling.

**Acceptance Criteria**
- Typing characters renders via Metal path with no visible latency
- Scrolling through a 10K-line file maintains 120fps on ProMotion
- Cursor blinks correctly and selection highlights track mouse drag

**Dependencies**
- Implement Metal Render Command Pipeline
- Implement Gap Buffer EditorBuffer

### ✅ Implement Minimap Render Pass (3d)

Add a separate Metal render pass producing a downscaled overview of the full document, rendered alongside the main editor viewport with scroll position indicator.

**Acceptance Criteria**
- Minimap renders syntax-colored representation of full document
- Clicking minimap scrolls editor to corresponding position
- Minimap updates incrementally on edits without full re-render

**Dependencies**
- Integrate Metal Renderer with EditorBuffer

### ✅ Add Core Text Fallback Rendering Path (2d)

Implement software fallback using standard SwiftUI Text views when MTLDevice creation fails. Log GPU unavailable and surface degraded mode in status bar.

**Acceptance Criteria**
- Editor remains functional when Metal device is unavailable
- Fallback is automatically engaged on MTLDevice creation failure
- Status bar shows degraded rendering mode indicator

**Dependencies**
- Integrate Metal Renderer with EditorBuffer

## Workspace, Persistence & File Watching
**Goal:** Build SwiftData persistence layer, FileWatcher with FSEvents, WorkspaceManager with file tree and tab management, and NavigationSplitView layout with state restoration.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement SwiftData Models and PersistenceManager (4d)

Define WorkspaceState, OpenDocument, SemanticEntry, EditorPreferences @Model classes with VersionedSchema. Build PersistenceManager actor with background ModelContext saves, 30s autosave, and schema migration plan.

**Acceptance Criteria**
- WorkspaceState round-trip save/load preserves all fields including CodableRect
- Background saves execute off MainActor without deadlocks
- Schema migration plan handles version transitions without data loss

**Dependencies**
- Define Shared Types and Error Enums

### ✅ Build FileWatcher with FSEvents and Debouncing (3d)

Implement FileWatcher actor using FSEvents API with 200ms debounce coalescing, .gitignore/.forgeignore filtering, symlink cycle detection (max 10 levels), and initial directory enumeration.

**Acceptance Criteria**
- Rapid file changes within 200ms window are coalesced into single batch event
- Paths matching .gitignore patterns are excluded from events
- Symlink cycles beyond 10 levels are detected and skipped with warning log

**Dependencies**
- Define Shared Types and Error Enums

### ✅ Implement WorkspaceManager with File Tree and Tabs (4d)

Build @Observable WorkspaceManager coordinating workspace lifecycle: file tree model from FileWatcher enumeration, TabGroup with open/close/reorder/pin and undo support, active document tracking.

**Acceptance Criteria**
- File tree reflects filesystem structure and updates on FileWatcher events
- Tabs can be opened, closed, reordered, and pinned with undo support
- Active document switches correctly when tabs are selected or closed

**Dependencies**
- Implement SwiftData Models and PersistenceManager
- Build FileWatcher with FSEvents and Debouncing

### ✅ Build NavigationSplitView Layout with Sidebar and Tab Bar (3d)

Create the main editor chrome using NavigationSplitView with sidebar file tree, tab bar, and editor content area. Apply .ultraThinMaterial and NSWindow titlebar customization via NSApplicationDelegate.

**Acceptance Criteria**
- Sidebar shows file tree with expand/collapse and file icons
- Tab bar displays open documents with close buttons and pin indicators
- NSWindow uses custom titlebar styling with .ultraThinMaterial background

**Dependencies**
- Implement WorkspaceManager with File Tree and Tabs

### ✅ Implement Workspace State Restoration (3d)

Save WorkspaceState on workspace close, app background, and 30s timer. Restore open tabs, sidebar width, active document, and window frame on workspace reopen. Store security-scoped bookmarks for workspace paths.

**Acceptance Criteria**
- Closing and reopening workspace restores all tabs and active document
- Window frame and sidebar width are preserved across launches
- Security-scoped bookmarks grant file access without re-prompting user

**Dependencies**
- Build NavigationSplitView Layout with Sidebar and Tab Bar
- Implement SwiftData Models and PersistenceManager

## LSP Integration
**Goal:** Integrate external language servers via JSON-RPC 2.0 over process pipes, providing completions, diagnostics, go-to-definition, and hover with automatic crash recovery.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Implement LSPCoordinator JSON-RPC Transport (4d)

Build actor LSPCoordinator managing child Process lifecycle, JSON-RPC 2.0 serialization/deserialization over stdin/stdout AsyncBytes, request/response correlation by ID, and 16MB message size validation.

**Acceptance Criteria**
- JSON-RPC requests serialize correctly with id, method, and params fields
- Responses are correlated to pending requests by ID within 10s timeout
- Messages exceeding 16MB are rejected before deserialization

**Dependencies**
- Define Shared Types and Error Enums

### ✅ Wire LSP Completions and Diagnostics to Editor UI (4d)

Integrate textDocument/completion and textDocument/publishDiagnostics into the editor. Show completion popup on trigger characters, inline diagnostics with severity icons, and didOpen/didChange notifications.

**Acceptance Criteria**
- Completion popup appears with ranked suggestions on typing trigger characters
- Diagnostics display inline with error/warning/info severity indicators
- didOpen and didChange notifications are sent to server on file open and edit

**Dependencies**
- Implement LSPCoordinator JSON-RPC Transport
- Implement Gap Buffer EditorBuffer

### ✅ Implement Go-to-Definition and Hover Info (3d)

Wire textDocument/definition and textDocument/hover LSP methods. Cmd+click navigates to definition, hover tooltip shows type info and documentation.

**Acceptance Criteria**
- Cmd+click on a symbol navigates to its definition file and line
- Hover tooltip displays type signature and doc comments from server
- Unsupported method responses gracefully disable the feature in UI

**Dependencies**
- Wire LSP Completions and Diagnostics to Editor UI

### ✅ Build LSP Crash Recovery with Exponential Backoff (2d)

Detect language server process termination via Process.terminationHandler. Implement automatic restart up to 3 times with 1s/2s/4s backoff. Surface status in the editor status bar.

**Acceptance Criteria**
- Server crash triggers automatic restart within backoff schedule
- After 3 failed restarts, user is notified and LSP features show unavailable
- Status bar reflects current LSP state: running, restarting, or unavailable

**Dependencies**
- Implement LSPCoordinator JSON-RPC Transport

### ✅ Validate LSP Server Binary Security (2d)

Validate language server paths: must exist, be executable, not symlink outside /usr/local or ~/.local. Support user-configurable paths stored in EditorPreferences with validation on each launch.

**Acceptance Criteria**
- Invalid server paths are rejected with descriptive error message
- Symlinks outside allowed directories are blocked
- User-configured paths in EditorPreferences are re-validated on each launch

**Dependencies**
- Implement LSPCoordinator JSON-RPC Transport
- Implement SwiftData Models and PersistenceManager

## Semantic Indexing
**Goal:** Build on-device semantic code search using CoreML embeddings, NaturalLanguage tokenization, and SwiftData storage with incremental indexing driven by file watcher events.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Bundle CoreML Embedding Model and Inference Pipeline (3d)

Bundle a sub-50MB CoreML code embedding model as SPM resource. Implement MLModel.prediction with MLComputeUnits.all for Neural Engine preference. Target <5ms per file embedding (256 dimensions).

**Acceptance Criteria**
- CoreML model loads from app bundle and produces 256-dimensional embeddings
- Inference prefers Neural Engine, falling back to GPU then CPU
- Single file embedding completes in under 5ms on Apple Silicon

**Dependencies**
- Define Shared Types and Error Enums

### ✅ Implement SemanticIndexer Actor with Cosine Similarity (4d)

Build actor SemanticIndexer: tokenize source via NLTokenizer(.word), embed via CoreML, store in SwiftData SemanticEntry with content-hash invalidation. Query by cosine similarity with 0.3 threshold.

**Acceptance Criteria**
- Query returns SemanticMatch results sorted by descending cosine similarity
- Results below 0.3 similarity threshold are excluded
- Content hash comparison correctly identifies changed files for re-indexing

**Dependencies**
- Bundle CoreML Embedding Model and Inference Pipeline
- Implement SwiftData Models and PersistenceManager

### ✅ Wire Incremental Indexing to FileWatcher Events (3d)

Subscribe SemanticIndexer to FileWatcher.events AsyncStream. Re-index only modified files detected by content hash change. Use TaskGroup with maxConcurrentTasks capped at active processor count.

**Acceptance Criteria**
- File modifications trigger re-indexing of only changed files
- Concurrent indexing tasks do not exceed active processor count
- Task cancellation during indexing releases MLModel resources cleanly

**Dependencies**
- Implement SemanticIndexer Actor with Cosine Similarity
- Build FileWatcher with FSEvents and Debouncing

### ✅ Build Index Status Reporting and Progress UI (2d)

Expose IndexStatus via AsyncStream from SemanticIndexer. Show index build progress in status bar with file count and estimated completion. Handle empty-index state gracefully in query results.

**Acceptance Criteria**
- Status bar shows indexing progress with file count during builds
- Queries during indexing return partial results with IndexStatus.building metadata
- Completed index build transitions status to idle with total file count

**Dependencies**
- Wire Incremental Indexing to FileWatcher Events

## Command Palette, Polish & Beta Release
**Goal:** Build animated command palette with semantic search, apply premium UI polish with materials and transitions, validate all performance targets, and ship notarized beta.

### User Stories
_None_

### Acceptance Criteria
_None_

### ✅ Build Command Palette with Fuzzy Matching (3d)

Implement CommandPaletteModel with ZStack overlay, fuzzy matching against registered commands and recent files, keyboard navigation via .onKeyPress (arrows, enter, escape), and CommandRegistry pattern.

**Acceptance Criteria**
- Fuzzy matching ranks exact prefix matches above substring matches
- Keyboard navigation cycles through results and executes on enter
- Escape dismisses palette and Cmd+Shift+P toggles it

**Dependencies**
- Implement WorkspaceManager with File Tree and Tabs

### ✅ Integrate Semantic Search into Command Palette (2d)

Wire SemanticIndexer.query into command palette results alongside file matches and registered commands. Show semantic matches with file path, symbol name, and relevance score.

**Acceptance Criteria**
- Semantic search results appear in palette within 200ms for 100K-line workspace
- Results show file path, symbol name, and snippet preview
- Selecting a semantic match opens the file at the matched line range

**Dependencies**
- Build Command Palette with Fuzzy Matching
- Implement SemanticIndexer Actor with Cosine Similarity

### ✅ Apply Premium UI Polish and Animations (3d)

Add matchedGeometryEffect transitions for command palette and tab switching, PhaseAnimator spring animations for sidebar, .ultraThinMaterial backgrounds, and NSWindow appearance customization.

**Acceptance Criteria**
- Command palette animates in/out with matched geometry transitions
- Sidebar expand/collapse uses spring animation via PhaseAnimator
- Tab switching feels fluid with smooth crossfade transitions

**Dependencies**
- Build Command Palette with Fuzzy Matching
- Build NavigationSplitView Layout with Sidebar and Tab Bar

### ✅ Build Settings Scene and Preferences CloudKit Sync (3d)

Implement Settings scene for theme, keybindings, editor, and font preferences. Store in EditorPreferences SwiftData model. Optional CloudKit sync via separate ModelConfiguration with network entitlement.

**Acceptance Criteria**
- Settings UI allows configuring theme, font, and editor preferences
- Preferences persist locally via SwiftData singleton per category
- CloudKit sync works when enabled and degrades gracefully when offline

**Dependencies**
- Implement SwiftData Models and PersistenceManager

### ✅ Performance Validation, Code Signing & Beta Ship (5d)

Profile all NFR targets with Instruments. Optimize to hit: <2s cold launch, <8ms keystroke latency, 120fps rendering, <500MB memory. Code sign with Developer ID, notarize, create DMG installer.

**Acceptance Criteria**
- Cold launch to interactive editor under 2s on M1 verified via XCTest metrics
- Keystroke-to-render latency under 8ms confirmed via Instruments signpost
- App is signed, notarized, and installs from DMG without Gatekeeper warnings

**Dependencies**
- Integrate Semantic Search into Command Palette
- Apply Premium UI Polish and Animations
- Build Settings Scene and Preferences CloudKit Sync

## ❓ Open Questions
- Which CoreML model architecture for code embeddings — fine-tuned distilbert, custom encoder, or Apple's NLEmbedding?
- Bundle tree-sitter grammars as pre-compiled .dylib binary targets or compile from source during build?
- Is LSP subprocess spawning feasible under Mac App Store sandbox review, or is direct download the only distribution path?
- Should CloudKit sync scope extend beyond preferences to include recent workspace bookmarks?
- Minimap rendering: downscaled Metal texture of full document or abstract colored-block representation?