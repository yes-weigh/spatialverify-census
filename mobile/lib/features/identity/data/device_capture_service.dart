import 'dart:io';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Capture metadata stored with each observation for device-bias compensation.
class DeviceCaptureMetadata {
  const DeviceCaptureMetadata({
    this.deviceModel,
    this.cameraFov,
    this.cameraResolution,
  });

  final String? deviceModel;
  final double? cameraFov;
  final String? cameraResolution;

  Map<String, dynamic> toPayload() => {
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (cameraFov != null) 'cameraFov': cameraFov,
        if (cameraResolution != null) 'cameraResolution': cameraResolution,
      };
}

class DeviceCaptureService {
  DeviceCaptureService({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;
  String? _cachedDeviceModel;

  Future<DeviceCaptureMetadata> capture({
    CameraController? controller,
    CameraDescription? description,
  }) async {
    final deviceModel = await _getDeviceModel();
    final resolution = _captureResolution(controller);
    final fov = _estimateFov(description);

    return DeviceCaptureMetadata(
      deviceModel: deviceModel,
      cameraFov: fov,
      cameraResolution: resolution,
    );
  }

  Future<String?> _getDeviceModel() async {
    if (_cachedDeviceModel != null) return _cachedDeviceModel;

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _cachedDeviceModel = '${info.manufacturer} ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        _cachedDeviceModel = info.utsname.machine;
      }
    } catch (_) {
      return null;
    }

    return _cachedDeviceModel;
  }

  String? _captureResolution(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) return null;
    final size = controller.value.previewSize;
    if (size == null) return null;
    return '${size.width.toInt()}x${size.height.toInt()}';
  }

  /// Approximate horizontal FOV from lens type when exact sensor data is unavailable.
  double? _estimateFov(CameraDescription? description) {
    if (description == null) return null;

    final name = description.name.toLowerCase();
    if (name.contains('ultra') || name.contains('0.5')) return 120;
    if (name.contains('tele') || name.contains('2x') || name.contains('3x')) return 30;
    if (description.lensDirection == CameraLensDirection.front) return 70;
    return 78;
  }
}
