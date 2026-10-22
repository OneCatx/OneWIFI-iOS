import CryptoKit
import Foundation
import Network
import Security

/// The UI reads this while the event stream is failing. The TLS callback and the
/// session delegate touch it from different queues.
final class CallTLSReport {
  private let lock = NSLock()
  private var diagnostic = CallTLSDiagnostic()

  func reset(pinConfigured: Bool) {
    lock.lock()
    diagnostic = CallTLSDiagnostic(pinConfigured: pinConfigured)
    lock.unlock()
  }

  func update(_ body: (inout CallTLSDiagnostic) -> Void) {
    lock.lock()
    body(&diagnostic)
    lock.unlock()
  }

  var summary: String {
    lock.lock()
    defer { lock.unlock() }
    return diagnostic.summary
  }
}

enum CallPinnedTLS {
  /// Replaces the system hostname check. The dialed address is often absent
  /// from the leaf, and accepting that failure still ends in -9802.
  static func options(pin: String, report: CallTLSReport) -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trust, complete in
      let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
      report.update { $0.stage = "leaf" }
      guard let leaf = SecTrustGetCertificateAtIndex(secTrust, 0) else {
        report.update { $0.pinMatches = false }
        complete(false)
        return
      }
      let der = SecCertificateCopyData(leaf) as Data
      let actual = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
      let matches = actual == pin
      report.update {
        $0.pinMatches = matches
        $0.stage = "pin"
      }
      guard matches else { complete(false); return }
      report.update { $0.stage = "validity" }
      guard CallCertificateValidity.containsNow(der) else { complete(false); return }
      report.update { $0.stage = "lifetime" }
      guard CallCertificateValidity.withinPinnedLifetime(der) else { complete(false); return }
      report.update {
        $0.securityStatus = 0
        $0.stage = "accepted"
      }
      complete(true)
    }, DispatchQueue(label: "onewifi.call.tls"))
    return options
  }
}

/// HTTP/1.1 over a pinned TLS connection. URLSession's own handshake still
/// checks the dialed name after the trust callback and aborts with -9802.
final class CallPinnedURLProtocol: URLProtocol {
  static let pinKey = "onewifi.call.pin"
  static let reportKey = "onewifi.call.report"
  private let queue = DispatchQueue(label: "onewifi.call.http")
  private var connection: NWConnection?
  private var decoder = CallHTTPDecoder()
  private var sentHeaders = false
  private var handshakeDone = false
  private var finished = false
  private var connectTimer: DispatchWorkItem?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "https" && URLProtocol.property(forKey: pinKey, in: request) is String
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host, let pin = URLProtocol.property(forKey: Self.pinKey, in: request) as? String else {
      fail(URLError(.badURL)); return
    }
    let report = URLProtocol.property(forKey: Self.reportKey, in: request) as? CallTLSReport ?? CallTLSReport()
    report.update { $0.stage = "origin" }
    let port = UInt16(url.port ?? 443)
    let tls = CallPinnedTLS.options(pin: pin, report: report)
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls))
    self.connection = connection
    connection.stateUpdateHandler = { [weak self] state in
      self?.queue.async { self?.observe(state) }
    }
    let timer = DispatchWorkItem { [weak self] in self?.fail(URLError(.timedOut)) }
    connectTimer = timer
    DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timer)
    connection.start(queue: queue)
  }

  override func stopLoading() {
    queue.async { [weak self] in
      guard let self, !self.finished else { return }
      self.finished = true
      self.connectTimer?.cancel()
      self.connection?.cancel()
    }
  }

  private func observe(_ state: NWConnection.State) {
    switch state {
    case .ready:
      handshakeDone = true
      connectTimer?.cancel()
      sendRequest()
    case .failed(let error):
      fail(handshakeDone ? URLError(.networkConnectionLost) : pinnedTransportError(error))
    case .cancelled:
      break
    default:
      break
    }
  }

  private func sendRequest() {
    guard let url = request.url, let host = url.host else { fail(URLError(.badURL)); return }
    let method = request.httpMethod ?? "GET"
    let path = url.path.isEmpty ? "/" : url.path
    let query = url.query.map { "?\($0)" } ?? ""
    var headers = request.allHTTPHeaderFields ?? [:]
    headers["Host"] = callHostHeader(host: host, port: url.port ?? 443)
    let streaming = request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
    headers["Connection"] = streaming ? "keep-alive" : "close"
    headers.removeValue(forKey: "Accept-Encoding")
    let body = request.httpBody ?? Data()
    if !body.isEmpty { headers["Content-Length"] = String(body.count) }
    var text = "\(method) \(path)\(query) HTTP/1.1\r\n"
    for (name, value) in headers where !name.isEmpty && !value.contains("\r") && !value.contains("\n") {
      text += "\(name): \(value)\r\n"
    }
    text += "\r\n"
    var bytes = Data(text.utf8)
    bytes.append(body)
    connection?.send(content: bytes, completion: .contentProcessed { [weak self] error in
      self?.queue.async {
        if let error { self?.fail(pinnedTransportError(error)); return }
        self?.read()
      }
    })
  }

  private func read() {
    guard !finished else { return }
    connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
      self?.queue.async {
        guard let self, !self.finished else { return }
        if let data, !data.isEmpty {
          do {
            let delivered = try self.decoder.append(data)
            if delivered.sawHeaders, !self.sentHeaders, let response = self.response(delivered.headers, status: delivered.status) {
              self.sentHeaders = true
              self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if !delivered.body.isEmpty { self.client?.urlProtocol(self, didLoad: delivered.body) }
            if delivered.finished { self.succeed(); return }
          } catch {
            self.fail(error); return
          }
        }
        if let error { self.fail(self.handshakeDone ? URLError(.networkConnectionLost) : pinnedTransportError(error)); return }
        if isComplete { self.succeed(); return }
        self.read()
      }
    }
  }

  private func response(_ headers: [String: String], status: Int) -> HTTPURLResponse? {
    guard status > 0, let url = request.url else { return nil }
    return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
  }

  private func succeed() {
    guard !finished else { return }
    finished = true
    connectTimer?.cancel()
    connection?.cancel()
    client?.urlProtocolDidFinishLoading(self)
  }

  private func fail(_ error: Error) {
    guard !finished else { return }
    finished = true
    connectTimer?.cancel()
    connection?.cancel()
    client?.urlProtocol(self, didFailWithError: error)
  }
}

private struct CallHTTPPiece {
  var status = 0
  var headers: [String: String] = [:]
  var sawHeaders = false
  var body = Data()
  var finished = false
}

private struct CallHTTPDecoder {
  private var buffer = Data()
  private var status = 0
  private var headers: [String: String] = [:]
  private var mode = Mode.headers
  private var remaining = 0

  private enum Mode { case headers, length, chunkSize, chunkData, chunkEnd, trailers, close }

  mutating func append(_ data: Data) throws -> CallHTTPPiece {
    guard buffer.count + data.count <= 1_048_576 + 65_536 else { throw CallGatewayFailure.protocolViolation }
    buffer.append(data)
    var piece = CallHTTPPiece()
    while !piece.finished {
      switch mode {
      case .headers:
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return piece }
        let headerBytes = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        let text = String(data: headerBytes, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n")
        let statusLine = lines.first?.split(separator: " ") ?? []
        guard statusLine.count >= 2, let code = Int(statusLine[1]) else { throw CallGatewayFailure.protocolViolation }
        status = code
        for line in lines.dropFirst() where !line.isEmpty {
          guard let split = line.firstIndex(of: ":") else { continue }
          let name = String(line[..<split]).trimmingCharacters(in: .whitespaces)
          var value = String(line[line.index(after: split)...])
          if value.hasPrefix(" ") { value.removeFirst() }
          headers[name] = value
        }
        piece.status = status
        piece.headers = headers
        piece.sawHeaders = true
        let encoding = headers.first { $0.key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame }?.value.lowercased() ?? ""
        if encoding.contains("chunked") { mode = .chunkSize }
        else if let length = headers.first(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame })?.value, let count = Int(length), count >= 0 {
          remaining = count
          mode = count == 0 ? .close : .length
          if count == 0 { piece.finished = true; mode = .close }
        } else { mode = .close }
      case .length:
        guard !buffer.isEmpty else { return piece }
        let take = min(remaining, buffer.count)
        piece.body.append(buffer.prefix(take))
        buffer.removeFirst(take)
        remaining -= take
        if remaining == 0 { piece.finished = true }
      case .chunkSize:
        guard let range = buffer.range(of: Data("\r\n".utf8)) else { return piece }
        let line = String(data: buffer.subdata(in: buffer.startIndex..<range.lowerBound), encoding: .ascii) ?? ""
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        let hex = line.split(separator: ";").first.map(String.init) ?? ""
        guard let size = Int(hex, radix: 16), size >= 0 else { throw CallGatewayFailure.protocolViolation }
        remaining = size
        mode = size == 0 ? .trailers : .chunkData
      case .chunkData:
        guard !buffer.isEmpty else { return piece }
        let take = min(remaining, buffer.count)
        piece.body.append(buffer.prefix(take))
        buffer.removeFirst(take)
        remaining -= take
        if remaining == 0 { mode = .chunkEnd }
      case .chunkEnd:
        guard buffer.count >= 2 else { return piece }
        guard buffer.prefix(2) == Data("\r\n".utf8) else { throw CallGatewayFailure.protocolViolation }
        buffer.removeFirst(2)
        mode = .chunkSize
      case .trailers:
        guard let range = buffer.range(of: Data("\r\n".utf8)) else { return piece }
        let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        if line.isEmpty { piece.finished = true }
      case .close:
        if !buffer.isEmpty { piece.body.append(buffer); buffer.removeAll(keepingCapacity: true) }
        return piece
      }
    }
    return piece
  }
}

final class CallPinnedWebSocket: CallMediaSocket {
  private let queue = DispatchQueue(label: "onewifi.call.ws")
  private let connection: NWConnection
  private let socketURL: URL
  private var responseBox: URLResponse?
  var response: URLResponse? { responseBox }
  private var receiver: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
  private var pinger: ((Error?) -> Void)?
  private var pendingSends: [(Data, (Error?) -> Void)] = []
  private var sending = false
  private var ready = false
  private var closed = false

  init(request: URLRequest, pin: String) throws {
    guard let url = request.url, url.scheme == "wss" || url.scheme == "https" else { throw CallGatewayFailure.invalidRequest }
    var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    parts?.scheme = "wss"
    guard let wss = parts?.url else { throw CallGatewayFailure.invalidRequest }
    socketURL = wss
    let tls = CallPinnedTLS.options(pin: pin, report: CallTLSReport())
    let parameters = NWParameters(tls: tls)
    let webSocket = NWProtocolWebSocket.Options()
    webSocket.autoReplyPing = true
    if let authorization = request.value(forHTTPHeaderField: "Authorization") {
      webSocket.setAdditionalHeaders([("Authorization", authorization)])
    }
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
    connection = NWConnection(to: .url(wss), using: parameters)
    connection.stateUpdateHandler = { [weak self] state in
      self?.queue.async { self?.observe(state) }
    }
  }

  func resume() { connection.start(queue: queue) }
  func cancel() {
    queue.async { [weak self] in
      guard let self else { return }
      self.closed = true
      self.connection.cancel()
      self.fail(URLError(.cancelled))
    }
  }
  func receive(_ completion: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
    queue.async { [weak self] in self?.receiver = completion }
  }
  func ping(_ completion: @escaping (Error?) -> Void) {
    queue.async { [weak self] in
      guard let self else { return }
      guard self.pinger == nil else { DispatchQueue.main.async { completion(CallGatewayFailure.stateConflict) }; return }
      self.pinger = completion
      guard self.ready else { return }
      self.sendFrame(Data(), opcode: .ping) { _ in }
    }
  }
  func send(_ data: Data, completion: @escaping (Error?) -> Void) {
    queue.async { [weak self] in
      guard let self, !self.closed else { DispatchQueue.main.async { completion(CallGatewayFailure.cancelled) }; return }
      guard data.count <= 6400 else { DispatchQueue.main.async { completion(CallGatewayFailure.protocolViolation) }; return }
      self.pendingSends.append((data, completion))
      self.pumpSends()
    }
  }

  private func observe(_ state: NWConnection.State) {
    switch state {
    case .ready:
      ready = true
      responseBox = HTTPURLResponse(url: socketURL, statusCode: 101, httpVersion: "HTTP/1.1", headerFields: nil)
      listen()
      if pinger != nil { sendFrame(Data(), opcode: .ping) { [weak self] error in if let error { self?.fail(error) } } }
      pumpSends()
    case .failed(let error):
      fail(ready ? URLError(.networkConnectionLost) : pinnedTransportError(error))
    case .cancelled:
      break
    default:
      break
    }
  }

  private func listen() {
    connection.receiveMessage { [weak self] data, context, _, error in
      self?.queue.async {
        guard let self, !self.closed else { return }
        if let error { self.fail(pinnedTransportError(error)); return }
        let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
        switch metadata?.opcode {
        case .pong?:
          let callback = self.pinger
          self.pinger = nil
          if let callback { DispatchQueue.main.async { callback(nil) } }
        case .binary?:
          let payload = data ?? Data()
          guard payload.count <= 6400 else { self.fail(CallGatewayFailure.protocolViolation); return }
          let callback = self.receiver
          self.receiver = nil
          if let callback { DispatchQueue.main.async { callback(.success(.data(payload))) } }
        case .text?:
          let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
          let callback = self.receiver
          self.receiver = nil
          if let callback { DispatchQueue.main.async { callback(.success(.string(text))) } }
        case .close?:
          self.fail(URLError(.networkConnectionLost))
          return
        default:
          break
        }
        self.listen()
      }
    }
  }

  private func pumpSends() {
    guard ready, !sending, !pendingSends.isEmpty else { return }
    let (data, completion) = pendingSends.removeFirst()
    sending = true
    sendFrame(data, opcode: .binary) { [weak self] error in
      self?.sending = false
      DispatchQueue.main.async { completion(error) }
      self?.pumpSends()
    }
  }

  private func sendFrame(_ data: Data, opcode: NWProtocolWebSocket.Opcode, completion: @escaping (Error?) -> Void) {
    let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
    let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
    connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
      completion(error.map(pinnedTransportError))
    })
  }

  private func fail(_ error: Error) {
    guard !closed else { return }
    closed = true
    connection.cancel()
    let receive = receiver
    let ping = pinger
    let sends = pendingSends
    receiver = nil
    pinger = nil
    pendingSends = []
    DispatchQueue.main.async {
      receive?(.failure(error))
      ping?(error)
      for send in sends { send.1(error) }
    }
  }
}

private func callHostHeader(host: String, port: Int) -> String {
  let shown = host.contains(":") ? "[\(host)]" : host
  return port == 443 ? shown : "\(shown):\(port)"
}

private func pinnedTransportError(_ error: Error) -> Error {
  NSError(domain: NSURLErrorDomain, code: URLError.secureConnectionFailed.rawValue, userInfo: [NSUnderlyingErrorKey: error])
}
