import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Visual fingerprint embeddings (field-test build uses deterministic fallback).
class EmbeddingService {
  bool _isLoaded = false;

  static const int embeddingDim = 1280;

  Future<void> loadModel() async {
    _isLoaded = true;
  }

  bool get isReady => _isLoaded;

  Future<List<double>> generateFromCameraImage(CameraImage image, int rotation) async {
    if (!_isLoaded) await loadModel();
    return _computeFallbackEmbedding(image);
  }

  Future<List<double>> generateFromBytes(Uint8List rgbBytes, int width, int height) async {
    if (!_isLoaded) await loadModel();
    return _computeFallbackFromRgb(rgbBytes, width, height);
  }

  List<double> _yuv420ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;
    final rgb = List<double>.filled(width * height * 3, 0);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);
        final yVal = yPlane[yIndex];
        final uVal = uPlane[uvIndex];
        final vVal = vPlane[uvIndex];
        rgb[yIndex * 3] = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toDouble();
        rgb[yIndex * 3 + 1] = (yVal - 0.344 * (uVal - 128) - 0.714 * (vVal - 128)).clamp(0, 255).toDouble();
        rgb[yIndex * 3 + 2] = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toDouble();
      }
    }
    return rgb;
  }

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = norm > 0 ? math.sqrt(norm) : 1;
    return vector.map((v) => v / norm).toList();
  }

  List<double> _computeFallbackEmbedding(CameraImage image) {
    final rgb = _yuv420ToRgb(image);
    return _computeFallbackFromRgb(
      Uint8List.fromList(rgb.map((e) => e.toInt()).toList()),
      image.width,
      image.height,
    );
  }

  List<double> _computeFallbackFromRgb(Uint8List rgb, int width, int height) {
    final embedding = List<double>.filled(embeddingDim, 0);
    final pixelCount = width * height;
    for (var i = 0; i < rgb.length; i++) {
      embedding[i % embeddingDim] += rgb[i] / pixelCount;
    }
    for (var bin = 0; bin < 256; bin++) {
      var count = 0.0;
      for (var i = 0; i < rgb.length; i += 3) {
        if ((rgb[i] ~/ 16) == bin % 16) count += 1;
      }
      embedding[(256 + bin) % embeddingDim] += count / pixelCount;
    }
    return _l2Normalize(embedding);
  }

  void dispose() {
    _isLoaded = false;
  }
}
