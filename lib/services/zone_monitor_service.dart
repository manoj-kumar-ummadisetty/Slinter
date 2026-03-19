import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class ZoneMonitorService {
  StreamSubscription<Position>? _positionStream;
  Timer? _pollingTimer;
  late Box silentZonesBox;

  bool _insideAnyZone = false;
  final FlutterLocalNotificationsPlugin notifications;

  final Map<String, DateTime> _lastTriggerTimes = {};

  ZoneMonitorService({required this.notifications});

  Future<void> initHive() async 
  {
    silentZonesBox = await Hive.openBox('silentZonesBox');
  }

  Future<void> startMonitoring() async 
  {
    await initHive();
    _startLocationStream();
    _startPollingBackup();
  }

  void stopMonitoring() {
    _positionStream?.cancel();
    _pollingTimer?.cancel();
  }

  void _startLocationStream() {
    LocationSettings settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) {
        _checkZones(position);
      },
      onError: (error) {
        print("Location stream error: $error");
      },
    );
  }

  void _startPollingBackup() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        _checkZones(position);
      } catch (e) {
        print("Polling error: $e");
      }
    });
  }

  Future<void> _checkZones(Position position) async 
  {
    try {
      bool currentlyInsideZone = false;

      print("Zones count: ${silentZonesBox.length}");
      for (var zone in silentZonesBox.values) 
      {
        if (zone['isActive'] != true) continue;
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          zone['latitude'],
          zone['longitude'],
        );
        print("Distance: $distance | Radius: ${zone['radius']}");
        if (distance <= zone['radius']) {
          currentlyInsideZone = true;
        }
      }

      if (currentlyInsideZone && !_insideAnyZone) {
        _enterZone();
      } else if (!currentlyInsideZone && _insideAnyZone) {
        _exitZone();
      }

      _insideAnyZone = currentlyInsideZone;
    } catch (e) {
      print("Zone checking error: $e");
    }
    _showNotification("TEST", "Service is running");
  }

  void _enterZone() 
  {
    if (!_canTrigger("enter")) return;

    _setSilentMode();

    _showNotification(
      "Entered Silent Zone",
      "Phone switched to silent mode",
    );
  }

  void _exitZone() {
    if (!_canTrigger("exit")) return;

    _setRingMode();

    _showNotification(
      "Exited Silent Zone",
      "Phone switched to ring mode",
    );
  }

  bool _canTrigger(String key) {
    DateTime now = DateTime.now();

    if (_lastTriggerTimes.containsKey(key)) {
      if (now.difference(_lastTriggerTimes[key]!) <
          const Duration(seconds: 20)) {
        return false;
      }
    }

    _lastTriggerTimes[key] = now;
    return true;
  }

  void _setSilentMode() {
    print("Silent mode activated");
    // integrate sound_mode package here
  }

  void _setRingMode() {
    print("Ring mode activated");
    // integrate sound_mode package here
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
    'slinter_channel',
    'Slinter Background Service',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidDetails);
    await notifications.show(
      id:Random().nextInt(100000),
      title:title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}