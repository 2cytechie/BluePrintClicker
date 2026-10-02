import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'recognition.dart';

/// OpenCV 模板匹配：灰度图 TM_CCOEFF_NORMED + minMaxLoc。
/// 针对游戏固定 UI 元素（速度优先），相似度阈值过滤。
/// 纯色模板（零方差）自动改用 TM_SQDIFF_NORMED（归一化差平方和），
/// 因为 CCOEFF 对零方差模板的归一化分母退化为 0，结果无意义。
class OpenCvMatcher {
  const OpenCvMatcher();

  MatchResult match(RawImage image, RawImage template, {double threshold = 0.8}) {
    if (template.width > image.width || template.height > image.height) {
      return const MatchResult(false, 0, 0, 0);
    }
    final imgMat = _bgraToGrayMat(image);
    final tplMat = _bgraToGrayMat(template);
    try {
      // 模板方差（灰度字节）
      final gray = template.toGray();
      double sum = 0, sq = 0;
      for (final v in gray) {
        sum += v;
        sq += v * v;
      }
      final n = gray.length.toDouble();
      final mean = sum / n;
      final variance = sq / n - mean * mean;
      final solidTemplate = variance <= 1e-9;

      final method = solidTemplate ? cv.TM_SQDIFF_NORMED : cv.TM_CCOEFF_NORMED;
      final result = cv.matchTemplate(imgMat, tplMat, method);
      try {
        final (minVal, maxVal, minLoc, maxLoc) = cv.minMaxLoc(result);
        double score;
        int cx, cy;
        if (solidTemplate) {
          // SQDIFF_NORMED：0 = 完全一致，越大越差
          score = 1.0 - math.sqrt(minVal.clamp(0.0, 1.0));
          cx = minLoc.x + template.width ~/ 2;
          cy = minLoc.y + template.height ~/ 2;
        } else {
          score = maxVal.clamp(-1.0, 1.0);
          cx = maxLoc.x + template.width ~/ 2;
          cy = maxLoc.y + template.height ~/ 2;
        }
        return MatchResult(score >= threshold, cx, cy, score);
      } finally {
        result.dispose();
      }
    } finally {
      imgMat.dispose();
      tplMat.dispose();
    }
  }

  cv.Mat _bgraToGrayMat(RawImage img) {
    final buf = calloc<ffi.Uint8>(img.bgra.length);
    try {
      buf.asTypedList(img.bgra.length).setAll(0, img.bgra);
      final mat = cv.Mat.fromBuffer(img.height, img.width, const cv.MatType.CV_8UC(4), buf.cast<ffi.Void>());
      final gray = cv.cvtColor(mat, cv.COLOR_BGRA2GRAY);
      mat.dispose();
      return gray;
    } finally {
      calloc.free(buf);
    }
  }
}
