import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shell around authenticated routes. Map screens are full-bleed — no bottom tabs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: child);
  }
}
