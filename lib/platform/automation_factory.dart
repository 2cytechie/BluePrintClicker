import 'dart:io';

import 'platform_automation.dart';
import 'windows_automation.dart';

/// 按当前平台返回 PlatformAutomation 实现。
/// Phase 1 仅 Windows；其余平台返回降级实现（拒绝动作并提示）。
PlatformAutomation createAutomation() {
  if (Platform.isWindows) return const WindowsAutomation();
  return const UnsupportedPlatformAutomation('当前平台暂不支持自动化（Android 实现将在后续版本提供）');
}
