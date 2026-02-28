import Foundation
import ForgeShared

// MARK: - JSON-RPC 2.0 Message Types

/// Maximum allowed message size: 16MB
private let maxMessageSize = 16 * 1_048_576

/// A JSON-RPC 2.0 request message.
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: JSONValue?

    public init(id: Int, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC 2.0 response message.
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(id: Int?, result: JSONValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

/// A JSON-RPC 2.0 notification (no id).
public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC error object.
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - JSONValue (Type-Erased JSON)

/// A type-erased JSON value for flexible LSP message payloads.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    /// Access a string value.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Access an object value.
    public var objectValue: [String: JSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    /// Access an array value.
    public var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    /// Subscript for object access.
    public subscript(key: String) -> JSONValue? {
        if case .object(let obj) = self { return obj[key] }
        return nil
    }
}

// MARK: - LSP Header Parsing

/// Parses and serializes LSP Content-Length header framing.
public enum LSPFraming {
    /// Encode a JSON-RPC message into LSP wire format (Content-Length header + body).
    public static func encode<T: Encodable>(_ message: T) throws -> Data {
        let bodyData = try JSONEncoder().encode(message)

        guard bodyData.count <= maxMessageSize else {
            throw LSPError.messageTooLarge(bodyData.count)
        }

        let header = "Content-Length: \(bodyData.count)\r\n\r\n"
        var frame = Data(header.utf8)
        frame.append(bodyData)
        return frame
    }

    /// Parse the Content-Length from a header line.
    public static func parseContentLength(from headerLine: String) -> Int? {
        let trimmed = headerLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("content-length:") else { return nil }
        let valueStr = trimmed.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
        return Int(valueStr)
    }
}
