import Testing
import Foundation
@testable import ForgeLSP

// MARK: - JSON-RPC Serialization Tests

@Suite("JSON-RPC Transport")
struct JSONRPCSerializationTests {

    // MARK: - JSONValue Encoding/Decoding

    @Test("JSONValue encodes null")
    func encodeNull() throws {
        let value = JSONValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test("JSONValue encodes bool")
    func encodeBool() throws {
        let value = JSONValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .bool(true))
    }

    @Test("JSONValue encodes int")
    func encodeInt() throws {
        let value = JSONValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("JSONValue encodes string")
    func encodeString() throws {
        let value = JSONValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .string("hello"))
    }

    @Test("JSONValue encodes array")
    func encodeArray() throws {
        let value = JSONValue.array([.int(1), .string("two"), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue encodes object")
    func encodeObject() throws {
        let value = JSONValue.object(["key": .string("value"), "count": .int(5)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue nested structure round-trips")
    func nestedRoundTrip() throws {
        let value = JSONValue.object([
            "method": .string("textDocument/completion"),
            "params": .object([
                "position": .object([
                    "line": .int(10),
                    "character": .int(5),
                ]),
                "items": .array([
                    .object(["label": .string("func"), "kind": .int(3)])
                ])
            ])
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue subscript accesses object keys")
    func subscriptAccess() {
        let value = JSONValue.object(["name": .string("test")])
        #expect(value["name"]?.stringValue == "test")
        #expect(value["missing"] == nil)
    }

    // MARK: - JSON-RPC Request

    @Test("JSONRPCRequest serialization")
    func requestSerialization() throws {
        let request = JSONRPCRequest(
            id: 1,
            method: "initialize",
            params: .object(["processId": .int(123)])
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == 1)
        #expect(decoded.method == "initialize")
        #expect(decoded.params?["processId"] == .int(123))
    }

    // MARK: - JSON-RPC Response

    @Test("JSONRPCResponse with result")
    func responseWithResult() throws {
        let response = JSONRPCResponse(id: 1, result: .object(["capabilities": .object([:])]))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.id == 1)
        #expect(decoded.result != nil)
        #expect(decoded.error == nil)
    }

    @Test("JSONRPCResponse with error")
    func responseWithError() throws {
        let response = JSONRPCResponse(
            id: 2,
            error: JSONRPCError(code: -32600, message: "Invalid Request")
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.id == 2)
        #expect(decoded.result == nil)
        #expect(decoded.error?.code == -32600)
        #expect(decoded.error?.message == "Invalid Request")
    }

    // MARK: - JSON-RPC Notification

    @Test("JSONRPCNotification serialization")
    func notificationSerialization() throws {
        let notification = JSONRPCNotification(
            method: "textDocument/didOpen",
            params: .object(["uri": .string("file:///test.swift")])
        )
        let data = try JSONEncoder().encode(notification)
        let decoded = try JSONDecoder().decode(JSONRPCNotification.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "textDocument/didOpen")
    }

    // MARK: - LSP Framing

    @Test("LSP framing encodes Content-Length header")
    func framingEncode() throws {
        let request = JSONRPCRequest(id: 1, method: "test")
        let frame = try LSPFraming.encode(request)
        let frameStr = String(data: frame, encoding: .utf8)!
        #expect(frameStr.hasPrefix("Content-Length: "))
        #expect(frameStr.contains("\r\n\r\n"))
    }

    @Test("LSP framing parses Content-Length")
    func framingParseLength() {
        #expect(LSPFraming.parseContentLength(from: "Content-Length: 42") == 42)
        #expect(LSPFraming.parseContentLength(from: "content-length: 100") == 100)
        #expect(LSPFraming.parseContentLength(from: "Content-Type: json") == nil)
    }

    @Test("LSP framing rejects oversized messages")
    func framingRejectsLargeMessage() {
        // Create a large string > 16MB
        let largeParams = JSONValue.string(String(repeating: "x", count: 17_000_000))
        let request = JSONRPCRequest(id: 1, method: "test", params: largeParams)
        #expect(throws: (any Error).self) {
            try LSPFraming.encode(request)
        }
    }
}
