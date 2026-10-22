import Foundation
import AVFoundation

protocol CallPCMTransporting: AnyObject {
  var onChange: (() -> Void)? { get set }
  var onFailure: ((String) -> Void)? { get set }
  var snapshot: [String: Any] { get }
  func start()
  func setSystemAudioActive(_ active: Bool)
  func setCaptureEnabled(_ enabled: Bool)
  func setMuted(_ muted: Bool)
  func setRoute(_ endpoint: String) throws
  func stop()
}

/// External boundaries; all callbacks are main-thread except onCapture (audio render thread).
/// The transport below remains the only lifecycle/ownership/queue state machine.
protocol CallMediaSocket: AnyObject {
  var response: URLResponse? { get }
  func resume()
  func cancel()
  func receive(_ completion: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
  func ping(_ completion: @escaping (Error?) -> Void)
  func send(_ data: Data, completion: @escaping (Error?) -> Void)
}
protocol CallAudioDevice: AnyObject {
  var onCapture: ((Result<Data, Error>) -> Void)? { get set }
  var onRouteChange: (() -> Void)? { get set }
  var onInterruption: (() -> Void)? { get set }
  var endpoint: String { get }
  var endpoints: [[String: String]] { get }
  func start() throws
  func stop()
  func setCaptureEnabled(_ enabled: Bool) throws
  func setRoute(_ endpoint: String) throws
  func play(_ data: Data, completion: @escaping () -> Void) throws
}
protocol CallMediaCancellation: AnyObject { func cancel() }
protocol CallMediaClock: AnyObject {
  var now: Date { get }
  func schedule(_ interval: TimeInterval, _ callback: @escaping () -> Void) -> CallMediaCancellation
}

/// Value buffer shared with tests. The owner serializes capture access using captureLock.
struct CallPCMFrames {
  private var partial = Data()
  private var capture: [Data] = []
  private var playback: [Data] = []
  private var muted = false
  // Keep the original latency ceiling; overflow sheds old speech instead of ending the call.
  static let captureLimit = 19 // Plus one in-flight WebSocket frame.
  static let playbackLimit = 22 // Plus three frames scheduled on the player.
  private(set) var captureDropped = 0
  private(set) var playbackDropped = 0
  var captureCount: Int { capture.count }
  var playbackCount: Int { playback.count }
  mutating func clearPlayback() { playback.removeAll(keepingCapacity: true) }
  mutating func clearCapture() { partial.removeAll(keepingCapacity: true); capture.removeAll(keepingCapacity: true) }
  mutating func setMuted(_ value: Bool) { muted = value; clearCapture() }
  mutating func appendCapture(_ bytes: Data) throws {
    guard bytes.count <= 6400, bytes.count % 2 == 0 else { throw CallGatewayFailure.protocolViolation }
    partial.append(muted ? Data(repeating: 0, count: bytes.count) : bytes)
    while partial.count >= 320 {
      if capture.count == Self.captureLimit { capture.removeFirst(); captureDropped += 1 }
      capture.append(Data(partial.prefix(320))); partial.removeFirst(320)
    }
  }
  mutating func popCapture() -> Data? { capture.isEmpty ? nil : capture.removeFirst() }
  mutating func appendPlayback(_ bytes: Data) throws {
    guard !bytes.isEmpty, bytes.count <= 6400, bytes.count % 2 == 0 else { throw CallGatewayFailure.protocolViolation }
    for offset in stride(from: 0, to: bytes.count, by: 320) {
      if playback.count == Self.playbackLimit { playback.removeFirst(); playbackDropped += 1 }
      playback.append(bytes.subdata(in: offset..<min(offset + 320, bytes.count)))
    }
  }
  mutating func popPlayback() -> Data? { playback.isEmpty ? nil : playback.removeFirst() }
}

final class CallPCMTransport: NSObject, CallPCMTransporting {
  var onChange: (() -> Void)?
  var onFailure: ((String) -> Void)?
  private let gateway: CallGatewayServing
  private let call: GatewayCall
  private let audio: CallAudioDevice
  private let clock: CallMediaClock
  private let socketFactory: () throws -> CallMediaSocket
  private let captureLock = NSLock()
  private var frames = CallPCMFrames()
  private var captureAccepting = false
  private var captureFault: String?
  private var metadataTask: URLSessionDataTask?
  private var socket: CallMediaSocket?
  private var timer: CallMediaCancellation?
  private var epoch = 0
  private var hardwareEpoch = 0
  private var started = false
  private var failed = false
  private var socketReady = false
  private var systemActive = false
  private var captureEnabled = false
  private var muted = false
  private var hardware = false
  private var hardwareStarting = false
  private var hardwarePendingSince: Date?
  private var hardwareAttempts = 0
  private var dtmfSupported = false
  private var sending = false
  private var scheduled = 0
  private var playbackFrames = CallPCMFrames()
  private var playbackProgressAt: Date?
  private var failureDiagnostic = ""
  private var sentFrames = 0
  private var receivedFrames = 0
  private var lastNotify = Date.distantPast
  private var lastPing = Date.distantPast
  private var pingPendingSince: Date?
  private var sendPendingSince: Date?
  private var openedAt = Date.distantPast

  convenience init(gateway: CallGatewayServing, call: GatewayCall) {
    self.init(gateway: gateway, call: call, audio: CallNativeAudioDevice(), clock: CallSystemMediaClock(), socketFactory: {
      try gateway.makeMediaSocket(deviceID: call.deviceID, callID: call.id)
    })
  }
  init(gateway: CallGatewayServing, call: GatewayCall, audio: CallAudioDevice, clock: CallMediaClock,
       socketFactory: @escaping () throws -> CallMediaSocket) {
    self.gateway = gateway; self.call = call; self.audio = audio; self.clock = clock; self.socketFactory = socketFactory
    super.init()
    audio.onCapture = { [weak self] result in
      guard let self else { return }
      self.captureLock.lock(); defer { self.captureLock.unlock() }
      guard self.captureAccepting else { return }
      do { try self.frames.appendCapture(result.get()) }
      catch { self.captureFault = self.captureFault ?? (error as? CallAudioFailure)?.rawValue ?? "call_audio_capture_invalid" }
    }
    audio.onRouteChange = { [weak self] in
      guard let self, self.started else { return }; self.rebuildHardware(); self.onChange?()
    }
    audio.onInterruption = { [weak self] in self?.setSystemAudioActive(false) }
  }
  var snapshot: [String: Any] {
    captureLock.lock(); let queued = frames.captureCount; let dropped = frames.captureDropped; captureLock.unlock()
    return ["audioReady": socketReady && hardware, "dtmfSupported": dtmfSupported,
     "sentFrames": sentFrames, "receivedFrames": receivedFrames,
     "captureQueued": queued, "captureDropped": dropped,
     "playbackQueued": playbackFrames.playbackCount + scheduled, "playbackDropped": playbackFrames.playbackDropped,
     "audioDiagnostic": failureDiagnostic,
     "endpoint": audio.endpoint, "endpoints": audio.endpoints]
  }
  func start() {
    guard !started else { return }; started = true; failed = false; epoch += 1
    let generation = epoch
    metadataTask = gateway.mediaMetadata(deviceID: call.deviceID, callID: call.id) { [weak self] result in
      guard let self, self.started, self.epoch == generation else { return }
      self.metadataTask = nil
      switch result {
      case .failure(let error): self.fail(callFailureCode(error))
      case .success(let media):
        self.dtmfSupported = media.dtmfSupported
        do {
          let socket = try self.socketFactory()
          self.socket = socket; self.openedAt = self.clock.now; socket.resume()
          self.receive(generation: generation)
          guard self.started, self.epoch == generation else { return }
          self.timer = self.clock.schedule(0.02) { [weak self] in self?.tick() }
          self.ping(generation: generation)
        } catch { self.fail(callFailureCode(error)) }
      }
    }
  }
  func setSystemAudioActive(_ active: Bool) {
    systemActive = active
    if active { updateHardware() } else { stopHardware() }
    onChange?()
  }
  func setCaptureEnabled(_ enabled: Bool) {
    guard captureEnabled != enabled else { return }; captureEnabled = enabled
    updateCapture(); onChange?()
  }
  func setMuted(_ value: Bool) {
    muted = value
    captureLock.lock(); captureAccepting = false; frames.setMuted(value); captureLock.unlock()
    updateCapture(); onChange?()
  }
  func setRoute(_ endpoint: String) throws {
    guard started, systemActive else { throw CallGatewayFailure.stateConflict }
    try audio.setRoute(endpoint); onChange?() // Snapshot reads currentRoute, not requested route.
  }
  func stop() {
    guard started else { return }; started = false; epoch += 1
    metadataTask?.cancel(); metadataTask = nil; timer?.cancel(); timer = nil
    socket?.cancel(); socket = nil; socketReady = false
    stopHardware(); sending = false; pingPendingSince = nil; sendPendingSince = nil
    onChange?()
  }
  private func fail(_ code: String) {
    guard started, !failed else { return }; failed = true
    captureLock.lock(); let queued = frames.captureCount; let dropped = frames.captureDropped; captureLock.unlock()
    failureDiagnostic = "AUDIO-D1 txQueued=\(queued) txDropped=\(dropped) rxQueued=\(playbackFrames.playbackCount + scheduled) rxDropped=\(playbackFrames.playbackDropped) sent=\(sentFrames) received=\(receivedFrames)"
    stop(); onFailure?(code)
  }
  /// Handshake status is authoritative for this media endpoint. All WS failures use this path.
  private func failSocket(_ error: Error) {
    if let response = socket?.response as? HTTPURLResponse, response.statusCode != 101 {
      if response.statusCode == 409 { fail(CallGatewayFailure.mediaBusy.code) }
      else { fail(CallGatewayClient.httpFailure(response.statusCode, object: nil).code) }
    } else { fail(CallGatewayClient.networkFailure(error).code) }
  }
  private func receive(generation: Int) {
    socket?.receive { [weak self] result in
      guard let self, self.started, self.epoch == generation else { return }
      switch result {
      case .failure(let error): self.failSocket(error)
      case .success(let message):
        guard case .data(let bytes) = message else { self.fail("call_audio_invalid_frame"); return }
        guard !bytes.isEmpty, bytes.count <= 6400, bytes.count % 2 == 0 else {
          self.fail("call_audio_invalid_frame"); return
        }
        do {
          // Keep only a small render window in AVAudioPlayerNode so stale queued speech can be shed.
          if self.hardware {
            try self.playbackFrames.appendPlayback(bytes)
            try self.pumpPlayback(generation: generation)
          }
          self.receivedFrames += (bytes.count + 319) / 320; self.notifyCounters()
          guard self.started, self.epoch == generation else { return }
          self.receive(generation: generation)
        } catch { self.fail("call_audio_playback") }
      }
    }
  }
  private func ping(generation: Int) {
    guard let socket, pingPendingSince == nil else { return }
    lastPing = clock.now; pingPendingSince = lastPing
    socket.ping { [weak self] error in
      guard let self, self.started, self.epoch == generation else { return }
      self.pingPendingSince = nil
      if let error { self.failSocket(error); return }
      if !self.socketReady { self.socketReady = true; self.updateHardware(); self.onChange?() }
    }
  }
  private func tick() {
    guard started else { return }
    let now = clock.now
    if (!socketReady && now.timeIntervalSince(openedAt) > 8) || (pingPendingSince.map { now.timeIntervalSince($0) > 8 } ?? false) {
      failSocket(URLError(.timedOut)); return
    }
    if sendPendingSince.map({ now.timeIntervalSince($0) > 2 }) ?? false {
      fail("call_audio_send_stalled"); return
    }
    if hardware, scheduled > 0, playbackProgressAt.map({ now.timeIntervalSince($0) > 2 }) ?? false {
      fail("call_audio_playback_stalled"); return
    }
    if hardwarePendingSince.map({ now.timeIntervalSince($0) > 5 }) ?? false {
      fail("call_audio_input_unavailable"); return
    }
    if now.timeIntervalSince(lastPing) > 15 { ping(generation: epoch) }
    updateHardware()
    pumpCapture(allowSilence: true)
  }
  private func pumpCapture(allowSilence: Bool = false) {
    captureLock.lock(); let fault = captureFault; captureLock.unlock()
    if let fault { fail(fault); return }
    guard started, socketReady, hardware, captureEnabled, !sending, let socket else { return }
    // Silence is timer-paced; completion-driven draining must never synthesize an unbounded stream.
    guard !muted || allowSilence else { return }
    captureLock.lock(); let bytes = muted ? Data(repeating: 0, count: 320) : frames.popCapture(); captureLock.unlock()
    guard let bytes else { return }
    sending = true; sendPendingSince = clock.now; let generation = epoch
    socket.send(bytes) { [weak self] error in
      guard let self, self.started, self.epoch == generation else { return }
      self.sending = false; self.sendPendingSince = nil
      if let error { self.failSocket(error) }
      else {
        self.sentFrames += 1; self.notifyCounters()
        // A late timer tick or send completion must not permanently reduce the 50 fps throughput.
        self.pumpCapture()
      }
    }
  }
  private func notifyCounters() {
    guard clock.now.timeIntervalSince(lastNotify) >= 0.25 else { return }; lastNotify = clock.now; onChange?()
  }
  private func updateHardware() {
    guard started, systemActive, socketReady, !hardware, !hardwareStarting else { return }
    let generation = epoch
    hardwareStarting = true; defer { hardwareStarting = false }
    do {
      try audio.start()
      guard started, systemActive, epoch == generation else { audio.stop(); return }
      hardware = true; hardwarePendingSince = nil; hardwareAttempts = 0; updateCapture()
    } catch CallAudioFailure.inputUnavailable {
      // The first CallKit activation can report a zero input format before the route settles.
      hardwareAttempts += 1
      if hardwarePendingSince == nil { hardwarePendingSince = clock.now }
      guard hardwareAttempts < 25, clock.now.timeIntervalSince(hardwarePendingSince ?? clock.now) <= 5 else {
        fail("call_audio_input_unavailable"); return
      }
    } catch { fail((error as? CallAudioFailure)?.rawValue ?? "call_audio_hardware") }
  }
  private func updateCapture() {
    captureLock.lock(); captureAccepting = false; frames.clearCapture(); captureLock.unlock()
    let enabled = started && hardware && systemActive && captureEnabled && !muted
    do {
      try audio.setCaptureEnabled(enabled)
      captureLock.lock(); captureAccepting = enabled; captureLock.unlock()
    } catch { fail((error as? CallAudioFailure)?.rawValue ?? "call_audio_capture") }
  }
  private func pumpPlayback(generation: Int) throws {
    while started, hardware, epoch == generation, scheduled < 3, let bytes = playbackFrames.popPlayback() {
      if scheduled == 0 { playbackProgressAt = clock.now }
      scheduled += 1; let audioGeneration = hardwareEpoch
      try audio.play(bytes) { [weak self] in
        guard let self, self.started, self.epoch == generation, self.hardwareEpoch == audioGeneration else { return }
        self.scheduled = max(0, self.scheduled - 1)
        self.playbackProgressAt = self.scheduled == 0 ? nil : self.clock.now
        do { try self.pumpPlayback(generation: generation) }
        catch { self.fail("call_audio_playback") }
      }
    }
  }
  private func rebuildHardware() { guard hardware else { updateHardware(); return }; stopHardware(); updateHardware() }
  private func stopHardware() {
    hardwareEpoch += 1
    captureLock.lock(); captureAccepting = false; frames.clearCapture(); captureFault = nil; captureLock.unlock()
    audio.stop(); hardware = false; scheduled = 0
    hardwarePendingSince = nil; hardwareAttempts = 0
    playbackFrames.clearPlayback(); playbackProgressAt = nil
  }
}

final class CallURLSessionSocket: CallMediaSocket {
  private let task: URLSessionWebSocketTask
  init(_ task: URLSessionWebSocketTask) { self.task = task }
  var response: URLResponse? { task.response }
  func resume() { task.resume() }
  func cancel() { task.cancel(with: .normalClosure, reason: nil) }
  func receive(_ completion: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
    task.receive { result in DispatchQueue.main.async { completion(result) } }
  }
  func ping(_ completion: @escaping (Error?) -> Void) {
    task.sendPing { error in DispatchQueue.main.async { completion(error) } }
  }
  func send(_ data: Data, completion: @escaping (Error?) -> Void) {
    task.send(.data(data)) { error in DispatchQueue.main.async { completion(error) } }
  }
}
private final class CallSystemMediaClock: CallMediaClock {
  var now: Date { Date() }
  func schedule(_ interval: TimeInterval, _ callback: @escaping () -> Void) -> CallMediaCancellation {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in callback() }
    RunLoop.main.add(timer, forMode: .common); return CallTimerCancellation(timer)
  }
}
private final class CallTimerCancellation: CallMediaCancellation {
  private let timer: Timer
  init(_ timer: Timer) { self.timer = timer }
  func cancel() { timer.invalidate() }
  deinit { timer.invalidate() }
}

/// iOS 26 replaced `allowBluetooth` with `allowBluetoothHFP`; older SDKs only
/// know the former, so keep the routing option behind one availability switch.
enum CallAudioOptions {
  static var bluetooth: AVAudioSession.CategoryOptions {
    if #available(iOS 26.0, *) { return .allowBluetoothHFP }
    return .allowBluetooth
  }
}

/// `AVAudioApplication` took over the record permission in iOS 17; the session
/// keeps the pre-17 answer so the 16.2 deployment target still builds.
enum CallMicrophonePermission {
  static var isGranted: Bool {
    if #available(iOS 17.0, *) { return AVAudioApplication.shared.recordPermission == .granted }
    return AVAudioSession.sharedInstance().recordPermission == .granted
  }

  static func request(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: completion)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(completion)
    }
  }
}

enum CallAudioFailure: String, Error {
  case permission = "call_audio_permission"
  case inputUnavailable = "call_audio_input_unavailable"
  case inputFormat = "call_audio_input_format"
  case converterUnavailable = "call_audio_converter_unavailable"
  case conversion = "call_audio_conversion"
  case captureNotReady = "call_audio_capture_not_ready"
}

/// Same real converter is used by the device tap and synthetic-PCM XCTest (no microphone needed).
final class CallCaptureConverter {
  private let converter: AVAudioConverter
  private let format: AVAudioFormat
  init(inputFormat: AVAudioFormat) throws {
    guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw CallAudioFailure.inputFormat
    }
    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: true),
      let converter = AVAudioConverter(from: inputFormat, to: format) else { throw CallAudioFailure.converterUnavailable }
    self.format = format; self.converter = converter
    converter.primeMethod = .none
  }
  func reset() { converter.reset() }
  func convert(_ input: AVAudioPCMBuffer) throws -> Data {
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 8000 / input.format.sampleRate)) + 32
    guard capacity <= 3200, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else { throw CallGatewayFailure.protocolViolation }
    var consumed = false; var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, status in
      if consumed { status.pointee = .noDataNow; return nil }
      consumed = true; status.pointee = .haveData; return input
    }
    guard error == nil, status != .error, let samples = output.int16ChannelData else { throw CallAudioFailure.conversion }
    return Data(bytes: samples[0], count: Int(output.frameLength) * 2)
  }
}

private final class CallNativeAudioDevice: CallAudioDevice {
  var onCapture: ((Result<Data, Error>) -> Void)?
  var onRouteChange: (() -> Void)?
  var onInterruption: (() -> Void)?
  private let session = AVAudioSession.sharedInstance()
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
  private let captureLock = NSLock()
  private var captureEnabled = false
  private var captureConverter: CallCaptureConverter?
  private var tap = false
  private var attached = false
  private var observers: [NSObjectProtocol] = []
  private func observe() {
    guard observers.isEmpty else { return }
    observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in self?.onRouteChange?() })
    observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
      guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        raw == AVAudioSession.InterruptionType.began.rawValue else { return }; self?.onInterruption?()
    })
    observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
      guard let self, self.attached, !self.engine.isRunning else { return }; self.onRouteChange?()
    })
  }
  deinit { stop() }
  var endpoint: String {
    guard let port = session.currentRoute.outputs.first else { return "receiver" }
    if port.portType == .builtInSpeaker { return "speaker" }
    if port.portType == .builtInReceiver { return "receiver" }
    if let input = session.currentRoute.inputs.first, input.portType != .builtInMic { return input.uid }
    return port.uid
  }
  var endpoints: [[String: String]] {
    var values = [["id": "receiver", "name": "听筒"], ["id": "speaker", "name": "扬声器"]]
    for port in session.availableInputs ?? [] where port.portType != .builtInMic { values.append(["id": port.uid, "name": port.portName]) }
    return values
  }
  func start() throws {
    observe()
    // Never activate the session here: activation belongs exclusively to CallKit.
    let bluetooth = CallAudioOptions.bluetooth
    if session.category != .playAndRecord || session.mode != .voiceChat || session.categoryOptions != [bluetooth] {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [bluetooth])
    }
    guard CallMicrophonePermission.isGranted else { throw CallAudioFailure.permission }
    // The wire format is 8 kHz, not a requirement on the current microphone hardware.
    // CallKit can activate the session before either input bus reports a real format.
    let input = engine.inputNode
    let hardwareFormat = input.inputFormat(forBus: 0)
    let outputFormat = input.outputFormat(forBus: 0)
    guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
      outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else { throw CallAudioFailure.inputUnavailable }
    let converter = try CallCaptureConverter(inputFormat: outputFormat)
    captureLock.lock(); captureEnabled = false; captureConverter = converter; captureLock.unlock()
    // Configure both I/O directions before starting. Enabling capture later only opens the data gate.
    input.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] buffer, _ in
      guard let self else { return }
      self.captureLock.lock(); defer { self.captureLock.unlock() }
      guard self.captureEnabled, let converter = self.captureConverter else { return }
      self.onCapture?(Result { try converter.convert(buffer) })
    }
    tap = true
    engine.attach(player); attached = true; engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.prepare(); try engine.start(); player.play()
  }
  func setCaptureEnabled(_ enabled: Bool) throws {
    captureLock.lock(); defer { captureLock.unlock() }
    guard captureEnabled != enabled else { return }
    captureEnabled = false
    // Discard converter history across mute/early-media boundaries as well as queued PCM.
    captureConverter?.reset()
    guard enabled else { return }
    guard CallMicrophonePermission.isGranted else { throw CallAudioFailure.permission }
    guard attached, tap, engine.isRunning, captureConverter != nil else { throw CallAudioFailure.captureNotReady }
    captureEnabled = true
  }
  func stop() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers.removeAll()
    captureLock.lock(); captureEnabled = false; captureConverter = nil; captureLock.unlock()
    if tap { engine.inputNode.removeTap(onBus: 0); tap = false }
    player.stop(); engine.stop()
    if attached { engine.disconnectNodeOutput(player); engine.detach(player); attached = false }
  }
  func setRoute(_ endpoint: String) throws {
    if endpoint == "speaker" { try session.setPreferredInput(nil); try session.overrideOutputAudioPort(.speaker) }
    else if endpoint == "receiver" {
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(session.availableInputs?.first(where: { $0.portType == .builtInMic }))
    } else {
      guard let port = session.availableInputs?.first(where: { $0.uid == endpoint }) else { throw CallGatewayFailure.invalidRequest }
      try session.overrideOutputAudioPort(.none); try session.setPreferredInput(port)
    }
  }
  func play(_ data: Data, completion: @escaping () -> Void) throws {
    guard !data.isEmpty, data.count <= 320, data.count % 2 == 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
      let samples = buffer.floatChannelData else { throw CallGatewayFailure.protocolViolation }
    buffer.frameLength = buffer.frameCapacity; let raw = [UInt8](data)
    for index in 0..<Int(buffer.frameLength) {
      let bits = UInt16(raw[index * 2]) | UInt16(raw[index * 2 + 1]) << 8
      samples[0][index] = Float(Int16(bitPattern: bits)) / 32768.0
    }
    // Refill when rendered, not after device/Bluetooth output latency has elapsed.
    player.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { _ in DispatchQueue.main.async { completion() } }
  }
}
