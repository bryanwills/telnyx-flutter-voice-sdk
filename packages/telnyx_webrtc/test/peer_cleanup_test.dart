import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Peer cleanup', () {
    final peerSource = File('lib/peer/peer.dart').readAsStringSync();

    test('native cleanSessions stops timers and stats collectors', () {
      final body = _methodBody(peerSource, 'Future<void> _cleanSessions()');

      expect(body, contains('_stopNegotiationTimer();'));
      expect(body, contains('_stopTrickleIceTimer();'));
      expect(body, contains('_statsManager?.stopStatsReporting();'));
      expect(body, contains('await _callReportCollector?.stop();'));
      expect(body, contains('for (final sess in _sessions.values)'));
      expect(body, contains('await sess.peerConnection?.dispose();'));
    });

    test('native closeSession cancels pending ICE timers on hangup', () {
      final body = _methodBody(peerSource, 'Future<void> _closeSession(');

      expect(body, contains('_stopNegotiationTimer();'));
      expect(body, contains('_stopTrickleIceTimer();'));
      expect(body, contains('await stopStats(session.sid);'));
    });
  });
}

String _methodBody(String source, String signaturePrefix) {
  final signatureIndex = source.indexOf(signaturePrefix);
  expect(signatureIndex, isNot(equals(-1)));

  final openBraceIndex = source.indexOf('{', signatureIndex);
  expect(openBraceIndex, isNot(equals(-1)));

  var depth = 0;
  for (var index = openBraceIndex; index < source.length; index++) {
    final character = source[index];
    if (character == '{') {
      depth++;
    } else if (character == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBraceIndex + 1, index);
      }
    }
  }

  fail('Could not find method body for $signaturePrefix');
}
