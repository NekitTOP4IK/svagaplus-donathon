import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/statistics.dart';
import '../models/svagaplus_subscription_event.dart';

class StorageException implements Exception {
  final String message;
  final Object? cause;
  const StorageException(this.message, [this.cause]);

  @override
  String toString() => 'StorageException: $message';
}

class SvagaPlusMutationResult {
  final bool changed;
  final int duration;
  final int appliedSeconds;
  final String status;

  const SvagaPlusMutationResult({
    required this.changed,
    required this.duration,
    required this.appliedSeconds,
    required this.status,
  });
}

class StorageService {
  static const String _companyName = 'MerryJoyKeyStudio';
  static const String _appName = 'DonatonTimer';
  static const String _dataFileName = 'data.json';
  static const String _backupFileName = 'data.json.bak';
  static const String _temporaryFileName = 'data.json.tmp';

  final Directory? _providedAppDataDir;
  Directory? _appDataDir;
  Map<String, dynamic> _data = <String, dynamic>{};
  Future<void> _mutationTail = Future<void>.value();

  StorageService({Directory? appDataDir}) : _providedAppDataDir = appDataDir;

  Future<Directory> _getAppDataDir() async {
    if (_appDataDir != null) return _appDataDir!;
    if (_providedAppDataDir != null) {
      _appDataDir = _providedAppDataDir;
    } else {
      final appData = await getApplicationSupportDirectory();
      final roamingPath = appData.parent.parent.path;
      _appDataDir = Directory('$roamingPath/$_companyName/$_appName');
    }
    await _appDataDir!.create(recursive: true);
    return _appDataDir!;
  }

  Future<File> _file(String name) async {
    final dir = await _getAppDataDir();
    return File('${dir.path}/$name');
  }

  Future<void> init() async {
    final dataFile = await _file(_dataFileName);
    final backupFile = await _file(_backupFileName);
    if (!await dataFile.exists() && !await backupFile.exists()) {
      _data = <String, dynamic>{};
      return;
    }

    try {
      _data = await _readMap(dataFile);
      return;
    } catch (_) {
      try {
        _data = await _readMap(backupFile);
        await dataFile.writeAsString(jsonEncode(_data), flush: true);
        return;
      } catch (backupError) {
        throw StorageException(
          'Neither data.json nor data.json.bak contains valid JSON',
          backupError,
        );
      }
    }
  }

  Future<Map<String, dynamic>> _readMap(File file) async {
    if (!await file.exists()) {
      throw const FormatException('File does not exist');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('Root is not an object');
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _copyData(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(value)) as Map<String, dynamic>,
      );

  Future<void> _writeSnapshot(Map<String, dynamic> snapshot) async {
    final dataFile = await _file(_dataFileName);
    final temporaryFile = await _file(_temporaryFileName);
    final backupFile = await _file(_backupFileName);
    try {
      await temporaryFile.writeAsString(jsonEncode(snapshot), flush: true);
      if (await backupFile.exists()) await backupFile.delete();
      if (await dataFile.exists()) await dataFile.rename(backupFile.path);
      await temporaryFile.rename(dataFile.path);
      if (await backupFile.exists()) await backupFile.delete();
    } catch (error) {
      if (!await dataFile.exists() && await backupFile.exists()) {
        try {
          await backupFile.rename(dataFile.path);
        } catch (_) {}
      }
      throw StorageException('Failed to persist data snapshot', error);
    } finally {
      if (await temporaryFile.exists()) {
        try {
          await temporaryFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<T> _mutate<T>(T Function(Map<String, dynamic> snapshot) change) {
    final next = _mutationTail.then((_) async {
      final snapshot = _copyData(_data);
      final result = change(snapshot);
      await _writeSnapshot(snapshot);
      _data = snapshot;
      return result;
    });
    _mutationTail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<void> saveTimerDuration(int durationSeconds) async {
    await _mutate<void>((snapshot) {
      snapshot['timer_duration'] = durationSeconds;
    });
  }

  int? loadTimerDuration() => (_data['timer_duration'] as num?)?.toInt();

  Future<void> saveTimerRunning(bool isRunning) async {
    await _mutate<void>((snapshot) {
      snapshot['timer_running'] = isRunning;
    });
  }

  bool loadTimerRunning() => _data['timer_running'] as bool? ?? false;

  Future<void> saveSettings(AppSettings settings) async {
    await _mutate<void>((snapshot) {
      snapshot['settings'] = settings.toJson();
    });
  }

  AppSettings? loadSettings() {
    final settingsData = _data['settings'];
    if (settingsData is! Map) return null;
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(settingsData));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStatistics(Statistics statistics) async {
    await _mutate<void>((snapshot) {
      snapshot['statistics'] = statistics.toJson();
    });
  }

  Statistics? loadStatistics() {
    final statsData = _data['statistics'];
    if (statsData is! Map) return null;
    try {
      return Statistics.fromJson(Map<String, dynamic>.from(statsData));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAll() async {
    await _mutate<void>((snapshot) => snapshot.clear());
  }

  Future<void> clearTimerDuration() async {
    await _mutate<void>((snapshot) {
      snapshot.remove('timer_duration');
    });
  }

  Future<void> clearStatistics() async {
    await _mutate<void>((snapshot) {
      snapshot.remove('statistics');
    });
  }

  int loadSvagaCursor() {
    final svaga = _data['svagaplus'];
    return svaga is Map ? (svaga['last_cursor'] as num?)?.toInt() ?? 0 : 0;
  }

  Map<String, dynamic> loadSvagaHistory() {
    final svaga = _data['svagaplus'];
    final history = svaga is Map ? svaga['history'] : null;
    return history is Map
        ? Map<String, dynamic>.from(history)
        : <String, dynamic>{};
  }

  Future<void> setSvagaCursor(int cursor) async {
    await _mutate<void>((snapshot) {
      final svaga = Map<String, dynamic>.from(
        snapshot['svagaplus'] is Map ? snapshot['svagaplus'] as Map : {},
      );
      final current = (svaga['last_cursor'] as num?)?.toInt() ?? 0;
      svaga['last_cursor'] = cursor > current ? cursor : current;
      snapshot['svagaplus'] = svaga;
    });
  }

  /// Sets a deliberately chosen cursor baseline, including one behind the
  /// previously acknowledged position.
  Future<void> replaceSvagaCursor(int cursor) async {
    await _mutate<void>((snapshot) {
      final svaga = Map<String, dynamic>.from(
        snapshot['svagaplus'] is Map ? snapshot['svagaplus'] as Map : {},
      );
      svaga['last_cursor'] = cursor < 0 ? 0 : cursor;
      snapshot['svagaplus'] = svaga;
    });
  }

  Future<void> saveSvagaHistoryEntry(Map<String, dynamic> entry) async {
    await _mutate<void>((snapshot) {
      final svaga = Map<String, dynamic>.from(
        snapshot['svagaplus'] is Map ? snapshot['svagaplus'] as Map : {},
      );
      final history = Map<String, dynamic>.from(
        svaga['history'] is Map ? svaga['history'] as Map : {},
      );
      final event = entry['event'];
      if (event is Map && event['id'] is String) {
        history[event['id'] as String] = entry;
      }
      svaga['history'] = history;
      snapshot['svagaplus'] = svaga;
    });
  }

  Future<SvagaPlusMutationResult> applySvagaEvent({
    required SvagaPlusSubscriptionEvent event,
    required int seconds,
    required int currentDuration,
  }) => _mutate<SvagaPlusMutationResult>((snapshot) {
    final svaga = Map<String, dynamic>.from(
      snapshot['svagaplus'] is Map ? snapshot['svagaplus'] as Map : {},
    );
    final history = Map<String, dynamic>.from(
      svaga['history'] is Map ? svaga['history'] as Map : {},
    );
    final existing = history[event.id];
    if (existing is Map) {
      return SvagaPlusMutationResult(
        changed: false,
        duration: currentDuration,
        appliedSeconds: (existing['appliedSeconds'] as num?)?.toInt() ?? 0,
        status: existing['status'] as String? ?? 'applied',
      );
    }

    history[event.id] = {
      'event': event.toJson(),
      'appliedSeconds': seconds,
      'status': 'applied',
      'appliedAt': DateTime.now().toUtc().toIso8601String(),
      'revertedAt': null,
    };
    svaga['history'] = history;
    final currentCursor = (svaga['last_cursor'] as num?)?.toInt() ?? 0;
    svaga['last_cursor'] = event.cursor > currentCursor
        ? event.cursor
        : currentCursor;
    snapshot['svagaplus'] = svaga;
    return SvagaPlusMutationResult(
      changed: true,
      duration: currentDuration + seconds,
      appliedSeconds: seconds,
      status: 'applied',
    );
  });

  Future<SvagaPlusMutationResult> revertSvagaEvent({
    required String eventId,
    required int currentDuration,
  }) => _mutate<SvagaPlusMutationResult>((snapshot) {
    final item = _historyFrom(snapshot)[eventId];
    if (item is! Map || item['status'] == 'reverted') {
      return SvagaPlusMutationResult(
        changed: false,
        duration: currentDuration,
        appliedSeconds: item is Map
            ? (item['appliedSeconds'] as num?)?.toInt() ?? 0
            : 0,
        status: 'reverted',
      );
    }
    final seconds = (item['appliedSeconds'] as num?)?.toInt() ?? 0;
    _setHistoryStatus(snapshot, eventId, item, 'reverted');
    return SvagaPlusMutationResult(
      changed: true,
      duration: currentDuration - seconds < 0 ? 0 : currentDuration - seconds,
      appliedSeconds: seconds,
      status: 'reverted',
    );
  });

  Future<SvagaPlusMutationResult> restoreSvagaEvent({
    required String eventId,
    required int currentDuration,
  }) => _mutate<SvagaPlusMutationResult>((snapshot) {
    final item = _historyFrom(snapshot)[eventId];
    if (item is! Map || item['status'] != 'reverted') {
      return SvagaPlusMutationResult(
        changed: false,
        duration: currentDuration,
        appliedSeconds: item is Map
            ? (item['appliedSeconds'] as num?)?.toInt() ?? 0
            : 0,
        status: 'applied',
      );
    }
    final seconds = (item['appliedSeconds'] as num?)?.toInt() ?? 0;
    _setHistoryStatus(snapshot, eventId, item, 'applied');
    return SvagaPlusMutationResult(
      changed: true,
      duration: currentDuration + seconds,
      appliedSeconds: seconds,
      status: 'applied',
    );
  });

  Map<String, dynamic> _historyFrom(Map<String, dynamic> snapshot) {
    final svaga = snapshot['svagaplus'];
    final history = svaga is Map ? svaga['history'] : null;
    return history is Map
        ? Map<String, dynamic>.from(history)
        : <String, dynamic>{};
  }

  void _setHistoryStatus(
    Map<String, dynamic> snapshot,
    String id,
    Map item,
    String status,
  ) {
    final svaga = Map<String, dynamic>.from(snapshot['svagaplus'] as Map);
    final history = Map<String, dynamic>.from(svaga['history'] as Map);
    final updated = Map<String, dynamic>.from(item);
    updated['status'] = status;
    updated['revertedAt'] = status == 'reverted'
        ? DateTime.now().toUtc().toIso8601String()
        : null;
    history[id] = updated;
    svaga['history'] = history;
    snapshot['svagaplus'] = svaga;
  }

  Future<String> getStoragePath() async => (await _getAppDataDir()).path;
}
