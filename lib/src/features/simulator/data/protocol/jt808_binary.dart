import 'dart:typed_data';

/// Big-endian body reader that fails before reading outside a message.
class Jt808Reader {
  Jt808Reader(this.bytes);
  final List<int> bytes;
  int _offset = 0;
  int get remaining => bytes.length - _offset;

  int byte() {
    if (remaining < 1) {
      throw const FormatException('Truncated message body');
    }
    return bytes[_offset++];
  }

  int word() => (byte() << 8) | byte();
  int dword() => (word() << 16) | word();

  List<int> take(int count) {
    if (count < 0 || count > remaining) {
      throw const FormatException('Truncated message body');
    }
    final result = bytes.sublist(_offset, _offset + count);
    _offset += count;
    return result;
  }

  void requireEnd() {
    if (remaining != 0) {
      throw const FormatException('Unexpected trailing body bytes');
    }
  }
}

class Jt808Writer {
  final List<int> _bytes = [];

  void byte(int value) {
    if (value < 0 || value > 0xff) {
      throw const FormatException('BYTE overflow');
    }
    _bytes.add(value);
  }

  void word(int value) {
    if (value < 0 || value > 0xffff) {
      throw const FormatException('WORD overflow');
    }
    _bytes.addAll([value >> 8, value & 0xff]);
  }

  void dword(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const FormatException('DWORD overflow');
    }
    word(value >> 16);
    word(value & 0xffff);
  }

  void bytes(List<int> values) {
    for (final value in values) {
      byte(value);
    }
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
