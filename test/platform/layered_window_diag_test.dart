import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blueprint_clicker/platform/win32/gdi32.dart' as gdi;
import 'package:blueprint_clicker/platform/win32/user32.dart' as u32;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('分层窗口链路诊断：注册类 → 创建 → DIB → UpdateLayeredWindow', () {
    final className = 'BPC_DIAG_WND_${DateTime.now().millisecondsSinceEpoch}';
    final registered = u32.registerMarkerWindowClass(className);
    // 若已注册过同名类也算成功（ERROR_CLASS_ALREADY_EXISTS → atom==0）
    expect(registered, isTrue, reason: 'RegisterClassExW 失败，结构布局可能有误');

    final exStyle = u32.wsExLayered |
        u32.wsExTransparent |
        u32.wsExToolwindow |
        u32.wsExTopmost |
        u32.wsExNoactivate;
    final hwnd = u32.createLayeredWindow(
      className: className,
      exStyle: exStyle,
      x: 50,
      y: 50,
      w: 64,
      h: 64,
    );
    expect(hwnd, isNonZero, reason: 'CreateWindowExW 失败');

    final memDC = gdi.createCompatibleDC(0);
    final (bmp, bits) = gdi.createDIBSection(memDC, 64, 64);
    expect(bmp, isNonZero, reason: 'CreateDIBSection 失败');
    final old = gdi.selectObject(memDC, bmp);
    expect(old, isNonZero, reason: 'SelectObject 失败');

    // 填充：中央 32x32 不透明红色方块（预乘 BGRA）
    final px = bits.asTypedList(64 * 64 * 4);
    for (var y = 16; y < 48; y++) {
      for (var x = 16; x < 48; x++) {
        final i = (y * 64 + x) * 4;
        px[i] = 0; // B
        px[i + 1] = 0; // G
        px[i + 2] = 255; // R
        px[i + 3] = 255; // A
      }
    }

    final pptDst = calloc<Int32>(2);
    final psize = calloc<Int32>(2);
    final pptSrc = calloc<Int32>(2);
    final pblend = calloc<Uint8>(4);
    try {
      pptDst[0] = 50;
      pptDst[1] = 50;
      psize[0] = 64;
      psize[1] = 64;
      pptSrc[0] = 0;
      pptSrc[1] = 0;
      pblend[0] = u32.acSrcOver;
      pblend[1] = 0;
      pblend[2] = 255;
      pblend[3] = u32.acSrcAlpha;
      final ok = u32.updateLayeredWindowContent(
        hwnd,
        0,
        pptDst,
        psize,
        memDC,
        pptSrc,
        0,
        pblend,
        u32.ulwAlpha,
      );
      expect(ok, isTrue, reason: 'UpdateLayeredWindow 失败（返回 0）');

      // 窗口可见性检查（IsWindowVisible）
      // 不 ShowWindow，跳过可见性，仅验证 ULW 成功即可
    } finally {
      calloc.free(pptDst);
      calloc.free(psize);
      calloc.free(pptSrc);
      calloc.free(pblend);
      gdi.deleteObject(bmp);
      gdi.deleteDC(memDC);
      expect(u32.destroyLayeredWindow(hwnd), isTrue);
      u32.unregisterMarkerWindowClass(className);
    }
  });
}
