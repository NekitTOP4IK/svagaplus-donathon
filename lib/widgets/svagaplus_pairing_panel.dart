import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/svagaplus_pairing_session.dart';
import '../providers/localization_provider.dart';

/// Панель активной привязки: код, ссылка, обратный отсчёт, отмена.
///
/// Отдельный [StatefulWidget], потому что нужен тикер для отсчёта.
class SvagaPlusPairingPanel extends StatefulWidget {
  final SvagaPlusPairingSession session;
  final LocalizationProvider localization;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final ValueChanged<Uri> onOpen;

  const SvagaPlusPairingPanel({
    super.key,
    required this.session,
    required this.localization,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  State<SvagaPlusPairingPanel> createState() => _SvagaPlusPairingPanelState();
}

class _SvagaPlusPairingPanelState extends State<SvagaPlusPairingPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _remaining(DateTime expiresAt) {
    final left = expiresAt.difference(DateTime.now().toUtc());
    if (left.isNegative) return widget.localization.tr('svagaplus_pairing_expired_now');
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return '${widget.localization.tr('svagaplus_pairing_expires_in')} '
        '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _copy(Uri uri) async {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.localization.tr('svagaplus_pairing_copied')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final tr = widget.localization.tr;

    if (session.state == SvagaPlusPairingState.failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(session.failureKey ?? 'svagaplus_pair_error_unknown')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onRetry,
              child: Text(tr('svagaplus_pairing_retry')),
            ),
          ],
        ),
      );
    }

    if (!session.inProgress || session.userCode == null) {
      return const SizedBox.shrink();
    }

    final uri = session.verificationUri;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('svagaplus_pairing_code')),
          const SizedBox(height: 4),
          SelectableText(
            session.userCode!,
            style: const TextStyle(fontSize: 24, letterSpacing: 4),
          ),
          if (session.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(_remaining(session.expiresAt!)),
          ],
          if (!session.browserOpened) ...[
            const SizedBox(height: 8),
            Text(tr('svagaplus_pairing_open_hint')),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (uri != null)
                TextButton(
                  onPressed: () => widget.onOpen(uri),
                  child: Text(tr('svagaplus_pairing_open')),
                ),
              if (uri != null)
                TextButton(
                  onPressed: () => _copy(uri),
                  child: Text(tr('svagaplus_pairing_copy')),
                ),
              TextButton(
                onPressed: widget.onCancel,
                child: Text(tr('svagaplus_pairing_cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
