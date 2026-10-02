import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ui/shell.dart';

/// 应用根：主题与布局壳（左侧导航栏 + 右侧内容；编辑器全屏）
class BlueprintApp extends StatelessWidget {
  const BlueprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '蓝图连点器',
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
