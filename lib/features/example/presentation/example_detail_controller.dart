import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_template/core/error/app_error.dart';
import 'package:flutter_template/core/network/network_cancellation_token.dart';
import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_template/features/example/domain/example_repository.dart';

/// 应用组装层为示例 Feature 提供 [ExampleRepository] 的唯一入口。
///
/// production 必须在根 `AppStateScope` override 该 provider；测试也只替换项目接口，不能
/// 注入 Dio、存储插件或平台对象。默认工厂有意不猜测数据源，缺少组装会被 Controller
/// 折叠为稳定未知错误，而不是静默访问真实网络。
final exampleRepositoryProvider = Provider<ExampleRepository>(
  (_) =>
      throw StateError('ExampleRepository must be provided by app assembly.'),
  name: 'exampleRepository',
);

/// 按已验证路由 ID 管理一个示例详情的异步状态。
///
/// 每个 ID 具有独立且自动释放的 [ExampleDetailController]。页面离开后 provider 取消活动
/// 读取并释放状态；再次进入会重新加载，不保留隐式缓存。状态只包含 [ExampleItem]、成功
/// 空值或稳定 [AppError]，不会保存 Repository、取消令牌或底层异常正文。
final exampleDetailProvider = AutoDisposeAsyncNotifierProviderFamily<
  ExampleDetailController,
  ExampleItem?,
  int
>(ExampleDetailController.new, name: 'exampleDetail');

/// 管理单个示例详情的加载、空、错误、重试和销毁行为。
///
/// 首次 [build] 与 [retry] 都只允许一个活动读取。重试会在调用 Repository 前同步发布
/// loading，因而同一事件循环中的重复点击不会并行请求。`ref.onDispose` 取消当前项目令牌；
/// generation 与令牌身份共同阻止依赖重建或页面销毁后的迟到结果覆盖新状态。
///
/// 本 Controller 不控制导航、渲染文案、缓存或客户端生命周期。Repository 的已知
/// `AppError` 保持原语义，未知对象在进入 `AsyncError` 前折叠为 [UnexpectedAppError]。
final class ExampleDetailController
    extends AutoDisposeFamilyAsyncNotifier<ExampleItem?, int> {
  /// 创建由 Riverpod 管理生命周期的示例详情 Controller。
  ///
  /// 调用方不应直接构造或缓存本实例；[exampleDetailProvider] 会为每个 ID 创建并在最后一个
  /// 监听者离开后释放它。Repository 由当前 ProviderScope override 决定。
  ExampleDetailController();

  static const AppErrorMapper _errorMapper = AppErrorMapper();

  NetworkCancellationToken? _activeCancellationToken;
  var _requestGeneration = 0;
  var _isDisposed = false;

  /// 为路由参数 [itemId] 启动首次读取。
  ///
  /// [itemId] 必须为正整数。返回的 Future 由 Riverpod 转换为 loading/data/error；成功
  /// `null` 保持为空数据。Repository override 变化时 Riverpod 重新执行本方法，旧读取会
  /// 先由上一轮 `onDispose` 取消，新一轮不会复用旧结果。
  @override
  Future<ExampleItem?> build(int itemId) async {
    _isDisposed = false;
    NetworkCancellationToken? cancellationToken;
    try {
      _requirePositiveItemId(itemId);
      final repository = ref.watch(exampleRepositoryProvider);
      final generation = ++_requestGeneration;
      cancellationToken = _beginRequest();
      ref.onDispose(_disposeCurrentLifecycle);
      return await _load(
        repository: repository,
        itemId: itemId,
        cancellationToken: cancellationToken,
        generation: generation,
      );
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_errorMapper.fromUnexpected(error), stackTrace);
    } finally {
      _clearActiveToken(cancellationToken);
    }
  }

  /// 在当前失败或空/数据状态后重新读取同一 [arg]。
  ///
  /// loading 期间或 provider 已销毁时调用会立即完成且不创建请求。有效重试先同步发布
  /// `AsyncLoading`，随后读取当前 Repository override；成功、空和稳定错误替换旧状态。
  /// 页面销毁或依赖重建后，返回的 Future 仍会完成，但不会写入已失效状态。
  Future<void> retry() async {
    if (_isDisposed || state.isLoading) {
      return;
    }

    // loading 必须在读取依赖和调用 Repository 之前发布，确保快速重复点击也只能进入一次。
    state = const AsyncLoading<ExampleItem?>();
    final generation = ++_requestGeneration;
    final cancellationToken = _beginRequest();
    try {
      _requirePositiveItemId(arg);
      final repository = ref.read(exampleRepositoryProvider);
      final item = await _load(
        repository: repository,
        itemId: arg,
        cancellationToken: cancellationToken,
        generation: generation,
      );
      if (_isCurrentRequest(generation, cancellationToken)) {
        state = AsyncData<ExampleItem?>(item);
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrentRequest(generation, cancellationToken)) {
        state = AsyncError<ExampleItem?>(
          _errorMapper.fromUnexpected(error),
          stackTrace,
        );
      }
    } finally {
      _clearActiveToken(cancellationToken);
    }
  }

  Future<ExampleItem?> _load({
    required ExampleRepository repository,
    required int itemId,
    required NetworkCancellationToken cancellationToken,
    required int generation,
  }) async {
    try {
      final item = await repository.loadItem(
        itemId: itemId,
        cancellationToken: cancellationToken,
      );
      if (generation != _requestGeneration || cancellationToken.isCancelled) {
        throw const NetworkCancelledError();
      }
      return item;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_errorMapper.fromUnexpected(error), stackTrace);
    }
  }

  NetworkCancellationToken _beginRequest() {
    // 正常状态下旧令牌已经清空；仍先取消非空值，以隔离依赖异常重建或未来修改造成的重叠。
    _activeCancellationToken?.cancel();
    final cancellationToken = NetworkCancellationToken();
    _activeCancellationToken = cancellationToken;
    return cancellationToken;
  }

  void _disposeCurrentLifecycle() {
    _isDisposed = true;
    _requestGeneration++;
    final cancellationToken = _activeCancellationToken;
    _activeCancellationToken = null;
    cancellationToken?.cancel();
  }

  bool _isCurrentRequest(
    int generation,
    NetworkCancellationToken cancellationToken,
  ) {
    return !_isDisposed &&
        generation == _requestGeneration &&
        identical(_activeCancellationToken, cancellationToken) &&
        !cancellationToken.isCancelled;
  }

  void _clearActiveToken(NetworkCancellationToken? cancellationToken) {
    if (cancellationToken != null &&
        identical(_activeCancellationToken, cancellationToken)) {
      _activeCancellationToken = null;
    }
  }

  static void _requirePositiveItemId(int itemId) {
    if (itemId <= 0) {
      throw ArgumentError('Example item ID must be positive.');
    }
  }
}
