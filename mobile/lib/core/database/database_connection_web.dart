import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async => WebDatabase('spatialverify_db'));
}
