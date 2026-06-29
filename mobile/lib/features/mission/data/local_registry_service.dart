import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/models.dart';
import '../models/mission_models.dart';

/// On-device project + EB registry — no backend required.
class LocalRegistryService {
  LocalRegistryService();

  static const defaultProjectId = 'local-project';
  static const _boxName = 'local_registry_v1';
  Box<dynamic>? _box;
  final _uuid = const Uuid();

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox(_boxName);
    await _seedDefaultProjectIfNeeded();
  }

  Future<void> ensureDefaultProject() async {
    await init();
  }

  Future<void> _seedDefaultProjectIfNeeded() async {
    final projects = listProjectsRaw();
    if (projects.isNotEmpty) return;
    await _box!.put('projects', [
      {
        'id': defaultProjectId,
        'name': 'My Field Missions',
        'description': 'On-device HLB missions',
        'isActive': true,
      },
    ]);
  }

  List<Map<String, dynamic>> listProjectsRaw() {
    final raw = _box?.get('projects') as List<dynamic>? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Project> listProjects() {
    return listProjectsRaw()
        .map((p) => Project(
              id: p['id'] as String,
              name: p['name'] as String,
              description: p['description'] as String?,
              isActive: p['isActive'] as bool? ?? true,
            ),)
        .toList();
  }

  List<Map<String, dynamic>> listEbsRaw(String projectId) {
    final key = 'ebs_$projectId';
    final raw = _box?.get(key) as List<dynamic>? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<EnumerationBlock> listEbs(String projectId) {
    return listEbsRaw(projectId).map(_ebFromMap).toList();
  }

  /// One enumerator → one HLB per project (reuse if already created).
  EnumerationBlock? getEnumeratorEb(String projectId) {
    final ebs = listEbs(projectId);
    return ebs.isEmpty ? null : ebs.first;
  }

  EnumerationBlock _ebFromMap(Map<String, dynamic> m) => EnumerationBlock(
        id: m['id'] as String,
        projectId: m['projectId'] as String,
        ebCode: m['ebCode'] as String,
        name: m['name'] as String?,
        status: m['status'] as String? ?? 'draft',
        progressPercent: (m['progressPercent'] as num?)?.toDouble() ?? 0,
        totalBuildings: m['totalBuildings'] as int? ?? 0,
      );

  Future<EnumerationBlock> createEb({
    required String projectId,
    required String ebCode,
    String? name,
  }) async {
    await init();
    final eb = {
      'id': _uuid.v4(),
      'projectId': projectId,
      'ebCode': ebCode,
      'name': name,
      'status': 'draft',
      'progressPercent': 0,
      'totalBuildings': 0,
      'createdAt': DateTime.now().toIso8601String(),
    };
    final key = 'ebs_$projectId';
    final list = listEbsRaw(projectId)..add(eb);
    await _box!.put(key, list);
    return _ebFromMap(eb);
  }

  Future<void> updateEbCode(String projectId, String ebId, String ebCode, {String? name}) async {
    await init();
    final key = 'ebs_$projectId';
    final list = listEbsRaw(projectId);
    final idx = list.indexWhere((e) => e['id'] == ebId);
    if (idx < 0) return;
    list[idx]['ebCode'] = ebCode;
    if (name != null) list[idx]['name'] = name;
    await _box!.put(key, list);
  }

  Future<void> updateEbStatus(String projectId, String ebId, {String? status, int? totalBuildings, double? progressPercent}) async {
    await init();
    final key = 'ebs_$projectId';
    final list = listEbsRaw(projectId);
    final idx = list.indexWhere((e) => e['id'] == ebId);
    if (idx < 0) return;
    if (status != null) list[idx]['status'] = status;
    if (totalBuildings != null) list[idx]['totalBuildings'] = totalBuildings;
    if (progressPercent != null) list[idx]['progressPercent'] = progressPercent;
    await _box!.put(key, list);
  }
}
