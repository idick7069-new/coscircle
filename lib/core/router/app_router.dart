import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/current_event/presentation/current_event_page.dart';
import '../../features/events/presentation/event_detail_page.dart';
import '../../features/home/presentation/home_shell_page.dart';
import '../../features/profile/presentation/onboarding_profile_page.dart';
import '../../features/profile/presentation/public_profile_page.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
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
      builder: (context, state) =>
          CurrentEventPage(eventId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/profiles/:code',
      builder: (context, state) =>
          PublicProfilePage(publicCode: state.pathParameters['code']!),
    ),
  ],
);
