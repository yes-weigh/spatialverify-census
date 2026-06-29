import 'package:flutter/material.dart';
import '../../scanner/data/object_detector.dart';

class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    required this.detections,
    required this.onDetectionTap,
    super.key,
  });

  final List<DetectedObject> detections;
  final void Function(DetectedObject) onDetectionTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: detections.map((detection) {
            final left = detection.boundingBox.x * constraints.maxWidth;
            final top = detection.boundingBox.y * constraints.maxHeight;
            final width = detection.boundingBox.width * constraints.maxWidth;
            final height = detection.boundingBox.height * constraints.maxHeight;

            return Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: GestureDetector(
                onTap: () => onDetectionTap(detection),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _confidenceColor(detection.confidence),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      color: _confidenceColor(detection.confidence).withValues(alpha: 0.8),
                      child: Text(
                        '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color(0xFF00E676);
    if (confidence >= 0.6) return const Color(0xFFFFD740);
    return const Color(0xFFFF5252);
  }
}
