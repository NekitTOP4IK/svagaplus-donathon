import 'package:flutter/material.dart';

import '../models/feed_entry.dart';
import '../providers/localization_provider.dart';

/// Лента «Последние донаты»: донаты и подписки SVAGA+ в одном списке.
class DonationFeedList extends StatelessWidget {
  final List<FeedEntry> entries;
  final LocalizationProvider localization;

  const DonationFeedList({
    super.key,
    required this.entries,
    required this.localization,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          localization.tr('no_donations'),
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) =>
          _FeedItem(entry: entries[index], localization: localization),
    );
  }
}

class _FeedItem extends StatelessWidget {
  final FeedEntry entry;
  final LocalizationProvider localization;

  const _FeedItem({required this.entry, required this.localization});

  @override
  Widget build(BuildContext context) {
    final muted = entry.reverted;
    final strike = muted ? TextDecoration.lineThrough : null;
    final isSubscription = entry.source == FeedSource.svagaPlus;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          if (isSubscription) ...[
            Image.asset(
              'assets/svagaplus.webp',
              width: 14,
              height: 14,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.favorite, color: Colors.pink, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.username,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: strike,
                    color: muted ? Colors.grey : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (isSubscription)
                  Text(
                    localization.tr(
                      entry.kind == FeedKind.newSubscription
                          ? 'svagaplus_new_subscription'
                          : 'svagaplus_renewed_subscription',
                    ),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      decoration: strike,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '+${entry.minutesAdded} min',
            style: TextStyle(
              color: muted ? Colors.grey : Colors.green,
              decoration: strike,
            ),
          ),
        ],
      ),
    );
  }
}
