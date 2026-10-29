import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_jtt808_simulator/src/middleware/app_route_observer.dart';
import 'package:flutter_jtt808_simulator/src/routing/global_navigator.dart';
import 'package:flutter_jtt808_simulator/src/routing/app_routes.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/screens/simulator_screen.dart';

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.home,
  observers: <NavigatorObserver>[AppRouteObserver()],
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const SimulatorScreen(),
    ),
  ],
);
