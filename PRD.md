# Forge

## 🎯 Product Vision
A macOS-native code editor that combines GPU-accelerated rendering, on-device AI-powered semantic indexing, and a local-first architecture to deliver a premium, privacy-respecting development experience rivaling Zed on Apple silicon.

## ❓ Problem Statement
Existing code editors are either Electron-based with sluggish performance and high memory usage, or native but lack intelligent code understanding. Developers on macOS deserve an editor that fully exploits Apple silicon GPU rendering, on-device machine learning, and native UI frameworks to provide zero-latency editing, semantic code navigation, and a polished experience without cloud dependencies.

## 🎯 Goals
- Deliver GPU-accelerated text rendering and UI compositing at 120fps using Metal shaders via SwiftUI 6
- Provide on-device semantic code indexing and search powered by CoreML and the NaturalLanguage framework with zero cloud dependency
- Persist codebase indexes, editor state, and workspace configuration locally using SwiftData with automatic background saving
- Achieve a premium native macOS feel through NSWindow customization, .ultraThinMaterial, and fluid SwiftUI animations
- Support concurrent language server communication, file watching, and AI indexing via Swift Structured Concurrency

## 🚫 Non-Goals
- Cross-platform support for Linux or Windows at initial launch
- Cloud-based AI inference or remote code analysis services
- Rust interop or WGPU rendering pipeline integration in the first release
- CRDT-based real-time collaborative editing
- Plugin marketplace or third-party extension API
- Replacing existing terminal emulators or Git GUI clients

## 👥 Target Users
- Professional macOS developers who value native performance and low-latency editing on Apple silicon
- Privacy-conscious engineers who prefer on-device AI code analysis over cloud-dependent tools
- Swift and iOS/macOS developers who want a first-class editing experience tuned for Apple platforms
- Power users migrating from VS Code or Sublime Text seeking lower memory usage and GPU-accelerated rendering

## 🧩 Core Features
- Metal Shader Rendering Engine: GPU-accelerated text rendering and UI compositing using Metal shaders through SwiftUI 6 TimelineView, targeting 120fps on ProMotion displays
- On-Device Semantic Indexer: CoreML and NaturalLanguage framework-powered code analysis that builds semantic indexes locally with zero-latency inference and full data privacy
- SwiftData Persistence Layer: Local-first storage of codebase indexes, editor state, workspace layouts, and recent files using SwiftData with automatic background saving
- Premium Native Editor Chrome: NSWindow customization with .ultraThinMaterial and .regularMaterial vibrancy, matchedGeometryEffect tab transitions, and PhaseAnimator-driven sidebar and command palette animations
- Command Palette: Quick-access overlay for commands, file navigation, and symbol search with fluid SwiftUI animation transitions
- Structured Concurrency Task Orchestration: Parallel execution of language server protocol communication, file system watchers, and AI indexing pipelines using Swift async/await and task groups
- Observation-Based State Management: Editor state reactivity built on the Observation framework for efficient SwiftUI view updates without manual publisher wiring
- Menu Bar and Settings Integration: Native macOS menu bar support and a dedicated Settings scene for editor configuration following Apple Human Interface Guidelines
- Optional CloudKit Sync: Opt-in synchronization of workspace preferences and editor settings across devices via CloudKit without exposing source code

## ⚙️ Non-Functional Requirements
- Target macOS 15+ (Sequoia) as the minimum supported operating system
- Maintain 120fps rendering during normal editing, scrolling, and animation on Apple silicon Macs
- Cold launch to interactive editor in under 2 seconds on M1 or later hardware
- Semantic index build for a 100K-line codebase must complete within 30 seconds using on-device CoreML inference
- Memory usage must stay below 500MB for workspaces with up to 50K files
- All AI inference and code analysis must execute on-device with no network calls required
- SwiftData background saves must not block the main thread or cause frame drops
- Editor must remain fully functional with no internet connection (local-first architecture)

## 📊 Success Metrics
- Consistent 120fps rendering measured via Instruments during scrolling and tab switching on M1+ hardware
- Semantic search returns results within 100ms for indexed codebases up to 100K lines
- App launch to editable state in under 2 seconds on Apple silicon
- Memory footprint under 300MB for a typical 10K-file workspace
- SwiftData persistence operations complete without main-thread frame drops as measured by hang detection in Instruments
- User-perceived latency for keystroke-to-render below 8ms

## 📌 Assumptions
- Target users are on macOS 15 (Sequoia) or later with Apple silicon hardware
- CoreML models for semantic code analysis can be bundled within the app at acceptable download sizes
- SwiftUI 6 Metal shader APIs provide sufficient control for custom text rendering comparable to GPUI-level performance
- SwiftData can handle semantic index datasets of up to several hundred megabytes without degradation
- The NaturalLanguage framework combined with custom CoreML models can produce useful semantic embeddings for common programming languages
- Language Server Protocol clients can be effectively managed through Swift Structured Concurrency without third-party networking libraries
- macOS-first launch strategy will attract sufficient early adopters before cross-platform expansion is needed

## ❓ Open Questions
- What specific CoreML model architecture should be used for semantic code embeddings, and what is the acceptable bundled model size?
- How will cross-platform expansion be handled post-launch — separate rendering layer, Swift-on-Linux, or a parallel implementation?
- Should the Metal shader rendering engine handle all text rendering directly, or defer to Core Text for complex Unicode and ligature support?
- What is the strategy for Rust FFI bridging if CRDT or WGPU components are needed in future releases?
- Which programming languages will the semantic indexer support at launch, and how will new language support be added?
- How will the optional CloudKit sync handle conflicts in workspace settings across devices?
- What is the licensing and distribution model — Mac App Store, direct download, or both?