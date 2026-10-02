import 'node_types.dart';

/// 蓝图节点实例
class BPNode {
  final String id;
  final String type;
  double x;
  double y;
  final Map<String, dynamic> params;

  BPNode({required this.id, required this.type, this.x = 0, this.y = 0, Map<String, dynamic>? params})
      : params = params ?? _defaultParams(type);

  NodeTypeDef get def => nodeDef(type);
  String get title => def.title;

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'x': x, 'y': y, 'params': params};

  factory BPNode.fromJson(Map<String, dynamic> j) => BPNode(
        id: j['id'] as String,
        type: j['type'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        params: Map<String, dynamic>.from(j['params'] as Map? ?? const {}),
      );

  BPNode copyWith({String? id, double? x, double? y, Map<String, dynamic>? params}) => BPNode(
        id: id ?? this.id,
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        params: params ?? Map.of(this.params),
      );

  /// 生成默认参数（按类型定义）
  static Map<String, dynamic> _defaultParams(String type) {
    final m = <String, dynamic>{};
    for (final f in nodeDef(type).params) {
      m[f.key] = f.defaultValue;
    }
    return m;
  }
}

class PortRef {
  final String nodeId;
  final String port;
  const PortRef({required this.nodeId, required this.port});

  Map<String, dynamic> toJson() => {'node': nodeId, 'port': port};
  factory PortRef.fromJson(Map<String, dynamic> j) =>
      PortRef(nodeId: j['node'] as String, port: j['port'] as String);

  @override
  bool operator ==(Object other) => other is PortRef && other.nodeId == nodeId && other.port == port;
  @override
  int get hashCode => Object.hash(nodeId, port);
  @override
  String toString() => '$nodeId.$port';
}

enum EdgeKind { exec, data }

class BPEdge {
  final String id;
  final PortRef from;
  final PortRef to;
  final EdgeKind kind;
  const BPEdge({required this.id, required this.from, required this.to, required this.kind});

  Map<String, dynamic> toJson() => {'id': id, 'from': from.toJson(), 'to': to.toJson(), 'kind': kind.name};

  factory BPEdge.fromJson(Map<String, dynamic> j) => BPEdge(
        id: j['id'] as String,
        from: PortRef.fromJson(Map<String, dynamic>.from(j['from'] as Map)),
        to: PortRef.fromJson(Map<String, dynamic>.from(j['to'] as Map)),
        kind: j['kind'] == 'data' ? EdgeKind.data : EdgeKind.exec,
      );
}

/// 蓝图脚本
class BlueprintScript {
  String name;
  final Map<String, BPNode> nodes;
  final Map<String, BPEdge> edges;
  /// 脚本级初始变量表
  final Map<String, Object> variables;
  DateTime updatedAt;
  final DateTime createdAt;

  BlueprintScript({
    required this.name,
    Map<String, BPNode>? nodes,
    Map<String, BPEdge>? edges,
    Map<String, Object>? variables,
    DateTime? updatedAt,
    DateTime? createdAt,
  })  : nodes = nodes ?? {},
        edges = edges ?? {},
        variables = variables ?? {},
        updatedAt = updatedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  BPNode? findStart() => nodes.values.where((n) => n.type == 'start').firstOrNull;

  List<BPEdge> outEdges(String nodeId, String port, {EdgeKind? kind}) => edges.values
      .where((e) => e.from.nodeId == nodeId && e.from.port == port && (kind == null || e.kind == kind))
      .toList();

  List<BPEdge> inEdges(String nodeId, String port, {EdgeKind? kind}) => edges.values
      .where((e) => e.to.nodeId == nodeId && e.to.port == port && (kind == null || e.kind == kind))
      .toList();

  void removeNode(String nodeId) {
    nodes.remove(nodeId);
    edges.removeWhere((k, e) => e.from.nodeId == nodeId || e.to.nodeId == nodeId);
  }

  Map<String, dynamic> toJson() => {
        'format': 'bpc',
        'version': 1,
        'name': name,
        'updatedAt': updatedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'variables': variables,
        'nodes': nodes.values.map((n) => n.toJson()).toList(),
        'edges': edges.values.map((e) => e.toJson()).toList(),
      };

  factory BlueprintScript.fromJson(Map<String, dynamic> j) => BlueprintScript(
        name: (j['name'] as String?) ?? '未命名',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        variables: Map<String, Object>.from(j['variables'] as Map? ?? const {}),
        nodes: {
          for (final n in (j['nodes'] as List? ?? []))
            (n as Map<String, dynamic>)['id'] as String: BPNode.fromJson(Map<String, dynamic>.from(n)),
        },
        edges: {
          for (final e in (j['edges'] as List? ?? []))
            (e as Map<String, dynamic>)['id'] as String: BPEdge.fromJson(Map<String, dynamic>.from(e)),
        },
      );

  BlueprintScript copy() => BlueprintScript.fromJson(toJson());
}

/// 录制生成的操作序列（可回放、可转为蓝图节点）
sealed class RecordedAction {
  final int offsetMs;
  const RecordedAction(this.offsetMs);
  Map<String, dynamic> toJson() => {'kind': runtimeType.toString(), 'offsetMs': offsetMs};
}

class RecClick extends RecordedAction {
  final int x, y, count;
  final String button;
  const RecClick(super.offsetMs, this.x, this.y, {this.count = 1, this.button = 'left'});
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'x': x, 'y': y, 'count': count, 'button': button};
}

class RecSwipe extends RecordedAction {
  final int x1, y1, x2, y2, durationMs;
  const RecSwipe(super.offsetMs, this.x1, this.y1, this.x2, this.y2, this.durationMs);
  @override
  Map<String, dynamic> toJson() =>
      {...super.toJson(), 'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'durationMs': durationMs};
}

class RecLongPress extends RecordedAction {
  final int x, y, durationMs;
  const RecLongPress(super.offsetMs, this.x, this.y, this.durationMs);
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'x': x, 'y': y, 'durationMs': durationMs};
}

/// 操作记录（录制会话）
class Recording {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<RecordedAction> actions;
  Recording({required this.id, required this.name, required this.createdAt, required this.actions});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '录制',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        actions: (j['actions'] as List? ?? [])
            .map((a) => _actionFromJson(Map<String, dynamic>.from(a as Map)))
            .whereType<RecordedAction>()
            .toList(),
      );

  static RecordedAction? _actionFromJson(Map<String, dynamic> j) {
    final offset = (j['offsetMs'] as num).toInt();
    switch (j['kind']) {
      case 'RecClick':
        return RecClick(offset, (j['x'] as num).toInt(), (j['y'] as num).toInt(),
            count: (j['count'] as num?)?.toInt() ?? 1, button: j['button'] as String? ?? 'left');
      case 'RecSwipe':
        return RecSwipe(offset, (j['x1'] as num).toInt(), (j['y1'] as num).toInt(),
            (j['x2'] as num).toInt(), (j['y2'] as num).toInt(), (j['durationMs'] as num).toInt());
      case 'RecLongPress':
        return RecLongPress(offset, (j['x'] as num).toInt(), (j['y'] as num).toInt(),
            (j['durationMs'] as num).toInt());
    }
    return null;
  }

  /// 转为可编辑/可运行的蓝图脚本
  BlueprintScript toBlueprint() {
    final s = BlueprintScript(name: name);
    final start = BPNode(id: 'n_start', type: 'start', x: 40, y: 60);
    s.nodes[start.id] = start;
    String prevId = start.id;
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final id = 'n_a$i';
      BPNode node;
      switch (a) {
        case RecClick c:
          node = BPNode(id: id, type: 'click', x: 60 + i * 190.0, y: 160, params: {
            'x': c.x, 'y': c.y, 'fingers': c.count, 'button': c.button,
          });
          // 与下一动作间隔较大时插入延时
        case RecSwipe w:
          node = BPNode(id: id, type: 'swipe', x: 60 + i * 190.0, y: 160, params: {
            'mode': 'coords', 'startX': w.x1, 'startY': w.y1, 'endX': w.x2, 'endY': w.y2,
            'angle': 0.0, 'distance': 200, 'durationMs': w.durationMs,
          });
        case RecLongPress p:
          node = BPNode(id: id, type: 'longPress', x: 60 + i * 190.0, y: 160, params: {
            'x': p.x, 'y': p.y, 'durationMs': p.durationMs,
          });
      }
      s.nodes[id] = node;
      final prevGap = i == 0 ? a.offsetMs : a.offsetMs - actions[i - 1].offsetMs;
      String linkFrom = prevId;
      if (prevGap > 80) {
        final dId = 'n_d$i';
        s.nodes[dId] = BPNode(id: dId, type: 'delay', x: 60 + i * 190.0 - 95, y: 40, params: {'ms': prevGap});
        s.edges['e_${dId}_o'] = BPEdge(id: 'e_${dId}_o',
            from: PortRef(nodeId: linkFrom, port: 'out'),
            to: PortRef(nodeId: dId, port: 'in'), kind: EdgeKind.exec);
        linkFrom = dId;
      }
      s.edges['e_${id}_i'] = BPEdge(id: 'e_${id}_i',
          from: PortRef(nodeId: linkFrom, port: linkFrom == start.id ? 'out' : 'out'),
          to: PortRef(nodeId: id, port: 'in'), kind: EdgeKind.exec);
      prevId = id;
    }
    return s;
  }
}
