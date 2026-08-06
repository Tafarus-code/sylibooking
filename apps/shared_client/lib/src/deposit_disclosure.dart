import 'package:flutter/material.dart';

/// Builds one line of the disclosure from the two facts that vary.
///
/// The words are localised and live in the apps; the amount and the window are
/// data and live here. Passing a builder rather than a finished string is what
/// stops the copy from being written once against one venue's numbers and then
/// quietly lying on the next.
typedef DepositCopy = String Function(String deposit, int windowMinutes);

/// What the customer is agreeing to, before they agree to it.
///
/// This box is doing commercial work, not decoration. It is the only place a
/// customer is told, before paying, that the money is offset against the bill
/// on arrival and kept if they never come — and how long "never come" means at
/// *this* venue, which is 30 minutes at a restaurant and 90 at a lounge.
///
/// The window is a parameter rather than a constant because the backend
/// resolves it per establishment type and captures it on the booking at the
/// moment it is made. Hardcoding 30 here would put a promise on the screen
/// that the server does not keep for half the venues on the platform.
class DepositDisclosure extends StatelessWidget {
  const DepositDisclosure({
    super.key,
    required this.deposit,
    required this.windowMinutes,
    required this.headline,
    required this.detail,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });

  /// Already formatted with its currency — "50 000 GNF".
  final String deposit;

  /// The venue's own grace period, as the backend resolved it.
  final int windowMinutes;

  /// The bold lead: what is being taken.
  final DepositCopy headline;

  /// The rest: what happens to it, either way.
  final DepositCopy detail;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF3E4),
          border: Border.all(color: const Color(0xFFEED9A9)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: headline(deposit, windowMinutes),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A5C1C),
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(text: detail(deposit, windowMinutes)),
            ],
          ),
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF6B5424),
          ),
        ),
      ),
    );
  }
}
