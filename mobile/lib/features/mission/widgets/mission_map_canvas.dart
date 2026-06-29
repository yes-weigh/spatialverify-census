import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_directions_service.dart';
import '../data/mission_map_session.dart';
import '../models/layout_georef_models.dart';
import 'google_mission_map.dart';
import 'mission_satellite_map.dart';

/// Unified mission map — Google Maps when configured, Esri satellite fallback.
class MissionMapCanvas extends StatelessWidget {
  const MissionMapCanvas({
    required this.center,
    required this.boundary,
    this.regions = const [],
    this.userPosition,
    this.mode = MissionMapMode.prediction,
    this.boundaryDrawProgress = 1.0,
    this.showPdfOverlay = false,
    this.pdfImageUrl,
    this.pdfBounds,
    this.pdfOpacity = 0.45,
    this.showRegionPins = false,
    this.showBoundary = true,
    this.showNavigationRoute = true,
    this.showStartMarker = true,
    this.draftPins = const [],
    this.showDraftPins = true,
    this.hlbBuildings = const [],
    this.hlbLandmarks = const [],
    this.hlbLineFeatures = const [],
    this.lineDraftPoints = const [],
    this.showHlbMarkings = true,
    this.walkPath = const [],
    this.showWalkPath = true,
    this.showBasemap = true,
    this.mapType = gmaps.MapType.hybrid,
    this.navigationDestination,
    this.navigationOrigin,
    this.travelMode = NavigationTravelMode.bicycling,
    this.fitToken = 0,
    this.followUserLocation = true,
    this.lockCameraGestures = false,
    this.onRouteLoaded,
    this.onMapLongPress,
    this.onMapTap,
    this.fineTuningLandmarkId,
    this.fineTuningLandmarkPosition,
    this.onLandmarkDrag,
    super.key,
  });

  final LatLng center;
  final List<GpsPoint> boundary;
  final List<MapRegionMarker> regions;
  final LatLng? userPosition;
  final MissionMapMode mode;
  final double boundaryDrawProgress;
  final bool showPdfOverlay;
  final String? pdfImageUrl;
  final ImageBounds? pdfBounds;
  final double pdfOpacity;
  final bool showRegionPins;
  final bool showBoundary;
  final bool showNavigationRoute;
  final bool showStartMarker;
  final List<MissionDraftPin> draftPins;
  final bool showDraftPins;
  final List<MissionHlbBuildingPin> hlbBuildings;
  final List<MissionHlbLandmarkPin> hlbLandmarks;
  final List<MissionMapLineFeature> hlbLineFeatures;
  final List<gmaps.LatLng> lineDraftPoints;
  final bool showHlbMarkings;
  final List<GpsPoint> walkPath;
  final bool showWalkPath;
  final bool showBasemap;
  final gmaps.MapType mapType;
  final gmaps.LatLng? navigationDestination;
  final gmaps.LatLng? navigationOrigin;
  final NavigationTravelMode travelMode;
  final int fitToken;
  final bool followUserLocation;
  final bool lockCameraGestures;
  final ValueChanged<DirectionsRoute?>? onRouteLoaded;
  final void Function(gmaps.LatLng position)? onMapLongPress;
  final void Function(gmaps.LatLng position)? onMapTap;
  final String? fineTuningLandmarkId;
  final gmaps.LatLng? fineTuningLandmarkPosition;
  final void Function(String landmarkId, gmaps.LatLng position)? onLandmarkDrag;

  @override
  Widget build(BuildContext context) {
    if (AppConfig.hasGoogleMaps) {
      return GoogleMissionMap(
        center: gmaps.LatLng(center.latitude, center.longitude),
        boundary: boundary,
        regions: regions,
        mode: mode,
        boundaryDrawProgress: boundaryDrawProgress,
        showPdfOverlay: showPdfOverlay,
        pdfImageUrl: pdfImageUrl,
        pdfBounds: pdfBounds,
        pdfOpacity: pdfOpacity,
        showRegionPins: showRegionPins,
        showBoundary: showBoundary,
        showNavigationRoute: showNavigationRoute,
        showStartMarker: showStartMarker,
        draftPins: draftPins,
        showDraftPins: showDraftPins,
        hlbBuildings: hlbBuildings,
        hlbLandmarks: hlbLandmarks,
        hlbLineFeatures: hlbLineFeatures,
        lineDraftPoints: lineDraftPoints,
        showHlbMarkings: showHlbMarkings,
        walkPath: walkPath,
        showWalkPath: showWalkPath,
        showBasemap: showBasemap,
        mapType: mapType,
        navigationDestination: navigationDestination,
        navigationOrigin: navigationOrigin ??
            (userPosition != null ? gmaps.LatLng(userPosition!.latitude, userPosition!.longitude) : null),
        travelMode: travelMode,
        fitToken: fitToken,
        userLocation: userPosition != null
            ? gmaps.LatLng(userPosition!.latitude, userPosition!.longitude)
            : null,
        followUserLocation: followUserLocation,
        lockCameraGestures: lockCameraGestures,
        onRouteLoaded: onRouteLoaded,
        onMapLongPress: onMapLongPress,
        onMapTap: onMapTap,
        fineTuningLandmarkId: fineTuningLandmarkId,
        fineTuningLandmarkPosition: fineTuningLandmarkPosition,
        onLandmarkDrag: onLandmarkDrag,
      );
    }

    return MissionSatelliteMap(
      center: center,
      boundary: boundary,
      regions: regions,
      userPosition: userPosition,
      mode: mode,
      boundaryDrawProgress: boundaryDrawProgress,
      showPdfOverlay: showPdfOverlay,
      pdfImageUrl: pdfImageUrl,
      pdfBounds: pdfBounds,
      pdfOpacity: pdfOpacity,
      showRegionPins: showRegionPins,
    );
  }
}
