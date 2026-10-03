import 'package:flutter/material.dart';

/// 应用配色方案（取自用户提供的色卡）
/// 象牙白 #FFFBF0 主背景 | 月白 #D6ECF0 卡片/面板 | 孔雀蓝 #00A4C5 主强调色
abstract final class AppColors {
  static const ivory = Color(0xFFFFFBF0); // 页面背景
  static const moonWhite = Color(0xFFD6ECF0); // 卡片/面板底色
  static const peacock = Color(0xFF00A4C5); // 主强调色
  static const peacockDark = Color(0xFF007D9C); // 悬停/按下
  static const peacockDeep = Color(0xFF005E75); // 深强调
  static const ink = Color(0xFF17323B); // 主文字
  static const inkSecondary = Color(0xFF4A6672); // 次级文字
  static const outline = Color(0xFFB8D4DC); // 描边
  static const canvasBg = Color(0xFFF4EFE4); // 画布背景（象牙白加深一档）
  static const danger = Color(0xFFC25B4E); // 危险操作（协调砖红）
  static const success = Color(0xFF2E8B6E); // 成功状态（协调青绿）

  /// 五类节点辅助色（孔雀蓝色系协调衍生）
  static const nodeInteraction = Color(0xFF00A4C5); // 交互：孔雀蓝
  static const nodeMedia = Color(0xFF006E8F); // 媒体：深海青
  static const nodeLogic = Color(0xFF4A7BA6); // 逻辑：雾蓝
  static const nodeData = Color(0xFF2E8B7A); // 数据：青玉
  static const nodeScript = Color(0xFF6B7FA3); // 脚本：岩蓝紫

  /// 执行流连线（孔雀蓝）与数据连线（青玉虚线）
  static const execWire = peacock;
  static const dataWire = nodeData;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: AppColors.peacock,
      onPrimary: Colors.white,
      primaryContainer: AppColors.moonWhite,
      onPrimaryContainer: AppColors.peacockDeep,
      secondary: AppColors.nodeData,
      onSecondary: Colors.white,
      surface: AppColors.ivory,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.moonWhite,
      onSurfaceVariant: AppColors.inkSecondary,
      outline: AppColors.outline,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.ivory,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ivory,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.moonWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.peacock,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.peacockDeep,
        side: const BorderSide(color: AppColors.peacock),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 106, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
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
        borderSide: const BorderSide(color: AppColors.peacock, width: 2),
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
      activeTrackColor: AppColors.peacock,
      thumbColor: AppColors.peacockDeep,
      inactiveTrackColor: AppColors.outline,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.peacockDeep,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
