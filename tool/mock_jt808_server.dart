import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_binary.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_codec.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_messages.dart';

/// Loopback-only test platform, deliberately not a production JT808 server.
Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 7100 : int.tryParse(args.single);
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln(
      'Usage: dart run tool/mock_jt808_server.dart [port: 1..65535]',
    );
    exitCode = 64;
    return;
  }
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  final peers = <_Peer>{};
  stdout.writeln(
    'LOCAL TEST PLATFORM · 127.0.0.1:${server.port} · JT/T 808-2013',
  );
  stdout.writeln(
    'No production authentication. Test authentication code: LOCAL-TEST',
  );
  stdout.writeln(
    'Commands: query | interval <1..3600> | text <message> | quit',
  );
  final input = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final trimmed = line.trim();
        if (trimmed == 'quit') {
          unawaited(server.close());
          for (final p in peers.toList()) {
            p.socket.destroy();
          }
          return;
        }
        for (final peer in peers.where((p) => p.online)) {
          if (trimmed == 'query') {
            peer.send(0x8201, const []);
          } else if (trimmed.startsWith('text ')) {
            peer.send(0x8300, [
              1,
              ...Jt808MessageBodies.encodeGbk(trimmed.substring(5)),
            ]);
          } else if (trimmed.startsWith('interval ')) {
            final value = int.tryParse(trimmed.substring(9));
            if (value != null && value >= 1 && value <= 3600) {
              peer.send(
                0x8103,
                (Jt808Writer()
                      ..byte(1)
                      ..dword(0x0029)
                      ..byte(4)
                      ..dword(value))
                    .toBytes(),
              );
            } else {
              stdout.writeln('Interval must be 1..3600 seconds.');
            }
          }
        }
      });
  final signal = ProcessSignal.sigint.watch().listen((_) {
    unawaited(server.close());
    for (final peer in peers.toList()) {
      peer.socket.destroy();
    }
  });
  await for (final socket in server) {
    final peer = _Peer(socket);
    peers.add(peer);
    peer.listen(() => peers.remove(peer));
  }
  await input.cancel();
  await signal.cancel();
}

class _Peer {
  _Peer(this.socket);
  final Socket socket;
  final codec = const Jt808Codec();
  final framer = Jt808PacketFramer();
  String phone = '';
  int sequence = 0;
  bool online = false;
  bool queried = false;
  void listen(void Function() onClose) {
    stdout.writeln(
      'TCP connected: ${socket.remoteAddress.address}:${socket.remotePort}',
    );
    socket.listen(
      (data) {
        for (final packet in framer.add(data)) {
          try {
            final frame = codec.decode(packet);
            phone = frame.phone;
            stdout.writeln(
              'RX $phone 0x${frame.messageId.toRadixString(16).padLeft(4, '0')} seq=${frame.sequence} bytes=${packet.length}',
            );
            if (frame.messageId == 0x0100) {
              send(
                0x8100,
                (Jt808Writer()
                      ..word(frame.sequence)
                      ..byte(0)
                      ..bytes(Jt808MessageBodies.encodeGbk('LOCAL-TEST')))
                    .toBytes(),
              );
            } else if (frame.messageId == 0x0102) {
              final valid =
                  Jt808MessageBodies.decodeGbk(frame.body) == 'LOCAL-TEST';
              online = valid;
              acknowledge(frame, valid ? 0 : 1);
            } else if (online && [0x0002, 0x0200].contains(frame.messageId)) {
              acknowledge(frame, 0);
              if (frame.messageId == 0x0200 && !queried) {
                queried = true;
                send(0x8201, const []);
              }
            }
          } catch (error) {
            stderr.writeln('Rejected invalid packet: $error');
          }
        }
      },
      onDone: () {
        stdout.writeln('TCP disconnected: $phone');
        onClose();
      },
      onError: (Object error) {
        stderr.writeln('TCP error: $error');
        onClose();
      },
      cancelOnError: true,
    );
  }

  void acknowledge(Jt808Frame frame, int result) => send(
    0x8001,
    Jt808MessageBodies.generalResponse(frame.sequence, frame.messageId, result),
  );
  void send(int id, List<int> body) {
    final frame = Jt808Frame(
      messageId: id,
      phone: phone,
      sequence: sequence++ & 0xffff,
      body: body,
    );
    socket.add(codec.encode(frame));
    stdout.writeln(
      'TX $phone 0x${id.toRadixString(16).padLeft(4, '0')} seq=${frame.sequence}',
    );
  }
}
