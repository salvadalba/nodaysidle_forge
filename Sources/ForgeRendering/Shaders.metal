#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Structures

struct TextVertex {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct TextVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

struct RectVertex {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct RectVertexOut {
    float4 position [[position]];
    float4 color;
};

// MARK: - Uniforms

struct Uniforms {
    float2 viewportSize;
    float  cursorBlinkOpacity;
    float  time;
};

// MARK: - Text Layer (Glyph Atlas Sampling)

vertex TextVertexOut textVertexShader(
    uint vertexID [[vertex_id]],
    const device TextVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    TextVertex in = vertices[vertexID];
    TextVertexOut out;

    // Convert pixel coordinates to clip space (-1 to 1)
    float2 clipPos = (in.position / uniforms.viewportSize) * 2.0 - 1.0;
    clipPos.y = -clipPos.y; // Flip Y for Metal
    out.position = float4(clipPos, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;

    return out;
}

fragment float4 textFragmentShader(
    TextVertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float4 texColor = glyphAtlas.sample(texSampler, in.texCoord);
    // Use texture alpha as coverage, apply vertex color
    return float4(in.color.rgb, in.color.a * texColor.a);
}

// MARK: - Selection Highlight Layer

vertex RectVertexOut selectionVertexShader(
    uint vertexID [[vertex_id]],
    const device RectVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    RectVertex in = vertices[vertexID];
    RectVertexOut out;

    float2 clipPos = (in.position / uniforms.viewportSize) * 2.0 - 1.0;
    clipPos.y = -clipPos.y;
    out.position = float4(clipPos, 0.0, 1.0);
    out.color = in.color;

    return out;
}

fragment float4 selectionFragmentShader(
    RectVertexOut in [[stage_in]]
) {
    // Semi-transparent selection highlight
    return in.color;
}

// MARK: - Cursor Layer

vertex RectVertexOut cursorVertexShader(
    uint vertexID [[vertex_id]],
    const device RectVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    RectVertex in = vertices[vertexID];
    RectVertexOut out;

    float2 clipPos = (in.position / uniforms.viewportSize) * 2.0 - 1.0;
    clipPos.y = -clipPos.y;
    out.position = float4(clipPos, 0.0, 1.0);
    out.color = float4(in.color.rgb, in.color.a * uniforms.cursorBlinkOpacity);

    return out;
}

fragment float4 cursorFragmentShader(
    RectVertexOut in [[stage_in]]
) {
    return in.color;
}

// MARK: - Minimap Layer

vertex TextVertexOut minimapVertexShader(
    uint vertexID [[vertex_id]],
    const device TextVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    TextVertex in = vertices[vertexID];
    TextVertexOut out;

    float2 clipPos = (in.position / uniforms.viewportSize) * 2.0 - 1.0;
    clipPos.y = -clipPos.y;
    out.position = float4(clipPos, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;

    return out;
}

fragment float4 minimapFragmentShader(
    TextVertexOut in [[stage_in]]
) {
    // Minimap renders colored blocks, no texture sampling needed
    return in.color;
}
