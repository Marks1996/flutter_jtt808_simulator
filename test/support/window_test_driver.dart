import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic native channel stub for window behavior tests and UI previews.
class WindowTestDriver {
  final List<MethodCall> calls = [];
  bool maximized = false;
  bool fullScreen = false;
  bool focused = true;
  String? failMethod;

  static const windowChannel = MethodChannel('window_manager');
  static const screenChannel = MethodChannel(
    'dev.leanflutter.plugins/screen_retriever',
  );

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call);
      if (call.method == failMethod) {
        throw PlatformException(code: 'test-failure');
      }
      switch (call.method) {
        case 'isMaximized':
          return maximized;
        case 'isFullScreen':
          return fullScreen;
        case 'isFocused':
          return focused;
        case 'isMinimized':
          return false;
        case 'maximize':
          maximized = true;
        case 'unmaximize':
          maximized = false;
        case 'setFullScreen':
          fullScreen = (call.arguments as Map)['isFullScreen'] as bool;
        case 'getBounds':
          return {'x': 0.0, 'y': 0.0, 'width': 1360.0, 'height': 900.0};
      }
      return true;
    });
    messenger.setMockMethodCallHandler(screenChannel, (call) async {
      const display = {
        'id': 'test-screen',
        'size': {'width': 1920.0, 'height': 1080.0},
        'visiblePosition': {'dx': 0.0, 'dy': 0.0},
        'visibleSize': {'width': 1920.0, 'height': 1040.0},
        'scaleFactor': 1.0,
      };
      return switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => {
          'displays': [display],
        },
        'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
        _ => throw StateError('Unexpected screen method: ${call.method}'),
      };
    });
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(screenChannel, null);
  }
}
