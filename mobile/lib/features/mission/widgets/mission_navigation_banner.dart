import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_directions_service.dart';
import '../../../core/theme/app_theme.dart';

/// Bottom banner — distance, ETA, and current turn for in-app navigation.
class MissionNavigationBanner extends StatelessWidget {
  const MissionNavigationBanner({
    required this.route,
    this.currentStepIndex = 0,
    this.loading = false,
    this.errorMessage,
    super.key,
  });

  final DirectionsRoute? route;
  final int currentStepIndex;
  final bool loading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasGoogleMaps) {
      return const SizedBox.shrink();
    }

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: const Color(0xFF14141E),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: loading
              ? const Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Finding bike route…', style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                )
              : route == null
                  ? Text(
                      errorMessage ?? 'Route unavailable — move closer or check connection',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    )
                  : _RouteSummary(route: route!, stepIndex: currentStepIndex),
        ),
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route, required this.stepIndex});

  final DirectionsRoute route;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final step = route.steps.isEmpty
        ? null
        : route.steps[stepIndex.clamp(0, route.steps.length - 1)];
    final modeLabel = route.travelMode == NavigationTravelMode.bicycling ? 'Bike' : 'Walk';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              route.travelMode == NavigationTravelMode.bicycling ? Icons.directions_bike : Icons.directions_walk,
              color: const Color(0xFF4285F4),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              '$modeLabel to HLB',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const Spacer(),
            Text(route.durationText, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          route.distanceText,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        if (step != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A44),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.35)),
            ),
            child: Text(
              step.instruction,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }
}
