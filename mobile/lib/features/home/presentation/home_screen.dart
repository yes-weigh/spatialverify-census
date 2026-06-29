import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final location = GoRouterState.of(context).matchedLocation;
    int currentIndex = 0;
    if (location.contains('/mission') || location.contains('/projects')) currentIndex = 1;

    return Scaffold(
      body: child,
      bottomNavigationBar: user != null
          ? Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: NavigationBar(
                selectedIndex: currentIndex.clamp(0, 1),
                backgroundColor: AppTheme.surface,
                indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.route_outlined),
                    selectedIcon: Icon(Icons.route),
                    label: 'Mission',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    selectedIcon: Icon(Icons.folder),
                    label: 'Projects',
                  ),
                ],
                onDestinationSelected: (index) {
                  switch (index) {
                    case 0:
                      context.go('/');
                    case 1:
                      context.go('/projects');
                  }
                },
              ),
            )
          : null,
    );
  }
}
