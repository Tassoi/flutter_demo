import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ci/check_architecture.dart';

void main() {
  group('validateArchitecture', () {
    test('accepts the intended layers and adapter locations', () {
      final List<String> violations = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/main.dart': "import 'package:template_app/app/bootstrap.dart';",
          'lib/app/bootstrap.dart':
              "import 'package:template_app/features/example/domain/item.dart';",
          'lib/core/network/dio_network_client.dart':
              "import 'package:dio/dio.dart';",
          'lib/features/example/domain/item.dart':
              "import 'package:template_app/core/error/error.dart';",
          'lib/features/example/presentation/page.dart':
              "import 'package:flutter_riverpod/flutter_riverpod.dart';",
          'lib/shared/assets/app_assets.dart':
              "import 'package:flutter_svg/flutter_svg.dart';",
        },
      );

      expect(violations, isEmpty);
    });

    test('reports reverse, app, main, and cross-feature dependencies', () {
      final List<String> violations = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/main.dart':
              "import 'package:template_app/core/error/error.dart';",
          'lib/core/error/error.dart':
              "export 'package:template_app/features/orders/domain/order.dart';",
          'lib/features/catalog/domain/item.dart':
              "import 'package:template_app/features/orders/domain/order.dart';",
          'lib/features/catalog/presentation/page.dart':
              "import 'package:template_app/app/router.dart';",
          'lib/shared/design/token.dart':
              "import 'package:template_app/app/theme.dart';",
        },
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[ARCH_CROSS_FEATURE_DEPENDENCY]',
          '[ARCH_FEATURE_APP_DEPENDENCY]',
          '[ARCH_MAIN_BOUNDARY]',
          '[ARCH_REVERSE_DEPENDENCY]',
        }),
      );
    });

    test('rejects relative imports and misplaced third-party adapters', () {
      final List<String> violations = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/core/network/other_client.dart':
              "import 'package:dio/dio.dart';",
          'lib/features/example/domain/item.dart':
              "import 'package:flutter_riverpod/flutter_riverpod.dart';",
          'lib/features/example/domain/traversal.dart':
              "import 'package:template_app/features/%2e%2e/app/router.dart';",
          'lib/shared/design/token.dart': "import '../assets/app_assets.dart';",
        },
      );

      expect(
        violations.map((String violation) => violation.split(' ').first),
        containsAll(<String>{
          '[ARCH_ADAPTER_BOUNDARY]',
          '[ARCH_FEATURE_APP_DEPENDENCY]',
          '[ARCH_RELATIVE_IMPORT]',
          '[ARCH_RIVERPOD_BOUNDARY]',
        }),
      );
    });
  });
}
