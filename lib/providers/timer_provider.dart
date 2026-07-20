import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/log_manager.dart';
import '../models/svagaplus_subscription_event.dart';

/// Провайдер для управления состоянием таймера донатона.
class TimerProvider extends ChangeNotifier {
  final StorageService _storageService;

  int _duration = 0;
  bool _isRunning = false;
  Timer? _timer;
  Future<void> _mutationTail = Future<void>.value();
  bool _tickPending = false;

  /// Creates a TimerProvider with the given StorageService.
  TimerProvider(this._storageService);

  /// Current timer duration in seconds.
  int get duration => _duration;

  /// Whether the timer is currently running (counting down).
  bool get isRunning => _isRunning;

  /// Hours component of the current duration.
  int get hours => _duration ~/ 3600;

  /// Minutes component of the current duration (0-59).
  int get minutes => (_duration % 3600) ~/ 60;

  /// Seconds component of the current duration (0-59).
  int get seconds => _duration % 60;

  /// Initializes the provider by loading saved timer state.
  Future<void> init() async {
    final savedDuration = _storageService.loadTimerDuration();
    if (savedDuration != null && savedDuration > 0) {
      _duration = savedDuration;
      notifyListeners();
    }
  }

  /// Starts the timer countdown.
  void start() {
    if (_isRunning) return;
    if (_duration <= 0) return;

    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
    LogManager.info('Таймер запущен: ${formatDuration()}');
    notifyListeners();
  }

  /// Stops the timer countdown.
  void stop() {
    if (!_isRunning) return;

    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    LogManager.info('Таймер остановлен: ${formatDuration()}');
    notifyListeners();
  }

  /// Toggles between running and stopped states.
  void toggle() {
    if (_isRunning) {
      stop();
    } else {
      start();
    }
  }

  /// Adds time to the timer.
  /// [seconds] - Number of seconds to add (can be negative for subtraction).
  void addTime(int seconds) {
    _fireAndForget(
      _enqueueMutation(() async {
        final nextDuration = _duration + seconds;
        final persistedDuration = nextDuration < 0 ? 0 : nextDuration;
        await _storageService.saveTimerDuration(persistedDuration);
        _duration = persistedDuration;
        notifyListeners();
      }),
    );
  }

  /// Adds one minute (60 seconds) to the timer.
  void addMinute() {
    addTime(60);
  }

  /// Subtracts one minute (60 seconds) from the timer.
  void subtractMinute() {
    addTime(-60);
  }

  /// Adds specified number of minutes to the timer.
  void addMinutes(int minutes) {
    addTime(minutes * 60);
  }

  /// Sets the timer to a specific time.
  void setTime(int hours, int minutes, int seconds) {
    _fireAndForget(
      _enqueueMutation(() async {
        final nextDuration = (hours * 3600) + (minutes * 60) + seconds;
        final persistedDuration = nextDuration < 0 ? 0 : nextDuration;
        await _storageService.saveTimerDuration(persistedDuration);
        _duration = persistedDuration;
        notifyListeners();
      }),
    );
  }

  /// Sets the timer duration directly in seconds.
  void setDuration(int seconds) {
    _fireAndForget(
      _enqueueMutation(() async {
        final persistedDuration = seconds < 0 ? 0 : seconds;
        await _storageService.saveTimerDuration(persistedDuration);
        _duration = persistedDuration;
        notifyListeners();
      }),
    );
  }

  /// Resets the timer to zero and stops it.
  void reset() {
    stop();
    _fireAndForget(
      _enqueueMutation(() async {
        await _storageService.saveTimerDuration(0);
        _duration = 0;
        notifyListeners();
      }),
    );
  }

  /// Formats the current duration as HH:MM:SS.
  String formatDuration() {
    final h = hours.toString().padLeft(2, '0');
    final m = minutes.toString().padLeft(2, '0');
    final s = seconds.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Formats a given duration in seconds as HH:MM:SS.
  static String formatSeconds(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Timer tick callback - decrements duration by 1 second.
  void _onTick(Timer timer) {
    if (_duration <= 0) {
      // Timer reached zero
      stop();
      return;
    }
    if (_tickPending) return;
    _tickPending = true;
    _fireAndForget(
      _enqueueMutation(() async {
        try {
          if (_duration > 0) {
            final persistedDuration = _duration - 1;
            await _storageService.saveTimerDuration(persistedDuration);
            _duration = persistedDuration;
            notifyListeners();
          } else {
            stop();
          }
        } finally {
          _tickPending = false;
        }
      }),
    );
  }

  /// Saves the current timer duration to persistent storage.
  Future<SvagaPlusMutationResult> applySvagaEvent(
    SvagaPlusSubscriptionEvent event,
    int seconds,
  ) => _enqueueMutation(() async {
    final result = await _storageService.applySvagaEvent(
      event: event,
      seconds: seconds,
      currentDuration: _duration,
    );
    if (result.changed) {
      _duration = result.duration;
      notifyListeners();
    }
    return result;
  });

  Future<SvagaPlusMutationResult> revertSvagaEvent(String eventId) =>
      _enqueueMutation(() async {
        final result = await _storageService.revertSvagaEvent(
          eventId: eventId,
          currentDuration: _duration,
        );
        if (result.changed) {
          _duration = result.duration;
          notifyListeners();
        }
        return result;
      });

  Future<SvagaPlusMutationResult> restoreSvagaEvent(String eventId) =>
      _enqueueMutation(() async {
        final result = await _storageService.restoreSvagaEvent(
          eventId: eventId,
          currentDuration: _duration,
        );
        if (result.changed) {
          _duration = result.duration;
          notifyListeners();
        }
        return result;
      });

  Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    final next = _mutationTail.then((_) => operation());
    _mutationTail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        LogManager.error('Ошибка сохранения таймера: $error');
      },
    );
    return next;
  }

  void _fireAndForget(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        LogManager.error('Ошибка сохранения таймера: $error');
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
