import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../brand/app_brand.dart';
import '../theme/app_theme.dart';

/// SpatialVerify logo — mark, wordmark, optional tagline.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 88,
    this.showWordmark = true,
    this.showTagline = false,
    this.tagline,
    this.compact = false,
    this.useRasterIcon = false,
  });

  final double size;
  final bool showWordmark;
  final bool showTagline;
  final String? tagline;
  final bool compact;
  final bool useRasterIcon;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: size * 0.55, useRasterIcon: useRasterIcon),
          if (showWordmark) ...[
            const SizedBox(width: 10),
            Text(
              AppBrand.name,
              style: TextStyle(
                fontSize: size * 0.28,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size, useRasterIcon: useRasterIcon, withGlow: true),
        if (showWordmark) ...[
          SizedBox(height: size * 0.22),
          Text(
            AppBrand.name,
            style: TextStyle(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -1,
            ),
          ),
        ],
        if (showTagline) ...[
          SizedBox(height: size * 0.08),
          Text(
            tagline ?? AppBrand.taglineShort,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.16,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// Icon mark — generated raster or SVG grid + verified pin.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 64,
    this.withGlow = false,
    this.useRasterIcon = false,
  });

  final double size;
  final bool withGlow;
  final bool useRasterIcon;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.22;

    Widget child;
    if (useRasterIcon) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          AppBrand.iconAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } else {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppBrand.accent.withValues(alpha: 0.4)),
        ),
        padding: EdgeInsets.all(size * 0.14),
        child: SvgPicture.asset(AppBrand.markAsset, fit: BoxFit.contain),
      );
    }

    if (!withGlow) return child;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppBrand.accent.withValues(alpha: 0.28),
            blurRadius: size * 0.45,
            spreadRadius: -size * 0.02,
          ),
        ],
      ),
      child: child,
    );
  }
}
