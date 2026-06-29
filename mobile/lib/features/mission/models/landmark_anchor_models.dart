import 'package:latlong2/latlong.dart';

/// Text label detected on the satellite panel of an HLO map (normalized UV 0–1).
class MapTextLabel {
  const MapTextLabel({
    required this.id,
    required this.text,
    required this.uvX,
    required this.uvY,
  });

  final String id;
  final String text;
  final double uvX;
  final double uvY;

  MapTextLabel copyWith({
    String? text,
    double? uvX,
    double? uvY,
  }) =>
      MapTextLabel(
        id: id,
        text: text ?? this.text,
        uvX: uvX ?? this.uvX,
        uvY: uvY ?? this.uvY,
      );
}

/// A Google Places candidate for a map label.
class PlaceMatchCandidate {
  const PlaceMatchCandidate({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
  });

  final String placeId;
  final String name;
  final String address;
  final LatLng location;
}

/// One OCR label with Places suggestions — user picks/confirms a match.
class LandmarkMatchRow {
  LandmarkMatchRow({
    required this.label,
    required this.suggestions,
    this.selected,
    this.confirmed = false,
  });

  final MapTextLabel label;
  final List<PlaceMatchCandidate> suggestions;
  PlaceMatchCandidate? selected;
  bool confirmed;

  bool get isReady => confirmed && selected != null;

  LandmarkMatchRow copyWith({
    MapTextLabel? label,
    List<PlaceMatchCandidate>? suggestions,
    PlaceMatchCandidate? selected,
    bool? confirmed,
  }) =>
      LandmarkMatchRow(
        label: label ?? this.label,
        suggestions: suggestions ?? this.suggestions,
        selected: selected ?? this.selected,
        confirmed: confirmed ?? this.confirmed,
      );
}
