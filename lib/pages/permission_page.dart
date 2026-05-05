import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:slinter/services/background_service.dart';

class PermissionPage extends StatelessWidget 
{
  const PermissionPage({super.key});
  Future<void> _requestLocationPermission(BuildContext context) async 
  {
    // STEP 1: Foreground location
    PermissionStatus whenInUse = await Permission.locationWhenInUse.status;

    if (whenInUse.isDenied) {
      whenInUse = await Permission.locationWhenInUse.request();
    }

    if (whenInUse.isPermanentlyDenied) {
      openAppSettings();
      return;
    }

    if (!whenInUse.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location permission required"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // STEP 2: Background location
    PermissionStatus locationStatus = await Permission.locationAlways.status;

    if (locationStatus.isDenied) {
      locationStatus = await Permission.locationAlways.request();
    }

    if (locationStatus.isPermanentlyDenied) {
      openAppSettings();
      return;
    }

    if (!locationStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Background location required"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // STEP 3: Notification permission
    PermissionStatus notificationStatus =
        await Permission.notification.request();

    if (!notificationStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Notification permission denied"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // STEP 4: Battery optimization
    PermissionStatus batteryStatus =
        await Permission.ignoreBatteryOptimizations.request();

    if (!batteryStatus.isGranted) {
      print("Battery optimization not disabled");
    }

    // STEP 5: Start service safely
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await initializeService();
    }

    // STEP 6: Navigate
    if (context.mounted) {
      Navigator.of(context).pushNamed('/home');
    }
  }

  
  void _showLocationPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Location Permission",
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "This app requires access to your location to provide better features based on your area. Do you want to allow location access?",
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Permission Denied"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              },
              child: const Text(
                "Deny",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Future.delayed(const Duration(milliseconds: 300), () 
                {
                  _requestLocationPermission(context);
                });
              },
              child: const Text(
                "Allow",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/app_background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.7),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // ✅ Bottom section
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: size.height * 0.32,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 44, 44, 44),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hello Welcome Back!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Manoj Kumar',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: const [
                      Text(
                        'Currently Your Mobile Is In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' Silent ',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        _showLocationPermissionDialog(context);
                      },
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
