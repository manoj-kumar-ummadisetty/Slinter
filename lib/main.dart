import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slinter/pages/username_page.dart';
import 'package:slinter/pages/get_started_page.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Init Hive ONCE
  await Hive.initFlutter();

  // 🔥 Open ALL boxes you use in the app
  await Hive.openBox('silentZonesBox');
  await Hive.openBox('profile'); // <-- IMPORTANT (userId stored here)

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
