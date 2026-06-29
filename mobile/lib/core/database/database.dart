import 'package:drift/drift.dart';

import 'database_connection.dart';

part 'database.g.dart';

class LocalUsers extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get role => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalProjects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get boundaryJson => text().nullable()();
  TextColumn get surveyRulesJson => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalAssets extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get status => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  RealColumn get heading => real().nullable()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  TextColumn get clientId => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalDetections extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get categoryLabel => text()();
  RealColumn get confidence => real()();
  TextColumn get boundingBoxJson => text()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get altitude => real().nullable()();
  RealColumn get heading => real().nullable()();
  TextColumn get clientId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalVerifications extends Table {
  TextColumn get id => text()();
  TextColumn get detectionId => text()();
  TextColumn get aiPrediction => text()();
  RealColumn get confidence => real()();
  TextColumn get humanDecision => text()();
  TextColumn get editedCategory => text().nullable()();
  RealColumn get editedLat => real().nullable()();
  RealColumn get editedLng => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get clientId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get verifiedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalAnchors extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get assetId => text().nullable()();
  TextColumn get anchorId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  RealColumn get heading => real().nullable()();
  TextColumn get cameraOrientationJson => text().nullable()();
  TextColumn get anchorDataJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isRelocated => boolean().withDefault(const Constant(false))();
  TextColumn get clientId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSurveySessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  RealColumn get coveragePercentage => real().withDefault(const Constant(0))();
  TextColumn get pathJson => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get clientId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get clientId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

class LocalAssetCategories extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get detectionLabelsJson => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalAssetObservations extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get assetId => text().nullable()();
  TextColumn get detectionId => text().nullable()();
  TextColumn get embeddingJson => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  RealColumn get accuracy => real().nullable()();
  RealColumn get heading => real().nullable()();
  TextColumn get viewType => text().withDefault(const Constant('unknown'))();
  TextColumn get categoryLabel => text().nullable()();
  TextColumn get weather => text().nullable()();
  TextColumn get lighting => text().nullable()();
  TextColumn get deviceModel => text().nullable()();
  RealColumn get cameraFov => real().nullable()();
  TextColumn get cameraResolution => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get capturedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalAssetEmbeddings extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get assetId => text()();
  TextColumn get detectionId => text().nullable()();
  TextColumn get embeddingJson => text()();
  TextColumn get categoryLabel => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalIdentityResolutions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get detectionId => text().nullable()();
  TextColumn get queryCategory => text()();
  TextColumn get verdict => text().nullable()();
  TextColumn get matchedAssetId => text().nullable()();
  RealColumn get finalConfidence => real().nullable()();
  TextColumn get embeddingJson => text()();
  TextColumn get payloadJson => text()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  LocalUsers,
  LocalProjects,
  LocalAssets,
  LocalDetections,
  LocalVerifications,
  LocalAnchors,
  LocalSurveySessions,
  SyncQueueItems,
  LocalAssetCategories,
  LocalAssetEmbeddings,
  LocalAssetObservations,
  LocalIdentityResolutions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppDatabaseConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(localAssetEmbeddings);
            await m.createTable(localIdentityResolutions);
          }
          if (from < 3) {
            await m.createTable(localAssetObservations);
          }
          if (from < 4) {
            await m.addColumn(localAssetObservations, localAssetObservations.deviceModel);
            await m.addColumn(localAssetObservations, localAssetObservations.cameraFov);
            await m.addColumn(localAssetObservations, localAssetObservations.cameraResolution);
          }
        },
      );

  Future<List<LocalAsset>> getAssetsByProject(String projectId) {
    return (select(localAssets)..where((a) => a.projectId.equals(projectId))).get();
  }

  Future<List<LocalAsset>> getAssetsByStatus(String projectId, String status) {
    return (select(localAssets)
          ..where((a) => a.projectId.equals(projectId) & a.status.equals(status)))
        .get();
  }

  Future<List<SyncQueueItem>> getPendingSyncItems() {
    return (select(syncQueueItems)
          ..where((s) => s.status.equals('pending') | s.status.equals('failed'))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
        .get();
  }

  Future<int> enqueueSyncItem(SyncQueueItemsCompanion item) {
    return into(syncQueueItems).insert(item);
  }

  Future<void> updateSyncStatus(int id, String status, {String? error}) {
    return (update(syncQueueItems)..where((s) => s.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: Value(status),
        errorMessage: Value(error),
        syncedAt: status == 'synced' ? Value(DateTime.now()) : const Value.absent(),
      ),
    );
  }

  Future<LocalSurveySession?> getActiveSession(String projectId) {
    return (select(localSurveySessions)
          ..where((s) => s.projectId.equals(projectId) & s.endedAt.isNull()))
        .getSingleOrNull();
  }
}
