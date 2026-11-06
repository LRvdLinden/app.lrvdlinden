import Foundation

/// JSON-waarde die de volgorde van sleutels en de precieze getallen bewaart. apps.json (LRvdLinden) en content.json
/// (PixelForges) gaan na Publiceren als commit naar GitHub; zo blijven velden die de app niet kent en de volgorde staan,
/// precies zoals bij beheer.html (dat het hele object terugstuurt).
enum JSON: Equatable {
    case object([(String, JSON)])
    case array([JSON])
    case string(String)
    /// Getal als tekst (zoals in het bestand), zodat 4.8 niet 4.7999999 wordt.
    case number(String)
    case bool(Bool)
    case null

    static func == (a: JSON, b: JSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(x), .array(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.number(x), .number(y)): return x == y
        case let (.bool(x), .bool(y)): return x == y
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: lezen

    subscript(key: String) -> JSON? {
        get {
            guard case let .object(kv) = self else { return nil }
            return kv.first { $0.0 == key }?.1
        }
        set {
            guard case var .object(kv) = self else {
                if let newValue { self = .object([(key, newValue)]) }
                return
            }
            if let i = kv.firstIndex(where: { $0.0 == key }) {
                if let newValue { kv[i].1 = newValue } else { kv.remove(at: i) }
            } else if let newValue {
                kv.append((key, newValue))
            }
            self = .object(kv)
        }
    }

    var str: String? {
        switch self {
        case let .string(s): return s
        case let .number(n): return n
        default: return nil
        }
    }

    var boolValue: Bool { if case let .bool(b) = self { return b }; return false }
    var items: [JSON] { if case let .array(a) = self { return a }; return [] }
    var keys: [String] { if case let .object(kv) = self { return kv.map(\.0) }; return [] }
    var isObject: Bool { if case .object = self { return true }; return false }

    /// Pad als "promo.title.nl"; lege tekst verwijdert de sleutel en lege objecten erboven (setPath in beheer.html).
    mutating func set(path: String, _ value: JSON?) {
        let parts = path.split(separator: ".").map(String.init)
        set(parts[...], value)
    }

    private mutating func set(_ parts: ArraySlice<String>, _ value: JSON?) {
        guard let first = parts.first else { return }
        if parts.count == 1 {
            self[first] = value
            return
        }
        var child = self[first] ?? .object([])
        child.set(parts.dropFirst(), value)
        if case let .object(kv) = child, kv.isEmpty { self[first] = nil } else { self[first] = child }
    }

    func value(path: String) -> JSON? {
        var cur: JSON? = self
        for p in path.split(separator: ".") { cur = cur?[String(p)] }
        return cur
    }

    func text(_ path: String) -> String { value(path: path)?.str ?? "" }

    /// Tekstveld uit een formulier: leeg = sleutel weg.
    mutating func setText(_ path: String, _ text: String) {
        set(path: path, text.isEmpty ? nil : .string(text))
    }

    // MARK: schrijven

    func serialized() -> String {
        var out = ""
        write(&out)
        return out
    }

    private func write(_ out: inout String) {
        switch self {
        case let .object(kv):
            out += "{"
            for (i, (k, v)) in kv.enumerated() {
                if i > 0 { out += "," }
                JSON.writeString(k, &out); out += ":"; v.write(&out)
            }
            out += "}"
        case let .array(a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(&out)
            }
            out += "]"
        case let .string(s): JSON.writeString(s, &out)
        case let .number(n): out += n
        case let .bool(b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    private static func writeString(_ s: String, _ out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    // MARK: parsen

    struct ParseError: Error {}

    static func parse(_ data: Data) throws -> JSON {
        var p = Parser(bytes: [UInt8](data))
        p.skipWS()
        let v = try p.value()
        p.skipWS()
        guard p.i == p.bytes.count else { throw ParseError() }
        return v
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skipWS() {
            while i < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) { i += 1 }
        }

        mutating func value() throws -> JSON {
            guard i < bytes.count else { throw ParseError() }
            switch bytes[i] {
            case UInt8(ascii: "{"):
                i += 1; skipWS()
                var kv: [(String, JSON)] = []
                if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
                while true {
                    skipWS()
                    guard case let .string(k) = try value() else { throw ParseError() }
                    skipWS()
                    guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw ParseError() }
                    i += 1; skipWS()
                    kv.append((k, try value()))
                    skipWS()
                    guard i < bytes.count else { throw ParseError() }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
                    throw ParseError()
                }
            case UInt8(ascii: "["):
                i += 1; skipWS()
                var a: [JSON] = []
                if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                while true {
                    skipWS()
                    a.append(try value())
                    skipWS()
                    guard i < bytes.count else { throw ParseError() }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                    throw ParseError()
                }
            case UInt8(ascii: "\""):
                return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default:
                let start = i
                while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
                guard i > start, let s = String(bytes: bytes[start..<i], encoding: .utf8), Double(s) != nil else {
                    throw ParseError()
                }
                return .number(s)
            }
        }

        mutating func literal(_ s: String) throws {
            let u = Array(s.utf8)
            guard i + u.count <= bytes.count, Array(bytes[i..<i + u.count]) == u else { throw ParseError() }
            i += u.count
        }

        mutating func string() throws -> String {
            i += 1
            var buf: [UInt8] = []
            while i < bytes.count {
                let c = bytes[i]
                if c == UInt8(ascii: "\"") { i += 1; return String(decoding: buf, as: UTF8.self) }
                if c == UInt8(ascii: "\\") {
                    i += 1
                    guard i < bytes.count else { throw ParseError() }
                    let e = bytes[i]
                    switch e {
                    case UInt8(ascii: "n"): buf.append(0x0A)
                    case UInt8(ascii: "r"): buf.append(0x0D)
                    case UInt8(ascii: "t"): buf.append(0x09)
                    case UInt8(ascii: "b"): buf.append(0x08)
                    case UInt8(ascii: "f"): buf.append(0x0C)
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code), i + 2 < bytes.count,
                           bytes[i + 1] == UInt8(ascii: "\\"), bytes[i + 2] == UInt8(ascii: "u") {
                            i += 2
                            let low = try hex4()
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        buf.append(contentsOf: Array(String(UnicodeScalar(code).map(Character.init) ?? "?").utf8))
                    default: buf.append(e)
                    }
                    i += 1
                } else {
                    buf.append(c); i += 1
                }
            }
            throw ParseError()
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 < bytes.count, let s = String(bytes: bytes[(i + 1)...(i + 4)], encoding: .ascii),
                  let v = UInt32(s, radix: 16) else { throw ParseError() }
            i += 4
            return v
        }
    }
}
