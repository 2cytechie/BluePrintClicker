import 'dart:async';

import '../models/blueprint.dart';
import 'platform_automation.dart';

/// 录制服务抽象：捕获用户操作序列。Windows 实现基于输入状态轮询。
abstract interface class RecordingService {
  bool get isRecording;
  Stream<RecordedAction> get events;
  void start();
  List<RecordedAction> stop();
}

/// Windows 实现：轮询 GetCursorPos/GetAsyncKeyState（10ms），
/// 检测按下/抬起/移动，合成点击、滑动、长按动作。
class WindowsRecordingService implements RecordingService {
  WindowsRecordingService(this._automation);
  final PlatformAutomation _automation;

  Timer? _timer;
  final List<RecordedAction> _actions = [];
  final StreamController<RecordedAction> _events = StreamController.broadcast();

  bool _leftDown = false;
  bool _rightDown = false;
  int _downX = 0;
  int _downY = 0;
  DateTime _downTime = DateTime.now();
  DateTime _start = DateTime.now();

  // 拖动检测：按下期间累计位移
  int _maxDist = 0;
  int _lastX = 0;
  int _lastY = 0;
  DateTime _lastMove = DateTime.now();

  @override
  bool get isRecording => _timer != null;

  @override
  Stream<RecordedAction> get events => _events.stream;

  @override
  void start() {
    if (isRecording) return;
    _actions.clear();
    _leftDown = _rightDown = false;
    _maxDist = 0;
    _start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _poll());
  }

  @override
  List<RecordedAction> stop() {
    _timer?.cancel();
    _timer = null;
    if (_leftDown || _rightDown) _onRelease();
    return List.of(_actions);
  }

  void _poll() {
    final (x, y) = _automation.cursorPos();
    final (l, r) = _automation.buttonsDown();

    if (_leftDown || _rightDown) {
      final d = (x - _downX).abs() + (y - _downY).abs();
      if (d > _maxDist) {
        _maxDist = d;
        _lastX = x;
        _lastY = y;
        _lastMove = DateTime.now();
      }
    }

    if (l && !_leftDown) _onDown(x, y, false);
    if (!l && _leftDown) _onRelease();
    if (r && !_rightDown) _onDown(x, y, true);
    if (!r && _rightDown) _onRelease();
  }

  void _onDown(int x, int y, bool right) {
    _rightDown = right;
    _leftDown = !right;
    _downX = x;
    _downY = y;
    _downTime = DateTime.now();
    _maxDist = 0;
    _lastX = x;
    _lastY = y;
    _lastMove = _downTime;
  }

  void _onRelease() {
    if (!_leftDown && !_rightDown) return;
    final held = DateTime.now().difference(_downTime).inMilliseconds;
    final offset = _downTime.difference(_start).inMilliseconds;
    final button = _rightDown ? 'right' : 'left';
    RecordedAction action;
    if (_maxDist > 24) {
      action = RecSwipe(offset, _downX, _downY, _lastX, _lastY,
          _lastMove.difference(_downTime).inMilliseconds.clamp(30, 10000));
    } else if (held >= 600) {
      action = RecLongPress(offset, _downX, _downY, held);
    } else {
      action = RecClick(offset, _downX, _downY, button: button);
    }
    _actions.add(action);
    _events.add(action);
    _leftDown = _rightDown = false;
    _maxDist = 0;
  }
}
