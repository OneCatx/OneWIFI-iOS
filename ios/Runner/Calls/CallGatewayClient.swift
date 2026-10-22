import Foundation
import Security
import CryptoKit

protocol CallGatewayServing: AnyObject {
  var configuration: CallGatewayConfiguration { get }
  var onSnapshot: (([GatewayCallDevice]) -> Void)? { get set }
  var onEventStatus: ((String) -> Void)? { get set }
  var eventFailure: String { get }
  var eventDiagnostic: String { get }
  func startEvents()
  func stopEvents()
  @discardableResult func performAction(deviceID: String, action: String, body: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask?
  @discardableResult func mediaMetadata(deviceID: String, callID: String, completion: @escaping (Result<CallMediaDescription, Error>) -> Void) -> URLSessionDataTask?
  func makeMediaSocket(deviceID: String, callID: String) throws -> URLSessionWebSocketTask
  func invalidate()
}

extension CallGatewayServing {
  var eventFailure: String { "" }
  var eventDiagnostic: String { "" }
}

final class CallGatewayClient: NSObject, CallGatewayServing, URLSessionDataDelegate, URLSessionWebSocketDelegate {
  let configuration: CallGatewayConfiguration
  var onSnapshot: (([GatewayCallDevice]) -> Void)?
  var onEventStatus: ((String) -> Void)?
  var eventFailure: String { stream.failure }
  var eventDiagnostic: String { stream.failure.isEmpty ? "" : tlsDiagnostic.summary }
  private var tlsDiagnostic = CallTLSDiagnostic()
  private var session: URLSession!
  private var stream: CallEventStream!
  private var invalidated = false
  private var expiryTimer: Timer?
  private struct Pending {
    var data = Data()
    var response: HTTPURLResponse?
    let completion: (Result<[String: Any], Error>) -> Void
  }
  private var pending: [Int: Pending] = [:]
  convenience init(configuration: CallGatewayConfiguration) { self.init(configuration: configuration, sessionConfiguration: .ephemeral) }
  init(configuration: CallGatewayConfiguration, sessionConfiguration: URLSessionConfiguration) {
    self.configuration = configuration
    super.init()
    sessionConfiguration.httpCookieStorage = nil
    sessionConfiguration.urlCredentialStorage = nil
    sessionConfiguration.urlCache = nil
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
    sessionConfiguration.timeoutIntervalForRequest = 40
    sessionConfiguration.timeoutIntervalForResource = 7 * 24 * 3600
    session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
    stream = CallEventStream { [weak self] in
      guard let self else { throw CallGatewayFailure.cancelled }
      self.tlsDiagnostic = CallTLSDiagnostic(pinConfigured: self.configuration.certificateFingerprint != nil)
      var request = try self.request(path: ["api", "calls", "events"])
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
      return self.session.dataTask(with: request)
    }
    stream.onSnapshot = { [weak self] in self?.onSnapshot?($0) }
    stream.onStatus = { [weak self] in self?.onEventStatus?($0) }
    if let expiry = configuration.expiresAt {
      expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.001, expiry.timeIntervalSinceNow), repeats: false) { [weak self] _ in
        guard let self else { return }; self.invalidate(); self.onEventStatus?("unauthorized")
      }
    }
  }
  func startEvents() { guard !invalidated else { return }; stream.start() }
  func stopEvents() { stream.stop() }
  func invalidate() {
    guard !invalidated else { return }; invalidated = true
    expiryTimer?.invalidate(); expiryTimer = nil; stream.stop()
    let callbacks = pending.values.map(\.completion); pending.removeAll()
    session.invalidateAndCancel()
    for callback in callbacks { callback(.failure(CallGatewayFailure.cancelled)) }
  }
  private func request(path: [String], query: [URLQueryItem] = []) throws -> URLRequest {
    guard !invalidated else { throw CallGatewayFailure.cancelled }
    if let expiry = configuration.expiresAt, expiry <= Date() { throw CallGatewayFailure.unauthorized }
    var components = URLComponents(url: configuration.origin, resolvingAgainstBaseURL: false)!
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    components.percentEncodedPath = "/" + (try path.map { segment in
      guard !segment.isEmpty, segment.utf8.count <= 512, let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed) else { throw CallGatewayFailure.invalidRequest }; return encoded
    }).joined(separator: "/")
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw CallGatewayFailure.invalidRequest }
    var request = URLRequest(url: url)
    request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    return request
  }
  @discardableResult func performAction(deviceID: String, action: String, body: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask? {
    do {
      let expected: Set<String>
      switch action { case "dial": expected = ["number"]; case "answer", "hangup": expected = ["id"]; case "dtmf": expected = ["id", "digit"]; default: throw CallGatewayFailure.invalidRequest }
      guard Set(body.keys) == expected, body.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else { throw CallGatewayFailure.invalidRequest }
      if action == "dtmf", let digit = body["digit"], (digit.count != 1 || !"0123456789*#ABCD".contains(digit)) { throw CallGatewayFailure.invalidRequest }
      var req = try request(path: ["api", "devices", deviceID, "calls", action]); req.httpMethod = "POST"; req.timeoutInterval = 12
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
      return json(req, completion: completion)
    } catch { DispatchQueue.main.async { completion(.failure(error)) }; return nil }
  }
  @discardableResult func mediaMetadata(deviceID: String, callID: String, completion: @escaping (Result<CallMediaDescription, Error>) -> Void) -> URLSessionDataTask? {
    do {
      var req = try request(path: ["api", "devices", deviceID, "calls", "media"], query: [URLQueryItem(name: "id", value: callID)])
      req.timeoutInterval = 8
      return json(req) { result in
        completion(result.flatMap { value in
          guard let id = value["id"] as? String, id == callID,
            let codec = value["codec"] as? String,
            let format = value["format"] as? String, format == "pcm_s16le_8000_mono",
            let dtmf = callStrictBool(value["dtmf"]) else { return .failure(CallGatewayFailure.protocolViolation) }
          return .success(CallMediaDescription(id: id, codec: codec, format: format, dtmfSupported: dtmf))
        })
      }
    } catch { DispatchQueue.main.async { completion(.failure(error)) }; return nil }
  }
  func makeMediaSocket(deviceID: String, callID: String) throws -> URLSessionWebSocketTask {
    var req = try request(path: ["api", "devices", deviceID, "calls", "media"], query: [URLQueryItem(name: "id", value: callID)])
    var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
    url.scheme = url.scheme == "https" ? "wss" : "ws"; req.url = url.url; req.timeoutInterval = 8
    let task = session.webSocketTask(with: req); task.maximumMessageSize = 6400; return task
  }
  private func json(_ request: URLRequest, completion: @escaping (Result<[String: Any], Error>) -> Void) -> URLSessionDataTask {
    let task = session.dataTask(with: request); pending[task.taskIdentifier] = Pending(completion: completion); task.resume(); return task
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
    if stream.owns(dataTask) {
      tlsDiagnostic.httpStatus = http.statusCode
      completionHandler(stream.response(http) ? .allow : .cancel); return
    }
    guard pending[dataTask.taskIdentifier] != nil else { completionHandler(.cancel); return }
    if response.expectedContentLength > 1_048_576 { finish(dataTask, .failure(CallGatewayFailure.protocolViolation)); completionHandler(.cancel); return }
    pending[dataTask.taskIdentifier]?.response = http; completionHandler(.allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    if stream.owns(dataTask) { stream.receive(data); return }
    guard let value = pending[dataTask.taskIdentifier] else { return }
    guard value.data.count + data.count <= 1_048_576 else { finish(dataTask, .failure(CallGatewayFailure.protocolViolation)); dataTask.cancel(); return }
    pending[dataTask.taskIdentifier]?.data.append(data)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if stream.owns(task) {
      tlsDiagnostic.record(error)
      stream.complete(error); return
    }
    guard let value = pending[task.taskIdentifier] else { return }
    if let error { finish(task, .failure(Self.networkFailure(error))); return }
    guard let response = value.response else { finish(task, .failure(CallGatewayFailure.transport)); return }
    let object = (try? JSONSerialization.jsonObject(with: value.data)) as? [String: Any]
    guard (200...299).contains(response.statusCode) else {
      finish(task, .failure(Self.httpFailure(response.statusCode, object: object))); return
    }
    guard let object, let data = object["data"] as? [String: Any] else { finish(task, .failure(CallGatewayFailure.protocolViolation)); return }
    finish(task, .success(data))
  }
  private func finish(_ task: URLSessionTask, _ result: Result<[String: Any], Error>) {
    pending.removeValue(forKey: task.taskIdentifier)?.completion(result)
  }
  static func httpFailure(_ status: Int, object: [String: Any]?) -> CallGatewayFailure {
    let code = (object?["error"] as? [String: Any])?["code"] as? String ?? object?["error"] as? String ?? object?["code"] as? String
    if code == "dtmf_unavailable" { return .dtmfUnavailable }; if code == "call_media_busy" { return .mediaBusy }
    switch status { case 401, 403: return .unauthorized; case 404, 501, 204: return .unavailable; case 409: return .stateConflict; case 400, 422: return .invalidRequest; default: return .transport }
  }
  static func networkFailure(_ error: Error) -> CallGatewayFailure {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
      if ns.code == NSURLErrorCancelled { return .cancelled }
      if (-1206 ... -1200).contains(ns.code) { return .trust }
    }
    return .transport
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else { completionHandler(.performDefaultHandling, nil); return }
    tlsDiagnostic.stage = "origin"
    guard challenge.protectionSpace.host.lowercased() == configuration.origin.host?.lowercased(),
      challenge.protectionSpace.port == (configuration.origin.port ?? 443),
      let trust = challenge.protectionSpace.serverTrust else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "system_default"
    guard let pin = configuration.certificateFingerprint else { completionHandler(.performDefaultHandling, nil); return }
    tlsDiagnostic.stage = "leaf"
    guard let leaf = SecTrustGetCertificateAtIndex(trust, 0) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    let der = SecCertificateCopyData(leaf) as Data
    let actual = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    tlsDiagnostic.pinMatches = actual == pin
    tlsDiagnostic.stage = "pin"
    guard actual == pin else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "validity"
    guard CallCertificateValidity.containsNow(der) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "policy"
    let policy = SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, configuration.origin.host! as CFString))
    tlsDiagnostic.securityStatus = Int(policy)
    guard policy == errSecSuccess else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "anchor"
    let anchor = SecTrustSetAnchorCertificates(trust, [leaf] as CFArray)
    tlsDiagnostic.securityStatus = Int(anchor)
    guard anchor == errSecSuccess else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "anchor_only"
    let anchorOnly = SecTrustSetAnchorCertificatesOnly(trust, true)
    tlsDiagnostic.securityStatus = Int(anchorOnly)
    guard anchorOnly == errSecSuccess else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "apple_trust"
    var trustError: CFError?
    let accepted = SecTrustEvaluateWithError(trust, &trustError)
    tlsDiagnostic.trustCode = trustError.map { CFErrorGetCode($0) }
    guard accepted else { completionHandler(.cancelAuthenticationChallenge, nil); return }
    tlsDiagnostic.stage = "accepted"
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}

// Session trust callbacks carry no task ID. Label their stage separately from SSE completion.
// Only fixed labels, booleans and numeric codes cross into the UI; never serialize NSError.userInfo.
struct CallTLSDiagnostic {
  var pinConfigured = false
  var stage = "no_challenge"
  var pinMatches: Bool?
  var securityStatus: Int?
  var trustCode: Int?
  var httpStatus: Int?
  private(set) var networkCodes: [String] = []

  mutating func record(_ error: Error?) {
    networkCodes = []
    var current = error as NSError?
    for _ in 0..<4 {
      guard let value = current else { break }
      let domain: String
      switch value.domain {
      case NSURLErrorDomain: domain = "URL"
      case "kCFErrorDomainCFNetwork": domain = "CFNetwork"
      case NSOSStatusErrorDomain: domain = "OSStatus"
      case NSPOSIXErrorDomain: domain = "POSIX"
      default: domain = "other"
      }
      networkCodes.append("\(domain):\(value.code)")
      // CFNetwork can report the TLS cause as scalar stream codes rather than a nested NSError.
      func streamInteger(_ key: String) -> Int? {
        guard let number = value.userInfo[key] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let integer = number.intValue
        guard (-1_000_000...1_000_000).contains(integer),
          number.doubleValue == Double(integer) else { return nil }
        return integer
      }
      if let code = streamInteger("_kCFStreamErrorCodeKey") {
        let streamDomain = streamInteger("_kCFStreamErrorDomainKey")
        networkCodes[networkCodes.count - 1] += "[streamDomain=\(streamDomain.map(String.init) ?? "unknown") streamCode=\(code)]"
      }
      current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
  }

  var summary: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    var parts = ["TLS-D1 · OS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      "pinConfigured=\(pinConfigured) sessionStage=\(stage)"]
    if let pinMatches { parts.append("pinMatches=\(pinMatches)") }
    if let securityStatus { parts.append("securityStatus=\(securityStatus)") }
    if let trustCode { parts.append("trustCode=\(trustCode)") }
    if let httpStatus { parts.append("HTTP=\(httpStatus)") }
    if !networkCodes.isEmpty { parts.append("SSE " + networkCodes.joined(separator: " > ")) }
    return parts.joined(separator: "\n")
  }
}

/// Anchored leaf trust may exempt anchor expiry. Read X.509 validity explicitly as well.
enum CallCertificateValidity {
  static func containsNow(_ data: Data, now: Date = Date()) -> Bool {
    struct DER {
      let bytes: [UInt8]; var offset = 0
      mutating func next() -> (UInt8, [UInt8])? {
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]; offset += 1; var length = Int(bytes[offset]); offset += 1
        if length & 128 != 0 {
          let count = length & 127; guard (1...4).contains(count), offset + count <= bytes.count else { return nil }
          length = 0; for _ in 0..<count { length = length * 256 + Int(bytes[offset]); offset += 1 }
        }
        guard length <= bytes.count - offset else { return nil }
        let value = Array(bytes[offset..<(offset + length)]); offset += length; return (tag, value)
      }
    }
    var root = DER(bytes: Array(data)); guard let cert = root.next(), cert.0 == 0x30 else { return false }
    var certBody = DER(bytes: cert.1); guard let tbs = certBody.next(), tbs.0 == 0x30 else { return false }
    var body = DER(bytes: tbs.1); guard let first = body.next() else { return false }
    if first.0 == 0xa0 { guard body.next() != nil else { return false } }
    guard body.next() != nil, body.next() != nil, let validity = body.next(), validity.0 == 0x30 else { return false }
    var times = DER(bytes: validity.1)
    func date(_ value: (UInt8, [UInt8])?) -> Date? {
      guard let value, let text = String(bytes: value.1, encoding: .ascii), text.hasSuffix("Z") else { return nil }
      let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
      var normalized = text
      if value.0 == 0x17, text.count == 13, let year = Int(text.prefix(2)) { normalized = (year >= 50 ? "19" : "20") + text }
      else if value.0 != 0x18 || text.count != 15 { return nil }
      formatter.dateFormat = "yyyyMMddHHmmss'Z'"; return formatter.date(from: normalized)
    }
    guard let start = date(times.next()), let end = date(times.next()) else { return false }
    return start <= now && now <= end
  }
}
