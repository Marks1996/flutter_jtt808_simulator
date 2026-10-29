import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

import '../../domain/simulator_models.dart';
import 'jt808_binary.dart';

/// Body formats verified against SmallChi/JT808 (2013 branches).
abstract final class Jt808MessageBodies {
  /// Uses the package's byte codec, not its 16-bit code-point codec.
  static Uint8List encodeGbk(String text) {
    try {
      final bytes = gbk_bytes.encode(text);
      if (bytes.any((b) => b < 0 || b > 255) || decodeGbk(bytes) != text) {
        throw const FormatException(
          'Text cannot be represented losslessly in GBK',
        );
      }
      return Uint8List.fromList(bytes);
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      Error.throwWithStackTrace(
        FormatException('Invalid GBK text: $error'),
        stack,
      );
    }
  }

  static String decodeGbk(List<int> bytes) {
    try {
      // The dependency substitutes some invalid input. Reject it explicitly.
      for (var i = 0; i < bytes.length; i++) {
        final lead = bytes[i];
        if (lead >= 0 && lead <= 0x7f) continue;
        if (lead < 0x81 || lead > 0xfe || ++i >= bytes.length) {
          throw const FormatException('Invalid GBK leading byte');
        }
        final trail = bytes[i];
        if (trail < 0x40 || trail > 0xfe || trail == 0x7f) {
          throw const FormatException('Invalid GBK trailing byte');
        }
      }
      final text = gbk_bytes.decode(bytes);
      final encoded = gbk_bytes.encode(text);
      if (encoded.length != bytes.length ||
          List.generate(
            bytes.length,
            (i) => encoded[i] != bytes[i],
          ).contains(true)) {
        throw const FormatException('Invalid or unmapped GBK text');
      }
      return text;
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      Error.throwWithStackTrace(
        FormatException('Invalid GBK bytes: $error'),
        stack,
      );
    }
  }

  static Uint8List registration(TerminalConfig config) {
    if (config.validationKey != null) {
      throw FormatException(
        'Invalid terminal configuration: ${config.validationKey}',
      );
    }
    final writer = Jt808Writer()
      ..word(config.province)
      ..word(config.city);
    void fixedAscii(String text, int length) {
      final bytes = ascii.encode(text);
      if (bytes.length > length) {
        throw const FormatException('Identity field too long');
      }
      writer.bytes([...bytes, ...List.filled(length - bytes.length, 0)]);
    }

    fixedAscii(config.manufacturer, 5);
    fixedAscii(config.model, 20);
    fixedAscii(config.terminalId, 7);
    writer
      ..byte(config.plateColor)
      ..bytes(encodeGbk(config.plate));
    final body = writer.toBytes();
    if (body.length > 1023) {
      throw const FormatException('Registration plate is too long');
    }
    return body;
  }

  static Uint8List authentication(String code) {
    final bytes = encodeGbk(code);
    if (bytes.isEmpty || bytes.length > 1023) {
      throw const FormatException(
        'Authentication code must contain 1..1023 GBK bytes',
      );
    }
    return bytes;
  }

  /// Speed and mileage use 0.1 km/h and 0.1 km units. Time is always UTC+8.
  static Uint8List location(
    LocationFix fix, {
    bool includeMileage = true,
    DateTime? now,
  }) {
    if (fix.validationKey != null) {
      throw FormatException('Invalid location: ${fix.validationKey}');
    }
    var status = fix.status & ~0x0c;
    if (fix.latitude.isNegative) status |= 1 << 2;
    if (fix.longitude.isNegative) status |= 1 << 3;
    final time = (fix.recordedAt ?? now ?? DateTime.now()).toUtc().add(
      const Duration(hours: 8),
    );
    if (time.year < 2000 || time.year > 2099) {
      throw const FormatException(
        '2013 location time must be in 2000..2099 UTC+8',
      );
    }
    final writer = Jt808Writer()
      ..dword(fix.alarm)
      ..dword(status)
      ..dword((fix.latitude.abs() * 1000000).round())
      ..dword((fix.longitude.abs() * 1000000).round())
      ..word(fix.altitude)
      ..word((fix.speed * 10).round())
      ..word(fix.direction);
    for (final value in [
      time.year % 100,
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
    ]) {
      writer.byte(((value ~/ 10) << 4) | (value % 10));
    }
    if (includeMileage) {
      writer
        ..byte(0x01)
        ..byte(0x04)
        ..dword((fix.mileage * 10).round());
    }
    return writer.toBytes();
  }

  static Uint8List generalResponse(
    int platformSequence,
    int messageId,
    int result,
  ) =>
      (Jt808Writer()
            ..word(platformSequence)
            ..word(messageId)
            ..byte(result))
          .toBytes();
}
