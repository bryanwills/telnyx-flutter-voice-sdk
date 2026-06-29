import 'package:flutter_test/flutter_test.dart';
import 'package:telnyx_webrtc/call.dart';
import 'package:telnyx_webrtc/call_manager.dart';
import 'package:telnyx_webrtc/model/call_state.dart';
import 'package:telnyx_webrtc/telnyx_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallManager.registerCall', () {
    test(
        'is idempotent — second call for same callId does not re-wrap callback',
        () {
      // Build a Call via the deprecated public TelnyxClient.call getter.
      // We do not connect the client; we only need a Call instance to wire up.
      final telnyxClient = TelnyxClient();
      final Call call = telnyxClient.call;
      call.callId = 'test-call-id-1';

      // The default callback installed by _createCall just logs; capture it
      // so we can detect if it's replaced by a wrapper.
      final originalCallback = call.callHandler.onCallStateChanged;

      final callManager = CallManager();
      callManager.registerCall(call);

      // First register should wrap the original callback.
      expect(
        identical(call.callHandler.onCallStateChanged, originalCallback),
        isFalse,
        reason: 'registerCall must wrap the original callback on first call',
      );

      final firstWrappedCallback = call.callHandler.onCallStateChanged;

      // Second register with the same callId should be a no-op (idempotency
      // guard). The callback reference must NOT change, otherwise
      // _onCallStateChanged would fire multiple times per state transition.
      callManager.registerCall(call);

      expect(
        identical(call.callHandler.onCallStateChanged, firstWrappedCallback),
        isTrue,
        reason:
            'registerCall must not re-wrap the callback for an already-registered callId',
      );

      // A third call with the same callId also stays idempotent.
      callManager.registerCall(call);
      expect(
        identical(call.callHandler.onCallStateChanged, firstWrappedCallback),
        isTrue,
      );
    });

    test('re-wraps after unregisterCall frees the callId', () {
      final telnyxClient = TelnyxClient();
      final Call call = telnyxClient.call;
      call.callId = 'test-call-id-2';

      final callManager = CallManager();
      callManager.registerCall(call);
      final wrapped = call.callHandler.onCallStateChanged;

      callManager.unregisterCall('test-call-id-2');

      // After unregistering, re-registering with the same callId should
      // re-wrap the callback (it's a fresh registration for a new lifecycle).
      callManager.registerCall(call);
      expect(
        identical(call.callHandler.onCallStateChanged, wrapped),
        isFalse,
        reason: 'After unregisterCall, the callback should be re-wrapped',
      );
    });

    test('registers different callIds independently', () {
      final telnyxClientA = TelnyxClient();
      final telnyxClientB = TelnyxClient();
      final Call callA = telnyxClientA.call..callId = 'call-A';
      final Call callB = telnyxClientB.call..callId = 'call-B';

      final callManager = CallManager();
      callManager.registerCall(callA);
      callManager.registerCall(callB);

      // Both callbacks must have been wrapped — independent registrations.
      final originalA = (CallState _) {};
      final originalB = (CallState _) {};
      // Reset to known noop callbacks to detect wrapping deterministically.
      callA.callHandler.onCallStateChanged = originalA;
      callB.callHandler.onCallStateChanged = originalB;

      callManager.registerCall(callA); // already registered — no-op
      callManager.registerCall(callA); // already registered — no-op

      expect(
        identical(callA.callHandler.onCallStateChanged, originalA),
        isTrue,
        reason: 'callA callback must remain untouched on re-register',
      );
      expect(
        identical(callB.callHandler.onCallStateChanged, originalB),
        isTrue,
        reason: 'callB callback must remain untouched (unrelated callId)',
      );
    });

    test('treats null callId as a single registration bucket', () {
      // The same null callId must not be wrapped multiple times.
      final telnyxClient = TelnyxClient();
      final Call call = telnyxClient.call; // callId is null by default
      final originalCallback = call.callHandler.onCallStateChanged;

      final callManager = CallManager();
      callManager.registerCall(call);
      final wrapped = call.callHandler.onCallStateChanged;
      expect(identical(wrapped, originalCallback), isFalse);

      // Second register with null callId should be a no-op (same bucket).
      callManager.registerCall(call);
      expect(identical(call.callHandler.onCallStateChanged, wrapped), isTrue);
    });
  });
}
