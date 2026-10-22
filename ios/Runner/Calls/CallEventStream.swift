import Foundation

struct CallServerEvent { let id: String; let type: String; let data: String }

/// Incremental byte parser: UTF-8 is decoded only after a complete line arrives.
/// EOF never dispatches an unterminated event; all event bytes count toward the cap.
struct CallEventParser {
  private let limit: Int
  private var line = Data()
  private var eventBytes = 0
  private var first = true
  private var afterCR = false
  private var id = ""
  private var type = "message"
  private var data: [String] = []
  init(limit: Int = 1_048_576) { self.limit = limit }
  mutating func append(_ bytes: Data) throws -> [CallServerEvent] {
    var result: [CallServerEvent] = []
    for byte in bytes {
      if afterCR && byte == 10 { afterCR = false; continue }
      afterCR = byte == 13
      eventBytes += 1
      guard eventBytes <= limit else { throw CallGatewayFailure.protocolViolation }
      if byte == 10 || byte == 13 {
        guard var text = String(data: line, encoding: .utf8) else { throw CallGatewayFailure.protocolViolation }
        line.removeAll(keepingCapacity: true)
        if first { first = false; if text.first == "\u{feff}" { text.removeFirst() } }
        if text.isEmpty {
          if !data.isEmpty { result.append(CallServerEvent(id: id, type: type, data: data.joined(separator: "\n"))) }
          type = "message"; data.removeAll(keepingCapacity: true); eventBytes = 0
        } else if !text.hasPrefix(":") {
          let split = text.firstIndex(of: ":")
          let field = split.map { String(text[..<$0]) } ?? text
          var value = split.map { String(text[text.index(after: $0)...]) } ?? ""
          if value.hasPrefix(" ") { value.removeFirst() }
          switch field {
          case "event": type = value.isEmpty ? "message" : value
          case "id": if !value.contains("\0") { id = value }
          case "data": data.append(value)
          default: break
          }
        }
      } else { line.append(byte) }
    }
    return result
  }
}

/// Owned by CallGatewayClient, on its main delegate queue. No replay cursor survives reconnect.
final class CallEventStream {
  var onSnapshot: (([GatewayCallDevice]) -> Void)?
  var onStatus: ((String) -> Void)?
  private(set) var failure = ""
  private let open: () throws -> URLSessionDataTask
  private var task: URLSessionDataTask?
  private var parser = CallEventParser()
  private var sequence: UInt64 = 0
  private var stopped = true
  private var epoch = 0
  private var failures = 0
  private var began = Date()
  private var lastByte = Date()
  private var watchdog: Timer?
  private var retry: DispatchWorkItem?
  init(open: @escaping () throws -> URLSessionDataTask) { self.open = open }
  func start() {
    guard stopped else { return }; stopped = false; epoch += 1; connect()
  }
  func stop() {
    cleanup()
    failure = ""
    onStatus?("stopped")
  }
  private func cleanup() {
    stopped = true; epoch += 1; retry?.cancel(); retry = nil
    watchdog?.invalidate(); watchdog = nil
    let old = task; task = nil; old?.cancel()
  }
  func owns(_ candidate: URLSessionTask) -> Bool { !stopped && candidate === task }
  private func connect() {
    guard !stopped else { return }
    let generation = epoch
    parser = CallEventParser(); sequence = 0; began = Date(); lastByte = began
    failure = ""
    onStatus?("connecting")
    guard !stopped, epoch == generation else { return }
    do {
      let opened = try open()
      guard !stopped, epoch == generation else { opened.cancel(); return }
      task = opened; opened.resume()
    } catch {
      guard !stopped, epoch == generation else { return }
      let code = callFailureCode(error)
      terminate(code == "call_unauthorized" ? "unauthorized" : "failed", failure: code); return
    }
    watchdog?.invalidate()
    watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self, !self.stopped, self.task != nil, self.epoch == generation else { return }
      if Date().timeIntervalSince(self.lastByte) > 35 { self.disconnected(status: "stale", failure: "call_events_stale") }
    }
  }
  func response(_ response: HTTPURLResponse) -> Bool {
    guard !stopped, task != nil else { return false }
    let code = response.statusCode
    if [401, 403].contains(code) { terminate("unauthorized", failure: "call_unauthorized"); return false }
    if [204, 404, 501].contains(code) { terminate("unavailable", failure: "call_unavailable"); return false }
    if code == 408 || code == 429 || (500...599).contains(code) {
      // Read-only SSE retries only; never replay a call mutation. Honor numeric
      // Retry-After within the existing 30-second backoff cap.
      let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
      let bounded = retryAfter.flatMap { $0.isFinite && $0 >= 0 ? min(30, $0) : nil } ?? 0
      disconnected(status: "offline", failure: code == 429 ? "call_events_rate_limited" : (code == 408 ? "call_transport" : "call_events_server_error"), minimumDelay: bounded)
      return false
    }
    guard code == 200 else { terminate("failed", failure: "call_events_http_rejected"); return false }
    guard response.mimeType?.lowercased() == "text/event-stream" else { terminate("failed", failure: "call_protocol_violation"); return false }
    return true
  }
  func receive(_ bytes: Data) {
    guard !stopped, task != nil else { return }
    let generation = epoch
    if !bytes.isEmpty { lastByte = Date() }
    do {
      for event in try parser.append(bytes) where event.type == "snapshot" {
        guard let next = UInt64(event.id), next > 0,
          let payload = event.data.data(using: .utf8),
          let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw CallGatewayFailure.protocolViolation }
        if next <= sequence { continue }
        let snapshot = try CallSnapshotDecoder.decode(json)
        sequence = next; failure = ""; onStatus?("connected")
        guard !stopped, task != nil, epoch == generation else { return }
        onSnapshot?(snapshot)
        if stopped || epoch != generation { return }
      }
    } catch { terminate("failed", failure: "call_protocol_violation") }
  }
  func complete(_ error: Error?) {
    guard !stopped, task != nil else { return }
    let ns = error as NSError?
    if ns?.domain == NSURLErrorDomain && ((-1206 ... -1200).contains(ns?.code ?? 0) || ns?.code == -1022) { terminate("failed", failure: "call_trust") }
    else { disconnected(status: "offline", failure: "call_transport") }
  }
  private func terminate(_ status: String, failure: String) {
    cleanup(); self.failure = failure; onStatus?(status)
  }
  private func disconnected(status: String, failure: String, minimumDelay: TimeInterval = 0) {
    let generation = epoch
    let old = task; task = nil; old?.cancel(); watchdog?.invalidate(); watchdog = nil
    self.failure = failure; onStatus?(status)
    guard !stopped, epoch == generation else { return }
    if Date().timeIntervalSince(began) >= 30 { failures = 0 }
    let delay = max(minimumDelay, min(30.0, pow(2.0, Double(failures)))); failures = min(failures + 1, 5)
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.stopped, self.epoch == generation else { return }; self.connect()
    }
    retry?.cancel(); retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
}
