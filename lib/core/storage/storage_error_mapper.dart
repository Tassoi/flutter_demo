import 'package:flutter_template/core/error/app_error.dart';

/// 把存储边界捕获的异常转换为稳定 [AppError] 的无状态映射器。
///
/// 映射器不导入 shared_preferences、flutter_secure_storage 或平台通道类型。两个 adapter
/// 只按正在执行的明确操作选择映射方法，不根据异常文本猜测原因；原始异常、键和值都不会
/// 进入返回对象。已有 [AppError] 保持原实例，便于测试后端或上游边界保留稳定语义。
final class StorageErrorMapper {
  /// 创建无缓存、无 I/O 的存储错误映射器。
  const StorageErrorMapper();

  /// 映射 adapter 或插件构造阶段的 [error]。
  AppError fromInitialization(Object error) =>
      _preserve(error, const StorageInitializationError());

  /// 映射读取、类型转换或解密阶段的 [error]。
  AppError fromRead(Object error) => _preserve(error, const StorageReadError());

  /// 映射写入或加密阶段的 [error]。
  AppError fromWrite(Object error) =>
      _preserve(error, const StorageWriteError());

  /// 映射删除单个键阶段的 [error]。
  AppError fromDelete(Object error) =>
      _preserve(error, const StorageDeleteError());

  /// 映射清理 adapter 自有范围阶段的 [error]。
  AppError fromClear(Object error) =>
      _preserve(error, const StorageClearError());

  AppError _preserve(Object error, AppError fallback) {
    return error is AppError ? error : fallback;
  }
}
