import 'dart:typed_data';

/// An unencrypted, unsegmented JT/T 808-2013 message. [body] is immutable.
class Jt808Frame {
  Jt808Frame({
    required this.messageId,
    required this.phone,
    required this.sequence,
    List<int> body = const [],
  }) : body = List<int>.unmodifiable(body);

  final int messageId;
  final String phone;
  final int sequence;
  final List<int> body;
}

/// Strict 2013 framing. Unsupported protocol flags are errors, not fallbacks.
class Jt808Codec {
  const Jt808Codec();

  static const maxBodyLength = 1023;
  static const maxFrameLength = (12 + maxBodyLength + 1) * 2 + 2;

  Uint8List encode(Jt808Frame frame) {
    _word(frame.messageId, 'message ID');
    _word(frame.sequence, 'sequence');
    if (!RegExp(r'^\d{12}$').hasMatch(frame.phone)) {
      throw const FormatException('2013 terminal phone must contain 12 digits');
    }
    if (frame.body.length > maxBodyLength) {
      throw const FormatException(
        'Message body exceeds 1023 bytes; segmentation is unsupported',
      );
    }
    _bytes(frame.body);
    final data = <int>[
      frame.messageId >> 8,
      frame.messageId & 0xff,
      frame.body.length >> 8,
      frame.body.length & 0xff,
      for (var i = 0; i < 12; i += 2)
        int.parse(frame.phone.substring(i, i + 2), radix: 16),
      frame.sequence >> 8,
      frame.sequence & 0xff,
      ...frame.body,
    ];
    data.add(data.fold<int>(0, (a, b) => a ^ b));
    final escaped = <int>[0x7e];
    for (final byte in data) {
      switch (byte) {
        case 0x7e:
          escaped.addAll([0x7d, 0x02]);
        case 0x7d:
          escaped.addAll([0x7d, 0x01]);
        default:
          escaped.add(byte);
      }
    }
    return Uint8List.fromList([...escaped, 0x7e]);
  }

  /// Decodes exactly one complete, escaped frame including both 0x7E flags.
  Jt808Frame decode(List<int> packet) {
    _bytes(packet);
    if (packet.length < 15 ||
        packet.length > maxFrameLength ||
        packet.first != 0x7e ||
        packet.last != 0x7e) {
      throw const FormatException('Invalid JT808 frame boundary or length');
    }
    final data = <int>[];
    for (var i = 1; i < packet.length - 1; i++) {
      var byte = packet[i];
      if (byte == 0x7e) {
        throw const FormatException('Unescaped frame delimiter');
      }
      if (byte == 0x7d) {
        if (++i >= packet.length - 1) {
          throw const FormatException('Truncated escape');
        }
        byte = switch (packet[i]) {
          0x01 => 0x7d,
          0x02 => 0x7e,
          _ => throw const FormatException('Invalid escape'),
        };
      }
      data.add(byte);
    }
    if (data.length < 13) {
      throw const FormatException('Truncated 2013 message header');
    }
    if (data.fold<int>(0, (a, b) => a ^ b) != 0) {
      throw const FormatException('JT808 XOR checksum mismatch');
    }
    final properties = (data[2] << 8) | data[3];
    if (properties & 0x4000 != 0) {
      throw const FormatException(
        'JT808-2019 is unsupported; only 2013 is supported',
      );
    }
    if (properties & 0x1c00 != 0) {
      throw const FormatException('Encrypted JT808 messages are unsupported');
    }
    if (properties & 0x2000 != 0) {
      throw const FormatException('Segmented JT808 messages are unsupported');
    }
    if (properties & 0x8000 != 0) {
      throw const FormatException('Reserved message property bit is set');
    }
    final length = properties & 0x03ff;
    if (data.length != 12 + length + 1) {
      throw const FormatException('JT808 body length does not match header');
    }
    final phone = StringBuffer();
    for (final byte in data.sublist(4, 10)) {
      if ((byte >> 4) > 9 || (byte & 15) > 9) {
        throw const FormatException('Invalid BCD terminal phone');
      }
      phone.write('${byte >> 4}${byte & 15}');
    }
    return Jt808Frame(
      messageId: (data[0] << 8) | data[1],
      phone: phone.toString(),
      sequence: (data[10] << 8) | data[11],
      body: data.sublist(12, data.length - 1),
    );
  }

  static Uint8List parseHex(String text) {
    final hex = text.replaceAll(RegExp(r'\s'), '');
    if (hex.isEmpty ||
        hex.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const FormatException('Expected complete hexadecimal byte pairs');
    }
    if (hex.length > maxFrameLength * 2) {
      throw const FormatException('Hex frame exceeds maximum frame length');
    }
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static String toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static void _word(int value, String label) {
    if (value < 0 || value > 0xffff) {
      throw FormatException('$label must fit in an unsigned 16-bit value');
    }
  }

  static void _bytes(List<int> data) {
    if (data.any((b) => b < 0 || b > 0xff)) {
      throw const FormatException('Byte value is outside 0..255');
    }
  }
}

/// Incremental TCP delimiter framing with a hard per-frame memory bound.
/// Invalid/oversized input is discarded until the next delimiter.
class Jt808PacketFramer {
  Jt808PacketFramer({
    this.maxBufferedBytes = Jt808Codec.maxFrameLength,
    this.onError,
  }) {
    if (maxBufferedBytes < 15 || maxBufferedBytes > Jt808Codec.maxFrameLength) {
      throw ArgumentError.value(maxBufferedBytes, 'maxBufferedBytes');
    }
  }

  final int maxBufferedBytes;
  final void Function(FormatException error, List<int> discarded)? onError;
  final List<int> _buffer = [];
  bool _started = false;

  int get bufferedBytes => _buffer.length;

  List<Uint8List> add(List<int> chunk) {
    final packets = <Uint8List>[];
    for (final byte in chunk) {
      if (byte < 0 || byte > 0xff) {
        onError?.call(
          const FormatException('TCP input contains a non-byte'),
          List.unmodifiable(_buffer),
        );
        reset();
        continue;
      }
      if (byte == 0x7e) {
        if (_started && _buffer.length > 1) {
          packets.add(Uint8List.fromList([..._buffer, 0x7e]));
        }
        _buffer
          ..clear()
          ..add(0x7e);
        _started = true;
      } else if (_started) {
        _buffer.add(byte);
        // Reserve one byte for the closing delimiter.
        if (_buffer.length >= maxBufferedBytes) {
          onError?.call(
            const FormatException('TCP frame exceeds buffer limit'),
            List.unmodifiable(_buffer),
          );
          reset();
        }
      }
    }
    return packets;
  }

  void reset() {
    _buffer.clear();
    _started = false;
  }
}
