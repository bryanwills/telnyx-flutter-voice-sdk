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
      // Multi-call scenario: show hold+accept, end+accept, and reject
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Incoming call while in a call',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: spacingM),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Hold current + Accept incoming
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'hold_accept',
                    onPressed: onHoldAndAccept,
                    backgroundColor: Colors.orange,
                    child: const Icon(Icons.phone_callback),
                  ),
                  const SizedBox(height: 4),
                  const Text('Hold &\nAccept',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              // End current + Accept incoming
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'end_accept',
                    onPressed: onEndAndAccept,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.phone_forwarded),
                  ),
                  const SizedBox(height: 4),
                  const Text('End &\nAccept',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              // Reject incoming
              DeclineButton(onPressed: onDecline),
            ],
          ),
        ],
      );
    }

    // Normal single-call scenario
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallButton(onPressed: onAccept),
        SizedBox(width: spacingM),
        DeclineButton(onPressed: onDecline),
      ],
    );
  }
}
