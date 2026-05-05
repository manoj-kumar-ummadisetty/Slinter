import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slinter/pages/get_started_page.dart';
import 'package:slinter/pages/username_page.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('silentZonesBox');
  await Hive.openBox('profile');

  const androidInitSettings = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const initSettings = InitializationSettings(android: androidInitSettings);

  await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

  const channel = AndroidNotificationChannel(
    'slinter_channel',
    'Slinter Background Service',
    description: 'Monitors silent zones in background',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  final prefs = await SharedPreferences.getInstance();
  final userName = prefs.getString('userName');

  runApp(MyApp(userName: userName));
}

class MyApp extends StatelessWidget {
  final String? userName;

  const MyApp({super.key, this.userName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: userName == null
          ? const UserNamePage()
          : GetStartedPage(userName: userName!),
    );
  }
}
