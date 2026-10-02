import 'dart:math' as math;
import 'dart:typed_data';

import 'recognition.dart';

/// 纯 Dart 模板匹配：灰度 NCC（归一化互相关），两级金字塔（降采样粗搜 + 原图精搜）。
/// 面向游戏 UI 元素识别（固定图标/按钮，速度优先）。
/// 纯色模板（零方差）自动退化为 NSSD（归一化差平方和）匹配。
class DartTemplateMatcher {
  const DartTemplateMatcher();

  /// image/template 均为 RawImage（使用其灰度字节）。
  MatchResult match(RawImage image, RawImage template, {double threshold = 0.8}) {
    if (template.width > image.width || template.height > image.height) {
      return const MatchResult(false, 0, 0, 0);
    }
    final big = image.toGray();
    final tpl = template.toGray();

    // 模板统计量：方差为 0（纯色）走 NSSD，否则走 NCC
    final tLen = template.width * template.height;
    double tSum = 0, tSq = 0;
    for (var i = 0; i < tLen; i++) {
      final v = tpl[i].toDouble();
      tSum += v;
      tSq += v * v;
    }
    final tMean = tSum / tLen;
    final tVar = tSq - tMean * tSum; // Σv² - mean·Σv（未除 tLen 的方差，比例不变）
    final bool solidTemplate = tVar <= 1e-9 * tLen;

    // 选择降采样系数：保证粗搜计算量可控
    final factor = _pickFactor(image.width, image.height, template.width, template.height);
    int bestX = 0, bestY = 0;
    double bestScore = -2;

    if (factor > 1) {
      final small = _downsample(big, image.width, image.height, factor);
      final smallTpl = _downsample(tpl, template.width, template.height, factor);
      final sw = image.width ~/ factor;
      final sh = image.height ~/ factor;
      final tw = (template.width / factor).round().clamp(2, sw);
      final th = (template.height / factor).round().clamp(2, sh);
      final (sx, sy, ss) = solidTemplate
          ? _nssdSearch(small, sw, sh, smallTpl, tw, th)
          : _nccSearch(small, sw, sh, smallTpl, tw, th);
      bestX = (sx * factor).clamp(0, image.width - template.width);
      bestY = (sy * factor).clamp(0, image.height - template.height);
      bestScore = ss;
    }

    // 原图精搜：在粗搜邻域内
    final radius = factor * 2;
    final x0 = (bestX - radius).clamp(0, image.width - template.width);
    final y0 = (bestY - radius).clamp(0, image.height - template.height);
    final x1 = (bestX + radius).clamp(0, image.width - template.width);
    final y1 = (bestY + radius).clamp(0, image.height - template.height);
    final (fx, fy, fs) = solidTemplate
        ? _nssdSearchRange(big, image.width, template.width, template.height, x0, y0, x1, y1, tMean)
        : _nccSearchRange(big, image.width, image.height, tpl, template.width, template.height, x0, y0, x1, y1);
    if (fs > bestScore) {
      bestX = fx;
      bestY = fy;
      bestScore = fs;
    }
    bestScore = bestScore.clamp(-1.0, 1.0);
    final found = bestScore >= threshold;
    // 中心坐标
    final cx = bestX + template.width ~/ 2;
    final cy = bestY + template.height ~/ 2;
    return MatchResult(found, cx, cy, bestScore);
  }

  int _pickFactor(int iw, int ih, int tw, int th) {
    var f = 1;
    while (iw ~/ (f * 2) > 2 * tw && ih ~/ (f * 2) > 2 * th && f < 8) {
      f *= 2;
    }
    return f;
  }

  Uint8List _downsample(Uint8List src, int w, int h, int f) {
    final nw = w ~/ f;
    final nh = h ~/ f;
    final out = Uint8List(nw * nh);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        out[y * nw + x] = src[y * f * w + x * f];
      }
    }
    return out;
  }

  (int, int, double) _nccSearch(Uint8List img, int iw, int ih, Uint8List tpl, int tw, int th) =>
      _nccSearchRange(img, iw, ih, tpl, tw, th, 0, 0, iw - tw, ih - th);

  (int, int, double) _nccSearchRange(
      Uint8List img, int iw, int ih, Uint8List tpl, int tw, int th, int x0, int y0, int x1, int y1) {
    // 模板统计量
    double tSum = 0, tSq = 0;
    final tLen = tw * th;
    for (var i = 0; i < tLen; i++) {
      final v = tpl[i].toDouble();
      tSum += v;
      tSq += v * v;
    }
    final tMean = tSum / tLen;
    final tVar = tSq - tMean * tSum;
    final tDenom = tVar <= 1e-9 * tLen ? 1.0 : tVar; // 纯色模板退化为常数

    var best = -2.0;
    var bx = x0, by = y0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        double s = 0, sq = 0, cross = 0;
        var idx = y * iw + x;
        for (var ty = 0; ty < th; ty++) {
          var ii = idx;
          var ti = ty * tw;
          for (var tx = 0; tx < tw; tx++) {
            final iv = img[ii].toDouble();
            final tv = tpl[ti];
            s += iv;
            sq += iv * iv;
            cross += iv * tv;
            ii++;
            ti++;
          }
          idx += iw;
        }
        final iMean = s / tLen;
        final iVar = sq - iMean * s;
        final iDenom = iVar <= 1e-9 * tLen ? 1.0 : iVar;
        final denom = math.sqrt(tDenom * iDenom);
        final ncc = denom <= 1e-9 ? 0.0 : (cross - tMean * s) / denom;
        if (ncc > best) {
          best = ncc;
          bx = x;
          by = y;
        }
      }
    }
    return (bx, by, best);
  }

  /// 纯色模板专用：NSSD = 1 - ||窗口 - 常量|| / (255 * sqrt(tLen))
  (int, int, double) _nssdSearch(
          Uint8List img, int iw, int ih, Uint8List tpl, int tw, int th) =>
      _nssdSearchRange(img, iw, tw, th, 0, 0, iw - tw, ih - th, tpl[0].toDouble());

  (int, int, double) _nssdSearchRange(
      Uint8List img, int iw, int tw, int th, int x0, int y0, int x1, int y1, double tplValue) {
    final tLen = tw * th;
    final denomNorm = 255.0 * math.sqrt(tLen.toDouble());
    var best = -2.0;
    var bx = x0, by = y0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        double diff = 0;
        var idx = y * iw + x;
        for (var ty = 0; ty < th; ty++) {
          var ii = idx;
          for (var tx = 0; tx < tw; tx++) {
            final d = img[ii] - tplValue;
            diff += d * d;
            ii++;
          }
          idx += iw;
        }
        final score = 1.0 - math.sqrt(diff) / denomNorm;
        if (score > best) {
          best = score;
          bx = x;
          by = y;
        }
      }
    }
    return (bx, by, best);
  }
}
