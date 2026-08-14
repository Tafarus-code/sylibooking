/// What comes out of the printer, checked without one.
///
/// The byte protocol is testable and the transport is not, so this covers the
/// first exactly and the second only as far as "a printer that is not there
/// fails in a way the kitchen can be told about".
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/src/printing/kitchen_ticket.dart';
import 'package:merchant_app/src/printing/ticket_printer.dart';
import 'package:shared_client/shared_client.dart';

Order orderFrom({
  String reference = 'a1b2c3d4-1111-2222-3333-444444444444',
  String customer = 'Mariama Diallo',
  String phone = '+224 620 00 00 00',
  DateTime? pickup,
  List<Map<String, dynamic>>? items,
}) =>
    Order.fromJson({
      'id': 1,
      'reference': reference,
      'establishment': 7,
      'establishment_name': 'Le Petit Baobab',
      'customer_name': customer,
      'customer_phone': phone,
      'pickup_time': (pickup ?? DateTime(2026, 8, 14, 20, 30))
          .toUtc()
          .toIso8601String(),
      'status': 'placed',
      'status_display': 'Placed',
      'items': items ??
          [
            {
              'id': 1,
              'menu_item': 3,
              'menu_item_name': 'Poulet yassa',
              'quantity': 2,
              'unit_price_at_order': '75000.00',
              'line_total': '150000.00',
            },
          ],
      'total': '150000.00',
    });

/// Reads the ticket back as the text a cook would see.
String rendered(List<int> bytes) => String.fromCharCodes(
      bytes.where((b) => b == 0x0A || (b >= 0x20 && b < 0x7F)),
    );

void main() {
  group('a ticket a kitchen can read', () {
    test('names the venue, the ticket and when it is wanted', () {
      final text = rendered(
        KitchenTicket(
          order: orderFrom(),
          venueName: 'Le Petit Baobab',
        ).toBytes(),
      );

      expect(text, contains('Le Petit Baobab'));
      expect(text, contains('TICKET A1B2C3D4'));
      expect(text, contains('POUR 20:30'));
      expect(text, contains('Mariama Diallo'));
    });

    test('shortens the reference to something sayable out loud', () {
      // The full UUID is the credential and has no business in a kitchen.
      final ticket = KitchenTicket(order: orderFrom(), venueName: 'X');

      expect(ticket.shortReference, 'A1B2C3D4');
      expect(rendered(ticket.toBytes()), isNot(contains('444444444444')));
    });

    test('puts the quantity before the dish, in a column', () {
      final text = rendered(
        KitchenTicket(
          order: orderFrom(
            items: [
              {
                'id': 1,
                'menu_item': 3,
                'menu_item_name': 'Poulet yassa',
                'quantity': 2,
                'unit_price_at_order': '75000.00',
                'line_total': '150000.00',
              },
              {
                'id': 2,
                'menu_item': 4,
                'menu_item_name': 'Alloco',
                'quantity': 12,
                'unit_price_at_order': '20000.00',
                'line_total': '240000.00',
              },
            ],
          ),
          venueName: 'Le Petit Baobab',
        ).toBytes(),
      );

      // Padded to the same width so a cook reads the numbers down the left
      // edge rather than hunting at the end of each name.
      expect(text, contains('2  Poulet yassa'));
      expect(text, contains('12 Alloco'));
    });

    test('flattens accents rather than trusting a code page', () {
      // A thermal printer picks its code page at the factory. "braisé" sent
      // raw arrives as a different glyph on every model.
      final text = rendered(
        KitchenTicket(
          order: orderFrom(
            items: [
              {
                'id': 1,
                'menu_item': 3,
                'menu_item_name': 'Poisson braisé à la sauce',
                'quantity': 1,
                'unit_price_at_order': '90000.00',
                'line_total': '90000.00',
              },
            ],
          ),
          venueName: 'Café Central',
        ).toBytes(),
      );

      expect(text, contains('Poisson braise a la sauce'));
      expect(text, contains('Cafe Central'));
    });

    test('keeps every byte inside ASCII', () {
      // Anything above 127 is where code pages start disagreeing.
      final bytes = KitchenTicket(
        order: orderFrom(customer: 'Aïssatou Baldé'),
        venueName: 'Le Cocotier',
      ).toBytes();

      expect(bytes.every((b) => b < 128), isTrue);
    });

    test('starts by initialising and ends by cutting', () {
      final bytes = KitchenTicket(
        order: orderFrom(),
        venueName: 'Le Petit Baobab',
      ).toBytes();

      expect(bytes.take(2), [0x1B, 0x40]);
      // Feed three lines, then cut — a cut with no feed slices the last dish
      // off the ticket.
      expect(bytes.skip(bytes.length - 4), [0x1D, 0x56, 0x42, 0x03]);
    });

    test('omits the phone line when there is no number', () {
      final text = rendered(
        KitchenTicket(
          order: orderFrom(phone: ''),
          venueName: 'Le Petit Baobab',
        ).toBytes(),
      );

      expect(text, isNot(contains('+224')));
      expect(text, contains('Mariama Diallo'));
    });
  });

  group('a reprint is the same ticket', () {
    test('printing the same order twice produces identical bytes', () {
      // **The property that makes a reprint a reprint.** Nothing in the
      // ticket reads the clock or a counter, so a kitchen holding two
      // dockets for one order finds them the same.
      final order = orderFrom();

      final first = KitchenTicket(order: order, venueName: 'Le Petit Baobab')
          .toBytes();
      final second = KitchenTicket(order: order, venueName: 'Le Petit Baobab')
          .toBytes();

      expect(first, equals(second));
    });

    test('two different orders do not', () {
      final a = KitchenTicket(order: orderFrom(), venueName: 'X').toBytes();
      final b = KitchenTicket(
        order: orderFrom(reference: 'ffffffff-1111-2222-3333-444444444444'),
        venueName: 'X',
      ).toBytes();

      expect(a, isNot(equals(b)));
    });
  });

  group('sending it somewhere', () {
    test('the console printer renders the ticket as readable text', () async {
      final lines = <String>[];
      final printer = ConsoleTicketPrinter(out: lines.add);

      await printer.send(
        KitchenTicket(order: orderFrom(), venueName: 'Le Petit Baobab')
            .toBytes(),
      );

      expect(lines.join('\n'), contains('TICKET A1B2C3D4'));
      // The protocol is stripped: the point of this output is the ticket,
      // not the escape codes around it.
      expect(lines.join().codeUnits.contains(0x1B), isFalse);
      expect(lines.join().codeUnits.contains(0x1D), isFalse);
    });

    test('the network printer writes the bytes it was given', () async {
      final socket = _FakeSocket();
      final printer = NetworkTicketPrinter(
        host: '192.168.1.50',
        connect: (host, port, {timeout}) async => socket,
      );
      final bytes = KitchenTicket(
        order: orderFrom(),
        venueName: 'Le Petit Baobab',
      ).toBytes();

      await printer.send(bytes);

      expect(socket.written, equals(bytes));
      expect(socket.closed, isTrue);
    });

    test('a printer that is not there is a PrinterException', () async {
      // The failure a kitchen actually meets: somebody unplugged it. It must
      // arrive as something the screen can say, not an unhandled socket
      // error halfway through service.
      final printer = NetworkTicketPrinter(
        host: '192.168.1.50',
        connect: (host, port, {timeout}) async =>
            throw const SocketException('refused'),
      );

      await expectLater(
        printer.send(const [1, 2, 3]),
        throwsA(isA<PrinterException>()),
      );
    });
  });
}

/// Enough of a Socket to record what a printer would have received.
class _FakeSocket extends Stream<Uint8List> implements Socket {
  final List<int> written = [];
  bool closed = false;

  @override
  void add(List<int> data) => written.addAll(data);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async => closed = true;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      const Stream<Uint8List>.empty().listen(onData);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
