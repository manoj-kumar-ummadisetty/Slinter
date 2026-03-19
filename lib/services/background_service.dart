import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'zone_monitor_service.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'slinter_channel',
    'Slinter Background Service',
    description: 'Monitors silent zones in background',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'slinter_channel',
      initialNotificationTitle: 'Slinter Running',
      initialNotificationContent: 'Monitoring silent zones',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async 
{
  WidgetsFlutterBinding.ensureInitialized(); // ✅ MUST FIRST

  // ✅ Notifications init
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize
  (
   settings:  initSettings,
  );

  // ✅ Create notification channel again
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'slinter_channel',
    'Slinter Background Service',
    description: 'Monitors silent zones in background',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // ✅ Hive init
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  ZoneMonitorService zoneMonitor =
      ZoneMonitorService(notifications: flutterLocalNotificationsPlugin);

  await zoneMonitor.startMonitoring();

  service.on('stopService').listen((event) {
    zoneMonitor.stopMonitoring();
    service.stopSelf();
  });
}