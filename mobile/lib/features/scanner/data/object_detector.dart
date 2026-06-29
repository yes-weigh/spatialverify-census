import 'package:camera/camera.dart';
import '../../../core/models/models.dart';

/// On-device object detection (field-test build uses empty fallback; server CV handles mission intelligence).
class ObjectDetector {
  bool _isLoaded = false;

  Future<void> loadModel() async {
    _isLoaded = true;
  }

  Future<List<DetectedObject>> detect(CameraImage image, int rotation) async {
    if (!_isLoaded) await loadModel();
    return [];
  }

  void dispose() {
    _isLoaded = false;
  }
}

class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  final String label;
  final double confidence;
  final BoundingBox boundingBox;
}
