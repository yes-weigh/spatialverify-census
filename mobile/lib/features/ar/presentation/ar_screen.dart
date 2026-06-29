import 'package:flutter/material.dart';

/// AR module disabled for field-test APK build (dependency conflicts with geolocator 13).
class ArScreen extends StatelessWidget {
  const ArScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR View')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'AR view is not included in this field-test build.\n\n'
            'Use Discovery Walk and the camera scanner for HLB mapping.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
