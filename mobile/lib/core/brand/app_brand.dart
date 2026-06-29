import 'package:flutter/material.dart';

/// SpatialVerify visual identity — census HLB field verification.
abstract final class AppBrand {
  static const name = 'SpatialVerify';
  static const shortName = 'SpatialVerify';

  static const tagline = 'Verify every block. Map every household.';
  static const taglineShort = 'Census field verification';
  static const taglineLogin = 'HLB mapping & verification in the field';

  static const accent = Color(0xFF00E5A0);
  static const accentDark = Color(0xFF00B87A);
  static const ink = Color(0xFF0A0A0F);
  static const mapBlue = Color(0xFF4285F4);

  static const markAsset = 'assets/icons/spatialverify_mark.svg';
  static const wordmarkAsset = 'assets/icons/spatialverify_wordmark.svg';
  static const iconAsset = 'assets/images/app_icon.png';

  static LinearGradient get accentGradient => const LinearGradient(
        colors: [accent, accentDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static BoxDecoration heroCardDecoration({double radius = 20}) => BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      );
}
