import 'package:flutter/material.dart';
import 'package:telnyx_flutter_webrtc/utils/dimensions.dart';
import 'package:telnyx_flutter_webrtc/view/widgets/call_controls/buttons/call_buttons.dart';

class CallInvitation extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onHoldAndAccept;
  final VoidCallback? onEndAndAccept;
  final bool hasActiveCall;

  const CallInvitation({
    super.key,
    required this.onAccept,
    required this.onDecline,
    this.onHoldAndAccept,
    this.onEndAndAccept,
    this.hasActiveCall = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hasActiveCall) {
      // Multi-call scenario: same UI as single incoming call.
      // Answer → hold current + accept incoming; Decline → reject incoming
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallButton(onPressed: onHoldAndAccept ?? onAccept),
          SizedBox(width: spacingM),
          DeclineButton(onPressed: onDecline),
        ],
      );
    }

    // Normal single-call scenario
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Semantics(
          identifier: 'accept_call_button',
          container: true,
          child: CallButton(
            key: const ValueKey('accept_call_button'),
            onPressed: onAccept,
          ),
        ),
        SizedBox(width: spacingM),
        Semantics(
          identifier: 'decline_call_button',
          container: true,
          child: DeclineButton(
            key: const ValueKey('decline_call_button'),
            onPressed: onDecline,
          ),
        ),
      ],
    );
  }
}
