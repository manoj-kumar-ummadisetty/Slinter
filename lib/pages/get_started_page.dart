import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:slinter/components/status_bar.dart';
import 'package:slinter/pages/home_page.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

/// Opens Android DND permission settings
void openDndSettings() {
  final intent = AndroidIntent(
    action: 'android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS',
  );
  intent.launch();
}

class GetStartedPage extends StatefulWidget {
  final String userName;
  const GetStartedPage({super.key, required this.userName});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage> {
  String _ringerStatus = "Checking...";
  Color _statusColor = Colors.orangeAccent;
  Timer? _timer;

  @override
  DateTime? _lastBackPressed;
  void initState() {
    super.initState();
    _startRingerStatusPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRingerStatusPolling() {
    // Immediately check once
    _updateRingerStatus();

    // Poll every 1 second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRingerStatus();
    });
  }

  Future<void> _updateRingerStatus() async {
    try {
      final ringer = await SoundMode.ringerModeStatus;
      if (!mounted) return;
      setState(() {
        if (ringer == RingerModeStatus.silent ||
            ringer == RingerModeStatus.vibrate) {
          _ringerStatus = "Silent";
          _statusColor = Colors.redAccent;
        } else {
          _ringerStatus = "Ring";
          _statusColor = Colors.greenAccent;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ringerStatus = "Unknown";
        _statusColor = Colors.grey;
      });
    }
  }

  // ===================== MAIN CONTROLLER =====================
 Future<bool> _handleGetStarted(BuildContext context) async 
 {
    // Request location permission FIRST
    final locationStatus = await Permission.location.request();

    if (!locationStatus.isGranted) {
      _showLocationPermissionDialog(context);
      return false;
    }

    // Check if GPS is ON
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return false;
    }

    // Check DND permission
    final dndGranted = await Permission.accessNotificationPolicy.isGranted;
    if (!dndGranted) {
      _showDndPermissionDialog(context);
      return false;
    }

    return true;
  }


  // ===================== LOCATION DIALOG =====================
  void _showLocationPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "Location Required",
          style: TextStyle(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "Please enable Location access and turn ON GPS to detect silent zones.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(context);
              final serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled) await Geolocator.openLocationSettings();
            },
            child: const Text("Turn ON"),
          ),
        ],
      ),
    );
  }

  // ===================== DND DIALOG =====================
  void _showDndPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "Do Not Disturb Access",
          style: TextStyle(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "DND access is required to automatically silence your phone inside zones.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(context);
              openDndSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return BlackStatusBar(
      child: WillPopScope
      (
        onWillPop: () async 
        {
          final now = DateTime.now();
      
          if (_lastBackPressed == null ||
              now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
            _lastBackPressed = now;
      
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.black,
                content: Center(
                  child: Text('Press back again to exit',style: TextStyle
                  (
                    color: Colors.orangeAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),),
                ),
                duration: Duration(seconds: 2),
              ),
            );
            return false;
          }
          return true; // exits app
        },
      
        child: BlackStatusBar(
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: Stack(
                children: [
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: size.height * 0.32,
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2C2C2C),
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
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          // 🔹 Real-time Sound Status
                          Row(
                            children: [
                              const Text(
                                "Currently Your Mobile Is In ",
                                style: TextStyle(color: Colors.white, fontSize: 15),
                              ),
                              Text(
                                _ringerStatus,
                                style: TextStyle(
                                  color: _statusColor,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                " Mode",
                                style: TextStyle(color: Colors.white, fontSize: 15),
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
                              onPressed: () async {
                                final canProceed = await _handleGetStarted(context);
                    
                                if (!mounted) return;
                    
                                if (canProceed) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HomePage(userName: widget.userName),
                                    ),
                                  );
                                }
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
            ),
          ),
        ),
      ),
    );
  }
}
