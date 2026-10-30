import 'basemap_settings.dart';
import 'route_planning.dart';
import 'simulator_models.dart';

export 'route_planning.dart';

export 'basemap_settings.dart';

class SimulatorWorkspace {
  SimulatorWorkspace({
    List<TerminalConfig> terminals = const [],
    List<DriveRoute> routes = const [],
    List<DriveTask> tasks = const [],
    this.theme = 'system',
    this.basemap = const BasemapSettings(),
    this.routing = const RoutePlanningSettings(),
  }) : terminals = List.unmodifiable(terminals),
       routes = List.unmodifiable(routes),
       tasks = List.unmodifiable(tasks);
  final List<TerminalConfig> terminals;
  final List<DriveRoute> routes;
  final List<DriveTask> tasks;
  final String theme;
  final BasemapSettings basemap;
  final RoutePlanningSettings routing;
  SimulatorWorkspace copyWith({
    List<TerminalConfig>? terminals,
    List<DriveRoute>? routes,
    List<DriveTask>? tasks,
    String? theme,
    BasemapSettings? basemap,
    RoutePlanningSettings? routing,
  }) => SimulatorWorkspace(
    terminals: terminals ?? this.terminals,
    routes: routes ?? this.routes,
    tasks: tasks ?? this.tasks,
    theme: theme ?? this.theme,
    basemap: basemap ?? this.basemap,
    routing: routing ?? this.routing,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'terminals': terminals.map((e) => e.toJson()).toList(),
    'routes': routes.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'theme': theme,
    'basemap': basemap.toJson(),
    'routing': routing.toJson(),
  };
  factory SimulatorWorkspace.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported workspace version');
    }
    final data = SimulatorWorkspace(
      routing: json['routing'] == null
          ? const RoutePlanningSettings()
          : RoutePlanningSettings.fromJson(
              Map<String, Object?>.from(json['routing'] as Map),
            ),
      terminals: (json['terminals'] as List)
          .map(
            (e) => TerminalConfig.fromJson(Map<String, Object?>.from(e as Map)),
          )
          .toList(),
      routes: (json['routes'] as List)
          .map((e) => DriveRoute.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
      tasks: (json['tasks'] as List)
          .map((e) => DriveTask.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
      theme: json['theme'] as String? ?? 'system',
      // Version 1 workspaces predate basemap preferences.
      basemap: json['basemap'] == null
          ? const BasemapSettings()
          : BasemapSettings.fromJson(
              Map<String, Object?>.from(json['basemap'] as Map),
            ),
    );
    if (data.terminals.any((e) => e.validationKey != null) ||
        data.routes.any(
          (e) =>
              e.points.length < 2 ||
              e.coordinateSystem != 'WGS84' ||
              e.points.any((p) => p.validationKey != null || p.speed <= 0),
        ) ||
        data.tasks.any(
          (t) =>
              !data.terminals.any((e) => e.id == t.terminalId) ||
              !data.routes.any((e) => e.id == t.routeId),
        ) ||
        data.terminals.map((e) => e.id).toSet().length !=
            data.terminals.length ||
        data.terminals.map((e) => e.phone).toSet().length !=
            data.terminals.length ||
        data.routes.map((e) => e.id).toSet().length != data.routes.length ||
        data.tasks.map((e) => e.id).toSet().length != data.tasks.length ||
        !['system', 'light', 'dark'].contains(data.theme)) {
      throw const FormatException('Invalid workspace data');
    }
    return data;
  }
}

abstract interface class SimulatorRepository {
  Future<SimulatorWorkspace> load();
  Future<void> save(SimulatorWorkspace workspace);
}
