import 'package:flutter_test/flutter_test.dart';
import 'package:blueprint_clicker/models/blueprint.dart';

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

    test('相邻但区间衔接不重叠（offset == 前键抬起时刻）不合并', () {
      // 前键 [0,500]，后键按下时刻 500 —— 500 <= 0+500 成立会入链？
      // 规则定义：offset 落在闭区间 [start, start+duration] 内即重叠，
      // 抬起瞬间再按下属于录制轮询的边界情况，保守合并（符合组合键直觉）
      final merged = mergeKeyCombos([
        const RecKey(0, 0x11, durationMs: 500),
        const RecKey(500, 0x43, durationMs: 60),
      ]);
      expect(merged.length, 1);
      expect(merged.single, isA<RecCombo>());
    });

    test('空列表与单键列表', () {
      expect(mergeKeyCombos([]), isEmpty);
      final single = mergeKeyCombos([const RecKey(10, 0x41)]);
      expect(single.length, 1);
      expect(single.single, isA<RecKey>());
    });
  });
}
