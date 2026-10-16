import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_state.dart';
import '../../features/social/presentation/join_circle_page.dart';

import '../../features/admin/presentation/admin_dashboard_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/email_action_page.dart';
import '../../features/current_event/presentation/current_event_page.dart';
import '../../features/events/presentation/event_detail_page.dart';
import '../../features/home/presentation/home_shell_page.dart';
import '../../features/profile/presentation/onboarding_profile_page.dart';
import '../../features/profile/presentation/public_profile_page.dart';
import '../../features/profile/presentation/profile_qr_scanner_page.dart';
import '../../features/social/presentation/circle_qr_scanner_page.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: sessionExpired,
  redirect: (context, state) async {
    final publicRoute =
        [
          '/login',
          '/forgot-password',
          '/verify-email',
          '/reset-password',
        ].contains(state.uri.path) ||
        state.uri.path.startsWith('/profiles/');
    if (publicRoute) return null;
    final token = (await SharedPreferences.getInstance()).getString(
      'auth_token',
    );
    if (sessionExpired.value || token == null || token.isEmpty) {
      return Uri(
        path: '/login',
        queryParameters: {'next': state.uri.toString()},
      ).toString();
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/join/:code',
      builder: (context, state) =>
          JoinCirclePage(inviteCode: state.pathParameters['code']!),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => EmailActionPage(
        mode: EmailActionMode.forgot,
        email: state.uri.queryParameters['email'] ?? '',
      ),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => EmailActionPage(
        mode: EmailActionMode.verify,
        token: state.uri.queryParameters['token'],
      ),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => EmailActionPage(
        mode: EmailActionMode.reset,
        token: state.uri.queryParameters['token'],
      ),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminDashboardPage(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingProfilePage(),
    ),
    GoRoute(path: '/', builder: (context, state) => const HomeShellPage()),
    GoRoute(
      path: '/events/:id',
      builder: (context, state) =>
          EventDetailPage(eventId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/current/:id',
      builder: (context, state) => CurrentEventPage(
        eventId: state.pathParameters['id'],
        dayIndex:
            int.tryParse(state.uri.queryParameters['dayIndex'] ?? '') ?? 1,
      ),
    ),
    GoRoute(
      path: '/profiles/:code',
      builder: (context, state) => PublicProfilePage(
        publicCode: state.pathParameters['code']!,
        eventId: state.uri.queryParameters['eventId'],
        dayIndex: int.tryParse(state.uri.queryParameters['dayIndex'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/scan-profile',
      builder: (context, state) => const ProfileQrScannerPage(),
    ),
    GoRoute(
      path: '/scan-circle',
      builder: (context, state) => const CircleQrScannerPage(),
    ),
  ],
);
