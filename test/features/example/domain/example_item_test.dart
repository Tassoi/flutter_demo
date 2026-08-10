import 'package:flutter_template/features/example/domain/example_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes readable values and keeps diagnostics content-free', () {
    final item = ExampleItem(
      id: 7,
      title: '  Example record  ',
      description: '  A neutral description.  ',
    );

    expect(item.id, 7);
    expect(item.title, 'Example record');
    expect(item.description, 'A neutral description.');
    expect(item.toString(), contains('id: 7'));
    expect(item.toString(), isNot(contains('neutral description')));
  });

  test('rejects invalid identifiers and unreadable or oversized text', () {
    final oversizedTitle =
        List<String>.filled(ExampleItem.maximumTitleLength + 1, 'x').join();
    final oversizedDescription =
        List<String>.filled(
          ExampleItem.maximumDescriptionLength + 1,
          'x',
        ).join();

    for (final create in <ExampleItem Function()>[
      () => ExampleItem(id: 0, title: 'Title', description: 'Description'),
      () => ExampleItem(id: 1, title: ' ', description: 'Description'),
      () => ExampleItem(id: 1, title: 'Title', description: '\n\t'),
      () =>
          ExampleItem(id: 1, title: oversizedTitle, description: 'Description'),
      () =>
          ExampleItem(id: 1, title: 'Title', description: oversizedDescription),
    ]) {
      expect(create, throwsArgumentError);
    }
  });

  test('validation failures never echo rejected text', () {
    const privateValue = 'private-example-description-token';

    expect(
      () => ExampleItem(id: 1, title: ' ', description: privateValue),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(privateValue)),
        ),
      ),
    );
  });
}
