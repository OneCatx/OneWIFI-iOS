import Foundation
import CoreFoundation
import Darwin

enum CallGatewayFailure: Error {
  case invalidConfiguration, unauthorized, unavailable, transport, protocolViolation
  case mediaBusy, stateConflict, dtmfUnavailable, invalidRequest, trust, cancelled
  case systemTransaction
  var code: String {
    switch self {
    case .invalidConfiguration: return "call_invalid_configuration"
    case .unauthorized: return "call_unauthorized"
    case .unavailable: return "call_unavailable"
    case .transport: return "call_transport"
    case .protocolViolation: return "call_protocol_violation"
    case .mediaBusy: return "call_media_busy"
    case .stateConflict: return "call_state_conflict"
    case .dtmfUnavailable: return "dtmf_unavailable"
    case .invalidRequest: return "call_invalid_request"
    case .trust: return "call_trust"
    case .cancelled: return "call_cancelled"
    case .systemTransaction: return "call_system_transaction"
    }
  }
}
func callFailureCode(_ error: Error) -> String { (error as? CallGatewayFailure)?.code ?? "call_transport" }

struct CallGatewayConfiguration {
  let origin: URL
  let token: String
  let expiresAt: Date?
  let certificateFingerprint: String?
  init(arguments: [String: Any]) throws {
    guard let text = arguments["origin"] as? String, let url = URL(string: text),
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = parts.host, !host.isEmpty, ["http", "https"].contains(parts.scheme ?? ""),
      parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/",
      let token = arguments["token"] as? String, !token.isEmpty, token.utf8.count <= 16384,
      !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
      throw CallGatewayFailure.invalidConfiguration
    }
    if parts.scheme == "http" && !Self.isLocal(host) { throw CallGatewayFailure.invalidConfiguration }
    var normalized = parts; normalized.path = ""
    guard let origin = normalized.url else { throw CallGatewayFailure.invalidConfiguration }
    self.origin = origin; self.token = token
    if let value = arguments["expiresAt"], !(value is NSNull) {
      guard let millis = value as? NSNumber, CFGetTypeID(millis) != CFBooleanGetTypeID(), millis.doubleValue.isFinite else { throw CallGatewayFailure.invalidConfiguration }
      let expiry = Date(timeIntervalSince1970: millis.doubleValue / 1000)
      guard expiry > Date() else { throw CallGatewayFailure.unauthorized }
      expiresAt = expiry
    } else { expiresAt = nil }
    if let value = arguments["certificateFingerprint"], !(value is NSNull) {
      guard let raw = value as? String else { throw CallGatewayFailure.invalidConfiguration }
      let pin = raw.replacingOccurrences(of: ":", with: "").lowercased()
      guard parts.scheme == "https", pin.count == 64, pin.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw CallGatewayFailure.invalidConfiguration }
      certificateFingerprint = pin
    } else { certificateFingerprint = nil }
  }
  private static func isLocal(_ raw: String) -> Bool {
    let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
    if host.contains(":") {
      var address = in6_addr()
      guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return false }
      let bytes = withUnsafeBytes(of: &address) { Array($0) }
      let loopback = bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1
      return loopback || bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
    }
    let segments = host.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 4, segments.allSatisfy({
      !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) && ($0.count == 1 || $0.first != "0")
    }) else { return false }
    let octets = segments.compactMap { UInt8($0) }
    guard octets.count == 4 else { return false }
    return octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 169 && octets[1] == 254)
  }
}

func callStrictBool(_ value: Any?) -> Bool? {
  guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
  return n.boolValue
}
struct GatewayCall {
  let deviceID: String; let id: String; let number: String; let direction: String
  let state: String; let mediaReady: Bool; let startedAt: String?; let endedAt: String?
  init(deviceID: String, json: [String: Any]) throws {
    guard let id = json["id"] as? String, !id.isEmpty, id.utf8.count <= 512,
      let number = json["number"] as? String, number.utf8.count <= 512,
      let direction = json["direction"] as? String, ["incoming", "outgoing"].contains(direction),
      let state = json["state"] as? String,
      ["ringing", "dialing", "early_media", "answering", "active", "ended", "failed"].contains(state) else { throw CallGatewayFailure.protocolViolation }
    let ready: Bool
    if let value = json["media_ready"] {
      guard let bool = callStrictBool(value) else { throw CallGatewayFailure.protocolViolation }; ready = bool
    } else { ready = false } // Go omits false via json omitempty.
    for key in ["started_at", "ended_at"] {
      if let value = json[key], !(value is NSNull), !(value is String) { throw CallGatewayFailure.protocolViolation }
    }
    self.deviceID = deviceID; self.id = id; self.number = number; self.direction = direction
    self.state = state; mediaReady = ready; startedAt = json["started_at"] as? String; endedAt = json["ended_at"] as? String
  }
  var isTerminal: Bool { state == "ended" || state == "failed" || !(endedAt ?? "").isEmpty }
  var dictionary: [String: Any] {
    ["id": id, "number": number, "direction": direction, "state": state, "media_ready": mediaReady,
     "started_at": startedAt as Any? ?? NSNull(), "ended_at": endedAt as Any? ?? NSNull()]
  }
}
struct GatewayCallDevice {
  let id: String; let label: String; let ready: Bool; let calls: [GatewayCall]
  init(id: String, label: String, ready: Bool, calls: [GatewayCall]) { self.id = id; self.label = label; self.ready = ready; self.calls = calls }
  var dictionary: [String: Any] { ["device_id": id, "label": label, "ready": ready, "calls": calls.map(\.dictionary)] }
}
struct CallMediaDescription {
  let id: String; let codec: String; let format: String; let dtmfSupported: Bool
  init(id: String, codec: String, format: String, dtmfSupported: Bool) { self.id = id; self.codec = codec; self.format = format; self.dtmfSupported = dtmfSupported }
}
enum CallSnapshotDecoder {
  static func decode(_ json: [String: Any]) throws -> [GatewayCallDevice] {
    guard let devices = json["devices"] as? [[String: Any]], devices.count <= 256 else { throw CallGatewayFailure.protocolViolation }
    var ids = Set<String>(); var total = 0
    return try devices.map { device in
      guard let id = device["device_id"] as? String, !id.isEmpty, id.utf8.count <= 512, ids.insert(id).inserted,
        let label = device["label"] as? String, label.utf8.count <= 4096,
        let ready = callStrictBool(device["ready"]), let rows = device["calls"] as? [[String: Any]], rows.count <= 256 else { throw CallGatewayFailure.protocolViolation }
      total += rows.count; guard total <= 4096 else { throw CallGatewayFailure.protocolViolation }
      var callIDs = Set<String>()
      let calls = try rows.map { row -> GatewayCall in
        let call = try GatewayCall(deviceID: id, json: row)
        guard callIDs.insert(call.id).inserted else { throw CallGatewayFailure.protocolViolation }; return call
      }
      return GatewayCallDevice(id: id, label: label, ready: ready, calls: calls)
    }
  }
}
