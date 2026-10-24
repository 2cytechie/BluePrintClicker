import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/blueprint.dart';
import '../platform/recording.dart'
    show describeAction, replayActions, vkName;
import '../platform/screen_marker.dart';
import '../state/providers.dart';
import 'common.dart';

/// 录制动作编辑页：从历史记录点击名称进入。
/// 支持修改每个动作参数、删除、上移/下移、追加新动作、试运行（F10 中止）、
/// 屏幕定位（GDI 置顶图标 + 拖拽改坐标）。所有修改即时保存。
class RecordingEditorPage extends ConsumerStatefulWidget {
  final Recording recording;
  const RecordingEditorPage({super.key, required this.recording});

  @override
  ConsumerState<RecordingEditorPage> createState() =>
      _RecordingEditorPageState();
}

class _RecordingEditorPageState extends ConsumerState<RecordingEditorPage> {
  late String _name;
  late final List<RecordedAction> _actions;
  int _expandedIndex = -1; // 展开编辑面板的动作（-1 = 全收起）
  int _markerIndex = -1; // 屏幕定位激活的动作（-1 = 无）
  bool _replaying = false;
  Future<void> _saveChain = Future.value(); // 串行化保存，避免乱序覆盖

  @override
  void initState() {
    super.initState();
    _name = widget.recording.name;
    _actions = List.of(widget.recording.actions);
  }

  @override
  void dispose() {
    ref.read(screenMarkerProvider).hide();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 即时保存（串行链避免连续编辑乱序写文件）
  void _save() {
    _saveChain = _saveChain.then((_) async {
      await ref.read(recordingStorageProvider).save(Recording(
            id: widget.recording.id,
            name: _name,
            createdAt: widget.recording.createdAt,
            actions: List.of(_actions),
          ));
      ref.invalidate(recordingsProvider);
    });
  }

  void _updateAction(int index, RecordedAction action) {
    setState(() => _actions[index] = action);
    _save();
    _refreshMarker();
  }

  void _addAction(RecordedAction action) {
    setState(() {
      _actions.add(action);
      _expandedIndex = _actions.length - 1; // 新动作直接展开便于编辑
    });
    _save();
  }

  void _removeAction(int index) {
    setState(() {
      _actions.removeAt(index);
      if (_expandedIndex >= _actions.length) _expandedIndex = -1;
    });
    if (_markerIndex == index) {
      _hideMarker();
    } else if (_markerIndex > index) {
      _markerIndex--;
    }
    _save();
  }

  void _moveAction(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _actions.length) return;
    if (_markerIndex == index) {
      _hideMarker();
    } else if (_markerIndex == target) {
      _markerIndex = index;
    }
    setState(() {
      final a = _actions.removeAt(index);
      _actions.insert(target, a);
      if (_expandedIndex == index) {
        _expandedIndex = target;
      } else if (_expandedIndex == target) {
        _expandedIndex = index;
      }
    });
    _save();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名录制'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final newName = (name ?? '').trim();
    if (newName.isEmpty || newName == _name) return;
    setState(() => _name = newName);
    _save();
  }

  Future<void> _replay() async {
    if (_replaying) return;
    final automation = ref.read(automationProvider);
    if (!automation.isSupported) {
      _toast(automation.unsupportedReason ?? '当前平台暂不支持回放');
      return;
    }
    if (_actions.isEmpty) {
      _toast('没有可回放的动作');
      return;
    }
    ref.read(screenMarkerProvider).hide();
    setState(() {
      _replaying = true;
      _markerIndex = -1;
    });
    try {
      await replayActions(automation, _actions);
      _toast('回放完成');
    } catch (e) {
      _toast('回放中断：$e');
    } finally {
      if (mounted) setState(() => _replaying = false);
    }
  }

  // ---- 屏幕定位 ----

  void _hideMarker() {
    ref.read(screenMarkerProvider).hide();
    _markerIndex = -1;
  }

  void _toggleMarker(int index) {
    if (_markerIndex == index) {
      _hideMarker();
      setState(() {});
      return;
    }
    _markerIndex = index;
    final points = _markerPointsFor(_actions[index]);
    if (points == null) {
      _markerIndex = -1;
      return;
    }
    ref.read(screenMarkerProvider).show(
          points,
          onDragEnd: (pointIndex, x, y) => _onMarkerDragged(index, pointIndex, x, y),
        );
    setState(() {});
  }

  void _refreshMarker() {
    if (_markerIndex < 0 || _markerIndex >= _actions.length) return;
    final points = _markerPointsFor(_actions[_markerIndex]);
    if (points == null) return;
    ref.read(screenMarkerProvider).updatePoints(points);
  }

  /// 拖拽屏幕图标结束：新坐标写回动作并保存
  void _onMarkerDragged(int actionIndex, int pointIndex, int x, int y) {
    final a = _actions[actionIndex];
    switch (a) {
      case RecClick c:
        _updateAction(
          actionIndex,
          RecClick(c.offsetMs, x, y, count: c.count, button: c.button),
        );
      case RecLongPress p:
        _updateAction(
          actionIndex,
          RecLongPress(p.offsetMs, x, y, p.durationMs),
        );
      case RecScroll s:
        _updateAction(
          actionIndex,
          RecScroll(s.offsetMs, x, y, dx: s.dx, dy: s.dy),
        );
      case RecSwipe w:
        _updateAction(
          actionIndex,
          pointIndex == 0
              ? RecSwipe(w.offsetMs, x, y, w.x2, w.y2, w.durationMs)
              : RecSwipe(w.offsetMs, w.x1, w.y1, x, y, w.durationMs),
        );
      default:
        break;
    }
  }

  /// 含坐标动作 → 屏幕标记点（null = 该动作无坐标）；只显示图标不显示坐标文字
  List<MarkerPoint>? _markerPointsFor(RecordedAction a) {
    switch (a) {
      case RecClick c:
        return [MarkerPoint(c.x, c.y, AppColors.peacock.toARGB32())];
      case RecLongPress p:
        return [MarkerPoint(p.x, p.y, AppColors.danger.toARGB32())];
      case RecScroll s:
        return [MarkerPoint(s.x, s.y, AppColors.nodeScript.toARGB32())];
      case RecSwipe w:
        return [
          MarkerPoint(w.x1, w.y1, AppColors.nodeData.toARGB32()),
          MarkerPoint(w.x2, w.y2, AppColors.nodeMedia.toARGB32()),
        ];
      default:
        return null;
    }
  }

  // ---- 添加动作 ----

  Future<void> _pickAndAddAction() async {
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('添加动作'),
        children: [
          for (final entry in const {
            'RecClick': ('点击', Icons.mouse_rounded, AppColors.peacock),
            'RecSwipe': ('滑动', Icons.swipe_rounded, AppColors.nodeMedia),
            'RecLongPress': ('长按', Icons.timer_rounded, AppColors.danger),
            'RecScroll': ('滚轮', Icons.swap_vert_rounded, AppColors.nodeScript),
            'RecKey': ('按键', Icons.keyboard_rounded, AppColors.nodeData),
            'RecCombo': ('组合键', Icons.keyboard_command_key_rounded, AppColors.success),
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry.key),
              child: Row(
                children: [
                  Icon(entry.value.$2, size: 20, color: entry.value.$3),
                  const SizedBox(width: 12),
                  Text(entry.value.$1,
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.ink)),
                ],
              ),
            ),
        ],
      ),
    );
    if (kind == null) return;
    final (sw, sh) = ref.read(automationProvider).screenSize;
    final cx = sw ~/ 2;
    final cy = sh ~/ 2;
    final lastOffset =
        _actions.isEmpty ? 0 : _actions.last.offsetMs;
    final offset = lastOffset + 500;
    final action = switch (kind) {
      'RecClick' => RecClick(offset, cx, cy),
      'RecSwipe' =>
        RecSwipe(offset, cx - 100, cy, cx + 100, cy, 300),
      'RecLongPress' => RecLongPress(offset, cx, cy, 800),
      'RecScroll' => RecScroll(offset, cx, cy, dy: 120),
      'RecKey' => RecKey(offset, 0x41, durationMs: 60),
      _ => RecCombo(offset, [0x11, 0x43], durationMs: 100),
    };
    _addAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PageHeader(
                    title: '编辑录制',
                    subtitle: _name,
                    trailing: [
                      IconButton(
                        tooltip: '重命名',
                        icon: const Icon(Icons.drive_file_rename_outline_rounded,
                            size: 20),
                        onPressed: _rename,
                      ),
                      if (_replaying)
                        const StatusBadge(
                            text: '回放中 · F10 中止', color: AppColors.nodeLogic),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 操作行：添加 / 试运行
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _replaying ? null : _pickAndAddAction,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加动作'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.peacock),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: _replaying ? null : _replay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('试运行'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _actions.isEmpty
                  ? Center(
                      child: Text(
                        '暂无动作，点击「添加动作」开始编排',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.inkSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _actions.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) => _ActionTile(
                        index: i,
                        action: _actions[i],
                        expanded: _expandedIndex == i,
                        marking: _markerIndex == i,
                        isFirst: i == 0,
                        isLast: i == _actions.length - 1,
                        hasCoordinate: _markerPointsFor(_actions[i]) != null,
                        onToggleExpand: () => setState(() =>
                            _expandedIndex = _expandedIndex == i ? -1 : i),
                        onUpdate: (a) => _updateAction(i, a),
                        onMoveUp: () => _moveAction(i, -1),
                        onMoveDown: () => _moveAction(i, 1),
                        onDelete: () => _removeAction(i),
                        onToggleMarker: () => _toggleMarker(i),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- 动作行 ----

class _ActionTile extends StatelessWidget {
  final int index;
  final RecordedAction action;
  final bool expanded;
  final bool marking;
  final bool isFirst;
  final bool isLast;
  final bool hasCoordinate;
  final VoidCallback onToggleExpand;
  final ValueChanged<RecordedAction> onUpdate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onToggleMarker;

  const _ActionTile({
    required this.index,
    required this.action,
    required this.expanded,
    required this.marking,
    required this.isFirst,
    required this.isLast,
    required this.hasCoordinate,
    required this.onToggleExpand,
    required this.onUpdate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onToggleMarker,
  });

  static (Color, String, IconData) _typeMeta(RecordedAction a) => switch (a) {
    RecClick() => (AppColors.peacock, '点击', Icons.mouse_rounded),
    RecSwipe() => (AppColors.nodeMedia, '滑动', Icons.swipe_rounded),
    RecLongPress() => (AppColors.danger, '长按', Icons.timer_rounded),
    RecScroll() => (AppColors.nodeScript, '滚轮', Icons.swap_vert_rounded),
    RecKey() => (AppColors.nodeData, '按键', Icons.keyboard_rounded),
    RecCombo() => (AppColors.success, '组合键', Icons.keyboard_command_key_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final (color, name, icon) = _typeMeta(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.moonWhite,
        borderRadius: BorderRadius.circular(12),
        border: marking ? Border.all(color: AppColors.peacock, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(name,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${index + 1}.',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
              const SizedBox(width: 6),
              Text(
                '[+${action.offsetMs}ms]',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.inkSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  describeAction(action),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
              ),
              _iconBtn(Icons.arrow_upward_rounded, '上移',
                  isFirst ? null : onMoveUp),
              _iconBtn(Icons.arrow_downward_rounded, '下移',
                  isLast ? null : onMoveDown),
              _iconBtn(Icons.delete_outline_rounded, '删除', onDelete,
                  color: AppColors.danger),
              _iconBtn(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  expanded ? '收起' : '编辑',
                  onToggleExpand,
                  color: expanded ? AppColors.peacock : AppColors.inkSecondary),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _EditPanel(
                action: action,
                hasCoordinate: hasCoordinate,
                marking: marking,
                onUpdate: onUpdate,
                onToggleMarker: onToggleMarker,
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 150),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed,
      {Color? color}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 18),
      color: color ?? AppColors.inkSecondary,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

// ---- 展开的编辑面板（按动作类型渲染字段） ----

class _EditPanel extends StatelessWidget {
  final RecordedAction action;
  final bool hasCoordinate;
  final bool marking;
  final ValueChanged<RecordedAction> onUpdate;
  final VoidCallback onToggleMarker;

  const _EditPanel({
    required this.action,
    required this.hasCoordinate,
    required this.marking,
    required this.onUpdate,
    required this.onToggleMarker,
  });

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      NumField(
        label: '偏移(ms)',
        value: action.offsetMs,
        width: 150,
        min: 0,
        max: 3600000,
        onChanged: (v) => _update(v: v),
      ),
      ..._typeFields(context),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ivory,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: fields,
          ),
          if (hasCoordinate) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    marking ? AppColors.peacock : AppColors.canvasBg,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: onToggleMarker,
              icon: Icon(
                marking ? Icons.location_on_rounded : Icons.location_on_outlined,
                size: 16,
              ),
              label: Text(marking ? '屏幕定位中 · 拖拽图标改坐标' : '屏幕定位'),
            ),
          ],
        ],
      ),
    );
  }

  void _update({int? v}) {
    final offset = v ?? action.offsetMs;
    switch (action) {
      case RecClick c:
        onUpdate(RecClick(offset, c.x, c.y, count: c.count, button: c.button));
      case RecSwipe w:
        onUpdate(RecSwipe(offset, w.x1, w.y1, w.x2, w.y2, w.durationMs));
      case RecLongPress p:
        onUpdate(RecLongPress(offset, p.x, p.y, p.durationMs));
      case RecScroll s:
        onUpdate(RecScroll(offset, s.x, s.y, dx: s.dx, dy: s.dy));
      case RecKey k:
        onUpdate(RecKey(offset, k.vkCode,
            durationMs: k.durationMs, extended: k.extended));
      case RecCombo b:
        onUpdate(RecCombo(offset, b.vkCodes,
            extendeds: b.extendeds, durationMs: b.durationMs));
    }
  }

  List<Widget> _typeFields(BuildContext context) => switch (action) {
    RecClick c => [
        _num('x', c.x, (v) => RecClick(c.offsetMs, v, c.y,
            count: c.count, button: c.button)),
        _num('y', c.y, (v) => RecClick(c.offsetMs, c.x, v,
            count: c.count, button: c.button)),
        _num('次数', c.count, (v) => RecClick(c.offsetMs, c.x, c.y,
            count: v, button: c.button),
            min: 1, max: 99),
        _buttonSelector(c),
      ],
    RecSwipe w => [
        _num('起点x', w.x1, (v) => RecSwipe(w.offsetMs, v, w.y1, w.x2, w.y2, w.durationMs)),
        _num('起点y', w.y1, (v) => RecSwipe(w.offsetMs, w.x1, v, w.x2, w.y2, w.durationMs)),
        _num('终点x', w.x2, (v) => RecSwipe(w.offsetMs, w.x1, w.y1, v, w.y2, w.durationMs)),
        _num('终点y', w.y2, (v) => RecSwipe(w.offsetMs, w.x1, w.y1, w.x2, v, w.durationMs)),
        _num('时长(ms)', w.durationMs, (v) => RecSwipe(w.offsetMs, w.x1, w.y1, w.x2, w.y2, v),
            min: 10, max: 60000),
      ],
    RecLongPress p => [
        _num('x', p.x, (v) => RecLongPress(p.offsetMs, v, p.y, p.durationMs)),
        _num('y', p.y, (v) => RecLongPress(p.offsetMs, p.x, v, p.durationMs)),
        _num('时长(ms)', p.durationMs,
            (v) => RecLongPress(p.offsetMs, p.x, p.y, v),
            min: 10, max: 60000),
      ],
    RecScroll s => [
        _num('x', s.x, (v) => RecScroll(s.offsetMs, v, s.y, dx: s.dx, dy: s.dy)),
        _num('y', s.y, (v) => RecScroll(s.offsetMs, s.x, v, dx: s.dx, dy: s.dy)),
        _num('垂直Δ', s.dy, (v) => RecScroll(s.offsetMs, s.x, s.y, dx: s.dx, dy: v)),
        _num('水平Δ', s.dx, (v) => RecScroll(s.offsetMs, s.x, s.y, dx: v, dy: s.dy)),
      ],
    RecKey k => [
        _keyPicker(
          context,
          label: '按键',
          text: vkName(k.vkCode),
          onPicked: (vk) => onUpdate(RecKey(k.offsetMs, vk,
              durationMs: k.durationMs, extended: k.extended)),
        ),
        _num('时长(ms)', k.durationMs,
            (v) => RecKey(k.offsetMs, k.vkCode,
                durationMs: v, extended: k.extended),
            min: 1, max: 60000),
      ],
    RecCombo b => [
        _comboEditor(context, b),
        _num('时长(ms)', b.durationMs,
            (v) => RecCombo(b.offsetMs, b.vkCodes,
                extendeds: b.extendeds, durationMs: v),
            min: 1, max: 60000),
      ],
  };

  /// 数字字段（自动从数据回显；外部更新坐标时输入框同步）
  Widget _num(String label, int value, RecordedAction Function(int v) make,
      {int min = -1000000, int max = 1000000}) {
    return NumField(
      label: label,
      value: value,
      width: 150,
      min: min,
      max: max,
      onChanged: (v) => onUpdate(make(v)),
    );
  }

  Widget _buttonSelector(RecClick c) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        initialValue: c.button,
        decoration: const InputDecoration(labelText: '按键'),
        items: const [
          DropdownMenuItem(value: 'left', child: Text('左键')),
          DropdownMenuItem(value: 'middle', child: Text('中键')),
          DropdownMenuItem(value: 'right', child: Text('右键')),
        ],
        onChanged: (v) {
          if (v == null) return;
          onUpdate(RecClick(c.offsetMs, c.x, c.y, count: c.count, button: v));
        },
      ),
    );
  }

  Widget _keyPicker(
    BuildContext context, {
    required String label,
    required String text,
    required ValueChanged<int> onPicked,
  }) {
    return SizedBox(
      width: 150,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final vk = await pickVirtualKeyDialog(context);
            if (vk != null) onPicked(vk);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(text,
                    style: const TextStyle(fontSize: 14, color: AppColors.ink))),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _comboEditor(BuildContext context, RecCombo b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < b.vkCodes.length; i++)
              InputChip(
                label: Text(vkName(b.vkCodes[i])),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                onDeleted: () {
                  final codes = List.of(b.vkCodes)..removeAt(i);
                  final exts = List.of(b.extendeds);
                  if (i < exts.length) exts.removeAt(i);
                  onUpdate(RecCombo(b.offsetMs, codes,
                      extendeds: List<bool>.from(exts),
                      durationMs: b.durationMs));
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加键'),
              onPressed: () async {
                final vk = await pickVirtualKeyDialog(context);
                if (vk == null) return;
                final codes = List.of(b.vkCodes)..add(vk);
                final exts = List.of(b.extendeds);
                while (exts.length < codes.length - 1) {
                  exts.add(false);
                }
                exts.add(false);
                onUpdate(RecCombo(b.offsetMs, codes,
                    extendeds: List<bool>.from(exts),
                    durationMs: b.durationMs));
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---- 通用小组件 ----

/// 常用可选虚拟键（编辑动作的按键/组合键用）
const List<int> kSelectableVks = [
  0x08, 0x09, 0x0D, 0x13, 0x14, 0x1B, 0x20, // Backspace Tab Enter Pause Caps Esc Space
  0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, // PgUp..Delete
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, // 0-9
  0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, //
  0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
  0x59, 0x5A, // A-Z
  0x5B, // Win
  0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, // 小键盘 0-9
  0x6A, 0x6B, 0x6D, 0x6E, 0x6F, // Num* + - . /
  0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, // F1-F12
  0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, // LShift RShift LCtrl RCtrl LAlt RAlt
  0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE, // 符号
];

/// 虚拟键选择对话框（列表展示 vkName）
Future<int?> pickVirtualKeyDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('选择按键'),
      content: SizedBox(
        width: 420,
        height: 460,
        child: ListView.builder(
          itemCount: kSelectableVks.length,
          itemBuilder: (_, i) {
            final vk = kSelectableVks[i];
            return ListTile(
              dense: true,
              title: Text(
                vkName(vk),
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
              ),
              onTap: () => Navigator.pop(ctx, vk),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
