import 'dart:async';
import 'dart:io';

import 'package:telnyx_webrtc/tx_socket_ping_metrics.dart';
import 'package:telnyx_webrtc/utils/logging/global_logger.dart';

/// Message callback for when a message is received
typedef OnMessageCallback = void Function(dynamic msg);

/// Close callback for when the connection is closed
typedef OnCloseCallback = void Function(int code, String reason);

/// Open callback for when the connection is opened
typedef OnOpenCallback = void Function();

/// TxSocket class to handle the WebSocket connection (dart:io implementation)
class TxSocket with TxSocketPingMetricsMixin {
  /// Default constructor that initializes the host address and logger
  TxSocket(this.hostAddress);

  String hostAddress;

  WebSocket? _socket;
  late OnOpenCallback onOpen;
  late OnMessageCallback onMessage;
  late OnCloseCallback onClose;
  int _connectGeneration = 0;

  /// Connect to the WebSocket server
  void connect() async {
    final generation = ++_connectGeneration;
    final openCallback = onOpen;
    final messageCallback = onMessage;
    final closeCallback = onClose;

    try {
      GlobalLogger().i('TxSocket :: connect : $hostAddress');

      final socket = await WebSocket.connect(hostAddress);
      if (!_isCurrentAttempt(generation)) {
        unawaited(socket.close());
        return;
      }

      _socket = socket;
      socket
        ..pingInterval = const Duration(seconds: 10)
        ..timeout(const Duration(seconds: 30));

      // Initialize connection tracking
      initializePingTracking();

      socket.listen(
        (dynamic data) {
          if (!_isActiveSocket(generation, socket)) return;

          // Check if this is a ping/pong message
          if (isPingMessage(data)) {
            handlePingReceived();
          }
          messageCallback.call(data);
        },
        onDone: () {
          if (!_isActiveSocket(generation, socket)) return;

          cleanPingIntervals();
          closeCallback.call(
            socket.closeCode ?? 0,
            socket.closeReason ?? 'Closed for unknown reason',
          );
          if (identical(_socket, socket)) {
            _socket = null;
          }
        },
      );

      openCallback.call();
      if (!_isActiveSocket(generation, socket)) {
        unawaited(socket.close());
        return;
      }

      // Emit initial calculating state
      emitInitialMetrics();
    } catch (e) {
      if (!_isCurrentAttempt(generation)) return;

      cleanPingIntervals();
      closeCallback.call(500, e.toString());
    }
  }

  /// Send data to the WebSocket server
  void send(dynamic data) {
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(data);
      GlobalLogger().i('TxSocket :: Send : ${data?.toString().trim()}');
    } else {
      GlobalLogger().d('WebSocket not connected, message $data not sent');
    }
  }

  /// Close the WebSocket connection
  void close() {
    _connectGeneration++;
    cleanPingIntervals();
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close());
    }
  }

  bool _isCurrentAttempt(int generation) {
    return generation == _connectGeneration;
  }

  bool _isActiveSocket(int generation, WebSocket socket) {
    return _isCurrentAttempt(generation) && identical(_socket, socket);
  }
}
