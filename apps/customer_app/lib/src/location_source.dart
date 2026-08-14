import 'package:geolocator/geolocator.dart';
import 'package:shared_client/shared_client.dart';

/// Why there is no position, when there is none.
///
/// The distinction matters on screen: "turn on GPS" and "you said no" need
/// different words, and neither should read as an error.
enum LocationStatus {
  /// We have a fix.
  available,

  /// The user declined, this time or permanently.
  denied,

  /// Location services are switched off on the device.
  servicesOff,

  /// Asked for and not yet answered, or never asked.
  unknown,

  /// Asked, permitted, and still no fix — a timeout or a bad sky view.
  unavailable,
}

typedef LocationResult = ({LatLng? position, LocationStatus status});

/// Where the customer is.
///
/// An interface so browse and detail can be tested without a platform
/// channel, and so a denied permission is an ordinary value rather than an
/// exception thrown from somewhere deep.
abstract class LocationSource {
  /// Whether permission has already been granted, without prompting.
  Future<bool> hasPermission();

  /// Prompt if needed, then try for a fix. Never throws.
  Future<LocationResult> current();
}

class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource();

  @override
  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (position: null, status: LocationStatus.servicesOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (position: null, status: LocationStatus.denied);
      }

      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          // A rough fix is enough for "1.2 km away", and waiting longer than
          // this on a weak signal is worse than showing no distance at all.
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (
        position: LatLng(fix.latitude, fix.longitude),
        status: LocationStatus.available,
      );
    } on Object {
      // A timeout, a platform quirk, an emulator with no fix — none of it is
      // worth an error screen when the whole feature is optional.
      return (position: null, status: LocationStatus.unavailable);
    }
  }
}

/// Returns a fixed answer without touching the platform. Used in tests.
class FakeLocationSource implements LocationSource {
  FakeLocationSource({
    this.position,
    this.status = LocationStatus.available,
    this.granted = true,
  });

  final LatLng? position;
  final LocationStatus status;
  final bool granted;

  int requestCount = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<LocationResult> current() async {
    requestCount++;
    if (status != LocationStatus.available) {
      return (position: null, status: status);
    }
    return (
      position: position ?? const LatLng(9.509167, -13.712222),
      status: LocationStatus.available,
    );
  }
}
