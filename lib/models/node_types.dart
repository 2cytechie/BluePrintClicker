import 'package:flutter/material.dart';
import '../core/theme.dart';

/// 节点大类
enum NodeCategory { interaction, media, logic, data, script }

extension NodeCategoryX on NodeCategory {
  String get label => switch (this) {
        NodeCategory.interaction => '交互',
        NodeCategory.media => '媒体',
        NodeCategory.logic => '逻辑',
        NodeCategory.data => '数据',
        NodeCategory.script => '脚本',
      };
  Color get color => switch (this) {
        NodeCategory.interaction => AppColors.nodeInteraction,
        NodeCategory.media => AppColors.nodeMedia,
        NodeCategory.logic => AppColors.nodeLogic,
        NodeCategory.data => AppColors.nodeData,
        NodeCategory.script => AppColors.nodeScript,
      };
  IconData get icon => switch (this) {
        NodeCategory.interaction => Icons.touch_app_rounded,
        NodeCategory.media => Icons.photo_camera_outlined,
        NodeCategory.logic => Icons.account_tree_outlined,
        NodeCategory.data => Icons.dataset_outlined,
        NodeCategory.script => Icons.code_rounded,
      };
}

enum PortKind { exec, data }

enum PortDir { input, output }

class PortDef {
  final String key;
  final PortKind kind;
  final PortDir dir;
  final String label;
  const PortDef(this.key, this.kind, this.dir, this.label);
  Map<String, dynamic> toJson() => {'key': key, 'kind': kind.name, 'dir': dir.name, 'label': label};
}

/// 参数字段类型（驱动属性面板渲染）
enum ParamType { int, double, string, bool, enum_, varName, templateFile }

class EnumOption {
  final String value;
  final String label;
  const EnumOption(this.value, this.label);
}

class ParamFieldDef {
  final String key;
  final String label;
  final ParamType type;
  final Object? defaultValue;
  final List<EnumOption> options;
  final String? hint;
  const ParamFieldDef(this.key, this.label, this.type, {this.defaultValue, this.options = const [], this.hint});
}

class NodeTypeDef {
  final String type;
  final String title;
  final NodeCategory category;
  final IconData icon;
  final List<PortDef> inputs;
  final List<PortDef> outputs;
  final List<ParamFieldDef> params;
  final String description;
  const NodeTypeDef({
    required this.type,
    required this.title,
    required this.category,
    required this.icon,
    required this.inputs,
    required this.outputs,
    required this.params,
    this.description = '',
  });
}

// ---- 端口定义快捷构造 ----
PortDef _inExec([String key = 'in', String label = '']) => PortDef(key, PortKind.exec, PortDir.input, label);
PortDef _outExec([String key = 'out', String label = '']) => PortDef(key, PortKind.exec, PortDir.output, label);
PortDef _inData(String key, String label) => PortDef(key, PortKind.data, PortDir.input, label);
PortDef _outData(String key, String label) => PortDef(key, PortKind.data, PortDir.output, label);

const _regionFields = [
  ParamFieldDef('useRegion', '仅指定区域', ParamType.bool, defaultValue: false),
  ParamFieldDef('rx', '区域X', ParamType.int, defaultValue: 0),
  ParamFieldDef('ry', '区域Y', ParamType.int, defaultValue: 0),
  ParamFieldDef('rw', '区域宽', ParamType.int, defaultValue: 400),
  ParamFieldDef('rh', '区域高', ParamType.int, defaultValue: 300),
];

/// 全部节点类型定义表（编辑器 / 属性面板 / 执行引擎共用）
final List<NodeTypeDef> kNodeTypes = [
  NodeTypeDef(
    type: 'start',
    title: '开始',
    category: NodeCategory.script,
    icon: Icons.play_arrow_rounded,
    description: '脚本执行入口，每个蓝图需要一个开始节点',
    inputs: [],
    outputs: [_outExec()],
    params: [],
  ),
  NodeTypeDef(
    type: 'click',
    title: '点击',
    category: NodeCategory.interaction,
    icon: Icons.ads_click_rounded,
    description: '在指定坐标模拟鼠标点击，多指以快速连点序列模拟',
    inputs: [_inExec()],
    outputs: [_outExec()],
    params: [
      ParamFieldDef('x', 'X 坐标', ParamType.int, defaultValue: 100),
      ParamFieldDef('y', 'Y 坐标', ParamType.int, defaultValue: 100),
      ParamFieldDef('fingers', '点击次数(多指)', ParamType.int, defaultValue: 1, hint: '1=单击，n=连点 n 次'),
      ParamFieldDef('button', '鼠标键', ParamType.enum_,
          defaultValue: 'left', options: [EnumOption('left', '左键'), EnumOption('right', '右键')]),
    ],
  ),
  NodeTypeDef(
    type: 'swipe',
    title: '滑动',
    category: NodeCategory.interaction,
    icon: Icons.swipe_rounded,
    description: '从起点滑动到终点（坐标模式）或按方向与距离滑动（方向模式）',
    inputs: [_inExec()],
    outputs: [_outExec()],
    params: [
      ParamFieldDef('mode', '模式', ParamType.enum_,
          defaultValue: 'coords',
          options: [EnumOption('coords', '起点终点'), EnumOption('direction', '方向距离')]),
      ParamFieldDef('startX', '起点X', ParamType.int, defaultValue: 400),
      ParamFieldDef('startY', '起点Y', ParamType.int, defaultValue: 300),
      ParamFieldDef('endX', '终点X', ParamType.int, defaultValue: 600),
      ParamFieldDef('endY', '终点Y', ParamType.int, defaultValue: 300),
      ParamFieldDef('angle', '方向角(度,0=右,逆时针)', ParamType.double, defaultValue: 0),
      ParamFieldDef('distance', '距离(px)', ParamType.int, defaultValue: 200),
      ParamFieldDef('durationMs', '时长(ms)', ParamType.int, defaultValue: 300),
    ],
  ),
  NodeTypeDef(
    type: 'longPress',
    title: '长按',
    category: NodeCategory.interaction,
    icon: Icons.pan_tool_rounded,
    description: '在指定坐标按下鼠标并保持指定时长',
    inputs: [_inExec()],
    outputs: [_outExec()],
    params: [
      ParamFieldDef('x', 'X 坐标', ParamType.int, defaultValue: 100),
      ParamFieldDef('y', 'Y 坐标', ParamType.int, defaultValue: 100),
      ParamFieldDef('durationMs', '时长(ms)', ParamType.int, defaultValue: 800),
    ],
  ),
  NodeTypeDef(
    type: 'screenshot',
    title: '截图',
    category: NodeCategory.media,
    icon: Icons.screenshot_monitor_rounded,
    description: '截取全屏或指定区域，供后续识别节点使用',
    inputs: [_inExec(), _inData('image', '输入图像(可空)')],
    outputs: [_outExec(), _outData('imageOut', '图像')],
    params: _regionFields,
  ),
  NodeTypeDef(
    type: 'ocr',
    title: '文字识别',
    category: NodeCategory.media,
    icon: Icons.text_fields_rounded,
    description: '对图像/屏幕区域进行 OCR，文本写入变量',
    inputs: [_inExec(), _inData('image', '输入图像(可空)')],
    outputs: [_outExec(), _outData('text', '文本'), _outData('x', '区域X'), _outData('y', '区域Y')],
    params: [
      ..._regionFields,
      ParamFieldDef('resultVar', '文本存入变量', ParamType.varName, defaultValue: 'ocrText'),
    ],
  ),
  NodeTypeDef(
    type: 'imageMatch',
    title: '图像识别',
    category: NodeCategory.media,
    icon: Icons.image_search_rounded,
    description: '在屏幕/图像中匹配模板图（游戏UI元素），命中结果写入变量',
    inputs: [_inExec(), _inData('image', '输入图像(可空)')],
    outputs: [_outExec(), _outData('found', '是否命中'), _outData('x', '命中X'), _outData('y', '命中Y'), _outData('score', '相似度')],
    params: [
      ParamFieldDef('templatePath', '模板图片', ParamType.templateFile, defaultValue: ''),
      ParamFieldDef('threshold', '相似度阈值', ParamType.double, defaultValue: 0.8),
      ..._regionFields,
      ParamFieldDef('foundVar', '命中标志存入变量', ParamType.varName, defaultValue: 'found'),
      ParamFieldDef('posXVar', '命中X存入变量', ParamType.varName, defaultValue: 'matchX'),
      ParamFieldDef('posYVar', '命中Y存入变量', ParamType.varName, defaultValue: 'matchY'),
    ],
  ),
  NodeTypeDef(
    type: 'condition',
    title: '条件判断',
    category: NodeCategory.logic,
    icon: Icons.call_split_rounded,
    description: '比较两个值，执行流走向 true 或 false 出口',
    inputs: [_inExec(), _inData('left', '左值'), _inData('right', '右值')],
    outputs: [PortDef('true', PortKind.exec, PortDir.output, '真'), PortDef('false', PortKind.exec, PortDir.output, '假')],
    params: [
      ParamFieldDef('op', '比较方式', ParamType.enum_,
          defaultValue: '==',
          options: [
            EnumOption('==', '等于'),
            EnumOption('!=', '不等于'),
            EnumOption('>', '大于'),
            EnumOption('<', '小于'),
            EnumOption('>=', '大于等于'),
            EnumOption('<=', '小于等于'),
            EnumOption('contains', '包含'),
          ]),
      ParamFieldDef('leftVar', '左值变量名(可空)', ParamType.varName, defaultValue: ''),
      ParamFieldDef('rightVar', '右值变量名(可空)', ParamType.varName, defaultValue: ''),
      ParamFieldDef('leftConst', '左值常量(无连接/变量时)', ParamType.string, defaultValue: ''),
      ParamFieldDef('rightConst', '右值常量(无连接/变量时)', ParamType.string, defaultValue: ''),
    ],
  ),
  NodeTypeDef(
    type: 'loop',
    title: '循环',
    category: NodeCategory.logic,
    icon: Icons.loop_rounded,
    description: '循环执行 body 分支，次数为 0 表示无限循环；体内最后节点连回 continue 输入',
    inputs: [_inExec('enter', '进入'), _inExec('continue', '体返回')],
    outputs: [PortDef('body', PortKind.exec, PortDir.output, '循环体'), PortDef('done', PortKind.exec, PortDir.output, '完成')],
    params: [
      ParamFieldDef('count', '循环次数(0=无限)', ParamType.int, defaultValue: 3),
    ],
  ),
  NodeTypeDef(
    type: 'delay',
    title: '延时',
    category: NodeCategory.logic,
    icon: Icons.timer_outlined,
    description: '等待指定毫秒后继续执行',
    inputs: [_inExec()],
    outputs: [_outExec()],
    params: [ParamFieldDef('ms', '等待毫秒', ParamType.int, defaultValue: 500)],
  ),
  NodeTypeDef(
    type: 'setVar',
    title: '设置变量',
    category: NodeCategory.data,
    icon: Icons.calculate_rounded,
    description: '新建或修改变量（数字/字符串/布尔自动推断）',
    inputs: [_inExec(), _inData('value', '值')],
    outputs: [_outExec(), _outData('valueOut', '值')],
    params: [
      ParamFieldDef('name', '变量名', ParamType.varName, defaultValue: 'myVar'),
      ParamFieldDef('const', '常量值(无连接时)', ParamType.string, defaultValue: ''),
    ],
  ),
  NodeTypeDef(
    type: 'storage',
    title: '数据存取',
    category: NodeCategory.data,
    icon: Icons.save_outlined,
    description: '将变量持久化保存到磁盘，或从磁盘读取（键值对 JSON 数据文件）',
    inputs: [_inExec(), _inData('value', '保存值')],
    outputs: [_outExec(), _outData('valueOut', '读取值')],
    params: [
      ParamFieldDef('action', '操作', ParamType.enum_,
          defaultValue: 'save', options: [EnumOption('save', '保存'), EnumOption('load', '读取')]),
      ParamFieldDef('key', '存储键', ParamType.string, defaultValue: 'myKey'),
      ParamFieldDef('name', '关联变量名', ParamType.varName, defaultValue: 'myVar'),
    ],
  ),
  NodeTypeDef(
    type: 'subScript',
    title: '子脚本',
    category: NodeCategory.script,
    icon: Icons.subdirectory_arrow_right_rounded,
    description: '调用已保存的其他脚本（独立变量表，递归深度上限 8）',
    inputs: [_inExec()],
    outputs: [_outExec()],
    params: [ParamFieldDef('scriptName', '脚本名称', ParamType.string, defaultValue: '')],
  ),
];

final Map<String, NodeTypeDef> kNodeTypesById = {for (final t in kNodeTypes) t.type: t};

NodeTypeDef nodeDef(String type) => kNodeTypesById[type] ?? kNodeTypesById['delay']!;
