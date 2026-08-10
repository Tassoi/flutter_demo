import 'package:flutter_template/features/example/routing/example_route_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExampleRouteContract', () {
    test('builds canonical detail locations', () {
      expect(ExampleRouteContract.detailLocation(1), Uri(path: '/example/1'));
      expect(
        ExampleRouteContract.detailLocation(ExampleRouteContract.maximumItemId),
        Uri(path: '/example/999999999'),
      );
    });

    test('parses only canonical positive item identifiers', () {
      expect(ExampleRouteContract.tryParseItemId('1'), 1);
      expect(
        ExampleRouteContract.tryParseItemId('999999999'),
        ExampleRouteContract.maximumItemId,
      );

      for (final value in <String?>[
        null,
        '',
        ' ',
        '0',
        '-1',
        '+1',
        '01',
        '1.0',
        'item-1',
        '1000000000',
      ]) {
        expect(
          ExampleRouteContract.tryParseItemId(value),
          isNull,
          reason: 'value=$value',
        );
      }
    });

    test('rejects identifiers outside the public location contract', () {
      for (final value in <int>[
        0,
        -1,
        ExampleRouteContract.maximumItemId + 1,
      ]) {
        expect(
          () => ExampleRouteContract.detailLocation(value),
          throwsArgumentError,
          reason: 'value=$value',
        );
      }
    });
  });
}
