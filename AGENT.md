# Agent Prompts — Forge

## Global Rules

### Do
- Use Swift 6 strict concurrency with @Sendable and actor isolation throughout
- Target macOS 15+ (Sequoia) on Apple Silicon exclusively via SwiftPM
- Use @Observable macro from Observation framework instead of ObservableObject
- Make all shared types Codable and Sendable in ForgeShared target
- Use structured concurrency (TaskGroup, async let) for all parallel work

### Don't
- Do not introduce any Electron, web, or cross-platform UI frameworks
- Do not use Combine or ObservableObject — use Observation framework only
- Do not add any network entitlements or server dependencies — local-first only
- Do not use Xcode project files — SwiftPM Package.swift is the sole build system
- Do not use rope data structure — gap buffer is the launch implementation

---

## Task Prompts
### Task 1: Project Scaffold & Core Editor Engine

**Role:** Expert Swift 6 Systems Engineer
**Goal:** Scaffold SwiftPM package and implement gap buffer editor with Tree-Sitter highlighting

**Context**
Initialize the SwiftPM multi-target project and build the fundamental text editing engine. This includes the gap buffer EditorBuffer, Tree-Sitter syntax highlighter, shared types, and a basic SwiftUI editor view with file open/save. macOS 15+ deployment target. All types in ForgeShared must be Codable and Sendable. Use @Observable for EditorBuffer, actor for SyntaxHighlighter.

**Files to Create**
- Package.swift
- Sources/ForgeApp/ForgeApp.swift
- Sources/ForgeShared/Types.swift
- Sources/ForgeShared/Errors.swift
- Sources/ForgeEditorEngine/EditorBuffer.swift
- Sources/ForgeEditorEngine/SyntaxHighlighter.swift
- Sources/ForgeEditorEngine/EditorView.swift
- Tests/ForgeEditorEngineTests/EditorBufferTests.swift

**Files to Modify**
_None_

**Steps**
1. Create Package.swift with targets: ForgeApp (executableTarget), ForgeEditorEngine, ForgeRendering, ForgeLSP, ForgeIndexer, ForgePersistence, ForgeShared. Set platform to .macOS(.v15). Add swift-tree-sitter SPM dependency.
2. In ForgeShared/Types.swift define Codable & Sendable structs: TextPosition(line:Int,column:Int), TextRange(start:TextPosition,end:TextPosition), SyntaxToken(range:TextRange,kind:String), FileChangeEvent(path:URL,kind:ChangeKind). In Errors.swift define LocalizedError enums: LSPError, IndexerError, PersistenceError, RenderingError.
3. Implement @Observable class EditorBuffer in ForgeEditorEngine with gap-buffer backing storage (ContiguousArray<UInt8>), O(1) insert/delete at cursor, multi-cursor state [TextPosition], selection ranges [TextRange], undo/redo stack (max 500 entries), and 10MB paste size validation.
4. Implement actor SyntaxHighlighter using swift-tree-sitter with bundled Swift grammar. Support incremental reparse via tree-sitter edit API, language detection from file extension, and output as [SyntaxToken]. Reparse after single-char edit must complete under 1ms.
5. Build EditorView as SwiftUI View wired to EditorBuffer. Implement file open via NSOpenPanel with security-scoped bookmarks persisted in UserDefaults, async file save, and reject files >100MB. Write EditorBufferTests covering insert, delete, undo, redo, multi-cursor, and paste rejection.

**Validation**
`swift build && swift test`

---

### Task 2: Metal Rendering Pipeline

**Role:** Expert Metal Graphics Engineer
**Goal:** Build Metal glyph atlas and GPU render pipeline for 120fps text rendering

**Context**
Replace SwiftUI text rendering with a GPU-accelerated Metal pipeline targeting 120fps on ProMotion displays. Build a glyph atlas with Core Text rasterization, a multi-layer render command pipeline (text, selection, cursor), minimap pass, and a Core Text software fallback. Use TimelineView(.animation) for frame scheduling. CAMetalLayer for the rendering surface.

**Files to Create**
- Sources/ForgeRendering/GlyphAtlas.swift
- Sources/ForgeRendering/MetalRenderingEngine.swift
- Sources/ForgeRendering/Shaders.metal
- Sources/ForgeRendering/MinimapRenderer.swift
- Sources/ForgeRendering/CoreTextFallback.swift
- Sources/ForgeRendering/MetalEditorView.swift

**Files to Modify**
- Sources/ForgeEditorEngine/EditorView.swift

**Steps**
1. Implement GlyphAtlas class managing a 2048x2048 RGBA8 MTLTexture. Rasterize glyphs via CTFont/CTLine into the atlas. Pre-warm ASCII glyphs on init. Implement LRU eviction per glyph page and automatic growth to 4096x4096 when capacity is exceeded.
2. Create Shaders.metal with vertex/fragment functions for three layers: text quads sampling glyph atlas, selection highlight rectangles with alpha blend, and cursor rectangle with blink opacity uniform. Build MetalRenderingEngine with MTLRenderCommandEncoder dispatching all three layers per frame.
3. Build MetalEditorView using NSViewRepresentable wrapping CAMetalLayer. Wire EditorBuffer.attributedContent and cursor/selection state into the viewport. Use TimelineView(.animation) to schedule frames at display refresh rate. Implement smooth scrolling with momentum.
4. Add MinimapRenderer as a separate Metal render pass producing a downscaled document overview. Render syntax-colored blocks beside the main editor. Support click-to-scroll and incremental update on edits.
5. Implement CoreTextFallback using standard SwiftUI Text views, activated automatically when MTLCreateSystemDefaultDevice() returns nil. Show degraded-mode indicator in a status bar view. Update EditorView.swift to switch between Metal and fallback paths.

**Validation**
`swift build`

---

### Task 3: Workspace Persistence & File Watching

**Role:** Expert SwiftUI & SwiftData Architect
**Goal:** Implement SwiftData persistence, FSEvents file watcher, and NavigationSplitView workspace layout

**Context**
Build the persistence layer with SwiftData models, FSEvents-based file watcher, workspace manager with file tree and tabs, and the main NavigationSplitView layout. SwiftData uses VersionedSchema for migrations. FileWatcher uses FSEvents with 200ms debounce. NSWindow gets .ultraThinMaterial titlebar customization. State restoration saves open tabs, sidebar width, and window frame on 30s timer.

**Files to Create**
- Sources/ForgePersistence/Models.swift
- Sources/ForgePersistence/PersistenceManager.swift
- Sources/ForgeApp/FileWatcher.swift
- Sources/ForgeApp/WorkspaceManager.swift
- Sources/ForgeApp/MainEditorView.swift
- Sources/ForgeApp/AppDelegate.swift
- Sources/ForgeApp/TabBarView.swift
- Sources/ForgeApp/SidebarView.swift

**Files to Modify**
- Sources/ForgeApp/ForgeApp.swift

**Steps**
1. Define SwiftData @Model classes in Models.swift: WorkspaceState (path, sidebarWidth, windowFrame as CodableRect, activeDocumentID), OpenDocument (url, isPinned, scrollPosition, cursorPosition), SemanticEntry (filePath, contentHash, embedding as [Float]), EditorPreferences (theme, font, tabWidth). Use VersionedSchema with V1.
2. Build actor PersistenceManager wrapping a background ModelContext. Implement save/fetch/delete for all models. Add 30s autosave timer via Task.sleep. Ensure all ModelContext operations run off @MainActor. Implement schema migration plan stub for future V2.
3. Implement actor FileWatcher using FSEvents C API (FSEventStreamCreate). Apply 200ms debounce via AsyncStream with continuation. Filter events against .gitignore and .forgeignore patterns. Detect symlink cycles at max 10 levels. Emit [FileChangeEvent] batches.
4. Build @Observable WorkspaceManager coordinating file tree model (recursive FileNode struct), TabGroup with open/close/reorder/pin and undo-close support, and active document tracking. Subscribe to FileWatcher.events to update file tree incrementally.
5. Create MainEditorView using NavigationSplitView with SidebarView (file tree with disclosure groups), TabBarView (horizontal scroll of open tabs with close/pin), and editor content area. In AppDelegate, customize NSWindow with .ultraThinMaterial titlebar. Implement state restoration: save WorkspaceState on close/background/30s timer, restore on launch.

**Validation**
`swift build && swift test`

---

### Task 4: LSP Integration & Semantic Indexing

**Role:** Expert Swift Concurrency & ML Engineer
**Goal:** Build LSP JSON-RPC coordinator and CoreML semantic indexer with incremental re-indexing

**Context**
Integrate external language servers via JSON-RPC 2.0 over stdin/stdout process pipes. Build LSPCoordinator actor with crash recovery. Wire completions, diagnostics, go-to-definition, and hover to editor UI. Separately, build on-device semantic search using a bundled sub-50MB CoreML embedding model, NLTokenizer, and SwiftData storage. SemanticIndexer actor uses cosine similarity with 0.3 threshold. Incremental indexing driven by FileWatcher events with TaskGroup concurrency capped at ProcessInfo.processInfo.activeProcessorCount.

**Files to Create**
- Sources/ForgeLSP/LSPCoordinator.swift
- Sources/ForgeLSP/JSONRPCTransport.swift
- Sources/ForgeLSP/LSPFeatures.swift
- Sources/ForgeIndexer/SemanticIndexer.swift
- Sources/ForgeIndexer/EmbeddingPipeline.swift
- Sources/ForgeApp/CompletionPopup.swift
- Sources/ForgeApp/DiagnosticsOverlay.swift
- Tests/ForgeLSPTests/JSONRPCTests.swift

**Files to Modify**
- Sources/ForgeEditorEngine/EditorView.swift
- Sources/ForgeApp/MainEditorView.swift

**Steps**
1. Implement JSONRPCTransport struct with Codable JSON-RPC 2.0 message types (Request, Response, Notification). Build actor LSPCoordinator managing child Process lifecycle via stdin/stdout AsyncBytes. Correlate responses by ID with 10s timeout via CheckedContinuation. Reject messages >16MB. Add crash recovery via Process.terminationHandler with 3 retries at 1s/2s/4s exponential backoff.
2. Implement LSPFeatures with methods: requestCompletion(at:), publishDiagnostics(handler:), gotoDefinition(at:), hover(at:). Wire textDocument/didOpen and textDocument/didChange notifications on file open and EditorBuffer edits. Validate LSP binary paths: must exist, be executable, no symlinks outside /usr/local or ~/.local.
3. Build CompletionPopup SwiftUI view showing ranked completions on trigger characters. Build DiagnosticsOverlay rendering inline error/warning/info markers. Wire Cmd+click for go-to-definition navigation and hover tooltip for type info. Integrate into EditorView and MainEditorView.
4. In EmbeddingPipeline, load bundled CoreML model as SPM resource. Implement prediction with MLComputeUnits.all (Neural Engine preferred). Target 256-dim output, <5ms per file. Build actor SemanticIndexer: tokenize via NLTokenizer(.word), embed via CoreML, store SemanticEntry in SwiftData with content-hash invalidation. Query by cosine similarity, 0.3 threshold.
5. Subscribe SemanticIndexer to FileWatcher.events. Re-index only files with changed content hash. Use TaskGroup with maxConcurrentTasks = ProcessInfo.processInfo.activeProcessorCount. Expose IndexStatus via AsyncStream for UI progress. Write JSONRPCTests for serialization and correlation.

**Validation**
`swift build && swift test`

---

### Task 5: Command Palette, Settings & Beta Polish

**Role:** Expert SwiftUI UX & Release Engineer
**Goal:** Build command palette, settings, premium animations, and ship notarized beta

**Context**
Build animated command palette with fuzzy matching and semantic search integration. Implement Settings scene for preferences with optional CloudKit sync. Apply premium UI polish: matchedGeometryEffect transitions for palette and tabs, PhaseAnimator spring animations for sidebar, .ultraThinMaterial backgrounds. Validate all performance targets with Instruments: <2s cold launch, <8ms keystroke latency, 120fps rendering, <500MB memory. Code sign with Developer ID and notarize for DMG distribution.

**Files to Create**
- Sources/ForgeApp/CommandPalette.swift
- Sources/ForgeApp/CommandRegistry.swift
- Sources/ForgeApp/SettingsView.swift
- Sources/ForgeApp/StatusBarView.swift
- Scripts/notarize.sh

**Files to Modify**
- Sources/ForgeApp/MainEditorView.swift
- Sources/ForgeApp/TabBarView.swift
- Sources/ForgeApp/SidebarView.swift
- Sources/ForgeApp/ForgeApp.swift

**Steps**
1. Build CommandRegistry as @Observable singleton collecting ForgeCommand entries from all modules. Implement CommandPalette as ZStack overlay with TextField, fuzzy matching (prefix > substring ranking), keyboard navigation via .onKeyPress (up/down/enter/escape), and Cmd+Shift+P toggle. Integrate SemanticIndexer.query results alongside file and command matches.
2. Create SettingsView as a Settings scene in ForgeApp.swift with TabView sections: Theme (light/dark/auto), Font (family, size, ligatures), Editor (tabWidth, insertSpaces, wordWrap), and Keybindings. Persist via EditorPreferences SwiftData model. Add optional CloudKit sync using separate ModelConfiguration with cloudKitDatabase.
3. Apply premium animations: matchedGeometryEffect with @Namespace for command palette open/close and tab switching transitions. PhaseAnimator spring animations for sidebar expand/collapse. Ensure .ultraThinMaterial is applied to sidebar, tab bar, and command palette backgrounds consistently.
4. Build StatusBarView showing: current file name, line:column position, LSP status (running/restarting/unavailable), indexing progress (file count + percentage), and rendering mode (Metal/CoreText fallback). Wire to LSPCoordinator.status, SemanticIndexer.indexStatus, and MetalRenderingEngine.isActive.
5. Create Scripts/notarize.sh performing: swift build -c release, codesign with Developer ID, productbuild or create-dmg for installer, xcrun notarytool submit with --wait. Add XCTest performance metrics for cold launch <2s and keystroke latency <8ms using measure {} blocks.

**Validation**
`swift build -c release && swift test`