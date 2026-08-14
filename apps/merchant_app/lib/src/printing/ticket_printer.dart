/// Sending a ticket somewhere, or standing ready to.
///
/// The same shape as the backend's `Notifier`, `PushSender` and
/// `PaymentProvider`, and for the same reason: an interface, a real
/// implementation behind configuration, and a console one that runs
/// everywhere else. No venue in this project has a printer yet, so the
/// console implementation is what runs — and because it runs, the code path
/// around it is exercised on every test rather than on the day hardware
/// arrives.
///
/// What is deliberately *not* here is a Bluetooth implementation. It needs a
/// platform plugin, runtime permissions and a pairing flow, none of which can
/// be written honestly against hardware nobody has held. The network printer
/// below covers the common counter setup — a box on the venue's wifi
/// listening on 9100 — and needs no dependency at all.
library;

import 'dart:async';
import 'dart:io';

/// Why a ticket did not print.
class PrinterException implements Exception {
  PrinterException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PrinterException: $message';
}

abstract class TicketPrinter {
  /// Deliver one ticket's bytes. Throws [PrinterException] if it cannot.
  Future<void> send(List<int> bytes);
}

/// Prints to the log. What runs until a venue owns a printer.
///
/// Not a no-op: it renders the ticket as text so the layout can be read
/// during development, which is the only way anybody sees a ticket today.
class ConsoleTicketPrinter implements TicketPrinter {
  ConsoleTicketPrinter({void Function(String)? out}) : _out = out ?? print;

  final void Function(String) _out;

  @override
  Future<void> send(List<int> bytes) async {
    _out('--- kitchen ticket (${bytes.length} bytes) ---');
    // Control bytes stripped rather than escaped: the point of this output
    // is to read the ticket, not the protocol.
    final text = String.fromCharCodes(
      bytes.where((b) => b == 0x0A || (b >= 0x20 && b < 0x7F)),
    );
    for (final line in text.split('\n')) {
      _out(line);
    }
  }
}

/// A printer on the venue's own network, listening on the ESC/POS port.
///
/// **Untested against real hardware**, and said plainly because the byte
/// protocol is covered by tests and the transport is not: nobody here has a
/// printer to plug in. What is tested is that the right bytes are written and
/// that a refused connection becomes a [PrinterException] rather than an
/// unhandled socket error — which is the failure a kitchen will actually meet
/// when somebody unplugs the printer.
class NetworkTicketPrinter implements TicketPrinter {
  NetworkTicketPrinter({
    required this.host,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
    Future<Socket> Function(String host, int port, {Duration? timeout})? connect,
  }) : _connect = connect ?? Socket.connect;

  final String host;
  final int port;

  /// A printer that does not answer quickly is off, out of paper, or gone.
  /// Waiting longer only delays telling somebody.
  final Duration timeout;

  final Future<Socket> Function(String host, int port, {Duration? timeout})
      _connect;

  @override
  Future<void> send(List<int> bytes) async {
    Socket? socket;
    try {
      socket = await _connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
    } on Object catch (error) {
      throw PrinterException('Could not reach the printer.', cause: error);
    } finally {
      // Closed in `finally` because a half-open socket to a printer holds
      // its single connection slot, and the next ticket then fails for a
      // reason that has nothing to do with the next ticket.
      await socket?.close();
    }
  }
}
