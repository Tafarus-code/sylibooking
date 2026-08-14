import 'package:shared_client/shared_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the device's own maps app at a set of coordinates.
///
/// No embedded map SDK: a `geo:` URI hands off to whatever the customer
/// already has and trusts — Google Maps, Waze, or anything else registered
/// for it — which is both lighter and better than a map we would have to
/// maintain.
abstract class DirectionsLauncher {
  /// False when nothing on the device could handle it.
  Future<bool> open(LatLng destination, {String? label});
}

class DeviceDirectionsLauncher implements DirectionsLauncher {
  const DeviceDirectionsLauncher();

  @override
  Future<bool> open(LatLng destination, {String? label}) async {
    final coordinates = '${destination.latitude},${destination.longitude}';
    final name = Uri.encodeComponent(label ?? '');

    // geo: first — it is the Android convention and lets the customer pick
    // their own app. The https fallback covers iOS and any device with no
    // geo: handler, and opens in a browser at worst.
    final candidates = [
      Uri.parse('geo:$coordinates?q=$coordinates${name.isEmpty ? '' : '($name)'}'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$coordinates',
      ),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            return true;
          }
        }
      } on Object {
        // Try the next one rather than failing the whole action.
        continue;
      }
    }
    return false;
  }
}

/// Records what it was asked to open, without leaving the app. Used in tests.
class FakeDirectionsLauncher implements DirectionsLauncher {
  FakeDirectionsLauncher({this.succeeds = true});

  final bool succeeds;
  final List<LatLng> opened = [];
  String? lastLabel;

  @override
  Future<bool> open(LatLng destination, {String? label}) async {
    opened.add(destination);
    lastLabel = label;
    return succeeds;
  }
}
