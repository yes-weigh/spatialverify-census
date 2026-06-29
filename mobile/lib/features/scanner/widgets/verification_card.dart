import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../identity/data/spatial_identity_service.dart';
import '../../scanner/data/object_detector.dart';

class VerificationCard extends StatefulWidget {
  const VerificationCard({
    required this.detection,
    required this.position,
    required this.onConfirm,
    required this.onReject,
    required this.onEdit,
    this.identityResult,
    this.isResolvingIdentity = false,
    super.key,
  });

  final DetectedObject detection;
  final Position? position;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final void Function(String category) onEdit;
  final IdentityResult? identityResult;
  final bool isResolvingIdentity;

  @override
  State<VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends State<VerificationCard> {
  bool _isEditing = false;
  late TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    _categoryController = TextEditingController(text: widget.detection.label);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  Color _verdictColor(IdentityVerdict verdict) {
    switch (verdict) {
      case IdentityVerdict.sameAsset:
        return AppTheme.verified;
      case IdentityVerdict.possibleMatch:
        return AppTheme.pending;
      case IdentityVerdict.newAsset:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration(radius: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'AI Detection',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                '${(widget.detection.confidence * 100).toStringAsFixed(0)}% confidence',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.detection.label.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (widget.position != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _IdentitySection(
            result: widget.identityResult,
            isLoading: widget.isResolvingIdentity,
            verdictColor: widget.identityResult != null
                ? _verdictColor(widget.identityResult!.verdict)
                : AppTheme.textSecondary,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.rejected,
                    side: const BorderSide(color: AppTheme.rejected),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    if (_isEditing) {
                      widget.onEdit(_categoryController.text);
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(_isEditing ? 'Save' : 'Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.identityResult == null && widget.isResolvingIdentity
                      ? null
                      : widget.onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.verified,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(
                    widget.identityResult?.verdict == IdentityVerdict.sameAsset
                        ? 'Link Asset'
                        : 'Confirm',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              widget.identityResult?.requiresReview == true
                  ? 'Supervisor review may be required'
                  : 'Human verification required',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.result,
    required this.isLoading,
    required this.verdictColor,
  });

  final IdentityResult? result;
  final bool isLoading;
  final Color verdictColor;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Running spatial identity check...', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (result == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: verdictColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: verdictColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint, color: verdictColor, size: 18),
              const SizedBox(width: 8),
              Text(
                result!.verdictLabel,
                style: TextStyle(
                  color: verdictColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${(result!.finalConfidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: verdictColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (result!.matchedAssetName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Match: ${result!.matchedAssetName}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ],
          if (result!.explanation?.summary != null) ...[
            const SizedBox(height: 6),
            Text(
              result!.explanation!.summary!,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
          if (result!.explanation?.insideCluster == true) ...[
            const SizedBox(height: 4),
            const Text(
              'Inside GPS cluster',
              style: TextStyle(color: AppTheme.verified, fontSize: 11),
            ),
          ],
          if (result!.explanation?.lastSeenAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last seen: ${result!.explanation!.lastSeenAt}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _ScoreChip('GPS', result!.scores['gps'] ?? 0),
              _ScoreChip('Visual', result!.scores['embedding'] ?? 0),
              _ScoreChip('Category', result!.scores['category'] ?? 0),
              _ScoreChip('Heading', result!.scores['heading'] ?? 0),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip(this.label, this.score);

  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label ${(score * 100).toStringAsFixed(0)}%',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
      ),
    );
  }
}
