import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:winrt_ocr_flutter/winrt_ocr_flutter.dart';

import 'opencv_matcher.dart';
import 'recognition.dart';
import 'template_match_dart.dart';

/// Windows 识别服务：OCR 用 Windows.Media.Ocr（winrt_ocr_flutter），
/// 模板匹配优先 OpenCV（opencv_dart，TM_CCOEFF_NORMED），
/// OpenCV 原生库不可用时自动回退纯 Dart 金字塔 NCC。
class WindowsRecognitionService implements RecognitionService {
  WindowsRecognitionService();

  final DartTemplateMatcher _dartMatcher = const DartTemplateMatcher();
  final OpenCvMatcher _cvMatcher = const OpenCvMatcher();
  bool? _opencvAvailable;

  @override
  bool get isAvailable => Platform.isWindows;

  // ---- OCR ----

  @override
  Future<OcrResult> recognizeText(RawImage image, {int? regionX, int? regionY, int? regionW, int? regionH}) async {
    var img = image;
    var ox = regionX ?? 0;
    var oy = regionY ?? 0;
    if (regionW != null && regionH != null && (regionW < image.width || regionH < image.height)) {
      img = _crop(image, regionX ?? 0, regionY ?? 0, regionW, regionH);
      ox = 0;
      oy = 0;
    }
    final png = await _encodePng(img);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bpc_ocr_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(png);
    String text;
    try {
      text = await WinrtOcr.recognizeText(file.path);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
    return OcrResult(text.trim(), x: ox, y: oy);
  }

  // ---- 模板匹配 ----

  @override
  Future<MatchResult> matchTemplate(RawImage image, RawImage template, {double threshold = 0.8}) async {
    if (_opencvAvailable ?? true) {
      try {
        final r = _cvMatcher.match(image, template, threshold: threshold);
        _opencvAvailable = true;
        return r;
      } catch (_) {
        _opencvAvailable = false;
      }
    }
    return _dartMatcher.match(image, template, threshold: threshold);
  }

  // ---- 辅助 ----

  RawImage _crop(RawImage img, int x, int y, int w, int h) {
    final cw = w.clamp(1, img.width - x);
    final ch = h.clamp(1, img.height - y);
    final out = Uint8List(cw * ch * 4);
    for (var row = 0; row < ch; row++) {
      final srcStart = ((y + row) * img.width + x) * 4;
      out.setRange(row * cw * 4, (row + 1) * cw * 4, img.bgra, srcStart);
    }
    return RawImage(cw, ch, out);
  }

  Future<Uint8List> _encodePng(RawImage img) async {
    final image = await img.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}

/// 从模板图片文件加载 RawImage（BGRA）。
/// ui.instantiateImageCodec 解码 PNG/JPG/BMP，输出 RGBA，再转为 BGRA 语义。
Future<RawImage> loadTemplateFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // RGBA → BGRA
    for (var i = 0; i < rgba.length; i += 4) {
      var t = rgba[i];
      rgba[i] = rgba[i + 2];
      rgba[i + 2] = t;
    }
    return RawImage(image.width, image.height, rgba);
  } finally {
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
