/// Turning an order into the bytes a thermal printer understands.
///
/// ESC/POS, because every cheap 58mm and 80mm printer sold into this market
/// speaks it and almost nothing else. The commands used here are the oldest
/// and most widely implemented ones — initialise, align, bold, double height,
/// feed, cut — so a ticket built by this code prints on hardware nobody has
/// chosen yet.
///
/// **A ticket is a pure function of its order.** Nothing here reads the clock
/// or a counter, so printing the same order twice produces byte-identical
/// output. That is what makes a reprint a reprint rather than a second,
/// subtly different ticket — a kitchen comparing two dockets should find them
/// the same or find them different for a reason.
library;

import 'dart:convert';

import 'package:shared_client/shared_client.dart';

/// ESC/POS control sequences, named so the layout below reads as a layout.
class _Cmd {
  static const init = [0x1B, 0x40];
  static const alignLeft = [0x1B, 0x61, 0x00];
  static const alignCentre = [0x1B, 0x61, 0x01];
  static const boldOn = [0x1B, 0x45, 0x01];
  static const boldOff = [0x1B, 0x45, 0x00];
  static const doubleHeight = [0x1D, 0x21, 0x01];
  static const normalSize = [0x1D, 0x21, 0x00];
  static const feed = [0x0A];

  /// Feed three lines and cut. The feed matters: a cut with no feed slices
  /// through the last line of text, which on a kitchen ticket is a dish.
  static const cut = [0x1D, 0x56, 0x42, 0x03];
}

/// How wide the paper is, in characters at the default font.
///
/// 32 is the 58mm roll, which is what a counter printer usually is. An 80mm
/// roll fits 48 and simply leaves the rules short, which is harmless.
const int ticketWidth = 32;

/// One kitchen ticket for one order.
class KitchenTicket {
  const KitchenTicket({required this.order, required this.venueName});

  final Order order;
  final String venueName;

  /// The reference, shortened to something a person can read aloud.
  ///
  /// The full UUID is the credential and stays out of the kitchen; the first
  /// block is enough to match a docket against the screen, which is all this
  /// is for.
  String get shortReference =>
      order.reference.split('-').first.toUpperCase();

  List<int> toBytes() {
    final out = <int>[..._Cmd.init];

    out
      ..addAll(_Cmd.alignCentre)
      ..addAll(_Cmd.boldOn)
      ..addAll(_Cmd.doubleHeight)
      ..addAll(_text(venueName))
      ..addAll(_Cmd.normalSize)
      ..addAll(_Cmd.boldOff)
      ..addAll(_Cmd.feed)
      ..addAll(_Cmd.alignLeft)
      ..addAll(_rule());

    // What the kitchen reads first: which ticket, and when it is wanted.
    out
      ..addAll(_Cmd.boldOn)
      ..addAll(_text('TICKET $shortReference'))
      ..addAll(_text('POUR ${_time(order.pickupTime)}'))
      ..addAll(_Cmd.boldOff)
      ..addAll(_text(order.customerName));

    if (order.customerPhone.isNotEmpty) {
      out.addAll(_text(order.customerPhone));
    }

    out.addAll(_rule());

    // Quantity first and padded, so a cook scanning the left edge reads the
    // numbers in a column rather than hunting for them at the end of a name.
    for (final line in order.items) {
      out.addAll(_text('${line.quantity}'.padRight(3) + line.menuItemName));
    }

    out
      ..addAll(_rule())
      ..addAll(_Cmd.feed)
      ..addAll(_Cmd.cut);

    return out;
  }

  List<int> _rule() => _text('-' * ticketWidth);

  List<int> _text(String value) => [..._encode(value), ..._Cmd.feed];

  /// `HH:MM`, in the venue's own time. A kitchen has never once wanted a date
  /// on a ticket it is cooking now.
  String _time(DateTime when) {
    final local = when.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Bytes for one line of text, with accents flattened.
  ///
  /// Thermal printers pick a code page at the factory and rarely agree on
  /// which. Sending `é` to a printer set to CP437 produces a different glyph
  /// on every model, so "Poisson braisé" arrives as something a cook has to
  /// decode. Flattened to ASCII it is merely unaccented, which is legible
  /// everywhere and wrong nowhere.
  List<int> _encode(String value) => ascii.encode(_flatten(value));
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
};

/// Latin text a thermal printer can render whatever code page it woke up in.
///
/// Anything still outside ASCII after flattening becomes '?', which is what
/// a printer would have done anyway — but deliberately, and without the byte
/// stream depending on the model.
String flattenForPrinter(String value) => _flatten(value);

String _flatten(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    if (_accents[lower] case final replacement?) {
      buffer.write(char == lower ? replacement : replacement.toUpperCase());
    } else if (rune < 128) {
      buffer.write(char);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}
