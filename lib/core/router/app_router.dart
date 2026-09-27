import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/view/login_page.dart';
import '../../features/documents/model/document.dart';
import '../../features/documents/view/document_details_page.dart';
import '../../features/documents/view/document_form_page.dart';
import '../../features/documents/view/documents_page.dart';
import '../../features/home/view/home_page.dart';
import '../../features/settings/view/settings_page.dart';
import '../../features/tasks/model/task.dart';
import '../../features/tasks/view/task_folder_page.dart';
import '../../features/tasks/view/task_form_page.dart';
import '../../features/tasks/view/tasks_page.dart';
import '../widgets/adaptive_scaffold.dart';
import 'transitions.dart';

/// Bridges a [Stream] to a [Listenable] so GoRouter re-evaluates its redirect
/// whenever the Supabase auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Central navigation. A [StatefulShellRoute] keeps a persistent adaptive
/// nav shell around three top-level sections, each with its own navigation
/// stack. Feature pages are declared under their section's branch.
final appRouter = GoRouter(
  initialLocation: '/home',
  refreshListenable: _AuthRefresh(Supabase.instance.client.auth.onAuthStateChange),
  redirect: (context, state) {
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    final atLogin = state.matchedLocation == '/login';
    if (!signedIn) return atLogin ? null : '/login';
    if (atLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => _Shell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomePage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/documents', builder: (_, _) => const DocumentsPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (_, _) => const TasksPage(),
              routes: [
                GoRoute(
                  path: 'folder/:entity',
                  pageBuilder: (context, state) => slideFadePage(
                    key: state.pageKey,
                    child: TaskFolderPage(entity: state.pathParameters['entity']!),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          ],
        ),
      ],
    ),
    // Full-screen routes above the shell (forms / details).
    GoRoute(
      path: '/task-form',
      pageBuilder: (context, state) =>
          slideFadePage(key: state.pageKey, child: TaskFormPage(task: state.extra as Task?)),
    ),
    GoRoute(
      path: '/document-form',
      pageBuilder: (context, state) => slideFadePage(
        key: state.pageKey,
        child: DocumentFormPage(document: state.extra as Document?),
      ),
    ),
    GoRoute(
      path: '/document-details',
      pageBuilder: (context, state) => slideFadePage(
        key: state.pageKey,
        child: DocumentDetailsPage(document: state.extra as Document),
      ),
    ),
  ],
);

class _Shell extends StatelessWidget {
  const _Shell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    AdaptiveDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'الرئيسية',
    ),
    AdaptiveDestination(
      icon: Icons.description_outlined,
      selectedIcon: Icons.description,
      label: 'الطلبات',
    ),
    AdaptiveDestination(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: 'المهمات',
    ),
    AdaptiveDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'الإعدادات',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      destinations: _destinations,
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      child: navigationShell,
    );
  }
}
