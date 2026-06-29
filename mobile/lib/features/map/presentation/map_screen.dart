import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;

  @override
  void initState() {
    super.initState();
    if (AppConfig.mapboxAccessToken.isNotEmpty) {
      MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _annotationManager = await mapboxMap.annotations.createPointAnnotationManager();

    await mapboxMap.style.setStyleURI(MapboxStyles.MAPBOX_STREETS);

    final assets = await ref.read(assetsProvider(widget.projectId).future);
    await _renderAssets(assets);
  }

  Future<void> _renderAssets(List<Asset> assets) async {
    if (_annotationManager == null) return;

    await _annotationManager!.deleteAll();

    final annotations = <PointAnnotationOptions>[];
    for (final asset in assets) {
      final color = _statusToColor(asset.status);
      annotations.add(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(asset.longitude, asset.latitude),
          ),
          iconSize: 1.2,
          iconColor: color,
          textField: asset.name,
          textSize: 12,
          textColor: Colors.white.value,
          textHaloColor: Colors.black.value,
          textHaloWidth: 1,
        ),
      );
    }

    if (annotations.isNotEmpty) {
      await _annotationManager!.createMulti(annotations);
    }
  }

  int _statusToColor(AssetStatus status) {
    switch (status) {
      case AssetStatus.verified:
        return Colors.green.value;
      case AssetStatus.pending:
        return Colors.yellow.value;
      case AssetStatus.rejected:
        return Colors.red.value;
      case AssetStatus.notSurveyed:
        return Colors.grey.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(assetsProvider(widget.projectId));

    ref.listen(assetsProvider(widget.projectId), (prev, next) {
      next.whenData((assets) => _renderAssets(assets));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          _LegendButton(),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () async {
              await _mapboxMap?.flyTo(
                CameraOptions(
                  center: Point(coordinates: Position(-122.4194, 37.7749)),
                  zoom: 16,
                ),
                MapAnimationOptions(duration: 1000),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('mapWidget'),
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(-122.4194, 37.7749)),
              zoom: 15,
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: assetsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (assets) => _AssetCountBar(assets: assets),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.legend_toggle_outlined),
      itemBuilder: (_) => [
        _legendItem('Verified', AppTheme.verified),
        _legendItem('Pending', AppTheme.pending),
        _legendItem('Rejected', AppTheme.rejected),
        _legendItem('Not Surveyed', AppTheme.notSurveyed),
      ],
    );
  }

  PopupMenuItem<String> _legendItem(String label, Color color) {
    return PopupMenuItem(
      value: label,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _AssetCountBar extends StatelessWidget {
  const _AssetCountBar({required this.assets});

  final List<Asset> assets;

  @override
  Widget build(BuildContext context) {
    final verified = assets.where((a) => a.status == AssetStatus.verified).length;
    final pending = assets.where((a) => a.status == AssetStatus.pending).length;
    final rejected = assets.where((a) => a.status == AssetStatus.rejected).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: AppTheme.glassDecoration(radius: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _CountItem(label: 'Verified', count: verified, color: AppTheme.verified),
          _CountItem(label: 'Pending', count: pending, color: AppTheme.pending),
          _CountItem(label: 'Rejected', count: rejected, color: AppTheme.rejected),
        ],
      ),
    );
  }
}

class _CountItem extends StatelessWidget {
  const _CountItem({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
