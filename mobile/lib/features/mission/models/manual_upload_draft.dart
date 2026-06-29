import 'dart:typed_data';

import '../data/hlo_pdf_metadata_parser.dart';
import '../data/mission_seed_location_resolver.dart';

/// PDF rasterized and ready for manual boundary + pin georeferencing.
class ManualUploadDraft {
  const ManualUploadDraft({
    required this.mapBytes,
    required this.layoutPath,
    required this.mapFilePath,
    required this.seed,
    this.metadata,
  });

  final Uint8List mapBytes;
  final String layoutPath;
  final String mapFilePath;
  final MissionSeedLocation seed;
  final HloPdfMetadata? metadata;
}
