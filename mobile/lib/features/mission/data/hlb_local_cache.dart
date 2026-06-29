import 'package:hive_flutter/hive_flutter.dart';

import 'hlb_local_state.dart';

/// Persists complete HLB state per enumeration block.
class HlbLocalCache {
  static const _boxName = 'hlb_local_state';

  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox(_boxName);
  }

  Future<HlbLocalState?> get(String ebId) async {
    await init();
    final raw = _box!.get(ebId);
    if (raw == null) return null;
    return HlbLocalState.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> put(HlbLocalState state) async {
    await init();
    await _box!.put(state.ebId, state.toJson());
  }

  Future<HlbLocalState> getOrCreate({
    required String ebId,
    required String ebCode,
    required String projectId,
  }) async {
    final existing = await get(ebId);
    if (existing != null) return existing;
    final state = HlbLocalState(ebId: ebId, ebCode: ebCode, projectId: projectId);
    await put(state);
    return state;
  }

  Future<void> remove(String ebId) async {
    await init();
    await _box!.delete(ebId);
  }
}
