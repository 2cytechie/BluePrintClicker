import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:blueprint_clicker/app.dart';

void main() {
  testWidgets('应用启动冒烟：首页渲染脚本区域与入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BlueprintApp()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 功能入口存在
    expect(find.text('快捷连点'), findsWidgets);
    expect(find.text('蓝图编辑器'), findsWidgets);
    // 脚本管理区域标题存在
    expect(find.textContaining('脚本'), findsWidgets);
  });

  testWidgets('快捷连点页可打开且控件渲染', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BlueprintApp()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('快捷连点').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 状态徽章与顶部控件存在（'开始'按钮位于列表深处，懒加载下不构建）
    expect(find.textContaining('待机'), findsWidgets);
    expect(find.textContaining('捕获当前鼠标位置'), findsWidgets);
  });
}
