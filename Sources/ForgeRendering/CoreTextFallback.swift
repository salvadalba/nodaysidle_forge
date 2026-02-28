import SwiftUI
import ForgeShared
import ForgeEditorEngine

// MARK: - CoreTextFallbackView

/// Software-rendered fallback editor view using standard SwiftUI Text.
/// Activated when MTLCreateSystemDefaultDevice() returns nil (no GPU available).
public struct CoreTextFallbackView: View {
    @Bindable var buffer: EditorBuffer
    let tokens: [SyntaxToken]

    public init(buffer: EditorBuffer, tokens: [SyntaxToken]) {
        self.buffer = buffer
        self.tokens = tokens
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Degraded mode banner
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("GPU unavailable — rendering in software fallback mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)

            // Standard text rendering
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<buffer.lineCount, id: \.self) { lineIndex in
                        HStack(spacing: 0) {
                            Text("\(lineIndex + 1)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 40, alignment: .trailing)
                                .padding(.trailing, 8)

                            Text(buffer.lineText(lineIndex))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(height: 20)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
