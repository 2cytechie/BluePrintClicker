import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blueprint_clicker/models/blueprint.dart';

void main() {
  group('蓝图序列化往返', () {
    test('节点/连接/参数/变量完整还原', () {
      final s = BlueprintScript(name: '测试脚本')
        ..variables['found'] = true
        ..variables['score'] = 3.14
        ..variables['label'] = 'hello';
      s.nodes['n1'] = BPNode(
        id: 'n1',
        type: 'start',
        x: 10,
        y: 20,
        params: {},
      );
      s.nodes['n2'] = BPNode(id: 'n2', type: 'click', x: 200, y: 120)
        ..params['x'] = 500
        ..params['y'] = 300
        ..params['fingers'] = 3
        ..params['button'] = 'right';
      s.nodes['n3'] = BPNode(id: 'n3', type: 'condition', x: 400, y: 200)
        ..params['op'] = '>=';
      s.edges['e1'] = BPEdge(
        id: 'e1',
        from: const PortRef(nodeId: 'n1', port: 'out'),
        to: const PortRef(nodeId: 'n2', port: 'in'),
        kind: EdgeKind.exec,
      );
      s.edges['e2'] = BPEdge(
        id: 'e2',
        from: const PortRef(nodeId: 'n2', port: 'found'),
        to: const PortRef(nodeId: 'n3', port: 'left'),
        kind: EdgeKind.data,
      );

      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
      final restored = BlueprintScript.fromJson(json);

      expect(restored.name, '测试脚本');
      expect(restored.variables['found'], true);
      expect(restored.variables['score'], 3.14);
      expect(restored.variables['label'], 'hello');
      expect(restored.nodes.length, 3);
      expect(restored.edges.length, 2);

      final n2 = restored.nodes['n2']!;
      expect(n2.params['x'], 500);
      expect(n2.params['fingers'], 3);
      expect(n2.params['button'], 'right');
      expect(n2.x, 200);
      expect(n2.y, 120);

      final e2 = restored.edges['e2']!;
      expect(e2.kind, EdgeKind.data);
      expect(e2.from.nodeId, 'n2');
      expect(e2.to.port, 'left');
    });

    test('JSON 字符串直接解析（导出格式）', () {
      const raw = '''
{
  "format": "bpc",
  "version": 1,
  "name": "导入测试",
  "updatedAt": "2026-01-01T10:00:00.000",
  "createdAt": "2026-01-01T09:00:00.000",
  "variables": {"a": 1},
  "nodes": [
    {"id": "x1", "type": "start", "x": 0.0, "y": 0.0, "params": {}},
    {"id": "x2", "type": "delay", "x": 300.0, "y": 0.0, "params": {"ms": 100}}
  ],
  "edges": [
    {"id": "xe", "from": {"node": "x1", "port": "out"}, "to": {"node": "x2", "port": "in"}, "kind": "exec"}
  ]
}
''';
      final s = BlueprintScript.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      expect(s.nodes.length, 2);
      expect(s.findStart()!.id, 'x1');
      expect(s.nodes['x2']!.params['ms'], 100);
      // 二次序列化保持一致
      final again = BlueprintScript.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(again.toJson()['nodes'].toString(), s.toJson()['nodes'].toString());
    });

    test('录制转蓝图：动作序列生成节点与延时', () {
      final rec = Recording(
        id: 'r1',
        name: '测试录制',
        createdAt: DateTime(2026, 1, 1),
        actions: const [
          RecClick(0, 100, 200, count: 2),
          RecSwipe(1500, 0, 0, 300, 400, 250),
          RecLongPress(3200, 50, 60, 900),
        ],
      );
      final bp = rec.toBlueprint();
      expect(bp.findStart(), isNotNull);
      // 3 动作节点 + 2 个插入延时（间隔>80ms）+ 1 start
      expect(bp.nodes.values.where((n) => n.type == 'click').length, 1);
      expect(bp.nodes.values.where((n) => n.type == 'swipe').length, 1);
      expect(bp.nodes.values.where((n) => n.type == 'longPress').length, 1);
      expect(bp.nodes.values.where((n) => n.type == 'delay').length, 2);
      // 执行链连续：从 start 沿 exec 边可遍历全部动作节点
      var visited = 0;
      var cur = bp.findStart()!;
      while (true) {
        visited++;
        final next = bp.outEdges(cur.id, 'out', kind: EdgeKind.exec);
        if (next.isEmpty) break;
        cur = bp.nodes[next.first.to.nodeId]!;
      }
      expect(visited, 6);
    });

    test('删除节点时级联删除连接', () {
      final s = BlueprintScript(name: 's');
      s.nodes['a'] = BPNode(id: 'a', type: 'start');
      s.nodes['b'] = BPNode(id: 'b', type: 'delay');
      s.edges['e'] = BPEdge(
          id: 'e',
          from: const PortRef(nodeId: 'a', port: 'out'),
          to: const PortRef(nodeId: 'b', port: 'in'),
          kind: EdgeKind.exec);
      s.removeNode('b');
      expect(s.edges, isEmpty);
    });
  });
}
