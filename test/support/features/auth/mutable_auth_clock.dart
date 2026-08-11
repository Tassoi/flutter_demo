import 'package:flutter_template/features/auth/domain/auth_clock.dart';

/// 认证测试使用的可变 UTC 时钟。
final class MutableAuthClock implements AuthClock {
  /// 以 [currentTime] 创建时钟。
  MutableAuthClock(DateTime currentTime) : currentTime = currentTime.toUtc();

  /// 下一次 [now] 返回的时间；测试可以显式推进。
  DateTime currentTime;

  @override
  DateTime now() => currentTime.toUtc();
}
