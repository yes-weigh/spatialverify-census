import 'landmark_anchor_models.dart';

/// Minimum control pins matched to Google Maps before continuing to satellite.
const kMinGeorefMatchedPins = 3;

/// User-placed control pin on the official HLO map (numbered 1, 2, 3…).
class PdfGeorefPin {
  PdfGeorefPin({
    required this.number,
    required this.uvX,
    required this.uvY,
    this.place,
    this.searchText = '',
  });

  final int number;
  final double uvX;
  final double uvY;
  PlaceMatchCandidate? place;
  String searchText;

  PdfGeorefPin copyWith({
    int? number,
    double? uvX,
    double? uvY,
    PlaceMatchCandidate? place,
    String? searchText,
    bool clearPlace = false,
  }) =>
      PdfGeorefPin(
        number: number ?? this.number,
        uvX: uvX ?? this.uvX,
        uvY: uvY ?? this.uvY,
        place: clearPlace ? null : (place ?? this.place),
        searchText: searchText ?? this.searchText,
      );

  bool get isReady => place != null;
}
