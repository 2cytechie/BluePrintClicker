import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/interpreter.dart';
import '../models/blueprint.dart';
import '../platform/automation_factory.dart';
import '../platform/platform_automation.dart';
import '../platform/recording.dart';
import '../services/recognition.dart';
import '../services/script_storage.dart';
import '../services/windows_recognition.dart';

// ---- 应用导航 ----

/// 侧边栏导航页签；编辑器为全屏页（不显示侧边栏）
enum AppTab { home, clicker, editor, recordings }

class AppNavNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void go(AppTab tab) => state = tab;
}

final appNavProvider = NotifierProvider<AppNavNotifier, AppTab>(AppNavNotifier.new);

// ---- 平台服务单例 ----

final automationProvider = Provider<PlatformAutomation>((ref) => createAutomation());

final recognitionProvider = Provider<RecognitionService>((ref) => WindowsRecognitionService());

final scriptStorageProvider = Provider<ScriptStorage>((ref) => ScriptStorage());

final recordingStorageProvider = Provider<RecordingStorage>((ref) => RecordingStorage());

final recordingServiceProvider = Provider<RecordingService>((ref) {
  final automation = ref.watch(automationProvider);
  if (automation.isSupported) return WindowsRecordingService(automation);
  return _NoopRecording();
});

class _NoopRecording implements RecordingService {
  @override
  bool get isRecording => false;
  @override
  Stream<RecordedAction> get events => const Stream.empty();
  @override
  void start() {}
  @override
  List<RecordedAction> stop() => [];
}

// ---- 脚本列表 ----

class ScriptListNotifier extends AsyncNotifier<List<BlueprintScript>> {
  @override
  Future<List<BlueprintScript>> build() async => ref.watch(scriptStorageProvider).listScripts();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(scriptStorageProvider).listScripts());
  }
}

final scriptListProvider =
    AsyncNotifierProvider<ScriptListNotifier, List<BlueprintScript>>(ScriptListNotifier.new);

// ---- 当前编辑脚本 ----

class CurrentScriptNotifier extends Notifier<BlueprintScript?> {
  @override
  BlueprintScript? build() => null;

  void open(BlueprintScript s) => state = s;
  void close() => state = null;

  void _touch() {
    final s = state;
    if (s != null) ref.read(scriptStorageProvider).save(s).then((_) => ref.read(scriptListProvider.notifier).refresh());
  }

  void updateNodePosition(String nodeId, double x, double y) {
    state?.nodes[nodeId]?..x = x..y = y;
  }

  void addNode(BPNode node) {
    state?.nodes[node.id] = node;
    _touch();
    state = state?.copy() ?? state;
    if (state != null) ref.read(selectedNodeProvider.notifier).select(node.id);
  }

  void updateNodeParams(String nodeId, String key, Object value) {
    state?.nodes[nodeId]?.params[key] = value;
    state = state?.copy() ?? state;
  }

  void removeNode(String nodeId) {
    state?.removeNode(nodeId);
    ref.read(selectedNodeProvider.notifier).select(null);
    state = state?.copy() ?? state;
  }

  void addEdge(BPEdge edge) {
    final s = state;
    if (s == null) return;
    // 执行流输出口只允许一条出边
    if (edge.kind == EdgeKind.exec) {
      s.edges.removeWhere((k, e) => e.from == edge.from && e.kind == EdgeKind.exec);
    }
    // 输入端口只允许一条入边
    s.edges.removeWhere((k, e) => e.to == edge.to);
    s.edges[edge.id] = edge;
    _touch();
    state = s.copy();
  }

  void removeEdge(String edgeId) {
    state?.edges.remove(edgeId);
    state = state?.copy() ?? state;
  }
}

final currentScriptProvider =
    NotifierProvider<CurrentScriptNotifier, BlueprintScript?>(CurrentScriptNotifier.new);

// ---- 编辑器交互状态 ----

class SelectedNodeNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedNodeProvider = NotifierProvider<SelectedNodeNotifier, String?>(SelectedNodeNotifier.new);

/// 正在拖拽的连线起点（输出口），拖到目标输入口松手完成连线
class PendingConnectionNotifier extends Notifier<PortRef?> {
  @override
  PortRef? build() => null;
  void begin(PortRef from) => state = from;
  void cancel() => state = null;
  bool get isActive => state != null;
}

final pendingConnectionProvider =
    NotifierProvider<PendingConnectionNotifier, PortRef?>(PendingConnectionNotifier.new);

// ---- 蓝图运行状态 ----

class RunnerState {
  final bool running;
  final String? currentNodeId;
  final List<String> logs;
  const RunnerState({this.running = false, this.currentNodeId, this.logs = const []});

  RunnerState copyWith({bool? running, String? currentNodeId, List<String>? logs}) => RunnerState(
        running: running ?? this.running,
        currentNodeId: currentNodeId ?? this.currentNodeId,
        logs: logs ?? this.logs,
      );
}

class RunnerNotifier extends Notifier<RunnerState> {
  BlueprintInterpreter? _engine;

  @override
  RunnerState build() => const RunnerState();

  void start(BlueprintScript script) {
    if (state.running) return;
    final automation = ref.read(automationProvider);
    if (!automation.isSupported) {
      state = state.copyWith(
          logs: [...state.logs, '✗ ${automation.unsupportedReason}'], running: false);
      return;
    }
    final engine = BlueprintInterpreter(
      automation: automation,
      recognition: ref.read(recognitionProvider),
      hooks: EngineHooks(
        log: (m) => _appendLog(m),
        onNodeChange: (id) => state = state.copyWith(currentNodeId: id),
        loadScript: (name) => ref.read(scriptStorageProvider).load(name),
      ),
    );
    _engine = engine;
    state = state.copyWith(running: true, logs: [...state.logs, '—— 启动 ${script.name} ——']);
    unawaited(engine.run(script).whenComplete(() {
      state = state.copyWith(running: false, currentNodeId: null);
      _engine = null;
    }));
  }

  void stop() {
    _engine?.stop();
    _appendLog('停止请求已发送');
  }

  void clearLogs() => state = state.copyWith(logs: []);

  void _appendLog(String m) {
    final now = TimeOfDayish.now();
    state = state.copyWith(logs: [...state.logs.takeLast(499), '[$now] $m']);
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}

class TimeOfDayish {
  static String now() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }
}

final runnerProvider = NotifierProvider<RunnerNotifier, RunnerState>(RunnerNotifier.new);

// ---- 快捷连点 ----

enum ClickerPhase { idle, running, paused }

class ClickerState {
  final int intervalMs;
  final List<(int, int)> points;
  final int durationSec; // 0 = 不限时
  final ClickerPhase phase;
  final int remainingSec;
  final int clickCount;
  const ClickerState({
    this.intervalMs = 100,
    this.points = const [],
    this.durationSec = 0,
    this.phase = ClickerPhase.idle,
    this.remainingSec = 0,
    this.clickCount = 0,
  });

  ClickerState copyWith({
    int? intervalMs,
    List<(int, int)>? points,
    int? durationSec,
    ClickerPhase? phase,
    int? remainingSec,
    int? clickCount,
  }) =>
      ClickerState(
        intervalMs: intervalMs ?? this.intervalMs,
        points: points ?? this.points,
        durationSec: durationSec ?? this.durationSec,
        phase: phase ?? this.phase,
        remainingSec: remainingSec ?? this.remainingSec,
        clickCount: clickCount ?? this.clickCount,
      );
}

class ClickerNotifier extends Notifier<ClickerState> {
  Timer? _timer;
  Timer? _tick;
  Stopwatch? _elapsed;
  int _index = 0;
  int _total = 0;

  @override
  ClickerState build() => const ClickerState();
  bool get _isSupported => ref.read(automationProvider).isSupported;

  void setInterval(int ms) {
    if (state.phase != ClickerPhase.idle) return;
    state = state.copyWith(intervalMs: ms.clamp(1, 60000));
  }

  void setDuration(int sec) {
    if (state.phase != ClickerPhase.idle) return;
    state = state.copyWith(durationSec: sec.clamp(0, 86400));
  }

  void addPoint(int x, int y) {
    if (state.phase != ClickerPhase.idle) return;
    state = state.copyWith(points: [...state.points, (x, y)]);
  }

  void removePoint(int index) {
    if (state.phase != ClickerPhase.idle) return;
    final pts = [...state.points]..removeAt(index);
    state = state.copyWith(points: pts);
  }

  Future<void> start() async {
    if (state.phase != ClickerPhase.idle || state.points.isEmpty || !automationAvailable()) return;
    state = state.copyWith(
        phase: ClickerPhase.running,
        remainingSec: state.durationSec,
        clickCount: 0);
    _index = 0;
    _total = 0;
    _elapsed = state.durationSec > 0 ? (Stopwatch()..start()) : null;
    _tick = state.durationSec > 0
        ? Timer.periodic(const Duration(milliseconds: 200), (_) => _updateCountdown())
        : null;
    unawaited(_loop());
  }

  bool automationAvailable() {
    if (_isSupported) return true;
    state = state.copyWith();
    return false;
  }

  void _updateCountdown() {
    final elapsed = _elapsed?.elapsed ?? Duration.zero;
    final remain = state.durationSec - elapsed.inSeconds;
    if (remain <= 0) {
      stop();
      return;
    }
    state = state.copyWith(remainingSec: remain);
  }

  Future<void> _loop() async {
    final automation = ref.read(automationProvider);
    while (state.phase == ClickerPhase.running && !_stoppedByTime()) {
      final pts = state.points;
      if (pts.isEmpty) break;
      final p = pts[_index % pts.length];
      _index++;
      _total++;
      state = state.copyWith(clickCount: _total);
      try {
        await automation.click(p.$1, p.$2);
      } catch (e) {
        pause();
        return;
      }
      // 分片等待，便于快速响应暂停/停止
      final interval = state.intervalMs;
      var waited = 0;
      while (waited < interval && state.phase == ClickerPhase.running) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        waited += 10;
      }
    }
  }

  bool _stoppedByTime() {
    if (_elapsed == null) return false;
    return _elapsed!.elapsed.inMilliseconds >= state.durationSec * 1000;
  }

  void pause() {
    if (state.phase != ClickerPhase.running) return;
    _elapsed?.stop();
    state = state.copyWith(phase: ClickerPhase.paused);
  }

  void resume() {
    if (state.phase != ClickerPhase.paused) return;
    _elapsed?.start();
    state = state.copyWith(phase: ClickerPhase.running);
    unawaited(_loop());
  }

  void stop() {
    _timer?.cancel();
    _tick?.cancel();
    _timer = null;
    _tick = null;
    _elapsed = null;
    _index = 0;
    state = state.copyWith(phase: ClickerPhase.idle, remainingSec: state.durationSec);
  }
}

final clickerProvider = NotifierProvider<ClickerNotifier, ClickerState>(ClickerNotifier.new);
