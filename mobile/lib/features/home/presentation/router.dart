import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/login_screen.dart';
import 'home_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../analytics/presentation/analytics_screen.dart';
import 'project_detail_screen.dart';
import '../../conflicts/presentation/conflicts_screen.dart';
import '../../mission/presentation/mission_landing_screen.dart';
import '../../mission/presentation/eb_list_screen.dart';
import '../../mission/presentation/mission_eb_router.dart';
import '../../mission/presentation/building_workflow_screen.dart';
import '../../mission/presentation/mission_home_screen.dart';
import '../../mission/presentation/end_of_day_review_screen.dart';
import '../../mission/presentation/discovery_hub_screen.dart';
import '../../mission/presentation/discovery_dashboard_screen.dart';
import '../../mission/presentation/discovery_replay_screen.dart';
import '../../mission/presentation/start_point_screen.dart';
import '../../mission/presentation/layout_georef_wizard_screen.dart';
import '../../mission/presentation/draft_hlb_map_screen.dart';
import '../../mission/presentation/coverage_gaps_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      if (authState.isLoading) return null;
      final isLoggedIn = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoggingIn) return '/login';
      if (isLoggedIn && isLoggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const MissionLandingScreen(),
          ),
          GoRoute(
            path: '/projects',
            builder: (context, state) => const ProjectListScreen(),
          ),
          GoRoute(
            path: '/project/:id',
            builder: (context, state) => ProjectDetailScreen(
              projectId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/map/:projectId',
            builder: (context, state) => MapScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId',
            builder: (context, state) => MissionHubScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId',
            builder: (context, state) => MissionEbRouter(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/source',
            redirect: (context, state) =>
                '/mission/${state.pathParameters['projectId']}/eb/${state.pathParameters['ebId']}/georef',
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/georef',
            builder: (context, state) => LayoutGeorefWizardScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/realign',
            builder: (context, state) => LayoutGeorefWizardScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
              restartAlignment: true,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/start-point',
            builder: (context, state) => StartPointScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/edit',
            redirect: (context, state) =>
                '/mission/${state.pathParameters['projectId']}/eb/${state.pathParameters['ebId']}',
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/replay',
            builder: (context, state) => DiscoveryReplayScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/dashboard',
            builder: (context, state) => DiscoveryDashboardScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/listing',
            builder: (context, state) => TodaysMissionScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/gaps',
            builder: (context, state) => CoverageGapsScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/hub',
            builder: (context, state) => DiscoveryHubScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/draft-map',
            builder: (context, state) => DraftHlbMapScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
            ),
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/end-day',
            builder: (context, state) {
              final lat = double.tryParse(state.uri.queryParameters['lat'] ?? '');
              final lng = double.tryParse(state.uri.queryParameters['lng'] ?? '');
              return EndOfDayReviewScreen(
                projectId: state.pathParameters['projectId']!,
                ebId: state.pathParameters['ebId']!,
                latitude: lat,
                longitude: lng,
              );
            },
          ),
          GoRoute(
            path: '/mission/:projectId/eb/:ebId/building/:buildingId',
            builder: (context, state) => BuildingWorkflowScreen(
              projectId: state.pathParameters['projectId']!,
              ebId: state.pathParameters['ebId']!,
              buildingId: state.pathParameters['buildingId']!,
            ),
          ),
          GoRoute(
            path: '/analytics/:projectId',
            builder: (context, state) => AnalyticsScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/conflicts',
            builder: (context, state) => const ConflictsScreen(),
          ),
        ],
      ),
    ],
  );
});

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (projects) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProjectCard(project: project),
            );
          },
        ),
      ),
    );
  }
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(selectedProjectProvider.notifier).state = project;
        context.push('/project/${project.id}');
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.glassDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.map_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (project.description != null)
                        Text(
                          project.description!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
