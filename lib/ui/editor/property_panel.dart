import 'package:fl_nodes_v2/fl_nodes_v2.dart' as fl;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/node_types.dart';

/// 属性面板：编辑当前选中节点的参数（数据存储于 GraphNode.data，
/// 经 NodeEditorController.updateNode 提交，支持撤销/重做）
class PropertyPanel extends StatelessWidget {
  const PropertyPanel({super.key, required this.controller});

  final fl.NodeEditorController controller;

  Future<void> _confirmDelete(BuildContext context, fl.GraphNode node) async {
    final def = nodeDef(node.type);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除节点？'),
        content: Text('将删除「${def.title}」及其所有连线。'),
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
    if (ok == true) controller.removeNodes([node.id]);
  }

  void _commit(fl.GraphNode node, ParamFieldDef f, Object value) {
    controller.updateNode(node.id, (n) => n.withData({f.key: value}));
  }

  Widget _buildField(fl.GraphNode node, ParamFieldDef f) {
    void onCommit(Object v) => _commit(node, f, v);
    switch (f.type) {
      case ParamType.int:
        return _ParamTextField(node: node, field: f, onCommit: onCommit, numberMode: _NumberMode.int);
      case ParamType.double:
        return _ParamTextField(node: node, field: f, onCommit: onCommit, numberMode: _NumberMode.double);
      case ParamType.string:
      case ParamType.varName:
        return _ParamTextField(node: node, field: f, onCommit: onCommit, numberMode: _NumberMode.none);
      case ParamType.bool:
        final v = node.data[f.key];
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            f.label,
            style: const TextStyle(fontSize: 13, color: AppColors.ink),
          ),
          value: v is bool ? v : f.defaultValue == true,
          onChanged: onCommit,
        );
      case ParamType.enum_:
        final current = node.data[f.key] as String? ?? f.defaultValue as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: f.options.any((o) => o.value == current) ? current : null,
            decoration: InputDecoration(labelText: f.label),
            items: [
              for (final o in f.options)
                DropdownMenuItem(value: o.value, child: Text(o.label)),
            ],
            onChanged: (v) {
              if (v != null) onCommit(v);
            },
          ),
        );
      case ParamType.templateFile:
        return _TemplateFileField(node: node, field: f, onCommit: onCommit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedIds = controller.selection.nodeIds;
        final node = selectedIds.isEmpty ? null : controller.graph.nodes[selectedIds.first];

        if (node == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 44, color: AppColors.outline),
                SizedBox(height: 12),
                Text('选中节点以编辑属性', style: TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
              ],
            ),
          );
        }

        final def = nodeDef(node.type);
        final color = def.category.color;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部：类别色图标 + 标题 + 类型名 + 删除
            Container(
              color: AppColors.moonWhite,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(def.icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          def.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        Text(def.type, style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除节点',
                    color: AppColors.danger,
                    onPressed: () => _confirmDelete(context, node),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                children: [
                  for (final f in def.params) _buildField(node, f),
                  const SizedBox(height: 12),
                  Text(
                    def.description,
                    style: const TextStyle(fontSize: 11, height: 1.5, color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _NumberMode { none, int, double }

/// 文本参数字段：持有本地 controller，避免每次全局刷新导致光标跳动
class _ParamTextField extends StatefulWidget {
  const _ParamTextField({
    required this.node,
    required this.field,
    required this.onCommit,
    required this.numberMode,
  });

  final fl.GraphNode node;
  final ParamFieldDef field;
  final void Function(Object value) onCommit;
  final _NumberMode numberMode;

  @override
  State<_ParamTextField> createState() => _ParamTextFieldState();
}

class _ParamTextFieldState extends State<_ParamTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _valueText());
  }

  String _valueText() {
    final v = widget.node.data[widget.field.key] ?? widget.field.defaultValue;
    if (v == null) return '';
    if (v is num) {
      final d = v.toDouble();
      return d == d.roundToDouble() ? d.round().toString() : '$d';
    }
    return '$v';
  }

  @override
  void didUpdateWidget(_ParamTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当切换到不同节点/字段时同步文本，保留输入中的光标位置
    if (oldWidget.node.id != widget.node.id || oldWidget.field.key != widget.field.key) {
      final t = _valueText();
      if (_controller.text != t) _controller.text = t;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    switch (widget.numberMode) {
      case _NumberMode.int:
        final v = int.tryParse(text.trim());
        if (v != null) widget.onCommit(v);
      case _NumberMode.double:
        final v = double.tryParse(text.trim());
        if (v != null) widget.onCommit(v);
      case _NumberMode.none:
        widget.onCommit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final hint = f.hint ?? (f.type == ParamType.varName ? '变量名' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        keyboardType: widget.numberMode == _NumberMode.none ? null : TextInputType.number,
        style: const TextStyle(fontSize: 13, color: AppColors.ink),
        decoration: InputDecoration(labelText: f.label, hintText: hint),
        onChanged: _onChanged,
      ),
    );
  }
}

/// 模板图片字段：只读路径展示 + 文件选择按钮
class _TemplateFileField extends StatelessWidget {
  const _TemplateFileField({required this.node, required this.field, required this.onCommit});

  final fl.GraphNode node;
  final ParamFieldDef field;
  final void Function(Object value) onCommit;

  Future<void> _pick() async {
    const group = XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'bmp']);
    final file = await openFile(acceptedTypeGroups: [group], confirmButtonText: '选择');
    if (file != null) onCommit(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final path = node.data[field.key] as String? ?? '';
    final name = path.isEmpty ? '' : path.replaceAll('\\', '/').split('/').last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label, style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Text(
                    path.isEmpty ? '未选择模板图片' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: path.isEmpty ? AppColors.inkSecondary : AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _pick, child: const Text('选择…')),
        ],
      ),
    );
  }
}
