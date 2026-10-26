import 'dart:typed_data';

import 'package:bluedot_clicker/services/recognition.dart';
import 'package:bluedot_clicker/services/template_match_dart.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在 BGRA 图像上画一个实心矩形
void _fillRect(Uint8List img, int imgW, int x, int y, int w, int h, int b, int g, int r) {
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      final p = (yy * imgW + xx) * 4;
      img[p] = b;
      img[p + 1] = g;
      img[p + 2] = r;
      img[p + 3] = 255;
    }
  }
}

RawImage _solidImage(int w, int h) => RawImage(w, h, Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128));

void main() {
  final matcher = const DartTemplateMatcher();

  test('模板匹配：纯色背景上的深色方块命中正确坐标', () {
    // 200x150 背景 (白色)，(80,60) 处 40x30 黑块
    final img = RawImage(200, 150, Uint8List(200 * 150 * 4));
    _fillRect(img.bgra, 200, 0, 0, 200, 150, 255, 255, 255);
    _fillRect(img.bgra, 200, 80, 60, 40, 30, 20, 20, 20);

    final tpl = RawImage(40, 30, Uint8List(40 * 30 * 4));
    _fillRect(tpl.bgra, 40, 0, 0, 40, 30, 20, 20, 20);

    final r = matcher.match(img, tpl, threshold: 0.8);
    expect(r.found, isTrue);
    expect(r.x, 80 + 20, reason: '中心 X'); // 左上(80,60) + 中心偏移(20,15)
    expect(r.y, 60 + 15, reason: '中心 Y');
    expect(r.score, greaterThan(0.95));
  });

  test('模板匹配：不存在目标时 score 低于阈值', () {
    final img = RawImage(200, 150, Uint8List(200 * 150 * 4));
    _fillRect(img.bgra, 200, 0, 0, 200, 150, 255, 255, 255);
    _fillRect(img.bgra, 200, 10, 10, 20, 20, 0, 0, 0);

    // 白色模板（图中无对应大块白区模板匹配分数应低? 白区存在——改用棋盘纹理模板）
    final tpl = RawImage(30, 30, Uint8List(30 * 30 * 4));
    for (var y = 0; y < 30; y++) {
      for (var x = 0; x < 30; x++) {
        final v = ((x ~/ 5) + (y ~/ 5)) % 2 == 0 ? 0 : 255;
        final p = (y * 30 + x) * 4;
        tpl.bgra[p] = v;
        tpl.bgra[p + 1] = v;
        tpl.bgra[p + 2] = v;
        tpl.bgra[p + 3] = 255;
      }
    }
    final r = matcher.match(img, tpl, threshold: 0.9);
    expect(r.found, isFalse, reason: '棋盘纹理在纯背景中不存在，score=${r.score}');
  });

  test('模板大于图像时不匹配', () {
    final r = matcher.match(_solidImage(10, 10), _solidImage(20, 20));
    expect(r.found, isFalse);
  });

  test('灰度化正确', () {
    final img = RawImage(1, 1, Uint8List.fromList([0, 0, 255, 255])); // 纯红 BGRA
    expect(img.toGray()[0], closeTo(76, 1)); // 0.299*255 ≈ 76
  });
}
