import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/localization_provider.dart';

import '../models/svagaplus_history_entry.dart';
import '../models/svagaplus_subscription_event.dart';
import '../providers/svagaplus_provider.dart';
import '../providers/timer_provider.dart';

class SvagaPlusHistoryScreen extends StatefulWidget {
  const SvagaPlusHistoryScreen({super.key});

  @override
  State<SvagaPlusHistoryScreen> createState() => _SvagaPlusHistoryScreenState();
}

class _SvagaPlusHistoryScreenState extends State<SvagaPlusHistoryScreen> {
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SvagaPlusProvider>().syncHistory();
    });
  }

  Future<void> _change(
    SvagaPlusHistoryEntry entry,
    SvagaPlusProvider provider,
  ) async {
    if (!_pending.add(entry.event.id)) return;
    setState(() {});
    final localization = context.read<LocalizationProvider>();
    try {
      if (entry.status == SvagaPlusHistoryStatus.applied) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(localization.tr('svagaplus_cancel')),
            content: Text(localization.tr('svagaplus_cancel_confirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(localization.tr('svagaplus_cancel')),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await provider.cancelHistoryEntry(entry.event.id);
      } else {
        await provider.restoreHistoryEntry(entry.event.id);
      }
    } finally {
      _pending.remove(entry.event.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationProvider>();
    final provider = context.watch<SvagaPlusProvider>();
    final entries = provider.history;
    return Scaffold(
      appBar: AppBar(title: Text(localization.tr('svagaplus_history'))),
      body: provider.historyError != null && entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localization.tr('svagaplus_history_error')),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: provider.historySyncing
                        ? null
                        : provider.syncHistory,
                    child: Text(localization.tr('svagaplus_retry')),
                  ),
                ],
              ),
            )
          : entries.isEmpty
          ? Center(child: Text(localization.tr('svagaplus_history_empty')))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final applied = entry.status == SvagaPlusHistoryStatus.applied;
                final busy = _pending.contains(entry.event.id);
                return ListTile(
                  leading: Image.asset(
                    'assets/svagaplus.webp',
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.star),
                  ),
                  title: Text(entry.event.subscriberName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localization.tr(
                          entry.event.eventType ==
                                  SvagaPlusEventType.newSubscription
                              ? 'svagaplus_new_subscription'
                              : 'svagaplus_renewed_subscription',
                        ),
                      ),
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatFullDate(entry.event.createdAt.toLocal()),
                      ),
                      Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(
                            entry.event.createdAt.toLocal(),
                          ),
                        ),
                      ),
                      Text(
                        '+${TimerProvider.formatSeconds(entry.appliedSeconds)}',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          label: Text(
                            localization.tr(
                              applied
                                  ? 'svagaplus_status_applied'
                                  : 'svagaplus_status_reverted',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: busy ? null : () => _change(entry, provider),
                    child: Text(
                      localization.tr(
                        applied ? 'svagaplus_cancel' : 'svagaplus_restore',
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
