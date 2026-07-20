import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/services/storage_service.dart';

void main() {
  test(
    'serializes SVAGA+ event, cursor and cancel/restore ledger atomically',
    () async {
      final directory = await Directory.systemTemp.createTemp('svaga-storage-');
      addTearDown(() => directory.delete(recursive: true));
      final storage = StorageService(appDataDir: directory);
      await storage.init();
      final event = SvagaPlusSubscriptionEvent(
        id: 'event-1',
        cursor: 7,
        eventType: 'new_subscription',
        subscriberName: 'Alice',
        createdAt: DateTime.utc(2026, 7, 20),
      );

      final applied = await storage.applySvagaEvent(
        event: event,
        seconds: 900,
        currentDuration: 10,
      );
      expect(applied.duration, 910);
      expect(storage.loadSvagaCursor(), 7);
      final reverted = await storage.revertSvagaEvent(
        eventId: event.id,
        currentDuration: 910,
      );
      expect(reverted.duration, 10);
      final restored = await storage.restoreSvagaEvent(
        eventId: event.id,
        currentDuration: 10,
      );
      expect(restored.duration, 910);
      final reloaded = StorageService(appDataDir: directory);
      await reloaded.init();
      expect(reloaded.loadSvagaHistory(), isNotEmpty);
    },
  );
}
