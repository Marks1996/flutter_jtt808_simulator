import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_codec.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_messages.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';

class _Repository implements SimulatorRepository {
  SimulatorWorkspace data = SimulatorWorkspace();
  @override
  Future<SimulatorWorkspace> load() async => data;
  @override
  Future<void> save(SimulatorWorkspace workspace) async {
    data = workspace;
  }
}

Future<void> _until(
  SimulatorController controller,
  bool Function() predicate,
) async {
  if (predicate()) return;
  final done = Completer<void>();
  void check() {
    if (predicate() && !done.isCompleted) done.complete();
  }

  controller.addListener(check);
  try {
    await done.future.timeout(const Duration(seconds: 8));
  } finally {
    controller.removeListener(check);
  }
}

void main() {
  test(
    'controller has one report scheduler; playback, pause, mileage and flags reach the real socket',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final repository = _Repository();
      final controller = SimulatorController(repository);
      const codec = Jt808Codec();
      final incoming = <Jt808Frame>[];
      final peers = <Socket>[];
      final disconnected = Completer<void>();
      void closed() {
        if (!disconnected.isCompleted) disconnected.complete();
      }

      var sequence = 0;
      void send(Socket socket, int id, List<int> body) => socket.add(
        codec.encode(
          Jt808Frame(
            messageId: id,
            phone: '013800138000',
            sequence: sequence++ & 0xffff,
            body: body,
          ),
        ),
      );
      final listener = server.listen((socket) {
        peers.add(socket);
        unawaited(
          socket.done.then<void>(
            (_) => closed(),
            onError: (Object error, StackTrace stack) => closed(),
          ),
        );
        final framer = Jt808PacketFramer();
        socket.listen(
          (bytes) {
            for (final packet in framer.add(bytes)) {
              final frame = codec.decode(packet);
              incoming.add(frame);
              if ([0x0102, 0x0002].contains(frame.messageId)) {
                send(
                  socket,
                  0x8001,
                  Jt808MessageBodies.generalResponse(
                    frame.sequence,
                    frame.messageId,
                    0,
                  ),
                );
              }
            }
          },
          onDone: closed,
          onError: (Object error) => closed(),
          cancelOnError: true,
        );
      });
      addTearDown(() async {
        controller.dispose();
        for (final socket in peers) {
          socket.destroy();
        }
        await listener.cancel();
        await server.close();
      });
      await controller.load();
      await controller.saveTerminal(
        TerminalConfig(
          id: 't',
          port: server.port,
          authCode: 'LOCAL-TEST',
          locationIntervalSeconds: 1,
        ),
      );
      final route = DriveRoute(
        id: 'r',
        name: 'Equator test',
        points: const [
          LocationFix(latitude: 0, longitude: 0, speed: 36),
          LocationFix(latitude: 0, longitude: 1, speed: 36),
        ],
      );
      await controller.saveRoute(route);
      await controller.saveTask(
        const DriveTask(
          id: 'job',
          name: 'Drive test',
          terminalId: 't',
          routeId: 'r',
        ),
      );
      controller.updateLocation(
        't',
        const LocationFix(mileage: 123.4, alarm: 2),
      );
      await controller.startTask('job');
      await _until(controller, () => controller.onlineCount == 1);
      final activeTime = Stopwatch()..start();
      expect(
        controller.runtime('t').lastSent,
        isNull,
        reason: 'authentication is not a position report',
      );
      await _until(
        controller,
        () =>
            incoming.where((f) => f.messageId == 0x0200).length >= 2 &&
            controller.runtime('t').lastSent != null,
      );
      final reports = incoming.where((f) => f.messageId == 0x0200).toList();
      expect(reports.length, 2, reason: 'one owner of automatic 0x0200 timers');
      expect(
        controller.taskRuntimes['job']!.player.travelledKm,
        closeTo(
          activeTime.elapsedMicroseconds /
              Duration.microsecondsPerSecond *
              0.01,
          0.008,
        ),
      );
      expect(controller.runtime('t').location.mileage, greaterThan(123.41));
      expect(
        reports.last.body[3],
        2,
        reason: 'alarm flags survive route progression',
      );
      final body = reports.last.body;
      final longitude =
          (body[12] << 24) | (body[13] << 16) | (body[14] << 8) | body[15];
      expect(
        longitude,
        greaterThan(100),
        reason: 'wire coordinates follow the advancing route',
      );

      controller.pauseTask('job');
      final paused = controller.runtime('t').location;
      send(peers.single, 0x8201, const []);
      await _until(
        controller,
        () => incoming.any((f) => f.messageId == 0x0201),
      );
      final query = incoming.lastWhere((f) => f.messageId == 0x0201);
      expect(
        query.body[20],
        0,
      ); // response sequence (2), then altitude (2), speed at 20.
      expect(query.body[21], 0);
      expect(controller.runtime('t').location.longitude, paused.longitude);

      await controller.startTask('job');
      expect(controller.taskRuntimes['job']!.clock.isRunning, isTrue);
      await controller.disconnect('t');
      await disconnected.future.timeout(const Duration(seconds: 2));
      final count = incoming.where((f) => f.messageId == 0x0200).length;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(incoming.where((f) => f.messageId == 0x0200).length, count);
      expect(controller.runtime('t').phase, ConnectionPhase.disconnected);
      expect(controller.taskRuntimes['job']!.phase, TaskPhase.paused);
    },
  );

  test(
    'manual hemisphere bits are normalized to the actual position',
    () async {
      final controller = SimulatorController(_Repository());
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveTerminal(const TerminalConfig(id: 't'));
      controller.updateLocation(
        't',
        const LocationFix(latitude: -33, longitude: -70, status: 3),
      );
      expect(controller.runtime('t').location.status, 15);
      controller.updateLocation(
        't',
        const LocationFix(latitude: 33, longitude: 70, status: 15),
      );
      expect(controller.runtime('t').location.status, 3);
    },
  );
}
