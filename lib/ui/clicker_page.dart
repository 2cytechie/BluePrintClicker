import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';

/// 快捷连点页：频率/时长/点位配置与运行控制
class ClickerPage extends ConsumerWidget {
  const ClickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(clickerProvider);
    final notifier = ref.read(clickerProvider.notifier);
    final idle = st.phase == ClickerPhase.idle;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('快捷连点'),
            const SizedBox(width: 10),
            _phaseBadge(st.phase),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ---- 控制卡：频率 ----
              SectionCard(
                title: '点击频率',
                icon: Icons.speed_rounded,
                child: Column(
                  children: [
                    Text(
                      '${st.intervalMs} ms / 次',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.peacock,
                      ),
                    ),
                    Slider(
                      value: st.intervalMs.clamp(1, 2000).toDouble(),
                      min: 1,
                      max: 2000,
                      divisions: 1999,
                      label: '${st.intervalMs} ms',
                      onChanged: idle
                          ? (v) => notifier.setInterval(v.round())
                          : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            label: '间隔 (ms)',
                            value: st.intervalMs,
                            enabled: idle,
                            onChanged: (n) {
                              if (n != null) notifier.setInterval(n);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ---- 时长卡 ----
              SectionCard(
                title: '运行时长',
                icon: Icons.timer_outlined,
                trailing: StatusBadge(
                  text: st.durationSec <= 0 ? '不限时' : '限定 ${st.durationSec} 秒',
                  color: AppColors.nodeLogic,
                ),
                child: st.phase == ClickerPhase.idle
                    ? _NumberField(
                        label: '时长 (秒，0=不限时)',
                        value: st.durationSec,
                        onChanged: (n) {
                          if (n != null) notifier.setDuration(n);
                        },
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('剩余时间',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.inkSecondary)),
                              const SizedBox(height: 4),
                              Text(
                                st.durationSec <= 0
                                    ? '∞'
                                    : '${st.remainingSec} 秒',
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.peacock,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('已点击',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.inkSecondary)),
                              const SizedBox(height: 4),
                              Text(
                                '${st.clickCount}',
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              // ---- 位置点卡 ----
              SectionCard(
                title: '点击位置',
                icon: Icons.place_rounded,
                trailing: StatusBadge(
                  text: '${st.points.length} 个点位',
                  color: AppColors.nodeData,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      onPressed: idle ? () => _captureCursor(ref) : null,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('捕获当前鼠标位置'),
                    ),
                    const SizedBox(height: 12),
                    _XYInput(
                      enabled: idle,
                      onAdd: (x, y) => notifier.addPoint(x, y),
                    ),
                    const SizedBox(height: 8),
                    if (st.points.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            '先添加至少一个点击位置',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.inkSecondary),
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < st.points.length; i++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                AppColors.peacock.withValues(alpha: 0.15),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.peacockDeep),
                            ),
                          ),
                          title: Text(
                            'X: ${st.points[i].$1}   Y: ${st.points[i].$2}',
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.ink),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColors.danger,
                            tooltip: '删除',
                            onPressed:
                                idle ? () => notifier.removePoint(i) : null,
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ---- 控制按钮行 ----
              SectionCard(
                title: '运行控制',
                icon: Icons.play_circle_outline_rounded,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (st.phase == ClickerPhase.running ||
                                st.points.isEmpty)
                            ? null
                            : () => notifier.start(),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('开始'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: st.phase == ClickerPhase.running
                            ? () => notifier.pause()
                            : null,
                        icon: const Icon(Icons.pause_rounded),
                        label: const Text('暂停'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: st.phase == ClickerPhase.paused
                            ? () => notifier.resume()
                            : null,
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        label: const Text('继续'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: st.phase != ClickerPhase.idle
                            ? () => notifier.stop()
                            : null,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('停止'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 捕获当前鼠标物理坐标并加入点位
  void _captureCursor(WidgetRef ref) {
    final automation = ref.read(automationProvider);
    final (x, y) = automation.cursorPos();
    ref.read(clickerProvider.notifier).addPoint(x, y);
  }

  static Widget _phaseBadge(ClickerPhase phase) => switch (phase) {
        ClickerPhase.idle =>
          const StatusBadge(text: '待机', color: AppColors.inkSecondary),
        ClickerPhase.running =>
          const StatusBadge(text: '运行中', color: AppColors.peacock),
        ClickerPhase.paused =>
          const StatusBadge(text: '已暂停', color: AppColors.nodeLogic),
      };
}

/// 数字输入框（局部 State 管理 controller，外部值变化时同步）
class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toString());

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化且与当前输入不一致时，同步显示
    if (int.tryParse(_controller.text) != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (v) => widget.onChanged(int.tryParse(v)),
    );
  }
}

/// X/Y 坐标输入 + 添加按钮
class _XYInput extends StatefulWidget {
  final bool enabled;
  final void Function(int x, int y) onAdd;

  const _XYInput({required this.enabled, required this.onAdd});

  @override
  State<_XYInput> createState() => _XYInputState();
}

class _XYInputState extends State<_XYInput> {
  final _xCtrl = TextEditingController();
  final _yCtrl = TextEditingController();

  @override
  void dispose() {
    _xCtrl.dispose();
    _yCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final x = int.tryParse(_xCtrl.text.trim());
    final y = int.tryParse(_yCtrl.text.trim());
    if (x == null || y == null) return;
    widget.onAdd(x, y);
    _xCtrl.clear();
    _yCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _xCtrl,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'X 坐标'),
            onSubmitted: (_) => _add(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('，', style: TextStyle(color: AppColors.inkSecondary)),
        ),
        Expanded(
          child: TextField(
            controller: _yCtrl,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Y 坐标'),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: widget.enabled ? _add : null,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
