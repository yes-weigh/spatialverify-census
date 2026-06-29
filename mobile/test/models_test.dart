import 'package:flutter_test/flutter_test.dart';
import 'package:spatialverify/core/models/models.dart';

void main() {
  group('Models', () {
    test('User.fromJson parses correctly', () {
      final user = User.fromJson({
        'id': '123',
        'email': 'test@example.com',
        'firstName': 'Test',
        'lastName': 'User',
        'role': 'field_worker',
      });

      expect(user.email, 'test@example.com');
      expect(user.role, UserRole.fieldWorker);
    });

    test('Asset.fromJson parses location', () {
      final asset = Asset.fromJson({
        'id': '456',
        'project_id': '789',
        'name': 'Pole',
        'status': 'verified',
        'location': {
          'type': 'Point',
          'coordinates': [-122.4194, 37.7749],
        },
      });

      expect(asset.latitude, 37.7749);
      expect(asset.longitude, -122.4194);
      expect(asset.status, AssetStatus.verified);
    });

    test('BoundingBox toJson', () {
      const bbox = BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4);
      final json = bbox.toJson();

      expect(json['x'], 0.1);
      expect(json['width'], 0.3);
    });
  });
}
