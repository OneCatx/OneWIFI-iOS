import Foundation
import Security
import CryptoKit

// No credentials or call actions: only TLS and an unauthenticated SSE GET.
final class TLSProbe: NSObject, URLSessionDataDelegate {
  let origin: URL
  let expectedPin: String
  var finished = false
  var httpStatus: Int?
  var session: URLSession!

  init(origin: URL, pin: String) {
    self.origin = origin
    self.expectedPin = pin
    super.init()
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }

  func start() {
    var request = URLRequest(url: origin.appendingPathComponent("api/calls/events"))
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    session.dataTask(with: request).resume()
  }

  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    let space = challenge.protectionSpace
    guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
      completionHandler(.performDefaultHandling, nil); return
    }
    let hostMatches = space.host.lowercased() == origin.host?.lowercased()
    let portMatches = space.port == (origin.port ?? 443)
    print("challenge hostMatches=\(hostMatches) portMatches=\(portMatches) port=\(space.port)")
    guard hostMatches, portMatches, let trust = space.serverTrust,
          let leaf = SecTrustGetCertificateAtIndex(trust, 0) else {
      print("rejected=origin_or_missing_trust")
      completionHandler(.cancelAuthenticationChallenge, nil); return
    }
    let der = SecCertificateCopyData(leaf) as Data
    let actual = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    let pinMatches = actual == expectedPin
    // This type is extracted verbatim from the app source at build time.
    let validity = CallCertificateValidity.containsNow(der)
    let lifetime = CallCertificateValidity.withinPinnedLifetime(der)
    print("pinMatches=\(pinMatches) appValidity=\(validity) lifetimeOk=\(lifetime)")
    var pinnedTrust: SecTrust?
    let created = SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &pinnedTrust)
    guard created == errSecSuccess, let pinnedTrust else {
      print("policyStatus=\(created)")
      completionHandler(.cancelAuthenticationChallenge, nil); return
    }
    let anchor = SecTrustSetAnchorCertificates(pinnedTrust, [leaf] as CFArray)
    let anchorOnly = SecTrustSetAnchorCertificatesOnly(pinnedTrust, true)
    var error: CFError?
    let accepted = SecTrustEvaluateWithError(pinnedTrust, &error)
    print("policyStatus=\(created) anchorStatus=\(anchor) anchorOnlyStatus=\(anchorOnly) appleTrust=\(accepted) pinnedTrust=\(accepted)")
    if let error {
      // Numeric trust errors only; never dump request/session contents.
      print("trustErrorCode=\(CFErrorGetCode(error))")
    }
    guard pinMatches, validity, lifetime, anchor == errSecSuccess,
          anchorOnly == errSecSuccess, accepted else {
      completionHandler(.cancelAuthenticationChallenge, nil); return
    }
    completionHandler(.useCredential, URLCredential(trust: pinnedTrust))
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    print("redirectRejected=\(response.statusCode)")
    completionHandler(nil)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    httpStatus = (response as? HTTPURLResponse)?.statusCode
    print("httpStatus=\(httpStatus ?? 0)")
    completionHandler(.cancel)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error as NSError? {
      print("completionErrorCode=\(error.code)")
      var current: NSError? = error
      for _ in 0..<4 {
        guard let value = current else { break }
        if let code = value.userInfo["_kCFStreamErrorCodeKey"] as? NSNumber {
          print("streamErrorCode=\(code.intValue)")
        }
        current = value.userInfo[NSUnderlyingErrorKey] as? NSError
      }
    }
    finished = true
  }
}

let args = CommandLine.arguments
 guard args.count == 3, let origin = URL(string: args[1]), origin.scheme == "https",
       origin.user == nil, origin.password == nil,
       args[2].count == 64, args[2].allSatisfy({ "0123456789abcdef".contains($0) }) else {
  fatalError("Expected HTTPS origin and independently verified certificate SHA-256")
}
print("atsEmbedded=\(Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") != nil)")
let probe = TLSProbe(origin: origin, pin: args[2])
probe.start()
let deadline = Date().addingTimeInterval(25)
while !probe.finished && Date() < deadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
probe.session.invalidateAndCancel()
// 401 is expected without credentials and proves HTTP was reached through TLS.
if probe.httpStatus != 401 { exit(1) }