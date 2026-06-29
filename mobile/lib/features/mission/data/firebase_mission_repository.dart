import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/models.dart';
import '../../../core/storage/mission_layout_storage.dart';
import '../models/mission_models.dart';
import 'hlb_local_state.dart';

/// Cloud persistence for HLB missions — Firestore state + Storage for PDF/layout.
class FirebaseMissionRepository {
  FirebaseMissionRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const defaultProjectId = 'default-project';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final _uuid = const Uuid();

  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => uid != null;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final id = uid;
    if (id == null) return null;
    return _db.collection('users').doc(id);
  }

  CollectionReference<Map<String, dynamic>>? get _projectsCol => _userDoc?.collection('projects');

  String _layoutStoragePath(String projectId, String ebId) =>
      'users/$uid/projects/$projectId/ebs/$ebId/layout.png';

  String _pdfStoragePath(String projectId, String ebId) =>
      'users/$uid/projects/$projectId/ebs/$ebId/source.pdf';

  Future<void> ensureWorkspace() async {
    final user = _userDoc;
    if (user == null) return;
    await user.set({
      'email': _auth.currentUser?.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final projects = await listProjects();
    if (projects.isEmpty) {
      await _projectsCol!.doc(defaultProjectId).set({
        'name': 'My Field Missions',
        'description': 'Cloud-synced HLB field work',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Project>> listProjects() async {
    final col = _projectsCol;
    if (col == null) return [];
    final snap = await col.orderBy('createdAt').get();
    return snap.docs.map((d) {
      final data = d.data();
      return Project(
        id: d.id,
        name: data['name'] as String? ?? 'Mission',
        description: data['description'] as String?,
        isActive: data['isActive'] as bool? ?? true,
      );
    }).toList();
  }

  Future<List<EnumerationBlock>> listEbs(String projectId) async {
    final col = _projectsCol?.doc(projectId).collection('ebs');
    if (col == null) return [];
    final snap = await col.orderBy('updatedAt', descending: true).get();
    return snap.docs.map((d) => _ebFromDoc(d.id, projectId, d.data())).toList();
  }

  EnumerationBlock _ebFromDoc(String id, String projectId, Map<String, dynamic> data) {
    final blockStatus = data['blockStatus'] as String? ?? 'draft';
    final buildings = (data['buildings'] as List<dynamic>?)?.length ?? 0;
    final phase = data['phase'] as String? ?? 'mapping';
    final status = blockStatus == 'published' || phase != 'mapping' ? 'published' : 'draft';
    return EnumerationBlock(
      id: id,
      projectId: projectId,
      ebCode: data['ebCode'] as String? ?? 'HLB',
      name: data['name'] as String?,
      status: status,
      progressPercent: (data['progressPercent'] as num?)?.toDouble() ?? 0,
      totalBuildings: buildings,
    );
  }

  Future<EnumerationBlock> createEb({
    required String projectId,
    required String ebCode,
    String? name,
  }) async {
    final col = _projectsCol?.doc(projectId).collection('ebs');
    if (col == null) throw StateError('Not signed in');

    final ebId = _uuid.v4();
    final now = DateTime.now();
    final state = HlbLocalState(ebId: ebId, ebCode: ebCode, projectId: projectId, updatedAt: now);
    await col.doc(ebId).set({
      ...state.toJson(),
      'name': name,
      'progressPercent': 0,
      'layoutStoragePath': _layoutStoragePath(projectId, ebId),
      'pdfStoragePath': _pdfStoragePath(projectId, ebId),
    });
    return _ebFromDoc(ebId, projectId, state.toJson());
  }

  Future<void> updateEbCode(String projectId, String ebId, String ebCode, {String? name}) async {
    final ref = _projectsCol?.doc(projectId).collection('ebs').doc(ebId);
    if (ref == null) return;
    await ref.set({
      'ebCode': ebCode,
      if (name != null) 'name': name,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> updateEbStatus(
    String projectId,
    String ebId, {
    String? status,
    int? totalBuildings,
    double? progressPercent,
  }) async {
    final ref = _projectsCol?.doc(projectId).collection('ebs').doc(ebId);
    if (ref == null) return;
    await ref.set({
      if (status != null) 'blockStatus': status == 'published' ? 'published' : 'draft',
      if (totalBuildings != null) 'totalBuildings': totalBuildings,
      if (progressPercent != null) 'progressPercent': progressPercent,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<HlbLocalState?> pullEbState(String projectId, String ebId) async {
    final ref = _projectsCol?.doc(projectId).collection('ebs').doc(ebId);
    if (ref == null) return null;
    final snap = await ref.get();
    if (!snap.exists) return null;

    final data = Map<String, dynamic>.from(snap.data()!);
    data.remove('layoutStoragePath');
    data.remove('pdfStoragePath');
    data.remove('name');
    data.remove('progressPercent');
    data.remove('totalBuildings');

    var state = HlbLocalState.fromJson(data);
    state = await _hydrateLayoutFiles(projectId, ebId, state);
    return state.copyWith(serverSyncedAt: DateTime.now());
  }

  Future<void> pushEbState(HlbLocalState state) async {
    final ref = _projectsCol?.doc(state.projectId).collection('ebs').doc(state.ebId);
    if (ref == null) return;

    final payload = state.toJson()
      ..['updatedAt'] = DateTime.now().toIso8601String()
      ..['layoutStoragePath'] = _layoutStoragePath(state.projectId, state.ebId)
      ..['pdfStoragePath'] = _pdfStoragePath(state.projectId, state.ebId)
      ..['progressPercent'] = _progressPercent(state)
      ..['totalBuildings'] = state.buildings.length;

    await ref.set(payload, SetOptions(merge: true));
    await _uploadLayoutIfPresent(state);
    await _uploadPdfIfPresent(state);
  }

  double _progressPercent(HlbLocalState state) {
    if (state.buildings.isEmpty) return 0;
    final listed = state.buildings.where((b) => b.buildingNumber > 0).length;
    return (listed / state.buildings.length * 100).clamp(0, 100);
  }

  Future<void> uploadLayoutBytes(String projectId, String ebId, List<int> bytes) async {
    if (uid == null) return;
    final localPath = await saveMissionLayoutBytes(ebId, bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    await _storage.ref(_layoutStoragePath(projectId, ebId)).putFile(File(localPath));
  }

  Future<void> uploadSourcePdf(String projectId, String ebId, File pdfFile) async {
    if (uid == null) return;
    await _storage.ref(_pdfStoragePath(projectId, ebId)).putFile(pdfFile);
    final ref = _projectsCol?.doc(projectId).collection('ebs').doc(ebId);
    await ref?.set({
      'sourcePdfName': pdfFile.path.split(Platform.pathSeparator).last,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<HlbLocalState> _hydrateLayoutFiles(String projectId, String ebId, HlbLocalState state) async {
    final layoutRef = _storage.ref(_layoutStoragePath(projectId, ebId));
    try {
      final localPath = await defaultMissionLayoutRef(ebId);
      if (localPath != null && !await missionLayoutExists(localPath)) {
        await layoutRef.writeToFile(File(localPath));
        final intel = Map<String, dynamic>.from(state.missionIntelligence ?? {});
        intel['layoutImagePath'] = localPath;
        return state.copyWith(missionIntelligence: intel);
      }
    } catch (_) {}
    return state;
  }

  Future<void> _uploadLayoutIfPresent(HlbLocalState state) async {
    if (uid == null) return;
    final intel = state.missionIntelligence;
    var path = intel?['layoutImagePath'] as String?;
    path ??= await defaultMissionLayoutRef(state.ebId);
    if (path == null || !await missionLayoutExists(path)) return;
    try {
      await _storage.ref(_layoutStoragePath(state.projectId, state.ebId)).putFile(File(path));
    } catch (_) {}
  }

  Future<void> _uploadPdfIfPresent(HlbLocalState state) async {
    if (uid == null) return;
    final pdfPath = state.layoutGeoref?['sourcePdfPath'] as String?;
    if (pdfPath == null || !await File(pdfPath).exists()) return;
    try {
      await _storage.ref(_pdfStoragePath(state.projectId, state.ebId)).putFile(File(pdfPath));
    } catch (_) {}
  }
}
