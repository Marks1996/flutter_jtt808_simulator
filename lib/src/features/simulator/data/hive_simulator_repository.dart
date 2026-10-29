import 'dart:convert';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../domain/simulator_repository.dart';

class HiveSimulatorRepository implements SimulatorRepository {
  Future<Box<String>> _box() => Hive.openBox<String>('simulator_workspace');
  @override
  Future<SimulatorWorkspace> load() async {
    final raw = (await _box()).get('workspace');
    return raw == null
        ? SimulatorWorkspace()
        : SimulatorWorkspace.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
  }

  @override
  Future<void> save(SimulatorWorkspace workspace) async {
    final box = await _box();
    await box.put('workspace', jsonEncode(workspace.toJson()));
    await box.flush();
  }
}
