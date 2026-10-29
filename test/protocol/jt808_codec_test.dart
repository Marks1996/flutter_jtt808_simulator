import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_binary.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_codec.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_messages.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_models.dart';

void main() {
  const codec = Jt808Codec();

  test('SmallChi README 0x0200 is an exact, independent wire fixture', () {
    // https://github.com/SmallChi/JT808#举个栗子-1
    const hex =
        '7E 02 00 00 26 12 34 56 78 90 12 00 7D 02 '
        '00 00 00 01 00 00 00 02 00 BA 7F 0E 07 E4 F1 1C '
        '00 28 00 3C 00 00 18 10 15 10 10 10 '
        '01 04 00 00 00 64 02 02 00 7D 01 13 7E';
    final packet = Jt808Codec.parseHex(hex);
    final frame = codec.decode(packet);
    expect(frame.messageId, 0x0200);
    expect(frame.phone, '123456789012');
    expect(frame.sequence, 126);
    expect(frame.body.length, 38);
    expect(
      frame.body,
      Jt808Codec.parseHex(
        '00 00 00 01 00 00 00 02 '
        '00 BA 7F 0E 07 E4 F1 1C 00 28 00 3C 00 00 18 10 15 10 10 10 '
        '01 04 00 00 00 64 02 02 00 7D',
      ),
    );
    expect(codec.encode(frame), orderedEquals(packet));
    expect(Jt808Codec.toHex(codec.encode(frame)), hex);

    final location = LocationFix(
      latitude: 12.222222,
      longitude: 132.444444,
      altitude: 40,
      speed: 6,
      alarm: 1,
      status: 2,
      mileage: 10,
      recordedAt: DateTime.utc(2018, 10, 15, 2, 10, 10),
    );
    final body = [
      ...Jt808MessageBodies.location(location),
      0x02,
      0x02,
      0x00,
      0x7d,
    ];
    expect(
      codec.encode(
        Jt808Frame(
          messageId: 0x0200,
          phone: '123456789012',
          sequence: 126,
          body: body,
        ),
      ),
      orderedEquals(packet),
    );
  });

  test(
    'checksum and reserved bytes are escaped across header, body and checksum',
    () {
      final frame = Jt808Frame(
        messageId: 0x7e7d,
        phone: '013800138000',
        sequence: 0x7d7e,
        body: [0x7e, 0x7d, 0, 255],
      );
      final packet = codec.encode(frame);
      expect(packet.sublist(1, packet.length - 1), isNot(contains(0x7e)));
      final decoded = codec.decode(packet);
      expect(decoded.messageId, frame.messageId);
      expect(decoded.sequence, frame.sequence);
      expect(decoded.body, frame.body);
      for (final checksum in [0x7e, 0x7d]) {
        // With this one-byte body, the header/body XOR is 0x03 ^ body.
        final candidate = Jt808Frame(
          messageId: 0x0002,
          phone: '000000000000',
          sequence: 0,
          body: [0x03 ^ checksum],
        );
        final encoded = codec.encode(candidate);
        expect(encoded.sublist(encoded.length - 3, encoded.length - 1), [
          0x7d,
          if (checksum == 0x7e) 0x02 else 0x01,
        ]);
        expect(codec.decode(encoded).body, candidate.body);
      }
    },
  );

  test('strict checksum, body length, BCD, escapes and unsupported flags', () {
    final valid = codec.encode(
      Jt808Frame(messageId: 0x0002, phone: '000000000000', sequence: 1),
    );
    final corrupt = [...valid]..[5] ^= 1;
    expect(() => codec.decode(corrupt), throwsFormatException);
    expect(
      () => codec.decode([0x7e, ...List.filled(12, 0), 0x7d, 0x7e]),
      throwsFormatException,
    );
    expect(
      () => codec.decode([0x7e, ...List.filled(12, 0), 0x7d, 3, 0x7e]),
      throwsFormatException,
    );
    expect(
      () => codec.decode([0x7e, ...List.filled(12, 0), 0x7e, 0x7e]),
      throwsFormatException,
    );
    expect(
      () => codec.decode(_raw([0, 2, 0, 1, ...List.filled(8, 0)])),
      throwsFormatException,
    );
    expect(
      () => codec.decode(_raw([0, 2, 0, 0, 0xfa, ...List.filled(7, 0)])),
      throwsFormatException,
    );
    for (final (flag, reason) in [
      (0x4000, '2019'),
      (0x2000, 'Segmented'),
      (0x0400, 'Encrypted'),
      (0x8000, 'Reserved'),
    ]) {
      expect(
        () => codec.decode(_raw([0, 2, flag >> 8, 0, ...List.filled(8, 0)])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains(reason),
          ),
        ),
      );
    }
    expect(
      () => codec.encode(Jt808Frame(messageId: 2, phone: '123', sequence: 0)),
      throwsFormatException,
    );
    expect(
      () => codec.encode(
        Jt808Frame(messageId: 2, phone: '000000000000', sequence: 65536),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.encode(
        Jt808Frame(
          messageId: 2,
          phone: '000000000000',
          sequence: 0,
          body: List.filled(1024, 0),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.encode(
        Jt808Frame(
          messageId: 2,
          phone: '000000000000',
          sequence: 0,
          body: [-1],
        ),
      ),
      throwsFormatException,
    );
    for (final hex in ['', '7', '7E ZZ', '0x7e', '7E-7E']) {
      expect(() => Jt808Codec.parseHex(hex), throwsFormatException);
    }
    expect(Jt808Codec.parseHex('7e\n 7D\t01'), [126, 125, 1]);
  });

  test('immutable body and 1023-byte largest body', () {
    final bytes = [1, 2];
    final frame = Jt808Frame(
      messageId: 2,
      phone: '000000000000',
      sequence: 0,
      body: bytes,
    );
    bytes[0] = 3;
    expect(frame.body, [1, 2]);
    expect(() => frame.body[0] = 0, throwsUnsupportedError);
    final largest = codec.encode(
      Jt808Frame(
        messageId: 0x7e7e,
        phone: '777777777777',
        sequence: 0x7e7e,
        body: List.filled(1023, 0x7e),
      ),
    );
    expect(codec.decode(largest).body, List.filled(1023, 0x7e));
  });

  test(
    'TCP split at every offset, coalescing, shared delimiter and bounded recovery',
    () {
      final a = codec.encode(
        Jt808Frame(
          messageId: 0x8300,
          phone: '123456789012',
          sequence: 0x7e,
          body: [0x7e, 0x7d],
        ),
      );
      final b = codec.encode(
        Jt808Frame(messageId: 0x8201, phone: '123456789012', sequence: 4),
      );
      for (var i = 0; i <= a.length; i++) {
        final framer = Jt808PacketFramer();
        final packets = [
          ...framer.add(a.sublist(0, i)),
          ...framer.add(a.sublist(i)),
        ];
        expect(packets, [a], reason: 'split at byte $i');
      }
      final framer = Jt808PacketFramer();
      expect(framer.add([1, 2, ...a, ...b]), [a, b]);
      framer.reset();
      expect(framer.add([...a, ...b.sublist(1)]), [a, b]);
      final errors = <FormatException>[];
      final bounded = Jt808PacketFramer(
        maxBufferedBytes: 30,
        onError: (e, _) => errors.add(e),
      );
      expect(bounded.add([0x7e, ...List.filled(10000, 1)]), isEmpty);
      expect(bounded.bufferedBytes, 0);
      expect(errors, hasLength(1));
      expect(bounded.add(b), [b]);
    },
  );

  test(
    'location signs, fixed units, optional mileage and UTC+8 year rollover',
    () {
      final fix = LocationFix(
        latitude: -33.865143,
        longitude: -151.2099,
        speed: 12.3,
        altitude: 17,
        direction: 359,
        mileage: 123.4,
        status: 3,
        alarm: 0x80000000,
        recordedAt: DateTime.parse('2025-12-31T18:01:02Z'),
      );
      final body = Jt808MessageBodies.location(fix);
      final reader = Jt808Reader(body);
      expect(reader.dword(), 0x80000000);
      expect(reader.dword(), 0x0f);
      expect(reader.dword(), 33865143);
      expect(reader.dword(), 151209900);
      expect(reader.word(), 17);
      expect(reader.word(), 123);
      expect(reader.word(), 359);
      expect(reader.take(6), [0x26, 1, 1, 2, 1, 2]);
      expect(reader.take(2), [1, 4]);
      expect(reader.dword(), 1234);
      reader.requireEnd();
      expect(
        Jt808MessageBodies.location(fix, includeMileage: false),
        hasLength(28),
      );
      final positive = Jt808Reader(
        Jt808MessageBodies.location(
          fix.copyWith(latitude: 1, longitude: 2, status: 15),
        ),
      );
      positive.dword();
      expect(positive.dword(), 3, reason: 'clear stale south/west flags');
      final offset = fix.copyWith(
        recordedAt: DateTime.parse('2026-01-01T02:01:02+08:00'),
      );
      expect(Jt808MessageBodies.location(offset), body);
      expect(
        () => Jt808MessageBodies.location(const LocationFix(latitude: 91)),
        throwsFormatException,
      );
      expect(
        () => Jt808MessageBodies.location(
          fix.copyWith(recordedAt: DateTime.utc(1990)),
        ),
        throwsFormatException,
      );
    },
  );
}

List<int> _raw(List<int> data) {
  final result = <int>[0x7e];
  for (final byte in [...data, data.fold<int>(0, (a, b) => a ^ b)]) {
    if (byte == 0x7e) {
      result.addAll([0x7d, 2]);
    } else if (byte == 0x7d) {
      result.addAll([0x7d, 1]);
    } else {
      result.add(byte);
    }
  }
  return [...result, 0x7e];
}
