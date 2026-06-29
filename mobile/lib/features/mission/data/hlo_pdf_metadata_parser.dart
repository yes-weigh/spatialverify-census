import 'dart:io';
import 'dart:typed_data';

/// Administrative fields printed on Census HLO layout map sidebars.
class HloPdfMetadata {
  const HloPdfMetadata({
    this.stateName,
    this.stateCode,
    this.district,
    this.districtCode,
    this.subDistrict,
    this.subDistrictCode,
    this.townVillage,
    this.townCode,
    this.wardNo,
    this.ebNo,
    this.subBlockNo,
  });

  final String? stateName;
  final String? stateCode;
  final String? district;
  final String? districtCode;
  final String? subDistrict;
  final String? subDistrictCode;
  final String? townVillage;
  final String? townCode;
  final String? wardNo;
  final String? ebNo;
  final String? subBlockNo;

  bool get hasLocationHints =>
      stateName != null ||
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
    final state = stateName?.trim();

    if (ward != null && town != null && districtName != null) {
      final wardInt = int.tryParse(ward);
      final wardLabel = wardInt != null ? wardInt.toString() : ward.replaceFirst(RegExp(r'^0+'), '');
      queries.add('Ward $wardLabel $town $districtName ${state ?? 'India'}');
    }
    if (eb != null && ward != null && town != null && districtName != null) {
      queries.add('Enumerator Block $eb Ward $ward $town $districtName ${state ?? 'India'}');
    }
    if (eb != null && town != null && districtName != null) {
      queries.add('EB $eb $town $districtName ${state ?? 'India'}');
    }
    if (sub != null && districtName != null) {
      queries.add('$sub $districtName ${state ?? 'India'}');
    }
    if (town != null && districtName != null) {
      queries.add('$town $districtName ${state ?? 'India'}');
    }
    if (districtName != null) {
      queries.add('$districtName ${state ?? 'India'}');
    }
    return queries.toSet().toList();
  }

  Map<String, dynamic> toJson() => {
        if (stateName != null) 'stateName': stateName,
        if (stateCode != null) 'stateCode': stateCode,
        if (district != null) 'district': district,
        if (districtCode != null) 'districtCode': districtCode,
        if (subDistrict != null) 'subDistrict': subDistrict,
        if (subDistrictCode != null) 'subDistrictCode': subDistrictCode,
        if (townVillage != null) 'townVillage': townVillage,
        if (townCode != null) 'townCode': townCode,
        if (wardNo != null) 'wardNo': wardNo,
        if (ebNo != null) 'ebNo': ebNo,
        if (subBlockNo != null) 'subBlockNo': subBlockNo,
      };

  factory HloPdfMetadata.fromJson(Map<String, dynamic> json) => HloPdfMetadata(
        stateName: json['stateName'] as String?,
        stateCode: json['stateCode'] as String?,
        district: json['district'] as String?,
        districtCode: json['districtCode'] as String?,
        subDistrict: json['subDistrict'] as String?,
        subDistrictCode: json['subDistrictCode'] as String?,
        townVillage: json['townVillage'] as String?,
        townCode: json['townCode'] as String?,
        wardNo: json['wardNo'] as String?,
        ebNo: json['ebNo'] as String?,
        subBlockNo: json['subBlockNo'] as String?,
      );
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

    final stateName = _match(ascii, RegExp(r'State(?:/UT)?\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final stateCode = _match(ascii, RegExp(r'State(?:/UT)?\s*Code\s*[:\.]?\s*(\d{1,2})', caseSensitive: false));
    final district = _match(ascii, RegExp(r'District\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final districtCode = _match(ascii, RegExp(r'District\s*Code\s*[:\.]?\s*(\d{1,4})', caseSensitive: false));
    final subDistrict = _match(
      ascii,
      RegExp(
        r'(?:Sub[-\s]?District|Tehsil|Taluk|PS|Dev\.?\s*Block|Circle|Mandal)\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s\.\-]{1,40})',
        caseSensitive: false,
      ),
    );
    final subDistrictCode = _match(
      ascii,
      RegExp(r'(?:Sub[-\s]?District|Tehsil|Taluk)\s*Code\s*[:\.]?\s*(\d{1,4})', caseSensitive: false),
    );
    final townVillage = _match(ascii, RegExp(r'Town/Village\s*Name\s*[:\.]?\s*([A-Za-z][A-Za-z\s]{1,40})', caseSensitive: false));
    final townCode = _match(ascii, RegExp(r'Town/Village\s*Code\s*[:\.]?\s*(\d{1,5})', caseSensitive: false));
    final wardNo = _match(ascii, RegExp(r'Ward\s*Code?\s*No\.?\s*[:\.]?\s*(\d{1,4})', caseSensitive: false));
    final ebNo = _match(
      ascii,
      RegExp(
        r'(?:Enumerator\s*Block\s*No\.?\s*\(EB\s*No\.?\)|EB\s*No\.?)\s*[:\.]?\s*(\d{1,4})',
        caseSensitive: false,
      ),
    );
    final subBlockNo = _match(
      ascii,
      RegExp(r'Sub[-\s]?Block\s*No\.?\s*[:\.]?\s*(\d{1,4})', caseSensitive: false),
    );

    final meta = HloPdfMetadata(
      stateName: _cleanLabel(stateName),
      stateCode: stateCode,
      district: _cleanLabel(district),
      districtCode: districtCode,
      subDistrict: _cleanLabel(subDistrict),
      subDistrictCode: subDistrictCode,
      townVillage: _cleanLabel(townVillage),
      townCode: townCode,
      wardNo: wardNo,
      ebNo: ebNo,
      subBlockNo: subBlockNo,
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
