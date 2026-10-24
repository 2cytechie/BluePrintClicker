import 'package:flutter/material.dart';

/// 应用配色方案（取自用户提供的色卡，深色主题）
/// 深海夜蓝 #28314E 背景 | 柔空蓝 #658AE4 主色 | 薄荷冰青 #A1FEEF 强调色
abstract final class AppColors {
  // —— 背景层次（深海夜蓝衍生） ——
  static const bg = Color(0xFF28314E); // 页面背景（深海夜蓝）
  static const surface = Color(0xFF333F63); // 卡片/面板底色（提亮一档）
  static const inputFill = Color(0xFF3B4870); // 输入框填充（再提亮一档）
  static const canvasBg = Color(0xFF222B47); // 画布背景（压暗一档）

  // —— 主题色：柔空蓝 ——
  static const primary = Color(0xFF658AE4); // 主强调色（柔空蓝）
  static const primaryDark = Color(0xFF5473D6); // 悬停/按下
  static const primaryDeep = Color(0xFF425FC4); // 深强调（亮底上的图标/文字）

  // —— 主题色：薄荷冰青 ——
  static const mint = Color(0xFFA1FEEF); // 强调/激活（滑块、成功态点缀）

  /// 亮色品牌底（柔空蓝/薄荷冰青/危险砖红）上的前景文字：深海军蓝
  static const onTint = Color(0xFF1A2542);

  // —— 文字 ——
  static const ink = Color(0xFFE9EEFB); // 主文字（近白）
  static const inkSecondary = Color(0xFF9BA9CC); // 次级文字（浅蓝灰）

  // —— 线条 ——
  static const outline = Color(0xFF47527C); // 描边/分隔

  // —— 功能色 ——
  static const danger = Color(0xFFE8795F); // 危险操作（砖红提亮适配深底）
  static const success = Color(0xFF5FE0C0); // 成功状态（薄荷青绿，与薄荷冰青协调）

  /// 五类节点辅助色（蓝—青光谱，自柔空蓝/薄荷冰青衍生）
  static const nodeInteraction = Color(0xFF658AE4); // 交互：柔空蓝
  static const nodeMedia = Color(0xFF8FB0F2); // 媒体：浅空蓝
  static const nodeLogic = Color(0xFF5568CE); // 逻辑：雾蓝紫
  static const nodeData = Color(0xFFA1FEEF); // 数据：薄荷冰青
  static const nodeScript = Color(0xFF5ED6C4); // 脚本：青玉薄荷

  /// 执行流连线（柔空蓝）与数据连线（薄荷冰青）
  static const execWire = primary;
  static const dataWire = nodeData;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onTint,
      primaryContainer: AppColors.primaryDeep,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.mint,
      onSecondary: AppColors.onTint,
      surface: AppColors.bg,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.surface,
      onSurfaceVariant: AppColors.inkSecondary,
      outline: AppColors.outline,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surfaceContainerHigh: AppColors.surface,
      surfaceContainerHighest: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 106, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.mint,
      inactiveTrackColor: AppColors.outline,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.primaryDeep,
      contentTextStyle: TextStyle(color: AppColors.ink),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
