import 'dart:async';

import '../models/blueprint.dart';
import 'platform_automation.dart';
import 'win32/mouse_hook.dart';
import 'win32/user32.dart' as u32;

/// 录制服务抽象：捕获用户操作序列。Windows 实现基于输入状态轮询 + 低级钩子。
abstract interface class RecordingService {
  bool get isRecording;
  Stream<RecordedAction> get events;
  void start();
  List<RecordedAction> stop();
}

/// 键盘轮询范围（跳过鼠标键与保留区）
const int _keyScanMin = 0x08;
const int _keyScanMax = 0xFE;

/// Windows 实现：10ms 轮询 GetCursorPos/GetAsyncKeyState 合成点击/滑动/长按/按键，
/// WH_MOUSE_LL 低级钩子捕获滚轮。不录制纯鼠标移动轨迹。
class WindowsRecordingService implements RecordingService {
  WindowsRecordingService(this._automation);
  final PlatformAutomation _automation;

  Timer? _timer;
  final List<RecordedAction> _actions = [];
  final StreamController<RecordedAction> _events = StreamController.broadcast();
  final MouseWheelHook _hook = MouseWheelHook();

  /// 当前按下的鼠标键（null = 无按下；同一时间只跟踪一个键）
  MouseButton? _pressed;
  int _downX = 0;
  int _downY = 0;
  DateTime _downTime = DateTime.now();
  DateTime _start = DateTime.now();

  // 拖动检测：按下期间累计位移
  int _maxDist = 0;
  int _lastX = 0;
  int _lastY = 0;
  DateTime _lastMove = DateTime.now();

  // 键盘轮询状态：vk → 按下时刻
  final Map<int, DateTime> _keysDown = {};

  @override
  bool get isRecording => _timer != null;

  @override
  Stream<RecordedAction> get events => _events.stream;

  @override
  void start() {
    if (isRecording) return;
    _actions.clear();
    _keysDown.clear();
    _pressed = null;
    _maxDist = 0;
    _start = DateTime.now();
    _hook.start(_onWheel);
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _poll());
  }

  @override
  List<RecordedAction> stop() {
    if (!isRecording) return List.of(_actions);
    _timer?.cancel();
    _timer = null;
    // 停止录制时的操作本身（点停止按钮、停止前仍按住的键/鼠标）不记录，直接丢弃
    _pressed = null;
    _maxDist = 0;
    _keysDown.clear();
    _hook.stop();
    // 时间重叠的按键合并为组合键（如 Ctrl+C）
    return mergeKeyCombos(_actions);
  }

  void _poll() {
    // 焦点在本应用窗口时（如点击「停止录制」按钮、切回窗口的 Alt+Tab），输入不记录
    final inSelfWindow = u32.getActiveWindow() != 0;
    final (x, y) = _automation.cursorPos();
    final (l, m, r) = _automation.buttonsDown();

    if (_pressed != null) {
      if (inSelfWindow) {
        // 按住期间焦点切回本应用：丢弃本次未完成的按下，不合成动作
        _pressed = null;
        _maxDist = 0;
      } else {
        final stillDown = switch (_pressed!) {
          MouseButton.left => l,
          MouseButton.middle => m,
          MouseButton.right => r,
        };
        if (!stillDown) {
          _onRelease();
        } else {
          final d = (x - _downX).abs() + (y - _downY).abs();
          if (d > _maxDist) {
            _maxDist = d;
            _lastX = x;
            _lastY = y;
            _lastMove = DateTime.now();
          }
        }
      }
    } else if (!inSelfWindow) {
      if (l) {
        _onDown(x, y, MouseButton.left);
      } else if (m) {
        _onDown(x, y, MouseButton.middle);
      } else if (r) {
        _onDown(x, y, MouseButton.right);
      }
    }

    _pollKeyboard(inSelfWindow);
  }

  /// 全键扫描：新按下记录时刻，抬起合成 RecKey（时序天然支持组合键）。
  /// 焦点在本应用时不记录（停止操作、窗口切换按键均不入列）。
  void _pollKeyboard(bool inSelfWindow) {
    final now = DateTime.now();
    for (var vk = _keyScanMin; vk <= _keyScanMax; vk++) {
      final down = u32.isKeyDown(vk);
      if (down && !_keysDown.containsKey(vk)) {
        if (!inSelfWindow) _keysDown[vk] = now;
      } else if (!down && _keysDown.containsKey(vk)) {
        final downAt = _keysDown.remove(vk)!;
        if (inSelfWindow) continue; // 抬起时焦点已切回本应用：丢弃
        _add(
          RecKey(
            _offset(downAt),
            vk,
            durationMs: now.difference(downAt).inMilliseconds.clamp(1, 60000),
            extended: u32.isExtendedKey(vk),
          ),
        );
      }
    }
  }

  /// 低级钩子回调：滚轮事件（保持轻量，只合成动作；焦点在本应用时不记录）
  void _onWheel(int x, int y, int dx, int dy) {
    if (!isRecording) return;
    if (u32.getActiveWindow() != 0) return;
    _add(RecScroll(_offset(DateTime.now()), x, y, dx: dx, dy: dy));
  }

  int _offset(DateTime t) => t.difference(_start).inMilliseconds;

  void _add(RecordedAction action) {
    _actions.add(action);
    _events.add(action);
  }

  void _onDown(int x, int y, MouseButton button) {
    _pressed = button;
    _downX = x;
    _downY = y;
    _downTime = DateTime.now();
    _maxDist = 0;
    _lastX = x;
    _lastY = y;
    _lastMove = _downTime;
  }

  void _onRelease() {
    final button = _pressed;
    if (button == null) return;
    final held = DateTime.now().difference(_downTime).inMilliseconds;
    final offset = _downTime.difference(_start).inMilliseconds;
    RecordedAction action;
    if (_maxDist > 24) {
      action = RecSwipe(
        offset,
        _downX,
        _downY,
        _lastX,
        _lastY,
        _lastMove.difference(_downTime).inMilliseconds.clamp(30, 10000),
      );
    } else if (held >= 600) {
      action = RecLongPress(offset, _downX, _downY, held);
    } else {
      action = RecClick(offset, _downX, _downY, button: button.name);
    }
    _add(action);
    _pressed = null;
    _maxDist = 0;
  }
}

/// 全局停止热键 F10 的虚拟键码（回放期间按下即刻中止）
const int vkStopReplay = 0x79;

/// 通用回放：按录制时的偏移间隔执行动作序列。
/// [cancelled] 返回 true 时中止；[log] 可选输出进度；
/// [loopCount] 循环次数、[loopIntervalMs] 两轮之间隔。
/// 内建 F10 停止热键检测（100ms 轮询），等待切分为小分片，按下即刻中止。
/// 供录制页回放、历史回放、编辑页试运行与蓝图「执行录制」节点共用。
Future<void> replayActions(
  PlatformAutomation automation,
  List<RecordedAction> actions, {
  bool Function()? cancelled,
  void Function(String message)? log,
  int loopCount = 1,
  int loopIntervalMs = 0,
}) async {
  var aborted = false;
  bool abortRequested() =>
      aborted ||
      (cancelled?.call() ?? false) ||
      automation.isKeyDown(vkStopReplay);

  // 分片等待：最多 100ms 一片，期间随时响应中止
  Future<bool> waitAbortable(int ms) async {
    var remaining = ms;
    while (remaining > 0) {
      final step = remaining > 100 ? 100 : remaining;
      await Future<void>.delayed(Duration(milliseconds: step));
      remaining -= step;
      if (abortRequested()) return true;
    }
    return false;
  }

  final rounds = loopCount.clamp(1, 9999);
  outer:
  for (var round = 0; round < rounds; round++) {
    var prevOffset = 0;
    for (final a in actions) {
      if (abortRequested()) break outer;
      final wait = a.offsetMs - prevOffset;
      if (wait > 0) {
        aborted = await waitAbortable(wait);
        if (aborted) break outer;
      }
      prevOffset = a.offsetMs;
      switch (a) {
        case RecClick c:
          await automation.click(
            c.x,
            c.y,
            button: switch (c.button) {
              'right' => MouseButton.right,
              'middle' => MouseButton.middle,
              _ => MouseButton.left,
            },
            count: c.count,
          );
        case RecSwipe w:
          await automation.swipe(
            w.x1,
            w.y1,
            w.x2,
            w.y2,
            durationMs: w.durationMs,
          );
        case RecLongPress p:
          await automation.longPress(p.x, p.y, durationMs: p.durationMs);
        case RecScroll s:
          await automation.scrollWheel(s.x, s.y, dy: s.dy, dx: s.dx);
        case RecKey k:
          await automation.keyTap(
            k.vkCode,
            durationMs: k.durationMs,
            extended: k.extended,
          );
        case RecCombo c:
          // 组合键：按下所有键（键间 20ms 确保修饰键生效）→ 按住 → 逆序抬起
          final pressed = <int>[];
          for (var i = 0; i < c.vkCodes.length; i++) {
            final vk = c.vkCodes[i];
            final ext = i < c.extendeds.length && c.extendeds[i];
            await automation.keyDown(vk, extended: ext);
            pressed.add(vk);
            if (abortRequested()) break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          var held = c.durationMs - pressed.length * 20;
          if (held > 0) {
            if (await waitAbortable(held)) {
              // 中止也要抬起已按下的键，避免目标窗口卡键
              for (final vk in pressed.reversed) {
                await automation.keyUp(vk);
              }
              return;
            }
          }
          for (var i = c.vkCodes.length - 1; i >= 0; i--) {
            final ext = i < c.extendeds.length && c.extendeds[i];
            await automation.keyUp(c.vkCodes[i], extended: ext);
          }
      }
      if (abortRequested()) break outer;
    }
    // 轮间隔（最后一轮之后不再等）
    if (round < rounds - 1 && loopIntervalMs > 0) {
      aborted = await waitAbortable(loopIntervalMs);
      if (aborted) break;
    }
  }
}

/// 动作摘要文本（录制页与动作编辑页共用）
String describeAction(RecordedAction a) => switch (a) {
  RecClick c =>
    '点击 (${c.x}, ${c.y}) ×${c.count}${c.button == 'right' ? ' 右键' : ''}${c.button == 'middle' ? ' 中键' : ''}',
  RecSwipe w =>
    '滑动 (${w.x1}, ${w.y1}) → (${w.x2}, ${w.y2}) ${w.durationMs}ms',
  RecLongPress p => '长按 (${p.x}, ${p.y}) ${p.durationMs}ms',
  RecScroll s => _scrollText(s),
  RecKey k =>
    '按键 [${vkName(k.vkCode)}] ${k.durationMs}ms${k.extended ? ' (扩展键)' : ''}',
  RecCombo c =>
    '组合键 [${c.vkCodes.map(vkName).join(' + ')}] ${c.durationMs}ms',
};

String _scrollText(RecScroll s) {
  if (s.dy != 0) {
    final up = s.dy > 0;
    final cells = (s.dy.abs() / 120).toStringAsFixed(1);
    return '滚轮 (${s.x}, ${s.y}) ${up ? '↑' : '↓'} $cells 格';
  }
  final right = s.dx > 0;
  final cells = (s.dx.abs() / 120).toStringAsFixed(1);
  return '滚轮 (${s.x}, ${s.y}) ${right ? '→' : '←'} $cells 格';
}

/// 虚拟键显示名称（UI 展示用）
String vkName(int vk) {
  String char(int code) => String.fromCharCode(code);
  if (vk >= 0x30 && vk <= 0x39) return char(vk); // 0-9
  if (vk >= 0x41 && vk <= 0x5A) return char(vk); // A-Z
  if (vk >= 0x70 && vk <= 0x87) return 'F${vk - 0x6F}'; // F1-F24
  if (vk >= 0x60 && vk <= 0x69) return 'Num${vk - 0x60}'; // 小键盘 0-9
  const names = {
    0x01: '左键',
    0x02: '右键',
    0x04: '中键',
    0x08: 'Backspace',
    0x09: 'Tab',
    0x0C: 'Clear',
    0x0D: 'Enter',
    0x10: 'Shift',
    0x11: 'Ctrl',
    0x12: 'Alt',
    0x13: 'Pause',
    0x14: 'CapsLock',
    0x1B: 'Esc',
    0x20: 'Space',
    0x21: 'PgUp',
    0x22: 'PgDn',
    0x23: 'End',
    0x24: 'Home',
    0x25: '←',
    0x26: '↑',
    0x27: '→',
    0x28: '↓',
    0x2C: 'PrintScreen',
    0x2D: 'Insert',
    0x2E: 'Delete',
    0x2F: 'Help',
    0x5B: 'Win',
    0x5C: 'Win',
    0x5D: '菜单',
    0x5F: 'Sleep',
    0x6A: 'Num*',
    0x6B: 'Num+',
    0x6D: 'Num-',
    0x6E: 'Num.',
    0x6F: 'Num/',
    0x90: 'NumLock',
    0x91: 'ScrollLock',
    0xA0: 'LShift',
    0xA1: 'RShift',
    0xA2: 'LCtrl',
    0xA3: 'RCtrl',
    0xA4: 'LAlt',
    0xA5: 'RAlt',
    0xA6: '浏览器后退',
    0xA7: '浏览器前进',
    0xA8: '浏览器刷新',
    0xA9: '浏览器停止',
    0xBA: ';',
    0xBB: '=',
    0xBC: ',',
    0xBD: '-',
    0xBE: '.',
    0xBF: '/',
    0xC0: '`',
    0xDB: '[',
    0xDC: '\\',
    0xDD: ']',
    0xDE: "'",
    0xE2: '\\',
  };
  return names[vk] ??
      'VK_0x${vk.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}
