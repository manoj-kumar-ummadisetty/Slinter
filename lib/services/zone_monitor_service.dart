import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ZoneMonitorService {
  final FlutterLocalNotificationsPlugin _notifications;
  ZoneMonitorService(this._notifications);
  final Map<String, DateTime> _lastTriggerTimes = {};

  /// Store previous state of zones
  final Map<String, bool> _zoneStates = {};

  StreamSubscription<Position>? _positionStream;

  void startMonitoring() 
  {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings
      (
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 15,
        timeLimit: null,
      ),
    ).listen((Position position) {
      _checkZonesWithPosition(position);
    });
  }

 void stopMonitoring() 
  {
    _positionStream?.cancel();
  }

  bool _canTrigger(String zoneKey)
  {
    if (!_lastTriggerTimes.containsKey(zoneKey)) return true;

    return DateTime.now()
            .difference(_lastTriggerTimes[zoneKey]!)
            .inSeconds > 10;
  }
  



  Future<void> _checkZonesWithPosition(Position position) async 
  {
    if (position.accuracy > 150) 
    {
      return;
    }
    final box = Hive.box('silentZonesBox');
    print("Zones count: ${box.length}");
    print("Zone data: ${box.values}");
    for (var zone in box.values) 
    {
      if (!zone['isActive']) continue;

      final double zoneLat = zone['latitude'];
      final double zoneLng = zone['longitude'];
      final double radius = zone['radius'];
      final String zoneKey =
          "${zone['latitude']}_${zone['longitude']}";
      final String zoneName =
          zone['zoneName']?.toString() ?? "Unnamed Zone";

      double distance = _calculateDistance(
        position.latitude,
        position.longitude,
        zoneLat,
        zoneLng,
      );

      bool wasInside = _zoneStates[zoneKey] ?? false;
      double exitBuffer = radius * 0.2;
      bool isInside = distance <= radius;
      bool isOutside = distance > (radius + exitBuffer);

      if (isInside && !wasInside && _canTrigger(zoneKey))
      {
        _zoneStates[zoneKey] = true;
        _lastTriggerTimes[zoneKey] = DateTime.now();
        await _setSilentMode();
        _showNotification("Entered $zoneName", "Phone switched to Silent");
      }
      if (isOutside && wasInside && _canTrigger(zoneKey)) 
      {
        _zoneStates[zoneKey] = false;
        _lastTriggerTimes[zoneKey] = DateTime.now();
        await _setRingMode();
        _showNotification("Exited $zoneName", "Phone switched to Ring");
      }
      print("Current Position: ${position.latitude}, ${position.longitude}");
      print("Zone: $zoneName Distance: $distance Radius: $radius");
    }
  }

  // 🔥 Distance Calculation (Haversine Formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // meters
    double dLat = _degToRad(lat2 - lat1);
    double dLon = _degToRad(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * (pi / 180);

  // 🔕 SET SILENT MODE
  Future<void> _setSilentMode() async {
    // You already have DND logic — call it here
    print("Silent Mode Activated");
  }

  // 🔔 SET RING MODE
  Future<void> _setRingMode() async {
    print("Ring Mode Activated");
  }

  // 🔔 Notification
  Future<void> _showNotification(String title, String body) async 
  {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'zone_channel',
      'Zone Notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}