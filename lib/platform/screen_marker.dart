import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'win32/gdi32.dart' as gdi;
import 'win32/user32.dart' as u32;

/// 屏幕标记点：位置（物理像素）+ 填充色（Flutter 0xAARRGGBB）
class MarkerPoint {
  final int x, y;
  final int color;
  const MarkerPoint(this.x, this.y, this.color);
}

/// 分层小窗口封装：透明置顶点击穿透（WS_EX_LAYERED|WS_EX_TRANSPARENT|TOPMOST|TOOLWINDOW|NOACTIVATE），
/// 窗口内容 = 32bpp 预乘 BGRA 位图（UpdateLayeredWindow + DWM 合成）。
/// 无背景保存/恢复 → 无闪烁无残留；窗口销毁即彻底消失。
class _LayeredWindow {
  static bool _classRegistered = false;
  static const _className = 'BPC_MARKER_WND';

  int _hwnd = 0;
  int _memDC = 0;
  int _bitmap = 0;
  Pointer<Uint8> _bits = nullptr;
  int _w = 0, _h = 0;

  bool get isValid => _hwnd != 0;
  int get width => _w;
  int get height => _h;

  void create(int x, int y, int w, int h) {
    destroy();
    if (!_classRegistered) {
      _classRegistered = u32.registerMarkerWindowClass(_className);
      if (!_classRegistered) return;
    }
    final exStyle = u32.wsExLayered |
        u32.wsExTransparent |
        u32.wsExToolwindow |
        u32.wsExTopmost |
        u32.wsExNoactivate;
    _hwnd = u32.createLayeredWindow(
      className: _className,
      exStyle: exStyle,
      x: x,
      y: y,
      w: w,
      h: h,
    );
    if (_hwnd == 0) return;
    _memDC = gdi.createCompatibleDC(0);
    final (bmp, bits) = gdi.createDIBSection(_memDC, w, h);
    _bitmap = bmp;
    _bits = bits;
    gdi.selectObject(_memDC, _bitmap);
    _w = w;
    _h = h;
  }

  /// 拷入预乘 BGRA 像素（长度须为 w*h*4）并设为窗口内容，同时更新窗口位置
  void update(Uint8List bgra, int x, int y) {
    if (!isValid) return;
    final n = _w * _h * 4;
    if (bgra.length != n) return;
    _bits.asTypedList(n).setAll(0, bgra);

    final pptDst = calloc<Int32>(2);
    final psize = calloc<Int32>(2);
    final pptSrc = calloc<Int32>(2);
    final pblend = calloc<Uint8>(4); // BLENDFUNCTION{AC_SRC_OVER,0,255,AC_SRC_ALPHA}
    try {
      pptDst[0] = x;
      pptDst[1] = y;
      psize[0] = _w;
      psize[1] = _h;
      pptSrc[0] = 0;
      pptSrc[1] = 0;
      pblend[0] = u32.acSrcOver;
      pblend[1] = 0;
      pblend[2] = 255;
      pblend[3] = u32.acSrcAlpha;
      u32.updateLayeredWindowContent(
        _hwnd,
        0, // hdcDst：ULW 不需要屏幕 DC
        pptDst,
        psize,
        _memDC,
        pptSrc,
        0, // crKey
        pblend,
        u32.ulwAlpha,
      );
      u32.showWindowNa(_hwnd);
    } finally {
      calloc.free(pptDst);
      calloc.free(psize);
      calloc.free(pptSrc);
      calloc.free(pblend);
    }
  }

  void destroy() {
    if (_bitmap != 0) {
      gdi.deleteObject(_bitmap);
      _bitmap = 0;
    }
    if (_memDC != 0) {
      gdi.deleteDC(_memDC);
      _memDC = 0;
    }
    if (_hwnd != 0) {
      u32.destroyLayeredWindow(_hwnd);
      _hwnd = 0;
    }
    _bits = nullptr;
    _w = 0;
    _h = 0;
  }
}

/// 屏幕置顶标记服务：分层透明小窗口绘制"圆形+白色加号"定位图标
/// （"+"中心精确对准坐标点，只显示图标不显示坐标文字），支持鼠标直接拖拽图标修改坐标。
/// 图标由 Flutter 离屏渲染（PictureRecorder → toImage，随 DPI 缩放、抗锯齿、逐像素透明）。
/// 拖拽由 WH_MOUSE_LL 钩子实现（窗口本身点击穿透，不干扰其他应用操作）。
class ScreenMarkerService {
  static const _radiusLogic = 13.0; // 图标半径（逻辑像素，随 DPI 放大渲染）
  static const _hitRadiusLogic = 20.0; // 拖拽命中半径（逻辑像素）
  static const _colorWhite = 0xFFFFFFFF;
  static const _colorLine = 0xFF8A94B8;

  List<MarkerPoint> _points = [];
  void Function(int index, int x, int y)? _onDragEnd;
  Timer? _timer;
  int _renderSeq = 0; // 渲染版本号：hide/重渲染后丢弃过期异步结果
  final _LayeredWindow _window = _LayeredWindow();

  NativeCallable<u32.HookProcC>? _proc;
  int _hookHandle = 0;
  final Set<int> _swallowUp = {};

  // 拖拽状态
  int _dragIndex = -1;
  int _dragOrigX = 0, _dragOrigY = 0;
  (int, int)? _lastCursor;
  (int, int, int)? _pendingDragEnd;

  bool get isActive => _points.isNotEmpty;

  double get _dpr =>
      ui.PlatformDispatcher.instance.views.first.devicePixelRatio;

  /// 显示一组可拖拽图标；恰好 2 个点时自动画连线（滑动起终点）
  void show(
    List<MarkerPoint> points, {
    required void Function(int index, int x, int y) onDragEnd,
  }) {
    hide();
    _points = List.of(points);
    _onDragEnd = onDragEnd;
    _installHook();
    _timer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _onTick(),
    );
    _renderGuarded();
  }

  /// 渲染 + 上屏；异常不再静默（debugPrint 到控制台便于排查）
  void _renderGuarded() {
    _render().catchError((e, st) {
      debugPrint('ScreenMarker render failed: $e\n$st');
    });
  }

  /// 编辑面板中坐标参数变化时同步图标位置（拖拽中的点以拖拽为准）
  void updatePoints(List<MarkerPoint> points) {
    if (!isActive) return;
    _points = List.of(points);
    final cur = _lastCursor;
    if (_dragIndex >= 0 && cur != null) {
      _points[_dragIndex] = _copy(_points[_dragIndex], cur.$1, cur.$2);
    }
    _renderGuarded();
  }

  /// 隐藏图标：销毁分层窗口（窗口即内容，销毁即彻底消失，无任何屏幕恢复动作）
  void hide() {
    _timer?.cancel();
    _timer = null;
    _renderSeq++;
    _window.destroy();
    _dragIndex = -1;
    _pendingDragEnd = null;
    _lastCursor = null;
    _swallowUp.clear();
    if (_hookHandle != 0) {
      u32.uninstallMouseHook(_hookHandle);
      _hookHandle = 0;
    }
    _proc?.close();
    _proc = null;
    _points = [];
    _onDragEnd = null;
  }

  MarkerPoint _copy(MarkerPoint p, int x, int y) =>
      MarkerPoint(x, y, p.color);

  // ---- 轮询驱动：拖拽位置更新 / Esc 取消 / 完成回调 ----

  void _onTick() {
    // Esc 取消拖拽：恢复拖拽起点的原坐标
    if (_dragIndex >= 0 && u32.isKeyDown(u32.vkEscape)) {
      final i = _dragIndex;
      _points[i] = _copy(_points[i], _dragOrigX, _dragOrigY);
      _dragIndex = -1;
      _renderGuarded();
    }
    // 完成拖拽：钩子 up 事件记录的结果在此回调（保证在 Timer 上下文执行）
    final pending = _pendingDragEnd;
    if (pending != null) {
      _pendingDragEnd = null;
      _dragIndex = -1;
      _onDragEnd?.call(pending.$1, pending.$2, pending.$3);
    } else if (_dragIndex >= 0) {
      final cur = _lastCursor;
      if (cur != null) {
        _points[_dragIndex] = _copy(_points[_dragIndex], cur.$1, cur.$2);
        _renderGuarded();
      }
    }
  }

  // ---- Flutter 离屏渲染 → 分层窗口 ----

  Future<void> _render() async {
    if (_points.isEmpty) return;
    final seq = ++_renderSeq;
    final dpr = _dpr;
    final radius = _radiusLogic * dpr;
    final margin = (radius + 8 * dpr).round(); // 阴影/描边余量（物理像素）

    // 物理像素包围盒（所有图标 ± 连线），clamp 主屏
    var left = 1 << 30, top = 1 << 30, right = -(1 << 30), bottom = -(1 << 30);
    for (final p in _points) {
      left = left < (p.x - margin) ? left : p.x - margin;
      top = top < (p.y - margin) ? top : p.y - margin;
      right = right > (p.x + margin) ? right : p.x + margin;
      bottom = bottom > (p.y + margin) ? bottom : p.y + margin;
    }
    final sw = u32.screenW();
    final sh = u32.screenH();
    final winX = left.clamp(0, sw - 4).toInt();
    final winY = top.clamp(0, sh - 4).toInt();
    final winW = (right - left).clamp(4, sw - winX).toInt();
    final winH = (bottom - top).clamp(4, sh - winY).toInt();

    // 窗口尺寸变化时重建窗口与 DIB（位置/内容随后由 update 设置）
    if (!_window.isValid ||
        _window.width != winW ||
        _window.height != winH) {
      _window.create(winX, winY, winW, winH);
      if (!_window.isValid) return;
    }

    // 绘制（画布 = 窗口区域，坐标 = 物理像素 - 窗口原点）
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ui.Offset local(MarkerPoint p) =>
        ui.Offset((p.x - winX).toDouble(), (p.y - winY).toDouble());

    // 连线（滑动起终点；两点间灰白线 + 终点方向箭头）
    if (_points.length == 2) {
      final a = local(_points[0]);
      final b = local(_points[1]);
      canvas.drawLine(a, b, ui.Paint()
        ..color = const ui.Color(0x66000000)
        ..strokeWidth = 5 * dpr
        ..strokeCap = ui.StrokeCap.round
        ..isAntiAlias = true);
      canvas.drawLine(a, b, ui.Paint()
        ..color = const ui.Color(_colorLine)
        ..strokeWidth = 2.5 * dpr
        ..strokeCap = ui.StrokeCap.round
        ..isAntiAlias = true);
      // 方向箭头：终点图标外侧指向滑动方向（距离足够时绘制）
      final delta = b - a;
      final dist = delta.distance;
      if (dist > 4 * radius) {
        final dir = delta / dist;
        final perp = ui.Offset(-dir.dy, dir.dx);
        final tip = b - dir * (radius + 6 * dpr); // 箭头顶点
        final back = tip - dir * (11 * dpr); // 箭头底部中心
        final w1 = back + perp * (7 * dpr);
        final w2 = back - perp * (7 * dpr);
        final arrow = ui.Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(w1.dx, w1.dy)
          ..lineTo(w2.dx, w2.dy)
          ..close();
        canvas.drawPath(arrow, ui.Paint()
          ..color = const ui.Color(0x66000000)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 5 * dpr
          ..isAntiAlias = true);
        canvas.drawPath(arrow, ui.Paint()
          ..color = const ui.Color(_colorLine)
          ..isAntiAlias = true);
      }
    }

    for (final p in _points) {
      final c = local(p);
      // 阴影（浮起感）
      final shadowPath = ui.Path()
        ..addOval(ui.Rect.fromCircle(
          center: c + ui.Offset(0, 2 * dpr),
          radius: radius,
        ));
      canvas.drawShadow(shadowPath, const ui.Color(0xFF000000), 4, false);
      // 主体圆（类型色填充）
      canvas.drawCircle(c, radius, ui.Paint()
        ..color = ui.Color(p.color)
        ..isAntiAlias = true);
      // 白描边
      canvas.drawCircle(c, radius, ui.Paint()
        ..color = const ui.Color(_colorWhite)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2 * dpr
        ..isAntiAlias = true);
      // 白色加号（"+"中心 = 坐标点）
      final half = radius * 0.55;
      final plus = ui.Paint()
        ..color = const ui.Color(_colorWhite)
        ..strokeWidth = 2.5 * dpr
        ..strokeCap = ui.StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawLine(c - ui.Offset(half, 0), c + ui.Offset(half, 0), plus);
      canvas.drawLine(c - ui.Offset(0, half), c + ui.Offset(0, half), plus);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(winW, winH);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();
    if (seq != _renderSeq) return; // 过期渲染（已 hide/重新渲染）
    if (data == null) return;

    // RGBA（直通）→ 预乘 BGRA（UpdateLayeredWindow 要求）
    final px = data.buffer.asUint8List();
    final bgra = Uint8List(px.length);
    for (var i = 0; i < px.length; i += 4) {
      final a = px[i + 3];
      if (a == 0) continue;
      bgra[i] = (px[i + 2] * a / 255).round(); // B
      bgra[i + 1] = (px[i + 1] * a / 255).round(); // G
      bgra[i + 2] = (px[i] * a / 255).round(); // R
      bgra[i + 3] = a;
    }
    _window.update(bgra, winX, winY);
  }

  // ---- 鼠标钩子：命中图标则开始拖拽（其余事件放行） ----

  void _installHook() {
    final proc = _proc = NativeCallable<u32.HookProcC>.isolateLocal(
      (int nCode, int wParam, int lParam) {
        if (nCode >= 0 && isActive) {
          switch (wParam) {
            case u32.wmLbuttondown:
              final info = Pointer<u32.MSLLHOOKSTRUCT>.fromAddress(lParam).ref;
              final hit = _hitTest(info.pt.x, info.pt.y);
              if (hit >= 0) {
                _dragIndex = hit;
                _dragOrigX = _points[hit].x;
                _dragOrigY = _points[hit].y;
                _swallowUp.add(u32.wmLbuttonup); // 吞 down 必须吞 up
                return 1; // 吞掉，目标窗口收不到
              }
            case u32.wmLbuttonup:
              if (_swallowUp.remove(u32.wmLbuttonup)) {
                final info =
                    Pointer<u32.MSLLHOOKSTRUCT>.fromAddress(lParam).ref;
                if (_dragIndex >= 0) {
                  _pendingDragEnd = (_dragIndex, info.pt.x, info.pt.y);
                }
                return 1;
              }
            case u32.wmMousemove:
              final info =
                  Pointer<u32.MSLLHOOKSTRUCT>.fromAddress(lParam).ref;
              _lastCursor = (info.pt.x, info.pt.y);
          }
        }
        return u32.callNextHook(nCode, wParam, lParam);
      },
      exceptionalReturn: 0, // 异常时放行事件
    );
    final handle = u32.installMouseHook(proc.nativeFunction);
    if (handle == 0) {
      proc.close();
      _proc = null;
      return;
    }
    _hookHandle = handle;
  }

  int _hitTest(int x, int y) {
    final r = (_hitRadiusLogic * _dpr).round();
    for (var i = 0; i < _points.length; i++) {
      final dx = x - _points[i].x;
      final dy = y - _points[i].y;
      if (dx * dx + dy * dy <= r * r) return i;
    }
    return -1;
  }
}
