import 'package:fl_nodes_v2/fl_nodes_v2.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/node_types.dart';
import '../../state/providers.dart';

/// 生成 NodeEditor.nodeBuilder 回调；运行中节点以柔空蓝发光高亮。
/// [runningNodeId] 由编辑器页捕获 runnerProvider 状态后传入。
fl.NodeWidgetBuilder nodeBodyBuilder({String? runningNodeId}) =>
    (context, node, state) => _NodeBodyContent(
          node: node,
          def: nodeDef(node.type),
          categoryColor: nodeDef(node.type).category.color,
          selected: state.isSelected,
          highlight: node.id == runningNodeId,
        );

class _NodeBodyContent extends StatelessWidget {
  const _NodeBodyContent({
    required this.node,
    required this.def,
    required this.categoryColor,
    required this.selected,
    required this.highlight,
  });

  final fl.GraphNode node;
  final NodeTypeDef def;
  final Color categoryColor;
  final bool selected;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final summary = _summaryLines();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? AppColors.success : (selected ? AppColors.primary : AppColors.outline),
          width: highlight || selected ? 2 : 1,
        ),
        boxShadow: highlight
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12)]
            : const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 类别色顶栏
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: categoryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Icon(def.icon, size: 15, color: AppColors.onTint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    def.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onTint),
                  ),
                ),
              ],
            ),
          ),
          // 参数摘要
          if (summary.isNotEmpty || node.type == 'playRecording')
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in summary.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary),
                      ),
                    ),
                  // 执行录制节点：显示所选录制（跟随录制重命名/删除实时更新）
                  if (node.type == 'playRecording')
                    _RecordingSummary(recordingId: node.data['recordingId'] as String? ?? ''),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 参数摘要（最多 4 行），跳过 useRegion=false 时的区域字段
  List<String> _summaryLines() {
    final lines = <String>[];
    String? v(String key) {
      final value = node.data[key];
      if (value == null) return null;
      final s = '$value';
      return s;
    }

    switch (node.type) {
      case 'click':
      case 'doubleClick':
        lines.add('位置 (${v('x')}, ${v('y')})');
        if (v('button') == 'right') lines.add('右键');
        if (v('button') == 'middle') lines.add('中键');
      case 'swipe':
        if (v('mode') == 'direction') {
          lines.add('方向 ${v('angle')}° 距离 ${v('distance')}');
        } else {
          lines.add('(${v('startX')},${v('startY')}) → (${v('endX')},${v('endY')})');
        }
        lines.add('${v('durationMs')}ms');
      case 'longPress':
        lines.add('位置 (${v('x')}, ${v('y')})');
        lines.add('保持 ${v('durationMs')}ms');
      case 'screenshot':
      case 'ocr':
      case 'imageMatch':
        if (node.type != 'screenshot') {
          if (node.type == 'imageMatch') {
            final tpl = v('templatePath') ?? '';
            lines.add('模板 ${tpl.isEmpty ? '未选择' : tpl.split('\\').last.split('/').last}');
            lines.add('阈值 ${v('threshold')}');
          }
          if (node.type == 'ocr') {
            final r = v('resultVar');
            if (r != null && r.isNotEmpty) lines.add('→ $r');
          }
        }
        if (v('useRegion') == 'true') {
          lines.add('区域 (${v('rx')},${v('ry')}) ${v('rw')}×${v('rh')}');
        } else {
          lines.add(node.type == 'screenshot' ? '全屏' : '全屏区域');
        }
      case 'condition':
        lines.add('左值 ${v('leftVar')?.isEmpty == false ? v('leftVar') : v('leftConst')}');
        lines.add('${_opLabel(v('op'))} 右值 ${v('rightVar')?.isEmpty == false ? v('rightVar') : v('rightConst')}');
      case 'loop':
        final count = v('count');
        lines.add(count == '0' ? '无限循环' : '循环 $count 次');
      case 'delay':
        lines.add('等待 ${v('ms')}ms');
      case 'setVar':
        lines.add('${v('name')} = ${v('const')}');
      case 'storage':
        lines.add('${v('action') == 'save' ? '保存' : '读取'} ${v('key')} ↔ ${v('name')}');
      case 'subScript':
        final s = v('scriptName');
        lines.add(s?.isEmpty == false ? '调用「$s」' : '未选择脚本');
      case 'start':
        final c = v('count') ?? '1'; // 旧脚本无此参数时按默认 1 次
        lines.add(c == '0' ? '一直执行（F10 停止）' : '执行 $c 次');
    }
    return lines;
  }

  String _opLabel(String? op) => switch (op) {
        '==' => '等于',
        '!=' => '不等于',
        '>' => '大于',
        '<' => '小于',
        '>=' => '≥',
        '<=' => '≤',
        'contains' => '包含',
        _ => '?',
      };
}

/// 执行录制节点的录制摘要：按 id 解析录制名（未选择/已删除给出提示）
class _RecordingSummary extends ConsumerWidget {
  const _RecordingSummary({required this.recordingId});

  final String recordingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const style = TextStyle(fontSize: 11, color: AppColors.inkSecondary);
    final async = ref.watch(recordingsProvider);

    Widget line(String label) => Text('录制：$label',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    if (recordingId.isEmpty) return line('未选择录制');
    return async.when(
      loading: () => line('…'),
      error: (e, _) => line('加载失败'),
      data: (list) {
        var name = '';
        for (final r in list) {
          if (r.id == recordingId) {
            name = r.name;
            break;
          }
        }
        return line(name.isEmpty ? '录制已删除' : name);
      },
    );
  }
}
