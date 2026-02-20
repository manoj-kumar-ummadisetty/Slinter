import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ZoneMonitorService {
  Timer? _timer;
  Position? _currentPosition;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Store previous state of zones
  final Map<String, bool> _zoneStates = {};

  // 🔥 START MONITORING
  void startMonitoring() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkZones();
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  // 🔥 CORE LOGIC
  Future<void> _checkZones() async {
    _currentPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final box = Hive.box('silentZonesBox');
    final zones = box.values.toList();

    for (var zone in zones) {
      if (!zone['isActive']) continue;

      final double zoneLat = zone['latitude'];
      final double zoneLng = zone['longitude'];
      final double radius = zone['radius'];
      final String zoneName = zone['zoneName']?.toString() ?? "Unnamed Zone";

      double distance = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        zoneLat,
        zoneLng,
      );

      bool isInside = distance <= radius;

      bool wasInside = _zoneStates[zoneName] ?? false;

      // 🔥 ENTRY DETECTED
      if (isInside && !wasInside) {
        _zoneStates[zoneName] = true;
        await _setSilentMode();
        _showNotification("Entered $zoneName", "Phone switched to Silent");
      }

      // 🔥 EXIT DETECTED
      if (!isInside && wasInside) {
        _zoneStates[zoneName] = false;
        await _setRingMode();
        _showNotification("Exited $zoneName", "Phone switched to Ring");
      }
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