import 'package:flutter_template/features/example/domain/example_item.dart';

/// 创建一个通过领域校验的示例项测试 Fixture。
///
/// 默认值用于与具体文案无关的状态和 Widget 测试；调用方只覆盖当前断言关心的字段。
/// [ExampleItem] 自身的边界与失败校验仍应直接调用构造函数，避免 Fixture 隐藏无效输入。
ExampleItem createExampleItemFixture({
  int id = 1,
  String title = 'Example record',
  String description = 'A neutral description for the selected record.',
}) {
  return ExampleItem(id: id, title: title, description: description);
}
