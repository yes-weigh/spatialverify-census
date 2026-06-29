import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/storage/mission_layout_storage.dart';

/// Layout PNG from disk (mobile) or Hive (web) or network URL.
class MissionLayoutImage extends StatelessWidget {
  const MissionLayoutImage({
    required this.ref,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String ref;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return Image.network(ref, fit: fit);
    }

    return FutureBuilder<Uint8List?>(
      future: readMissionLayoutBytes(ref),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(bytes, fit: fit);
      },
    );
  }
}
