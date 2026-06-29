import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const missionLayoutUriPrefix = 'mission-layout://';

Future<String> saveMissionLayoutBytes(String ebId, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final missionDir = Directory(p.join(dir.path, 'missions', ebId));
  await missionDir.create(recursive: true);
  final path = p.join(missionDir.path, 'layout.png');
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<String> saveMissionFullSheetBytes(String ebId, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final missionDir = Directory(p.join(dir.path, 'missions', ebId));
  await missionDir.create(recursive: true);
  final path = p.join(missionDir.path, 'fullSheet.png');
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<String?> defaultMissionLayoutRef(String ebId) async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'missions', ebId, 'layout.png');
}

Future<String?> defaultMissionFullSheetRef(String ebId) async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'missions', ebId, 'fullSheet.png');
}

Future<bool> missionLayoutExists(String ref) async {
  if (ref.startsWith('http://') || ref.startsWith('https://')) return true;
  if (ref.startsWith(missionLayoutUriPrefix)) return false;
  return File(ref).exists();
}

Future<Uint8List?> readMissionLayoutBytes(String ref) async {
  if (ref.startsWith('http://') || ref.startsWith('https://')) return null;
  if (ref.startsWith(missionLayoutUriPrefix)) return null;
  final file = File(ref);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
