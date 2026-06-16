import 'dart:async';

import 'package:telnyx_webrtc/call.dart';
import 'package:telnyx_webrtc/model/call_state.dart';
import 'package:telnyx_webrtc/utils/logging/global_logger.dart';

/// Manages multi-call state within the Telnyx WebRTC SDK.
///
/// CallManager tracks which call is currently active ([currentCall]) and which
/// calls are on hold ([heldCalls]). It mirrors the role that `TelnyxCommon`
/// plays in the Android SDK, providing a centralised source of truth for
/// call-related decisions such as "hold current and accept incoming" or
/// "end current and unhold last".
///
/// **Typical flow when a second call arrives:**
/// 1. The app receives an `invite` event via [TelnyxClient.onSocketMessageReceived].
/// 2. The app checks [currentCall] – if it is non-null, a call is already active.
/// 3. The app decides how to handle the incoming call:
///    - [holdCurrentAndAcceptIncoming] – put the active call on hold and answer.
///    - [endCurrentAndAcceptIncoming] – hang up the active call and answer.
///    - [rejectCall] – decline the incoming call without disturbing the active one.
/// 4. When the active call ends ([endCurrentAndUnholdLast]), any held call is
///    automatically restored as the new active call.
class CallManager {
  Call? _currentCall;
  final List<Call> _heldCalls = [];

  final _currentCallController = StreamController<Call?>.broadcast();
  final _heldCallsController = StreamController<List<Call>>.broadcast();

  /// A broadcast stream that emits whenever [currentCall] changes.
  Stream<Call?> get currentCallStream => _currentCallController.stream;

  /// A broadcast stream that emits whenever [heldCalls] changes.
  Stream<List<Call>> get heldCallsStream => _heldCallsController.stream;

  /// The call that is currently active (not on hold).
  ///
  /// Returns `null` when there is no active call.
  Call? get currentCall => _currentCall;

  /// An unmodifiable view of the calls currently on hold.
  List<Call> get heldCalls => List.unmodifiable(_heldCalls);

  /// Whether there is an active (non-held) call.
  bool get hasActiveCall => _currentCall != null;

  /// Sets [call] as the current active call.
  ///
  /// If [call] is currently in [heldCalls] it will be removed from there first.
  /// If there was a previous [currentCall] it is *not* automatically put on hold –
  /// the caller is responsible for managing that transition (see
  /// [holdCurrentAndAcceptIncoming]).
  void setCurrentCall(Call? call) {
    if (call != null) {
      _heldCalls.removeWhere((c) => c.callId == call.callId);
    }

    _currentCall = call;
    _currentCallController.add(call);
    _notifyHeldCallsChanged();
  }

  /// Registers a call so that its hold-status is observed.
  ///
  /// When the call transitions to held it is added to [heldCalls]; when it
  /// transitions away from held it is removed. This mirrors the
  /// `registerCall` / hold-status-observer pattern in the Android SDK.
  void registerCall(Call call) {
    // Listen for state changes. When the call transitions to/from held we
    // update the held-calls list.
    // We attach a listener via the existing CallHandler callback chain by
    // wrapping the existing callback.
    final originalCallback = call.callHandler.onCallStateChanged;
    call.callHandler.onCallStateChanged = (CallState state) {
      originalCallback(state);
      _onCallStateChanged(call, state);
    };
  }

  /// Unregisters a call, removing it from held-calls tracking.
  ///
  /// Call this when a call ends (BYE received or local hang-up) to clean up.
  void unregisterCall(String? callId) {
    if (callId == null) return;

    _heldCalls.removeWhere((c) => c.callId == callId);
    if (_currentCall?.callId == callId) {
      _currentCall = null;
      _currentCallController.add(null);
    }
    _notifyHeldCallsChanged();
  }

  /// Returns the last held call, or `null` if there are no held calls.
  Call? getLastHeldCall() {
    return _heldCalls.isNotEmpty ? _heldCalls.last : null;
  }

  // ---------------------------------------------------------------------------
  // High-level multi-call operations (mirrors Android domain use-cases)
  // ---------------------------------------------------------------------------

  /// Holds the current active call (if any) and accepts an incoming call.
  ///
  /// [incomingCallId] – the callId of the ringing incoming call.
  /// [acceptCall] – a function that actually performs the accept logic on the
  ///   [TelnyxClient] and returns the accepted [Call].
  ///
  /// Returns the accepted call.
  Call holdCurrentAndAcceptIncoming(
    String incomingCallId,
    Call Function(String callId) acceptCall,
  ) {
    // Hold the current call if it is not already on hold.
    if (_currentCall != null && !_currentCall!.onHold) {
      GlobalLogger().i(
        'CallManager: Holding current call ${_currentCall!.callId} before accepting incoming $incomingCallId',
      );
      _currentCall!.onHoldUnholdPressed();
      _addHeldCall(_currentCall!);
    }

    final acceptedCall = acceptCall(incomingCallId);
    setCurrentCall(acceptedCall);

    return acceptedCall;
  }

  /// Ends the current active call and accepts an incoming call.
  ///
  /// [incomingCallId] – the callId of the ringing incoming call.
  /// [endCall] – a function that ends a call by callId.
  /// [acceptCall] – a function that accepts the incoming call and returns it.
  ///
  /// Returns the accepted call.
  Call endCurrentAndAcceptIncoming(
    String incomingCallId, {
    required void Function(String callId) endCall,
    required Call Function(String callId) acceptCall,
  }) {
    if (_currentCall != null) {
      GlobalLogger().i(
        'CallManager: Ending current call ${_currentCall!.callId} before accepting incoming $incomingCallId',
      );
      endCall(_currentCall!.callId!);
      unregisterCall(_currentCall!.callId);
    }

    final acceptedCall = acceptCall(incomingCallId);
    setCurrentCall(acceptedCall);

    return acceptedCall;
  }

  /// Ends the specified call and, if there is a held call, unholds the last
  /// one and makes it the new [currentCall].
  ///
  /// This mirrors `EndCurrentAndUnholdLast` in the Android SDK.
  void endCurrentAndUnholdLast(String callId) {
    unregisterCall(callId);

    final lastHeld = getLastHeldCall();
    if (lastHeld != null) {
      GlobalLogger().i(
        'CallManager: Unholding last held call ${lastHeld.callId} after ending $callId',
      );
      lastHeld.onHoldUnholdPressed();
      _heldCalls.remove(lastHeld);
      setCurrentCall(lastHeld);
    }
  }

  /// Rejects an incoming call by sending BYE with USER_BUSY cause.
  ///
  /// This is a no-op on the CallManager state if the call was not the current
  /// call (which it shouldn't be – it's ringing). The actual BYE sending is
  /// done by [rejectCall] on the [Call] object itself.
  void onIncomingCallRejected(String callId) {
    // A rejected incoming call was never the current call, so we only need to
    // ensure it's removed from the general tracking (if it was somehow
    // registered).
    unregisterCall(callId);
  }

  /// Handles a remote BYE for the given [callId].
  ///
  /// If the ended call was [currentCall], the current call is cleared and the
  /// last held call (if any) is automatically unheld and made active.
  void onByeReceived(String callId) {
    if (_currentCall?.callId == callId) {
      _currentCall = null;
      _currentCallController.add(null);

      // Auto-unhold the last held call
      final lastHeld = getLastHeldCall();
      if (lastHeld != null) {
        GlobalLogger().i(
          'CallManager: Auto-unholding held call ${lastHeld.callId} after remote BYE for $callId',
        );
        lastHeld.onHoldUnholdPressed();
        _heldCalls.remove(lastHeld);
        setCurrentCall(lastHeld);
      }
    } else {
      // It was a held call that got ended remotely
      _heldCalls.removeWhere((c) => c.callId == callId);
      _notifyHeldCallsChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _addHeldCall(Call call) {
    if (!_heldCalls.any((c) => c.callId == call.callId)) {
      _heldCalls.add(call);
      _notifyHeldCallsChanged();
    }
  }

  void _notifyHeldCallsChanged() {
    _heldCallsController.add(List.unmodifiable(_heldCalls));
  }

  void _onCallStateChanged(Call call, CallState state) {
    if (state == CallState.held) {
      _addHeldCall(call);
    } else if (state == CallState.active) {
      // If a held call becomes active, remove it from the held list.
      final wasHeld = _heldCalls.any((c) => c.callId == call.callId);
      if (wasHeld) {
        _heldCalls.removeWhere((c) => c.callId == call.callId);
        _notifyHeldCallsChanged();
      }
    }
  }

  /// Dispose all stream controllers. Call this when the TelnyxClient is
  /// disconnected and will no longer be used.
  void dispose() {
    _currentCallController.close();
    _heldCallsController.close();
  }
}
