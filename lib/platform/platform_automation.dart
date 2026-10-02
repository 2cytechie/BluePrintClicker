import 'dart:typed_data';

/// 截屏结果（BGRA 原始像素）
class ScreenCapture {
  final int width;
  final int height;
  /// BGRA 顺序原始字节（Windows GDI 原生顺序）
  final Uint8List bgra;
  const ScreenCapture(this.width, this.height, this.bgra);

  /// 转为 RGBA
  Uint8List toRgba() {
    final rgba = Uint8List(bgra.length);
    for (var i = 0; i < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2];
      rgba[i + 1] = bgra[i + 1];
      rgba[i + 2] = bgra[i];
      rgba[i + 3] = bgra[i + 3];
    }
    return rgba;
  }
}

class RectPx {
  final int x, y, w, h;
  const RectPx(this.x, this.y, this.w, this.h);
}

/// 鼠标按键
enum MouseButton { left, right }

/// 平台自动化抽象接口。
/// UI 与执行引擎只依赖此接口；Windows 实现 Phase 1 提供，Android 为 Phase 2。
abstract interface class PlatformAutomation {
  bool get isSupported;
  String? get unsupportedReason;

  /// 屏幕物理分辨率
  (int, int) get screenSize;

  Future<void> moveMouse(int x, int y);
  Future<void> click(int x, int y, {MouseButton button = MouseButton.left, int count = 1});
  Future<void> press(int x, int y, {MouseButton button = MouseButton.left});
  Future<void> release({MouseButton button = MouseButton.left});
  Future<void> swipe(int x1, int y1, int x2, int y2, {int durationMs = 300});
  Future<void> longPress(int x, int y, {int durationMs = 800, MouseButton button = MouseButton.left});

  /// 截屏（全屏或区域）
  Future<ScreenCapture> capture({RectPx? region});

  /// 当前鼠标物理坐标（录制用）
  (int, int) cursorPos();

  /// 鼠标左/右键是否按下（录制用）
  (bool left, bool right) buttonsDown();
}

/// 未支持平台的降级实现：拒绝所有动作，给出提示，不崩溃。
class UnsupportedPlatformAutomation implements PlatformAutomation {
  const UnsupportedPlatformAutomation([this._reason = '当前平台暂不支持自动化']);
  final String _reason;
  @override
  bool get isSupported => false;
  @override
  String? get unsupportedReason => _reason;
  @override
  (int, int) get screenSize => (1280, 720);
  @override
  Future<void> moveMouse(int x, int y) => _deny();
  @override
  Future<void> click(int x, int y, {MouseButton button = MouseButton.left, int count = 1}) => _deny();
  @override
  Future<void> press(int x, int y, {MouseButton button = MouseButton.left}) => _deny();
  @override
  Future<void> release({MouseButton button = MouseButton.left}) => _deny();
  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, {int durationMs = 300}) => _deny();
  @override
  Future<void> longPress(int x, int y, {int durationMs = 800, MouseButton button = MouseButton.left}) => _deny();
  @override
  Future<ScreenCapture> capture({RectPx? region}) async {
    throw UnsupportedError(unsupportedReason!);
  }

  @override
  (int, int) cursorPos() => (0, 0);
  @override
  (bool, bool) buttonsDown() => (false, false);
  Never _deny() => throw UnsupportedError(unsupportedReason!);
}
