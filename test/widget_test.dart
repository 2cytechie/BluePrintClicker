import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:blueprint_clicker/app.dart';

void main() {
  testWidgets('应用启动冒烟：首页渲染脚本区域与入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BlueprintApp()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 功能入口存在
    expect(find.text('蓝图编辑器'), findsWidgets);
    expect(find.text('录制回放'), findsWidgets);
    // 脚本管理区域标题存在
    expect(find.textContaining('脚本'), findsWidgets);
  });

  testWidgets('录制回放页可打开且控件渲染', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BlueprintApp()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('录制回放').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 录制操作区状态徽章与历史记录区存在
    expect(find.textContaining('待机'), findsWidgets);
    expect(find.textContaining('历史记录'), findsWidgets);
  });
}
