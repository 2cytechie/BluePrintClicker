import 'package:fl_nodes_v2/fl_nodes_v2.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/blueprint.dart';
import '../../models/node_types.dart' show nodeDef;
import '../../state/providers.dart';
import 'node_body.dart';
import 'node_bridge.dart';
import 'node_palette.dart';
import 'property_panel.dart';

/// 蓝图编辑器页面：基于 fl_nodes_v2，全屏显示（侧边栏不显示）
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late final fl.NodeEditorController _controller;
  final GlobalKey<fl.NodeEditorState> _editorKey = GlobalKey();
  BlueprintScript? _loadedScript;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _controller = fl.NodeEditorController(definitions: blueprintNodeRegistry);
    // 打开脚本 → 载入图（不同实例才载入，避免编辑引起的刷新重置画布）
    ref.listenManual(currentScriptProvider, (prev, next) {
      if (next == null) return;
      if (identical(next, _loadedScript)) return;
      _loadedScript = next;
      _controller.replaceGraph(
        blueprintToGraph(next),
        recordHistory: false,
        normalise: true,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitContent());
    });
    final initial = ref.read(currentScriptProvider);
    if (initial != null) {
      _loadedScript = initial;
      _controller.replaceGraph(blueprintToGraph(initial), recordHistory: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitContent());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fitContent() {
    final editor = _editorKey.currentState;
    if (editor != null) {
      _controller.camera.fitToContent(editor.viewportSize);
    }
  }

  /// 从编辑器图模型转回脚本（所见即所得）
  BlueprintScript? _currentAsScript() {
    final loaded = _loadedScript;
    if (loaded == null) return null;
    return graphToBlueprint(_controller.graph, name: loaded.name, createdAt: loaded.createdAt);
  }

  Future<void> _save() async {
    final script = _currentAsScript();
    if (script == null) return;
    try {
      await ref.read(scriptStorageProvider).save(script);
      ref.read(currentScriptProvider.notifier).open(script);
      _loadedScript = script;
      _controller.project.markSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('脚本已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败')));
      }
    }
  }

  void _run() {
    final script = _currentAsScript();
    if (script == null) return;
    ref.read(runnerProvider.notifier).start(script);
  }

  void _showPaletteSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.moonWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      builder: (_) => NodePalette(
        controller: _controller,
        editorStateKey: _editorKey,
        popOnAdd: true,
      ),
    );
  }

  void _showPropsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      builder: (_) => PropertyPanel(controller: _controller),
    );
  }

  Future<void> _confirmDeleteConnection(fl.NodeConnection c) async {
    final fromNode = _controller.graph.nodes[c.from.nodeId];
    final toNode = _controller.graph.nodes[c.to.nodeId];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连线？'),
        content: Text('将删除 ${fromNode?.type ?? '?'} → ${toNode?.type ?? '?'} 的连线。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) _controller.removeConnections([c.id]);
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(currentScriptProvider);
    final runner = ref.watch(runnerProvider);
    final runningNodeId = runner.currentNodeId;
    final currentNodeTitle = () {
      if (runningNodeId == null || _loadedScript == null) return '…';
      final n = _controller.graph.nodes[runningNodeId];
      return n == null ? '…' : nodeDef(n.type).title;
    }();

    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(script, runner, currentNodeTitle),
          const Divider(height: 1),
          Expanded(
            child: _loadedScript == null
                ? _buildGuide()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final editor = fl.NodeEditor(
                        key: _editorKey,
                        controller: _controller,
                        nodeBuilder: nodeBodyBuilder(runningNodeId: runningNodeId),
                        theme: fl.NodeEditorTheme.light(accent: AppColors.peacock)
                            .copyWith(background: AppColors.canvasBg),
                        onConnectionTap: _confirmDeleteConnection,
                      );
                      if (constraints.maxWidth >= 1100) {
                        return Row(
                          children: [
                            SizedBox(
                                width: 240,
                                child: NodePalette(
                                    controller: _controller, editorStateKey: _editorKey)),
                            const VerticalDivider(width: 1),
                            Expanded(child: editor),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 320, child: PropertyPanel(controller: _controller)),
                          ],
                        );
                      }
                      // 窄屏：画布占满，节点库与属性面板从弹出层打开
                      return Stack(
                        children: [
                          Positioned.fill(child: editor),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: FloatingActionButton.small(
                              heroTag: 'editor_palette',
                              tooltip: '节点库',
                              onPressed: _showPaletteSheet,
                              child: const Icon(Icons.apps_rounded),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: FloatingActionButton.extended(
                              heroTag: 'editor_props',
                              tooltip: '属性面板',
                              onPressed: _showPropsSheet,
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('属性'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          // 可展开的运行日志面板
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _showLogs ? const _LogsPanel() : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ---- 顶部工具栏 ----

  Widget _buildToolbar(BlueprintScript? script, RunnerState runner, String currentNodeTitle) {
    return Container(
      color: AppColors.moonWhite,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回首页',
            onPressed: () => ref.read(appNavProvider.notifier).go(AppTab.home),
            icon: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.inkSecondary),
          ),
          const Icon(Icons.account_tree_rounded, color: AppColors.peacock, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              script?.name ?? '未打开脚本',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          if (_controller.project.isDirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.fiber_manual_record, size: 10, color: AppColors.peacock),
            ),
          // 运行中显示当前节点指示
          if (runner.running)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '运行中 · $currentNodeTitle',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                  ),
                ],
              ),
            ),
          runner.running
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: () => ref.read(runnerProvider.notifier).stop(),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('停止'),
                )
              : FilledButton.icon(
                  onPressed: script == null ? null : _run,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('运行'),
                ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: script == null ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: _showLogs ? '收起日志' : '运行日志',
            onPressed: () => setState(() => _showLogs = !_showLogs),
            icon: Icon(
              Icons.article_outlined,
              color: _showLogs ? AppColors.peacock : AppColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 未打开脚本时的引导 ----

  Widget _buildGuide() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schema_outlined, size: 72, color: AppColors.outline),
          const SizedBox(height: 16),
          const Text(
            '尚未打开脚本',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.inkSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            '从首页选择或新建一个蓝图脚本后开始编辑',
            style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.read(appNavProvider.notifier).go(AppTab.home),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('返回首页'),
          ),
        ],
      ),
    );
  }
}

/// 底部运行日志面板：最新日志在底部，自动滚动
class _LogsPanel extends ConsumerStatefulWidget {
  const _LogsPanel();

  @override
  ConsumerState<_LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends ConsumerState<_LogsPanel> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(runnerProvider.select((s) => s.logs));
    // 新日志到达时滚动到底部
    ref.listen(runnerProvider.select((s) => s.logs.length), (_, _) => _jumpBottom());
    return Container(
      height: 220,
      color: AppColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(color: AppColors.peacockDeep),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 16, color: AppColors.moonWhite),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '运行日志',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.moonWhite),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(runnerProvider.notifier).clearLogs(),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.moonWhite),
                  label: const Text('清空', style: TextStyle(fontSize: 12, color: AppColors.moonWhite)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  logs[i],
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.moonWhite),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
