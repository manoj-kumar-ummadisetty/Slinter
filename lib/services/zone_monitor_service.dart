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
  late Box silentZonesBox;
  String? _currentZoneName;
  DateTime? _lastCheckTime;
  bool _notificationsReady = false;

  ZoneMonitorService({required this.service});

  Future<void> initHive() async {
    if (!Hive.isBoxOpen('silentZonesBox')) {
      silentZonesBox = await Hive.openBox('silentZonesBox');
    } else {
      silentZonesBox = Hive.box('silentZonesBox');
    }
  }

  Future<void> startMonitoring() async {
    await initHive();
    await _initNotifications();
    _lastTriggerTimes.clear();

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _startLocationStream();
  }

  void stopMonitoring() {
    _positionStream?.cancel();
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

      final position = await Geolocator.getCurrentPosition();
      await _checkZones(position);

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
            ),
          ).listen(
            (position) async {
              await _checkZones(position);
            },
            onError: (_) {
              _positionStream?.cancel();
              Future.delayed(const Duration(seconds: 5), _startLocationStream);
            },
          );
    } catch (_) {
      Future.delayed(const Duration(seconds: 10), _startLocationStream);
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

      for (final zone in silentZonesBox.values) {
        if (zone is! Map || zone['isActive'] != true) continue;

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

      if (currentlyInsideZone && _currentZoneName != detectedZoneName) {
        _currentZoneName = detectedZoneName;
        await _enterZone(_currentZoneName!);
      } else if (!currentlyInsideZone && _currentZoneName != null) {
        await _exitZone(_currentZoneName!);
        _currentZoneName = null;
      }
    } catch (_) {
      // Keep monitoring alive even if one saved zone has invalid data.
    }
  }

  Future<void> _enterZone(String zoneName) async {
    if (!_canTrigger('enter_$zoneName')) return;

    await _showZoneNotification(
      title: 'Entered $zoneName',
      body: 'Phone switched to silent mode',
    );
    await _vibrateIfAvailable();
    await SoundMode.setSoundMode(RingerModeStatus.silent);

    service.invoke('zone_entered', {'zoneName': zoneName});
  }

  Future<void> _exitZone(String zoneName) async {
    if (!_canTrigger('exit_$zoneName')) return;

    await _showZoneNotification(
      title: 'Exited $zoneName',
      body: 'Phone switched back to ring mode',
    );
    await _vibrateIfAvailable();
    await SoundMode.setSoundMode(RingerModeStatus.normal);

    service.invoke('zone_exited', {'zoneName': zoneName});
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
}
