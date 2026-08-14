// Aliased: image_picker exports its own ImageSource, which would collide with
// the interface below.
import 'package:image_picker/image_picker.dart' as picker;

/// One picked image: the bytes and a filename the server can read.
typedef PickedImage = ({List<int> bytes, String filename});

/// Where an image comes from.
///
/// An interface rather than calling image_picker directly, so the upload
/// paths can be exercised in widget tests — the real picker is a platform
/// channel and cannot run in one.
abstract class ImageSource {
  /// Null when the user backs out of the picker.
  Future<PickedImage?> pick({bool fromCamera = false});
}

class DeviceImageSource implements ImageSource {
  DeviceImageSource({picker.ImagePicker? imagePicker})
      : _picker = imagePicker ?? picker.ImagePicker();

  final picker.ImagePicker _picker;

  @override
  Future<PickedImage?> pick({bool fromCamera = false}) async {
    final file = await _picker.pickImage(
      source: fromCamera
          ? picker.ImageSource.camera
          : picker.ImageSource.gallery,
      // Phones here produce very large files on poor connections, and the
      // server caps uploads at 5 MB. Shrinking before sending is the
      // difference between an upload that works and one that times out.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    return (bytes: await file.readAsBytes(), filename: file.name);
  }
}

/// Returns a fixed image without touching the platform. Used in tests.
class FakeImageSource implements ImageSource {
  FakeImageSource({this.image, this.cancels = false});

  final PickedImage? image;

  /// Mimics the user dismissing the picker.
  final bool cancels;

  int pickCount = 0;

  @override
  Future<PickedImage?> pick({bool fromCamera = false}) async {
    pickCount++;
    if (cancels) return null;
    return image ?? (bytes: List<int>.filled(64, 1), filename: 'test.jpg');
  }
}
