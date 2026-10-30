import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utils/async_state.dart';
import '../../../../utils/failure.dart';
import '../../data/maps/http_route_planner.dart';
import '../../domain/route_planning.dart';

final routePlannerProvider = Provider<RoutePlanner>(
  (ref) => HttpRoutePlanner.instance,
);

/// Owns only the unsaved selection and request, never the saved route/workspace.
class RoutePlanningController extends ChangeNotifier {
  RoutePlanningController(
    this.planner, {
    List<RouteWaypoint> waypoints = const [],
  }) : _waypoints = List.of(waypoints),
       _initial = List.of(waypoints);
  final RoutePlanner planner;
  final List<RouteWaypoint> _initial;
  List<RouteWaypoint> _waypoints;
  List<RouteWaypoint> get waypoints => List.unmodifiable(_waypoints);
  RequestState<PlannedRoute> state = const RequestInitial();
  RoutePlanningCancellation? _cancellation;
  int _generation = 0;
  bool _disposed = false;
  bool get hasChanges => !listEquals(_initial, _waypoints);

  void replace(List<RouteWaypoint> points) {
    if (listEquals(points, _waypoints)) return;
    _waypoints = List.of(points);
    invalidate();
  }

  void invalidate() {
    _generation++;
    _cancellation?.cancel();
    state = const RequestInitial();
    notifyListeners();
  }

  void add(RouteWaypoint point) {
    if (point.isValid && _waypoints.length < RoutePlanMetadata.maxWaypoints) {
      replace([..._waypoints, point]);
    }
  }

  void update(int index, RouteWaypoint point) {
    if (!point.isValid) return;
    final points = [..._waypoints];
    points[index] = point;
    replace(points);
  }

  void remove(int index) => replace([..._waypoints]..removeAt(index));

  void move(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _waypoints.length) return;
    final points = [..._waypoints];
    final point = points.removeAt(index);
    points.insert(target, point);
    replace(points);
  }

  Future<void> plan(RoutePlanningSettings settings) async {
    if (state.isLoading) return;
    if (_waypoints.length < 2 || settings.planningValidationKey != null) {
      state = RequestFailure(
        UnknownFailure(settings.planningValidationKey ?? 'routing_points'),
      );
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    final cancellation = _cancellation = RoutePlanningCancellation();
    state = const RequestLoading();
    notifyListeners();
    final result = await planner.plan(
      settings: settings,
      waypoints: waypoints,
      cancellation: cancellation,
    );
    if (_disposed || generation != _generation || cancellation.isCancelled) {
      return;
    }
    state = result.fold(RequestFailure.new, RequestSuccess.new);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancellation?.cancel();
    super.dispose();
  }
}
