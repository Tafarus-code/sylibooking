import 'dart:math' as math;

/// A point on the earth.
class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  String toString() => '$latitude,$longitude';
}

/// Mean earth radius in kilometres, as used by the haversine formula.
const _earthRadiusKm = 6371.0088;

double _radians(double degrees) => degrees * math.pi / 180.0;

/// Great-circle distance in kilometres between two points.
///
/// Haversine: accurate to a fraction of a percent at city scale, needs no
/// network call, and treats the earth as a sphere — good enough to tell a
/// customer a lounge is 1.2 km away.
double distanceKm(LatLng from, LatLng to) {
  final deltaLat = _radians(to.latitude - from.latitude);
  final deltaLon = _radians(to.longitude - from.longitude);

  final a = math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(_radians(from.latitude)) *
          math.cos(_radians(to.latitude)) *
          math.pow(math.sin(deltaLon / 2), 2);

  return _earthRadiusKm * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

/// "450 m away", "1.2 km away", "34 km away".
///
/// Metres below a kilometre because "0.4 km" reads as further than it is, and
/// no decimal past ten because nobody walks 34.2 km.
String formatDistance(double kilometres) {
  if (kilometres < 1) {
    final metres = (kilometres * 1000).round();
    // Round to the nearest 10 m: GPS is not accurate enough to justify more,
    // and "437 m" implies a precision that is not there.
    final rounded = (metres / 10).round() * 10;
    return '${rounded == 0 ? metres : rounded} m away';
  }
  if (kilometres < 10) return '${kilometres.toStringAsFixed(1)} km away';
  return '${kilometres.round()} km away';
}
