import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../theme/app_theme.dart';
import 'app_release_info.dart';
import 'app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    required this.release,
    required this.updateService,
    super.key,
  });

  final AppReleaseInfo release;
  final AppUpdateService updateService;

  static Future<void> show(
    BuildContext context, {
    required AppReleaseInfo release,
    required AppUpdateService updateService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !release.mandatory,
      builder: (_) => AppUpdateDialog(release: release, updateService: updateService),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _installing = false;
  double? _progress;
  String? _status;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _status = 'Downloading update…';
    });

    try {
      await for (final event in widget.updateService.installRelease(widget.release)) {
        if (!mounted) return;
        setState(() {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              _status = 'Downloading… ${event.value ?? ''}';
              final raw = event.value;
              if (raw != null) {
                final parsed = double.tryParse(raw.replaceAll('%', ''));
                if (parsed != null) _progress = parsed / 100;
              }
            case OtaStatus.INSTALLING:
              _status = 'Opening installer…';
              _progress = null;
            case OtaStatus.ALREADY_RUNNING_ERROR:
              _error = 'An update is already in progress.';
              _installing = false;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _error = 'Allow install from this source in Android settings, then retry.';
              _installing = false;
            case OtaStatus.INTERNAL_ERROR:
              _error = event.value ?? 'Update failed.';
              _installing = false;
            case OtaStatus.DOWNLOAD_ERROR:
              _error = event.value ?? 'Download failed.';
              _installing = false;
            case OtaStatus.CANCELED:
              _error = 'Download canceled.';
              _installing = false;
            case OtaStatus.CHECKSUM_ERROR:
              _error = 'Downloaded file failed verification.';
              _installing = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _installing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final notes = release.releaseNotes.trim();

    return PopScope(
      canPop: !release.mandatory && !_installing,
      child: AlertDialog(
        title: Text(release.mandatory ? 'Update required' : 'Update available'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Version ${release.versionName} (build ${release.buildNumber}) is ready.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(notes, style: const TextStyle(color: AppTheme.textSecondary)),
              ],
              if (_status != null) ...[
                const SizedBox(height: 16),
                Text(_status!, style: const TextStyle(fontSize: 13)),
              ],
              if (_progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.orange)),
              ],
            ],
          ),
        ),
        actions: [
          if (!release.mandatory && !_installing)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: _installing ? null : _install,
            child: Text(_installing ? 'Working…' : 'Download & install'),
          ),
        ],
      ),
    );
  }
}
