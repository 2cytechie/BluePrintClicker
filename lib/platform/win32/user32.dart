import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Win32 user32.dll FFI 绑定（鼠标模拟、光标/按键状态、屏幕尺寸）
final DynamicLibrary user32Lib = DynamicLibrary.open('user32.dll');

// ---- 常量 ----
const int inputMouse = 0;
const int mouseeventfMove = 0x0001;
const int mouseeventfLeftdown = 0x0002;
const int mouseeventfLeftup = 0x0004;
const int mouseeventfRightdown = 0x0008;
const int mouseeventfRightup = 0x0010;
const int mouseeventfAbsolutemove = 0x8000;
const int smCxscreen = 0;
const int smCyscreen = 1;
const int vkLbutton = 0x01;
const int vkRbutton = 0x02;

final class _MouseInput extends Struct {
  @Long() external int dx;
  @Long() external int dy;
  @Uint32() external int mouseData;
  @Uint32() external int dwFlags;
  @Uint32() external int time;
  external Pointer<Void> dwExtraInfo;
}

final class _InputUnion extends Union {
  external _MouseInput mi;
}

final class _INPUT extends Struct {
  @Uint32() external int type;
  external _InputUnion u;
}

typedef _SendInputC = Int32 Function(Uint32 cInputs, Pointer<_INPUT> pInputs, Int32 cbSize);
typedef _SendInputDart = int Function(int cInputs, Pointer<_INPUT> pInputs, int cbSize);
final _sendInput = user32Lib.lookupFunction<_SendInputC, _SendInputDart>('SendInput');

typedef _GetSystemMetricsC = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);
final _getSystemMetrics = user32Lib.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>('GetSystemMetrics');

typedef _SetCursorPosC = Int32 Function(Int32 x, Int32 y);
typedef _SetCursorPosDart = int Function(int x, int y);
final _setCursorPos = user32Lib.lookupFunction<_SetCursorPosC, _SetCursorPosDart>('SetCursorPos');

final class _POINT extends Struct {
  @Long() external int x;
  @Long() external int y;
}

typedef _GetCursorPosC = Int32 Function(Pointer<_POINT>);
typedef _GetCursorPosDart = int Function(Pointer<_POINT>);
final _getCursorPos = user32Lib.lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');

typedef _GetAsyncKeyStateC = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);
final _getAsyncKeyState = user32Lib.lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>('GetAsyncKeyState');

int screenW() => _getSystemMetrics(smCxscreen);
int screenH() => _getSystemMetrics(smCyscreen);

(int, int) cursorPos() {
  final p = calloc<_POINT>();
  _getCursorPos(p);
  final r = (p.ref.x, p.ref.y);
  calloc.free(p);
  return r;
}

(bool, bool) mouseButtonsDown() => (_getAsyncKeyState(vkLbutton) & 0x8000 != 0, _getAsyncKeyState(vkRbutton) & 0x8000 != 0);

void setCursorPos(int x, int y) => _setCursorPos(x, y);

void _sendMouse(int flags, int dxNorm, int dyNorm, int mouseData) {
  final p = calloc<_INPUT>();
  final inp = p.ref;
  inp.type = inputMouse;
  inp.u.mi.dx = dxNorm;
  inp.u.mi.dy = dyNorm;
  inp.u.mi.mouseData = mouseData;
  inp.u.mi.dwFlags = flags;
  inp.u.mi.time = 0;
  inp.u.mi.dwExtraInfo = nullptr;
  _sendInput(1, p, sizeOf<_INPUT>());
  calloc.free(p);
}

void _moveToNorm(int x, int y) {
  final w = screenW(), h = screenH();
  final nx = (x * 65535 ~/ (w - 1)).clamp(0, 65535);
  final ny = (y * 65535 ~/ (h - 1)).clamp(0, 65535);
  _sendMouse(mouseeventfMove | mouseeventfAbsolutemove, nx, ny, 0);
}

void moveTo(int x, int y) => _moveToNorm(x, y);

void mouseDown({bool right = false}) =>
    _sendMouse(right ? mouseeventfRightdown : mouseeventfLeftdown, 0, 0, 0);

void mouseUp({bool right = false}) => _sendMouse(right ? mouseeventfRightup : mouseeventfLeftup, 0, 0, 0);

/// 绝对坐标单击（先移动再按下抬起）
void clickAt(int x, int y, {bool right = false}) {
  _moveToNorm(x, y);
  mouseDown(right: right);
  mouseUp(right: right);
}

/// 供拖拽/长按使用：移动到位置
void moveAbsolute(int x, int y) => _moveToNorm(x, y);
