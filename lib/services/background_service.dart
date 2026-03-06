import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:slinter/services/zone_monitor_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'silent_zone_service',
    'Silent Zone Monitoring',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'silent_zone_service',
      initialNotificationTitle: 'Silent Zones Active',
      initialNotificationContent: 'Monitoring your location',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
  if 
  (!(await service.isRunning())) 
  {
    await service.startService();
  }
}
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {

  // 🔥 VERY IMPORTANT
  await Hive.initFlutter();
  await Hive.openBox('silentZonesBox');
 LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) 
  {
    permission = await Geolocator.requestPermission();
  }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await notifications.initialize(settings: initSettings);

  // Debug notification
  notifications.show(
    id: 1,
    title: "Service Started",
    body: "Monitoring",
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'silent_zone_service',
        'Silent Zone Monitoring',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
  service.on('stopService').listen((event) 
  {
    service.stopSelf();
  });
  ZoneMonitorService zoneService = ZoneMonitorService(notifications);
  zoneService.startMonitoring();
}