import 'dart:async';
import 'dart:math';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:vibration/vibration.dart';

class ZoneMonitorService {
  final ServiceInstance service;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _lastTriggerTimes = {};

  StreamSubscription<Position>? _positionStream;
  Timer? _fallbackTimer;
  late Box silentZonesBox;
  late Box monitorStateBox;
  String? _currentZoneName;
  DateTime? _lastCheckTime;
  bool _notificationsReady = false;
  bool _isStopping = false;

  ZoneMonitorService({required this.service});

  Future<void> initHive() async {
    if (!Hive.isBoxOpen('silentZonesBox')) {
      silentZonesBox = await Hive.openBox('silentZonesBox');
    } else {
      silentZonesBox = Hive.box('silentZonesBox');
    }

    if (!Hive.isBoxOpen('zoneMonitorStateBox')) {
      monitorStateBox = await Hive.openBox('zoneMonitorStateBox');
    } else {
      monitorStateBox = Hive.box('zoneMonitorStateBox');
    }

    final savedZoneName = monitorStateBox.get('currentZoneName');
    _currentZoneName = savedZoneName is String && savedZoneName.isNotEmpty
        ? savedZoneName
        : null;
  }

  Future<void> startMonitoring() async {
    await initHive();
    await _initNotifications();
    _lastTriggerTimes.clear();
    _isStopping = false;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    if (!_hasActiveZones()) {
      _stopService();
      return;
    }

    _startFallbackPolling();
    _startLocationStream();
  }

  void stopMonitoring() {
    _isStopping = true;
    _positionStream?.cancel();
    _positionStream = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  Future<void> refreshMonitoring() async {
    await initHive();

    if (!_hasActiveZones()) {
      _stopService();
      return;
    }

    _lastCheckTime = null;
    await _checkCurrentPositionOnce();
  }

  Future<void> _initNotifications() async {
    if (_notificationsReady) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(settings: initSettings);

    const channel = AndroidNotificationChannel(
      'slinter_channel',
      'Slinter Background Service',
      description: 'Monitors silent zones in background',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _notificationsReady = true;
  }

  void _startLocationStream() async {
    if (_isStopping) return;

    _positionStream?.cancel();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      await _checkCurrentPositionOnce();

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 50,
            ),
          ).listen(
            (position) async {
              await _checkZones(position);
            },
            onError: (_) {
              _positionStream?.cancel();
              if (!_isStopping) {
                Future.delayed(
                  const Duration(seconds: 10),
                  _startLocationStream,
                );
              }
            },
          );
    } catch (_) {
      if (!_isStopping) {
        Future.delayed(const Duration(seconds: 20), _startLocationStream);
      }
    }
  }

  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (_isStopping) return;
      await refreshMonitoring();
    });
  }

  Future<void> _checkCurrentPositionOnce() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _checkZones(position);
    } catch (_) {
      // The stream or next fallback tick will try again.
    }
  }

  Future<void> _checkZones(Position position) async {
    if (_lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) <
            const Duration(seconds: 8)) {
      return;
    }

    _lastCheckTime = DateTime.now();

    try {
      var currentlyInsideZone = false;
      String? detectedZoneName;
      var activeZoneCount = 0;

      for (final zone in silentZonesBox.values) {
        if (zone is! Map || zone['isActive'] != true) continue;
        activeZoneCount++;

        final latitude = zone['latitude'];
        final longitude = zone['longitude'];
        final radius = zone['radius'];

        if (latitude is! num || longitude is! num || radius is! num) continue;

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          latitude.toDouble(),
          longitude.toDouble(),
        );

        if (distance <= radius.toDouble()) {
          currentlyInsideZone = true;
          detectedZoneName = (zone['zoneName'] ?? 'Silent Zone').toString();
          break;
        }
      }

      if (activeZoneCount == 0) {
        if (_currentZoneName != null) {
          await _exitZone(_currentZoneName!);
          _currentZoneName = null;
          await monitorStateBox.delete('currentZoneName');
        }
        _stopService();
        return;
      }

      if (currentlyInsideZone && _currentZoneName != detectedZoneName) {
        _currentZoneName = detectedZoneName;
        await _enterZone(_currentZoneName!);
      } else if (currentlyInsideZone && _currentZoneName == detectedZoneName) {
        await _ensureSilentMode();
      } else if (!currentlyInsideZone && _currentZoneName != null) {
        await _exitZone(_currentZoneName!);
        _currentZoneName = null;
        await monitorStateBox.delete('currentZoneName');
      }
    } catch (_) {
      // Keep monitoring alive even if one saved zone has invalid data.
    }
  }

  Future<void> _enterZone(String zoneName) async {
    await monitorStateBox.put('currentZoneName', zoneName);

    if (!_canTrigger('enter_$zoneName')) return;

    await _ensureSilentMode();
    await _showZoneNotification(
      title: 'Entered $zoneName',
      body: 'Phone switched to silent mode',
    );
    await _vibrateIfAvailable();

    service.invoke('zone_entered', {'zoneName': zoneName});
  }

  Future<void> _exitZone(String zoneName) async {
    if (!_canTrigger('exit_$zoneName')) return;

    await _ensureRingMode();
    await _showZoneNotification(
      title: 'Exited $zoneName',
      body: 'Phone switched back to ring mode',
    );
    await _vibrateIfAvailable();

    service.invoke('zone_exited', {'zoneName': zoneName});
  }

  Future<void> _ensureSilentMode() async {
    try {
      final currentMode = await SoundMode.ringerModeStatus;
      if (currentMode != RingerModeStatus.silent) {
        await SoundMode.setSoundMode(RingerModeStatus.silent);
      }
    } catch (_) {
      await SoundMode.setSoundMode(RingerModeStatus.silent);
    }
  }

  Future<void> _ensureRingMode() async {
    try {
      final currentMode = await SoundMode.ringerModeStatus;
      if (currentMode != RingerModeStatus.normal) {
        await SoundMode.setSoundMode(RingerModeStatus.normal);
      }
    } catch (_) {
      await SoundMode.setSoundMode(RingerModeStatus.normal);
    }
  }

  Future<void> _showZoneNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'slinter_channel',
      'Slinter Background Service',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notifications.show(
      id: Random().nextInt(100000),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _vibrateIfAvailable() async {
    if (await Vibration.hasVibrator() == true) {
      await Vibration.vibrate(pattern: [0, 500, 200, 500]);
    }
  }

  bool _canTrigger(String key) {
    final now = DateTime.now();
    final lastTriggerTime = _lastTriggerTimes[key];

    if (lastTriggerTime != null &&
        now.difference(lastTriggerTime) < const Duration(seconds: 20)) {
      return false;
    }

    _lastTriggerTimes[key] = now;
    return true;
  }

  bool _hasActiveZones() {
    return silentZonesBox.values.any(
      (zone) => zone is Map && zone['isActive'] == true,
    );
  }

  void _stopService() {
    stopMonitoring();
    service.stopSelf();
  }
}
