import 'package:flutter_test/flutter_test.dart';
import 'package:bluedot_clicker/models/blueprint.dart';

void main() {
  group('mergeKeyCombos 组合键合并', () {
    test('Ctrl(0,500) + C(100,60) → 合并为 RecCombo', () {
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 500),
        const RecKey(100, 0x43, durationMs: 60),
      ]);
      expect(merged.length, 1);
      final combo = merged.single as RecCombo;
      expect(combo.offsetMs, 0);
      expect(combo.vkCodes, [0x11, 0x43]); // Ctrl 按下顺序在前
      expect(combo.durationMs, 500); // max(0+500, 100+60) - 0
    });

    test('三个键的链条（Ctrl+Shift+A）全部合并', () {
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 600),
        const RecKey(50, 0x10, durationMs: 500),
        const RecKey(100, 0x41, durationMs: 60),
      ]);
      expect(merged.length, 1);
      final combo = merged.single as RecCombo;
      expect(combo.vkCodes, [0x11, 0x10, 0x41]);
      expect(combo.offsetMs, 0);
      expect(combo.durationMs, 600);
    });

    test('快速连打两个独立键（间隔大于按住时长）不合并', () {
      final merged = mergeKeyCombos([
        const RecKey(0, 0x41, durationMs: 40),
        const RecKey(200, 0x42, durationMs: 40),
      ]);
      expect(merged.length, 2);
      expect(merged[0], isA<RecKey>());
      expect(merged[1], isA<RecKey>());
    });

    test('中间插入鼠标动作打断合并链', () {
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 500),
        const RecClick(100, 10, 20),
        const RecKey(300, 0x43, durationMs: 60),
      ]);
      expect(merged.length, 3);
      expect(merged[0], isA<RecKey>());
      expect(merged[1], isA<RecClick>());
      expect(merged[2], isA<RecKey>());
    });

    test('已是 RecCombo 的序列再跑一遍 → 幂等不变', () {
      const actions = [
        RecCombo(0, [0x11, 0x43], extendeds: [false, false], durationMs: 500),
        RecKey(800, 0x41, durationMs: 40),
      ];
      final merged = mergeKeyCombos(actions);
      expect(merged.length, 2);
      expect(merged[0], isA<RecCombo>());
      expect((merged[0] as RecCombo).vkCodes, [0x11, 0x43]);
      expect(merged[1], isA<RecKey>());
    });

    test('相邻但区间衔接（offset == 前键抬起时刻）不合并', () {
      // 前键 [0,500] 与后键按下@500 相交（闭区间端点）→ 同簇，
      // 但嵌套判据不满足：up前=500 < up后=560 → 非嵌套 → 保持独立
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 500),
        const RecKey(500, 0x43, durationMs: 60),
      ]);
      expect(merged.length, 2);
      expect(merged[0], isA<RecKey>());
      expect(merged[1], isA<RecKey>());
    });

    test('长按 Alt 连点 3 次 Tab（交错簇）→ 保持 4 个独立 RecKey', () {
      // Alt+Tab 切换窗口：Alt 按住 2 秒，期间 3 次 Tab 依次点击。
      // 簇相连（各 Tab 与 Alt 区间重叠）但非嵌套（Tab1.up=160 < Tab2.up=660），
      // 不得合并为 RecCombo（表达不了交错），保持独立由事件流回放还原。
      final merged = mergeKeyCombos([
        const RecKey(0, 0x12, durationMs: 2000), // Alt
        const RecKey(100, 0x09, durationMs: 60), // Tab 1
        const RecKey(600, 0x09, durationMs: 60), // Tab 2
        const RecKey(1100, 0x09, durationMs: 60), // Tab 3
      ]);
      expect(merged.length, 4);
      for (final a in merged) {
        expect(a, isA<RecKey>());
      }
      final alt = merged[0] as RecKey;
      expect(alt.vkCode, 0x12);
      expect(alt.durationMs, 2000);
    });

    test('长按修饰键 + 单主键（嵌套）→ 合并为 RecCombo', () {
      // Ctrl 按住 2 秒期间按下 C：up_Ctrl=2000 >= up_C=160 → 嵌套 → 合并
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 2000), // Ctrl
        const RecKey(100, 0x43, durationMs: 60), // C
      ]);
      expect(merged.length, 1);
      final combo = merged.single as RecCombo;
      expect(combo.vkCodes, [0x11, 0x43]);
      expect(combo.durationMs, 2000);
    });

    test('空列表与单键列表', () {
      expect(mergeKeyCombos([]), isEmpty);
      final single = mergeKeyCombos([const RecKey(10, 0x41)]);
      expect(single.length, 1);
      expect(single.single, isA<RecKey>());
    });
  });
}
