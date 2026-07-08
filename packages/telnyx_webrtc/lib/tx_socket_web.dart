// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:telnyx_webrtc/tx_socket_ping_metrics.dart';
import 'package:telnyx_webrtc/utils/logging/global_logger.dart';

/// Message callback for when a message is received
typedef OnMessageCallback = void Function(dynamic msg);

/// Close callback for when the connection is closed
typedef OnCloseCallback = void Function(int code, String reason);

/// Open callback for when the connection is opened
typedef OnOpenCallback = void Function();

/// TxSocket class to handle the WebSocket connection (dart:html implementation)
class TxSocket with TxSocketPingMetricsMixin {
  /// Default constructor that initializes the host address and logger
  TxSocket(this.hostAddress) {
    hostAddress = hostAddress.replaceAll('https:', 'wss:');
  }

  String hostAddress;

  WebSocket? _socket;
  late OnOpenCallback onOpen;
  late OnMessageCallback onMessage;
  late OnCloseCallback onClose;
  int _connectGeneration = 0;

  /// Connect to the WebSocket server
  void connect() {
    final generation = ++_connectGeneration;
    final openCallback = onOpen;
    final messageCallback = onMessage;
    final closeCallback = onClose;

    try {
      final socket = WebSocket(hostAddress);

      socket.onOpen.listen((e) {
        if (!_isCurrentAttempt(generation)) {
          socket.close();
          return;
        }

        _socket = socket;

        // Initialize connection tracking
        initializePingTracking();

        openCallback.call();
        if (_isActiveSocket(generation, socket)) {
          // Emit initial calculating state
          emitInitialMetrics();
        } else {
          socket.close();
        }
      });

      socket.onMessage.listen((e) {
        if (!_isActiveSocket(generation, socket)) return;

        // Check if this is a ping/pong message
        if (isPingMessage(e.data)) {
          handlePingReceived();
        }
        messageCallback.call(e.data);
      });

      socket.onClose.listen((e) {
        if (!_isActiveSocket(generation, socket)) return;

        cleanPingIntervals();
        closeCallback.call(
          e.code ?? 0,
          e.reason ?? 'Closed for unknown reason',
        );
        if (identical(_socket, socket)) {
          _socket = null;
        }
      });
    } catch (e) {
      if (!_isCurrentAttempt(generation)) return;

      cleanPingIntervals();
      closeCallback.call(500, e.toString());
    }
  }

  /// Send data to the WebSocket server
  void send(data) {
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.OPEN) {
      socket.send(data);
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
    socket?.close();
  }

  bool _isCurrentAttempt(int generation) {
    return generation == _connectGeneration;
  }

  bool _isActiveSocket(int generation, WebSocket socket) {
    return _isCurrentAttempt(generation) && identical(_socket, socket);
  }
}
