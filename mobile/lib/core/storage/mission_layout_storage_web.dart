import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

const missionLayoutUriPrefix = 'mission-layout://';

Future<Box<dynamic>> _layoutBox() => Hive.openBox('mission_layout_bytes');

String _hiveKey(String ebId) => '$ebId/layout.png';

Future<String> saveMissionLayoutBytes(String ebId, Uint8List bytes) async {
  final box = await _layoutBox();
  await box.put(_hiveKey(ebId), bytes);
  return '$missionLayoutUriPrefix$ebId/layout.png';
}

Future<String> saveMissionFullSheetBytes(String ebId, Uint8List bytes) async {
  final box = await _layoutBox();
  await box.put('$ebId/fullSheet.png', bytes);
  return '$missionLayoutUriPrefix$ebId/fullSheet.png';
}

Future<String?> defaultMissionLayoutRef(String ebId) async {
  final box = await _layoutBox();
  return box.containsKey(_hiveKey(ebId)) ? '$missionLayoutUriPrefix$ebId/layout.png' : null;
}

Future<String?> defaultMissionFullSheetRef(String ebId) async {
  final box = await _layoutBox();
  return box.containsKey('$ebId/fullSheet.png') ? '$missionLayoutUriPrefix$ebId/fullSheet.png' : null;
}

Future<bool> missionLayoutExists(String ref) async {
  if (ref.startsWith('http://') || ref.startsWith('https://')) return true;
  final bytes = await readMissionLayoutBytes(ref);
  return bytes != null && bytes.isNotEmpty;
}

Future<Uint8List?> readMissionLayoutBytes(String ref) async {
  if (ref.startsWith(missionLayoutUriPrefix)) {
    final parts = ref.substring(missionLayoutUriPrefix.length).split('/');
    final ebId = parts.first;
    final fileName = parts.length > 1 ? parts.sublist(1).join('/') : 'layout.png';
    final box = await _layoutBox();
    final key = fileName == 'fullSheet.png' ? '$ebId/fullSheet.png' : _hiveKey(ebId);
    final data = box.get(key);
    if (data is Uint8List) return data;
    if (data is List) return Uint8List.fromList(data.cast<int>());
    return null;
  }
  return null;
}
