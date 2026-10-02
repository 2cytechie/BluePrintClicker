import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/blueprint.dart';
import '../platform/platform_automation.dart';
import '../state/providers.dart';
import 'common.dart';

/// 历史录制列表（本地 FutureProvider，操作后 invalidate 刷新）
final recordingsProvider =
    FutureProvider<List<Recording>>((ref) => ref.watch(recordingStorageProvider).list());

/// 录制与回放页
class RecordingPage extends ConsumerStatefulWidget {
  const RecordingPage({super.key});

  @override
  ConsumerState<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends ConsumerState<RecordingPage> {
  StreamSubscription<RecordedAction>? _sub;
  int _liveCount = 0; // 录制中实时捕获的动作数
  Recording? _lastRecording; // 最近一次停止后的录制结果
  bool _replaying = false;

  @override
  void initState() {
    super.initState();
    // 监听录制事件流：每捕获一个动作就刷新计数
    _sub = ref.read(recordingServiceProvider).events.listen((_) {
      if (mounted) setState(() => _liveCount++);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 开始录制
  void _startRecording() {
    final automation = ref.read(automationProvider);
    if (!automation.isSupported) {
      _toast(automation.unsupportedReason ?? '当前平台暂不支持录制');
      return;
    }
    final service = ref.read(recordingServiceProvider);
    service.start();
    setState(() {
      _liveCount = 0;
      _lastRecording = null;
    });
    _toast('录制已开始，请切换到目标窗口进行操作');
  }

  /// 停止录制并保存会话
  Future<void> _stopRecording() async {
    final service = ref.read(recordingServiceProvider);
    final actions = service.stop();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final r = Recording(
      id: 'r_${now.millisecondsSinceEpoch}',
      name: '录制 ${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
      createdAt: now,
      actions: actions,
    );
    await ref.read(recordingStorageProvider).save(r);
    if (!mounted) return;
    setState(() {
      _lastRecording = r;
      _liveCount = 0;
    });
    ref.invalidate(recordingsProvider);
  }

  /// 回放动作序列（按录制时的偏移间隔执行）
  Future<void> _replay(List<RecordedAction> actions) async {
    final automation = ref.read(automationProvider);
    if (!automation.isSupported) {
      _toast(automation.unsupportedReason ?? '当前平台暂不支持回放');
      return;
    }
    if (_replaying || actions.isEmpty) return;
    setState(() => _replaying = true);
    var prevOffset = 0;
    try {
      for (final a in actions) {
        final wait = a.offsetMs - prevOffset;
        if (wait > 0) {
          await Future<void>.delayed(Duration(milliseconds: wait));
        }
        prevOffset = a.offsetMs;
        switch (a) {
          case RecClick c:
            await automation.click(
              c.x,
              c.y,
              button:
                  c.button == 'right' ? MouseButton.right : MouseButton.left,
              count: c.count,
            );
          case RecSwipe w:
            await automation
                .swipe(w.x1, w.y1, w.x2, w.y2, durationMs: w.durationMs);
          case RecLongPress p:
            await automation.longPress(p.x, p.y, durationMs: p.durationMs);
        }
      }
      _toast('回放完成');
    } catch (e) {
      _toast('回放中断：$e');
    } finally {
      if (mounted) setState(() => _replaying = false);
    }
  }

  /// 将录制转为蓝图脚本保存
  Future<void> _saveAsScript(Recording r) async {
    final s = r.toBlueprint();
    await ref.read(scriptStorageProvider).save(s);
    await ref.read(scriptListProvider.notifier).refresh();
    _toast('已保存为脚本「${s.name}」，可在首页查看');
  }

  String _actionLabel(RecordedAction a) => switch (a) {
        RecClick c =>
          '点击 (${c.x}, ${c.y}) ×${c.count}${c.button == 'right' ? ' 右键' : ''}',
        RecSwipe w =>
          '滑动 (${w.x1}, ${w.y1}) → (${w.x2}, ${w.y2}) ${w.durationMs}ms',
        RecLongPress p => '长按 (${p.x}, ${p.y}) ${p.durationMs}ms',
      };

  @override
  Widget build(BuildContext context) {
    final service = ref.read(recordingServiceProvider);
    final recording = service.isRecording;

    return Scaffold(
      appBar: AppBar(title: const Text('录制与回放')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ---- 新建录制 ----
              SectionCard(
                title: '新建录制',
                icon: Icons.fiber_manual_record_rounded,
                trailing: recording
                    ? const StatusBadge(text: '录制中', color: AppColors.danger)
                    : const StatusBadge(
                        text: '待机', color: AppColors.inkSecondary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording
                          ? '正在录制 · 已捕获 $_liveCount 个动作，请切换到目标窗口操作'
                          : '点击「开始录制」后，切换到目标窗口进行点击/滑动/长按操作',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.inkSecondary),
                    ),
                    const SizedBox(height: 14),
                    recording
                        ? FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                            ),
                            onPressed: _stopRecording,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('停止录制'),
                          )
                        : FilledButton.icon(
                            onPressed: _replaying ? null : _startRecording,
                            icon: const Icon(Icons.fiber_manual_record_rounded),
                            label: const Text('开始录制'),
                          ),
                  ],
                ),
              ),
              // ---- 最近录制预览 ----
              if (_lastRecording != null) ...[
                const SizedBox(height: 14),
                SectionCard(
                  title: '「${_lastRecording!.name}」动作预览',
                  icon: Icons.list_alt_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _lastRecording!.actions.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '${i + 1}. [+${_lastRecording!.actions[i].offsetMs}ms] ${_actionLabel(_lastRecording!.actions[i])}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.ink),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _replaying
                                  ? null
                                  : () => _saveAsScript(_lastRecording!),
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: const Text('保存为脚本'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _replaying
                                  ? null
                                  : () => _replay(_lastRecording!.actions),
                              icon:
                                  const Icon(Icons.play_arrow_rounded, size: 18),
                              label: const Text('立即回放'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // ---- 历史记录 ----
              const _HistorySection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史录制记录列表
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recordingsProvider);
    return SectionCard(
      title: '历史记录',
      icon: Icons.history_rounded,
      child: list.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('加载失败：$e',
            style: const TextStyle(fontSize: 13, color: AppColors.danger)),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '暂无历史录制，完成一次录制后会自动保存在这里',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final r in items)
                _HistoryTile(
                  key: ValueKey(r.id),
                  recording: r,
                  isLast: r == items.last,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 单条历史记录（展开状态由自身管理）
class _HistoryTile extends ConsumerStatefulWidget {
  final Recording recording;
  final bool isLast;

  const _HistoryTile({super.key, required this.recording, required this.isLast});

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile> {
  bool _expanded = false;

  Recording get recording => widget.recording;

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = recording;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.videocam_outlined,
                  size: 20, color: AppColors.peacock),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtTime(r.createdAt)} · ${r.actions.length} 个动作',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: _expanded ? AppColors.peacock : AppColors.inkSecondary,
                ),
                tooltip: '查看',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                color: AppColors.peacock,
                tooltip: '回放',
                onPressed: () => _replayRecording(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.save_alt_rounded, size: 20),
                color: AppColors.inkSecondary,
                tooltip: '转脚本',
                onPressed: () => _toScript(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.danger,
                tooltip: '删除',
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
        ),
        // 展开的动作明细
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.ivory,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < r.actions.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${i + 1}. [+${r.actions[i].offsetMs}ms] ${_label(r.actions[i])}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.inkSecondary),
                    ),
                  ),
              ],
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 150),
        ),
        if (!widget.isLast) const Divider(),
      ],
    );
  }

  String _label(RecordedAction a) => switch (a) {
        RecClick c =>
          '点击 (${c.x}, ${c.y}) ×${c.count}${c.button == 'right' ? ' 右键' : ''}',
        RecSwipe w =>
          '滑动 (${w.x1}, ${w.y1}) → (${w.x2}, ${w.y2}) ${w.durationMs}ms',
        RecLongPress p => '长按 (${p.x}, ${p.y}) ${p.durationMs}ms',
      };

  Future<void> _replayRecording(BuildContext context, WidgetRef ref) async {
    final automation = ref.read(automationProvider);
    if (!automation.isSupported) {
      _toast(context, automation.unsupportedReason ?? '当前平台暂不支持回放');
      return;
    }
    // 回放为耗时操作，逐个执行动作（间隔按录制偏移差）
    final actions = recording.actions;
    var prevOffset = 0;
    try {
      for (final a in actions) {
        final wait = a.offsetMs - prevOffset;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        prevOffset = a.offsetMs;
        switch (a) {
          case RecClick c:
            await automation.click(
              c.x,
              c.y,
              button:
                  c.button == 'right' ? MouseButton.right : MouseButton.left,
              count: c.count,
            );
          case RecSwipe w:
            await automation
                .swipe(w.x1, w.y1, w.x2, w.y2, durationMs: w.durationMs);
          case RecLongPress p:
            await automation.longPress(p.x, p.y, durationMs: p.durationMs);
        }
      }
      if (context.mounted) _toast(context, '回放完成');
    } catch (e) {
      if (context.mounted) _toast(context, '回放中断：$e');
    }
  }

  Future<void> _toScript(BuildContext context, WidgetRef ref) async {
    final s = recording.toBlueprint();
    await ref.read(scriptStorageProvider).save(s);
    await ref.read(scriptListProvider.notifier).refresh();
    if (!context.mounted) return;
    _toast(context, '已保存为脚本「${s.name}」');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除录制'),
        content: Text('确定删除「${recording.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(recordingStorageProvider).delete(recording.id);
    ref.invalidate(recordingsProvider);
  }
}

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
