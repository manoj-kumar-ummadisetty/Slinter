import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slinter/pages/username_page.dart';
import 'package:slinter/pages/get_started_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async 
{
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('silentZonesBox');
  await Hive.openBox('profile');

  // 🔥 Initialize notifications
  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@drawable/ic_notification');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidInitSettings);

  await flutterLocalNotificationsPlugin.initialize(
      settings: initSettings,
    );

  final prefs = await SharedPreferences.getInstance();
  final String? userName = prefs.getString('userName');

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
