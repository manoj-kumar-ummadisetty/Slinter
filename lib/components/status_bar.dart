import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlackStatusBar extends StatelessWidget {
  final Widget child;

  const BlackStatusBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.dark,
      ),
      child: child,
    );
  }
}
