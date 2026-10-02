/// Windows FFI 集成冒烟：验证 user32/gdi32 绑定与真实系统交互。
/// 仅在 Windows 上运行。
library;

import 'package:blueprint_clicker/platform/platform_automation.dart';
import 'package:blueprint_clicker/platform/win32/gdi32.dart' as gdi;
import 'package:blueprint_clicker/platform/win32/user32.dart' as u32;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

    test('GetCursorPos 返回屏幕范围内坐标', () {
      final (x, y) = u32.cursorPos();
      expect(x, inInclusiveRange(0, u32.screenW()));
      expect(y, inInclusiveRange(0, u32.screenH()));
    });

    test('屏幕尺寸为正', () {
      expect(u32.screenW(), greaterThan(0));
      expect(u32.screenH(), greaterThan(0));
    });

    test('GDI 全屏截屏返回正确尺寸的 BGRA 数据', () {
      final cap = gdi.captureScreen();
      expect(cap.width, u32.screenW());
      expect(cap.height, u32.screenH());
      expect(cap.bgra.length, cap.width * cap.height * 4);
      // 真实屏幕不应是纯黑帧（统计非零字节）
      final nonZero = cap.bgra.where((b) => b != 0).length;
      expect(nonZero, greaterThan(0), reason: '截屏不应为全黑');
    });

    test('GDI 区域截屏（100x80 区域）', () {
      final cap = gdi.captureScreen(region: const RectPx(0, 0, 100, 80));
      expect(cap.width, 100);
      expect(cap.height, 80);
      expect(cap.bgra.length, 100 * 80 * 4);
    });

    test('鼠标模拟：移动+点击当前位置不抛异常', () async {
      final (x, y) = u32.cursorPos();
      u32.moveAbsolute(x, y);
      u32.clickAt(x, y); // 在原位点击，无副作用
      final (x2, y2) = u32.cursorPos();
      expect(x2, x);
      expect(y2, y);
    });
}
