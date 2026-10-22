import AVFoundation
import Flutter
import Foundation

/// 8 kHz 单声道 s16le。下行播放，上行按 160 样本一帧回给 Dart。
final class CallAudioBridge: NSObject {
  static let channelName = "com.oneims.onewifi/call_audio"
  static let sampleRate = 8000.0

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var channel: FlutterMethodChannel?
  private var started = false
  private var tapInstalled = false
  private var playerAttached = false
  private var sessionActive = false
  private var generation = 0
  private var pendingStart: FlutterResult?
  private let requestPermission: (@escaping (Bool) -> Void) -> Void

  init(requestPermission: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
    AVAudioSession.sharedInstance().requestRecordPermission(completion)
  }) {
    self.requestPermission = requestPermission
    super.init()
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "gone", message: "audio bridge released", details: nil))
        return
      }
      switch call.method {
      case "start":
        self.start(result: result)
      case "stop":
        do {
          try self.stop()
          result(nil)
        } catch {
          result(FlutterError(code: "audio_stop", message: error.localizedDescription, details: nil))
        }
      case "play":
        if let data = call.arguments as? FlutterStandardTypedData {
          self.play(data.data)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func start(result: @escaping FlutterResult) {
    if started {
      result(nil)
      return
    }
    cancelPendingStart()
    let requestGeneration = generation
    pendingStart = result
    requestPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else { return }
        guard requestGeneration == self.generation, let result = self.pendingStart else { return }
        self.pendingStart = nil
        guard granted else {
          result(FlutterError(code: "mic_denied", message: "麦克风权限被拒绝", details: nil))
          return
        }
        do {
          try self.startEngine()
          result(nil)
        } catch {
          // Release any session/node/tap acquired before engine.start failed.
          // Preserve both errors if deactivation itself also fails.
          var message = error.localizedDescription
          do { try self.stopEngine() } catch {
            message += "; " + error.localizedDescription
          }
          result(FlutterError(code: "audio", message: message, details: nil))
        }
      }
    }
  }

  private func startEngine() throws {
    if started { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth, .defaultToSpeaker]
    )
    try session.setPreferredSampleRate(Self.sampleRate)
    try session.setActive(true)
    sessionActive = true

    let pcm = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Self.sampleRate,
      channels: 1,
      interleaved: true
    )!
    engine.attach(player)
    playerAttached = true
    engine.connect(player, to: engine.mainMixerNode, format: pcm)
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard let converter = AVAudioConverter(from: inputFormat, to: pcm) else {
      throw NSError(domain: Self.channelName, code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "无法创建音频格式转换器"])
    }
    let captureGeneration = generation
    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.capture(buffer, converter: converter, format: pcm, generation: captureGeneration)
    }
    tapInstalled = true
    try engine.start()
    player.play()
    started = true
  }

  private func play(_ data: Data) {
    guard started, let buffer = Self.pcmBuffer(data) else { return }
    player.scheduleBuffer(buffer)
  }

  /// A packet must contain complete s16le samples; never copy a trailing byte
  /// into a buffer whose capacity was rounded down.
  static func pcmBuffer(_ data: Data) -> AVAudioPCMBuffer? {
    guard !data.isEmpty, data.count % 2 == 0,
          let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate, channels: 1, interleaved: true) else { return nil }
    let frames = AVAudioFrameCount(data.count / 2)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
      return nil
    }
    buffer.frameLength = frames
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      memcpy(buffer.int16ChannelData![0], base, data.count)
    }
    return buffer
  }

  private func capture(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter,
                       format: AVAudioFormat, generation: Int) {
    let ratio = Self.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else {
      return
    }
    var error: NSError?
    var consumed = false
    converter.convert(to: output, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return buffer
    }
    if error != nil || output.frameLength == 0 { return }
    let count = Int(output.frameLength) * 2
    let bytes = Data(bytes: output.int16ChannelData![0], count: count)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.started, self.generation == generation else { return }
      self.channel?.invokeMethod("mic", arguments: FlutterStandardTypedData(bytes: bytes))
    }
  }

  private func cancelPendingStart() {
    generation += 1
    let pending = pendingStart
    pendingStart = nil
    pending?(FlutterError(code: "cancelled", message: "音频启动已取消", details: nil))
  }

  func stop() throws {
    cancelPendingStart()
    try stopEngine()
  }

  private func stopEngine() throws {
    started = false
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    if playerAttached { player.stop() }
    engine.stop()
    if playerAttached {
      engine.disconnectNodeOutput(player)
      engine.detach(player)
      playerAttached = false
    }
    if sessionActive {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      sessionActive = false
    }
  }
}
