import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 8 kHz 单声道 s16le，和 WEB `callAudio.js` / 服务端 `pcmLittleEndian` 一致。
const int kCallSampleRate = 8000;
const int kCallFrameSamples = 160;

/// 把通话 WebSocket 上的 PCM 接到本机听筒，并把麦克风帧送回去。
abstract interface class CallHandset {
  Future<void> attach(WebSocket socket);

  void playDownlink(List<int> pcm);

  Future<void> detach();
}

final class ChannelCallHandset implements CallHandset {
  ChannelCallHandset({MethodChannel? channel})
    : channel =
          channel ?? const MethodChannel('com.oneims.onewifi/call_audio') {
    this.channel.setMethodCallHandler(_onNative);
  }

  final MethodChannel channel;
  WebSocket? _socket;
  final BytesBuilder _uplink = BytesBuilder(copy: false);
  int _generation = 0;

  Future<void> _onNative(MethodCall call) async {
    if (call.method != 'mic') return;
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    final chunk = call.arguments;
    if (chunk is! Uint8List || chunk.isEmpty) return;
    _uplink.add(chunk);
    final frameBytes = kCallFrameSamples * 2;
    while (_uplink.length >= frameBytes) {
      final pending = _uplink.takeBytes();
      socket.add(pending.sublist(0, frameBytes));
      if (pending.length > frameBytes) {
        _uplink.add(pending.sublist(frameBytes));
      }
    }
  }

  @override
  Future<void> attach(WebSocket socket) async {
    if (identical(_socket, socket)) return;
    final generation = ++_generation;
    _socket = null;
    _uplink.clear();
    await _stop();
    if (generation != _generation) return;
    await channel.invokeMethod<void>('start');
    if (generation != _generation) return;
    _socket = socket;
  }

  @override
  void playDownlink(List<int> pcm) {
    if (_socket == null || pcm.isEmpty) return;
    unawaited(channel.invokeMethod<void>('play', Uint8List.fromList(pcm)));
  }

  @override
  Future<void> detach() async {
    _generation += 1;
    _socket = null;
    _uplink.clear();
    await _stop();
  }

  Future<void> _stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // 桌面测试或尚未接原生通道时，信令通话仍可用。
    }
  }
}

final class SilentCallHandset implements CallHandset {
  @override
  Future<void> attach(WebSocket socket) async {}

  @override
  void playDownlink(List<int> pcm) {}

  @override
  Future<void> detach() async {}
}

List<int>? pcmPayload(Object? event) {
  if (event is Uint8List) return event;
  if (event is List<int>) return event;
  if (event is ByteBuffer) return event.asUint8List();
  return null;
}
