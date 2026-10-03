import 'dart:ffi';

import 'user32.dart' as u32;

/// WH_MOUSE_LL 低级鼠标钩子封装：捕获全局滚轮事件。
///
/// 钩子安装在当前线程（Flutter 平台线程，自带消息循环），
/// 回调经 NativeCallable.isolateLocal 进入 Dart；回调保持轻量，
/// 避免低级钩子处理超时被系统摘除。滚动delta 为 mouseData 高 16 位有符号值。
class MouseWheelHook {
  NativeCallable<u32.HookProcC>? _proc;
  int _handle = 0;
  bool _installed = false;

  bool get isInstalled => _installed;

  /// 安装钩子。[onWheel] 参数：(x, y, dx, dy)，dy/dx 正负表示滚动方向，120 为一格。
  bool start(void Function(int x, int y, int dx, int dy) onWheel) {
    if (_installed) return true;
    final proc = NativeCallable<u32.HookProcC>.isolateLocal((int nCode, int wParam, int lParam) {
      if (nCode >= 0 &&
          (wParam == u32.wmMousewheel || wParam == u32.wmMouseHwheel)) {
        final info = Pointer<u32.MSLLHOOKSTRUCT>.fromAddress(lParam).ref;
        final raw = (info.mouseData >> 16) & 0xFFFF;
        final delta = raw < 0x8000 ? raw : raw - 0x10000; // 有符号 short
        if (wParam == u32.wmMousewheel) {
          onWheel(info.pt.x, info.pt.y, 0, delta);
        } else {
          onWheel(info.pt.x, info.pt.y, delta, 0);
        }
      }
      return u32.callNextHook(nCode, wParam, lParam);
    }, exceptionalReturn: 0);
    final handle = u32.installMouseHook(proc.nativeFunction);
    if (handle == 0) {
      proc.close();
      return false;
    }
    _proc = proc;
    _handle = handle;
    _installed = true;
    return true;
  }

  /// 卸载钩子
  void stop() {
    if (!_installed) return;
    u32.uninstallMouseHook(_handle);
    _proc?.close();
    _proc = null;
    _handle = 0;
    _installed = false;
  }
}
