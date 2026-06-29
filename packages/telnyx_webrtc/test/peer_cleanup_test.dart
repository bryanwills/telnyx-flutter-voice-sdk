import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:telnyx_webrtc/tx_socket.dart';
import 'package:telnyx_webrtc/utils/stats/webrtc_stats_reporter.dart';

void main() {
  group('WebRTC stats cleanup', () {
    test('stop during startup prevents delayed timers from being created',
        () async {
      final socket = _FakeSocket();
      final peerConnection = _FakePeerConnection();
      final reporter = WebRTCStatsReporter(
        socket,
        peerConnection,
        'call-id',
        'peer-id',
        true,
        onCallQualityChange: (_) {},
      );

      final startup = reporter.startStatsReporting();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      reporter.stopStatsReporting();

      await startup;
      await Future<void>.delayed(
        const Duration(
          milliseconds: WebRTCStatsReporter.callQualityIntervalMs * 3,
        ),
      );

      expect(peerConnection.getStatsCallCount, 0);
      expect(
          socket.sentTypes,
          containsAll([
            'debug_report_start',
            'debug_report_stop',
          ]));
    });

    test('start and stop are idempotent', () async {
      final socket = _FakeSocket();
      final peerConnection = _FakePeerConnection();
      final reporter = WebRTCStatsReporter(
        socket,
        peerConnection,
        'call-id',
        'peer-id',
        true,
        onCallQualityChange: (_) {},
      );

      await reporter.startStatsReporting();
      await reporter.startStatsReporting();

      reporter
        ..stopStatsReporting()
        ..stopStatsReporting();

      expect(socket.countSentType('debug_report_start'), 1);
      expect(socket.countSentType('debug_report_stop'), 1);
    });
  });
}

class _FakeSocket extends TxSocket {
  _FakeSocket() : super('wss://example.test');

  final List<String> _sentMessages = [];

  List<String> get sentTypes => _sentMessages
      .map((message) => jsonDecode(message) as Map<String, dynamic>)
      .map((message) => message['type'] as String)
      .toList();

  int countSentType(String type) {
    return sentTypes.where((sentType) => sentType == type).length;
  }

  @override
  void send(dynamic data) {
    _sentMessages.add(data as String);
  }
}

class _FakePeerConnection extends RTCPeerConnection {
  int getStatsCallCount = 0;

  @override
  RTCSignalingState? get signalingState => null;

  @override
  RTCIceGatheringState? get iceGatheringState => null;

  @override
  RTCIceConnectionState? get iceConnectionState => null;

  @override
  RTCPeerConnectionState? get connectionState => null;

  @override
  Map<String, dynamic> get getConfiguration => {};

  @override
  Future<void> dispose() async {}

  @override
  Future<void> setConfiguration(Map<String, dynamic> configuration) async {}

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<void> addStream(MediaStream stream) async {}

  @override
  Future<void> removeStream(MediaStream stream) async {}

  @override
  Future<RTCSessionDescription?> getLocalDescription() async {
    return null;
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}

  @override
  Future<RTCSessionDescription?> getRemoteDescription() async {
    return null;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async {
    getStatsCallCount++;
    return [
      StatsReport('remote-inbound', 'remote-inbound-rtp', 0, {
        'kind': 'audio',
        'jitter': 0.01,
        'roundTripTime': 0.1,
      }),
    ];
  }

  @override
  List<MediaStream?> getLocalStreams() {
    return [];
  }

  @override
  List<MediaStream?> getRemoteStreams() {
    return [];
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit dataChannelDict,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> restartIce() async {}

  @override
  Future<void> close() async {}

  @override
  RTCDTMFSender createDtmfSender(MediaStreamTrack track) {
    throw UnimplementedError();
  }

  @override
  Future<List<RTCRtpSender>> getSenders() async {
    return [];
  }

  @override
  Future<List<RTCRtpReceiver>> getReceivers() async {
    return [];
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async {
    return [];
  }

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> removeTrack(RTCRtpSender sender) async {
    return true;
  }

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    throw UnimplementedError();
  }
}
