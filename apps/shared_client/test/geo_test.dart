import 'package:flutter_test/flutter_test.dart';
import 'package:shared_client/shared_client.dart';

/// Reference points. The expected distances come from published
/// great-circle figures, so these catch a formula that drifts rather than
/// merely re-stating whatever the code happens to return.
const conakry = LatLng(9.509167, -13.712222); // Kaloum
const labe = LatLng(11.318056, -12.283056);
const kankan = LatLng(10.385000, -9.306389);
const paris = LatLng(48.856614, 2.352222);
const london = LatLng(51.507351, -0.127758);

void main() {
  group('distanceKm', () {
    test('a point is zero from itself', () {
      expect(distanceKm(conakry, conakry), 0);
    });

    test('Conakry to Labé is about 253 km', () {
      expect(distanceKm(conakry, labe), closeTo(253, 3));
    });

    test('Conakry to Kankan is about 492 km', () {
      // Cross-checked by hand: 4.406° of longitude at ~10°N is ~483 km, plus
      // 0.876° of latitude at ~97 km, giving √(483² + 97²) ≈ 492.
      expect(distanceKm(conakry, kankan), closeTo(492, 5));
    });

    test('Paris to London is about 344 km', () {
      // The classic reference pair for haversine implementations.
      expect(distanceKm(paris, london), closeTo(344, 3));
    });

    test('it is symmetric', () {
      expect(
        distanceKm(conakry, labe),
        closeTo(distanceKm(labe, conakry), 0.0001),
      );
    });

    test('a short hop within Conakry is under a kilometre', () {
      // Roughly 500 m north of the first point.
      const nearby = LatLng(9.513667, -13.712222);
      expect(distanceKm(conakry, nearby), closeTo(0.5, 0.05));
    });

    test('it copes with crossing the equator and the meridian', () {
      const northOfEquator = LatLng(1.0, 1.0);
      const southOfEquator = LatLng(-1.0, -1.0);
      expect(distanceKm(northOfEquator, southOfEquator), closeTo(314, 3));
    });

    test('antipodal points are half the circumference apart', () {
      expect(
        distanceKm(const LatLng(0, 0), const LatLng(0, 180)),
        closeTo(20015, 10),
      );
    });
  });

  group('formatDistance', () {
    test('under a kilometre reads in metres', () {
      expect(formatDistance(0.45), '450 m away');
    });

    test('metres round to the nearest ten', () {
      // GPS is not accurate enough to justify "437 m".
      expect(formatDistance(0.437), '440 m away');
    });

    test('a very short distance still shows something', () {
      expect(formatDistance(0.003), '3 m away');
    });

    test('one to ten kilometres keeps one decimal', () {
      expect(formatDistance(1.24), '1.2 km away');
      expect(formatDistance(9.99), '10.0 km away');
    });

    test('beyond ten kilometres drops the decimal', () {
      expect(formatDistance(34.4), '34 km away');
      expect(formatDistance(253.2), '253 km away');
    });
  });

  group('Establishment.position', () {
    Establishment build({Object? lat, Object? lon}) =>
        Establishment.fromJson({
          'id': 1,
          'name': 'Le Petit Baobab',
          'type': 'lounge',
          'type_display': 'Lounge',
          'city': 'Conakry',
          'address': 'Kaloum',
          'latitude': lat,
          'longitude': lon,
        });

    test('coordinates arrive as strings from DRF', () {
      final venue = build(lat: '9.509167', lon: '-13.712222');

      expect(venue.hasPosition, isTrue);
      expect(venue.position!.latitude, closeTo(9.509167, 0.000001));
    });

    test('numbers are accepted too', () {
      final venue = build(lat: 9.509167, lon: -13.712222);
      expect(venue.hasPosition, isTrue);
    });

    test('a venue with no coordinates has no position', () {
      expect(build().hasPosition, isFalse);
      expect(build().position, isNull);
    });

    test('half a coordinate pair is no position at all', () {
      expect(build(lat: '9.5').hasPosition, isFalse);
      expect(build(lon: '-13.7').hasPosition, isFalse);
    });

    test('unparseable coordinates are treated as missing', () {
      expect(build(lat: 'north', lon: 'west').hasPosition, isFalse);
    });
  });
}
