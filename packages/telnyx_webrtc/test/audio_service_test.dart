import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:telnyx_webrtc/call.dart';
import 'package:telnyx_webrtc/model/call_state.dart';
import 'package:telnyx_webrtc/model/network_reason.dart';
import 'package:telnyx_webrtc/telnyx_client.dart';
import 'package:telnyx_webrtc/tx_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopAudio stops without disposing the reusable player', () async {
    final playback = FakeAudioPlayback();
    final service = AudioService(playbackFactory: () => playback);

    await service.playLocalFile('assets/audio/ringtone.wav');
    await service.stopAudio();
    await service.playLocalFile('assets/audio/ringback.wav');

    expect(playback.assets, [
      'assets/audio/ringtone.wav',
      'assets/audio/ringback.wav',
    ]);
    expect(playback.stopCalls, 1);
    expect(playback.disposeCalls, 0);
    expect(playback.playCalls, 2);
  });

  test('stopAudio cancels an in-flight playLocalFile', () async {
    final setAssetCompleter = Completer<void>();
    final playback = FakeAudioPlayback(
      setAssetCompleter: setAssetCompleter,
    );
    final service = AudioService(playbackFactory: () => playback);

    final playFuture = service.playLocalFile('assets/audio/ringtone.wav');
    await pumpEventQueue();

    await service.stopAudio();
    setAssetCompleter.complete();
    await playFuture;

    expect(playback.assets, ['assets/audio/ringtone.wav']);
    expect(playback.stopCalls, 1);
    expect(playback.setLoopModeCalls, 0);
    expect(playback.playCalls, 0);
  });

  test('playLocalFile recreates playback after explicit dispose', () async {
    final playbacks = <FakeAudioPlayback>[];
    final service = AudioService(
      playbackFactory: () {
        final playback = FakeAudioPlayback();
        playbacks.add(playback);
        return playback;
      },
    );

    await service.playLocalFile('assets/audio/ringtone.wav');
    await service.dispose();
    await service.playLocalFile('assets/audio/ringback.wav');

    expect(playbacks, hasLength(2));
    expect(playbacks.first.disposeCalls, 1);
    expect(playbacks.last.assets, ['assets/audio/ringback.wav']);
  });

  test('Call.stopAudio does not allocate audio service', () {
    final call = _createCall()..stopAudio();

    expect(call.hasAudioService, isFalse);
  });

  test('terminal dropped call state disposes audio service once', () async {
    final playback = FakeAudioPlayback();
    final service = AudioService(playbackFactory: () => playback);
    final call = _createCall(audioService: service)
      ..playAudio('assets/audio/ringback.wav');
    await pumpEventQueue();

    call.callHandler
      ..changeState(
        CallState.dropped.withNetworkReason(NetworkReason.networkLost),
      )
      ..changeState(
        CallState.dropped.withNetworkReason(NetworkReason.networkLost),
      );
    await pumpEventQueue();

    expect(playback.disposeCalls, 1);
    expect(call.hasAudioService, isFalse);
  });

  test('terminal call state disposes audio service once', () async {
    final playback = FakeAudioPlayback();
    final service = AudioService(playbackFactory: () => playback);
    final call = _createCall(audioService: service)
      ..playAudio('assets/audio/ringback.wav');
    await pumpEventQueue();

    call.callHandler
      ..changeState(CallState.done)
      ..changeState(CallState.done);
    await pumpEventQueue();

    expect(playback.disposeCalls, 1);
    expect(call.hasAudioService, isFalse);
  });
}

Call _createCall({AudioService? audioService}) {
  final handler = CallHandler((_) {}, null);
  final call = Call(
    FakeTxSocket(),
    TelnyxClient(),
    'session-id',
    'assets/audio/ringtone.wav',
    'assets/audio/ringback.wav',
    handler,
    () {},
    false,
    audioService: audioService,
  )..callState = CallState.active;
  handler.call = call;
  return call;
}

class FakeAudioPlayback implements AudioPlayback {
  FakeAudioPlayback({this.setAssetCompleter});

  final Completer<void>? setAssetCompleter;
  final List<String> assets = <String>[];
  int playCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  int setLoopModeCalls = 0;
  bool disposed = false;

  @override
  Future<void> setAsset(String filePath) async {
    if (disposed) {
      throw StateError('playback is disposed');
    }

    assets.add(filePath);
    await setAssetCompleter?.future;
  }

  @override
  Future<void> setLoopMode(LoopMode loopMode) async {
    if (disposed) {
      throw StateError('playback is disposed');
    }

    setLoopModeCalls += 1;
  }

  @override
  Future<void> play() async {
    if (disposed) {
      throw StateError('playback is disposed');
    }

    playCalls += 1;
  }

  @override
  Future<void> stop() async {
    if (disposed) {
      throw StateError('playback is disposed');
    }

    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    disposed = true;
  }
}

class FakeTxSocket extends TxSocket {
  FakeTxSocket() : super('wss://example.test');

  final sentMessages = <dynamic>[];

  @override
  void connect() {}

  @override
  void close() {}

  @override
  void send(dynamic data) {
    sentMessages.add(data);
  }
}
