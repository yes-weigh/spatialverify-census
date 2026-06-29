import 'dart:io';
import 'dart:typed_data';

/// Administrative fields printed on Census HLO layout map sidebars.
class HloPdfMetadata {
  const HloPdfMetadata({
    this.district,
    this.subDistrict,
    this.townVillage,
    this.wardNo,
    this.ebNo,
  });

  final String? district;
  final String? subDistrict;
  final String? townVillage;
  final String? wardNo;
  final String? ebNo;

  bool get hasLocationHints =>
      district != null ||
      subDistrict != null ||
      townVillage != null ||
      wardNo != null ||
      ebNo != null;

  /// Queries ordered from most specific to broadest.
  List<String> geocodeQueries() {
    final queries = <String>[];
    final districtName = district?.trim();
    final sub = subDistrict?.trim();
    final town = townVillage?.trim();
    final ward = wardNo?.trim();
    final eb = ebNo?.trim();

    if (ward != null && town != null && districtName != null) {
      final wardInt = int.tryParse(ward);
      final wardLabel = wardInt != null ? wardInt.toString() : ward.replaceFirst(RegExp(r'^0+'), '');
      queries.add('Ward $wardLabel $town $districtName Kerala India');
    }
    if (eb != null && ward != null && town != null && districtName != null) {
      queries.add('Enumerator Block $eb Ward $ward $town $districtName Kerala India');
    }
    if (eb != null && town != null && districtName != null) {
      queries.add('EB $eb $town $districtName Kerala India');
    }
    if (sub != null && districtName != null) {
      queries.add('$sub $districtName Kerala India');
    }
    if (town != null && districtName != null) {
      queries.add('$town $districtName Kerala India');
    }
    if (districtName != null) {
      queries.add('$districtName Kerala India');
    }
    return queries.toSet().toList();
  }

  Map<String, dynamic> toJson() => {
        if (district != null) 'district': district,
        if (subDistrict != null) 'subDistrict': subDistrict,
        if (townVillage != null) 'townVillage': townVillage,
        if (wardNo != null) 'wardNo': wardNo,
        if (ebNo != null) 'ebNo': ebNo,
      };
}

/// Extracts sidebar labels from Census PDF bytes (text is embedded in content streams).
class HloPdfMetadataParser {
  static Future<HloPdfMetadata?> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    if (!lower.endsWith('.pdf')) return null;
    final bytes = await file.readAsBytes();
    return parseBytes(bytes);
  }

  static HloPdfMetadata? parseBytes(Uint8List bytes) {
    final ascii = _extractReadableText(bytes);
    if (ascii.length < 40) return null;

    final district = _match(ascii, RegExp(r'District\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final subDistrict = _match(ascii, RegExp(r'Sub[-\s]?District\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final townVillage = _match(ascii, RegExp(r'Town/Village\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final wardNo = _match(ascii, RegExp(r'Ward\s*No\.?\s*[:\.]?\s*(\d{1,4})', caseSensitive: false));
    final ebNo = _match(
      ascii,
      RegExp(
        r'(?:Enumerator\s*Block\s*No\.?\s*\(EB\s*No\.?\)|EB\s*No\.?)\s*[:\.]?\s*(\d{1,4})',
        caseSensitive: false,
      ),
    );

    final meta = HloPdfMetadata(
      district: _cleanLabel(district),
      subDistrict: _cleanLabel(subDistrict),
      townVillage: _cleanLabel(townVillage),
      wardNo: wardNo,
      ebNo: ebNo,
    );
    return meta.hasLocationHints ? meta : null;
  }

  static String _extractReadableText(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      if (b == 10 || b == 13 || (b >= 32 && b <= 126)) {
        buffer.writeCharCode(b);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _match(String haystack, RegExp pattern) {
    final m = pattern.firstMatch(haystack);
    return m?.group(1)?.trim();
  }

  static String? _cleanLabel(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'\bCode\s*No\.?\b.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
