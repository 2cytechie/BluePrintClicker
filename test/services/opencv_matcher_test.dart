import 'dart:typed_data';

import 'package:bluedot_clicker/services/opencv_matcher.dart';
import 'package:bluedot_clicker/services/recognition.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// OpenCV（opencv_dart/dartcv4）原生库加载与模板匹配验证。
/// 若原生库不可用会直接抛异常（不经 fallback），用于证明 OpenCV 链路真实可用。
void main() {
  final matcher = const OpenCvMatcher();

  test('OpenCV 模板匹配：命中且坐标精确', () {
    final img = RawImage(200, 150, Uint8List(200 * 150 * 4));
    _fillRect(img.bgra, 200, 0, 0, 200, 150, 255, 255, 255);
    _fillRect(img.bgra, 200, 80, 60, 40, 30, 20, 20, 20);

    final tpl = RawImage(40, 30, Uint8List(40 * 30 * 4));
    _fillRect(tpl.bgra, 40, 0, 0, 40, 30, 20, 20, 20);

    final r = matcher.match(img, tpl, threshold: 0.8);
    expect(r.found, isTrue);
    expect(r.x, 80 + 20);
    expect(r.y, 60 + 15);
    expect(r.score, greaterThan(0.95));
  });

  test('OpenCV 模板匹配：无目标时低于阈值', () {
    final img = RawImage(200, 150, Uint8List(200 * 150 * 4));
    _fillRect(img.bgra, 200, 0, 0, 200, 150, 255, 255, 255);
    _fillRect(img.bgra, 200, 10, 10, 20, 20, 0, 0, 0);

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
    expect(r.found, isFalse);
  });

  test('OpenCV 模板大于图像返回未命中', () {
    final small = RawImage(10, 10, Uint8List(10 * 10 * 4));
    final big = RawImage(20, 20, Uint8List(20 * 20 * 4));
    final r = matcher.match(small, big); // image=10x10, template=20x20
    expect(r.found, isFalse);
  });
}
