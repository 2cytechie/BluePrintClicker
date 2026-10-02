import 'dart:async';

import 'platform_automation.dart';
import 'win32/gdi32.dart' as gdi;
import 'win32/user32.dart' as u32;

/// PlatformAutomation 的 Windows 实现：SendInput 鼠标模拟 + GDI 截屏。
/// 所有坐标为屏幕物理像素。
class WindowsAutomation implements PlatformAutomation {
  const WindowsAutomation();

  @override
  bool get isSupported => true;
  @override
  String? get unsupportedReason => null;

  @override
  (int, int) get screenSize => (u32.screenW(), u32.screenH());

  @override
  Future<void> moveMouse(int x, int y) async => u32.moveAbsolute(x, y);

  @override
  Future<void> click(int x, int y, {MouseButton button = MouseButton.left, int count = 1}) async {
    final right = button == MouseButton.right;
    final n = count.clamp(1, 20);
    for (var i = 0; i < n; i++) {
      u32.clickAt(x, y, right: right);
      if (i < n - 1) await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  @override
  Future<void> press(int x, int y, {MouseButton button = MouseButton.left}) async {
    u32.moveAbsolute(x, y);
    u32.mouseDown(right: button == MouseButton.right);
  }

  @override
  Future<void> release({MouseButton button = MouseButton.left}) async =>
      u32.mouseUp(right: button == MouseButton.right);

  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, {int durationMs = 300}) async {
    final steps = (durationMs / 12).clamp(4, 120).toInt();
    final dt = durationMs / steps;
    u32.moveAbsolute(x1, y1);
    u32.mouseDown();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      // 轻微缓动
      final e = t * t * (3 - 2 * t);
      u32.moveAbsolute((x1 + (x2 - x1) * e).round(), (y1 + (y2 - y1) * e).round());
      await Future<void>.delayed(Duration(milliseconds: dt.round()));
    }
    u32.mouseUp();
  }

  @override
  Future<void> longPress(int x, int y, {int durationMs = 800, MouseButton button = MouseButton.left}) async {
    u32.moveAbsolute(x, y);
    u32.mouseDown(right: button == MouseButton.right);
    await Future<void>.delayed(Duration(milliseconds: durationMs.clamp(1, 60000)));
    u32.mouseUp(right: button == MouseButton.right);
  }

  @override
  Future<ScreenCapture> capture({RectPx? region}) async => gdi.captureScreen(region: region);

  @override
  (int, int) cursorPos() => u32.cursorPos();

  @override
  (bool, bool) buttonsDown() => u32.mouseButtonsDown();
}
