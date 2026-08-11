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
          'lib/app/localization/generated/app_localizations.dart':
              "import 'package:flutter_localizations/flutter_localizations.dart';\n"
              "import 'app_localizations_en.dart';\n"
              "import 'app_localizations_zh.dart';",
          'lib/app/localization/generated/app_localizations_en.dart':
              "import 'package:intl/intl.dart';\n"
              "import 'app_localizations.dart';",
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

    test('confines screen adaptation package to the project adapter', () {
      final List<String> accepted = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/shared/layout/app_screen_adaptation.dart':
              "import 'package:flutter_screenutil/flutter_screenutil.dart';",
        },
      );
      final List<String> rejected = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/features/catalog/presentation/catalog_page.dart':
              "import 'package:flutter_screenutil/flutter_screenutil.dart';",
        },
      );

      expect(accepted, isEmpty);
      expect(rejected, hasLength(1));
      expect(rejected.single, startsWith('[ARCH_ADAPTER_BOUNDARY]'));
      expect(rejected.single, contains('app_screen_adaptation.dart'));
    });

    test('confines intl packages to Flutter localization outputs', () {
      final List<String> violations = validateArchitecture(
        packageName: 'template_app',
        sources: <String, String>{
          'lib/app/localization/app_locale.dart':
              "import 'package:intl/intl.dart';",
          'lib/features/catalog/presentation/catalog_page.dart':
              "import 'package:flutter_localizations/flutter_localizations.dart';",
        },
      );

      expect(violations, hasLength(2));
      expect(
        violations.every(
          (String violation) =>
              violation.startsWith('[ARCH_LOCALIZATION_BOUNDARY]'),
        ),
        isTrue,
      );
    });

    test(
      'rejects font and branding generation dependencies from runtime code',
      () {
        final List<String> violations = validateArchitecture(
          packageName: 'template_app',
          sources: <String, String>{
            'lib/shared/assets/icon_font.dart':
                "import 'package:icon_font_generator/icon_font_generator.dart';",
            'lib/core/config/xml_reader.dart': "import 'package:xml/xml.dart';",
            'lib/app/config/yaml_reader.dart':
                "import 'package:yaml/yaml.dart';",
            'lib/app/branding/launcher.dart':
                "import 'package:flutter_launcher_icons/main.dart';",
            'lib/app/branding/splash.dart':
                "import 'package:flutter_native_splash/cli_commands.dart';",
            'lib/shared/assets/image_reader.dart':
                "import 'package:image/image.dart';",
          },
        );

        expect(violations, hasLength(6));
        expect(
          violations.every(
            (String violation) =>
                violation.startsWith('[ARCH_TOOL_DEPENDENCY]'),
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects relative imports outside the exact generated relationships',
      () {
        final List<String> violations = validateArchitecture(
          packageName: 'template_app',
          sources: <String, String>{
            'lib/app/localization/generated/app_localizations_en.dart':
                "import '../app_locale.dart';",
            'lib/app/localization/generated/unexpected.dart':
                "import 'app_localizations.dart';",
          },
        );

        expect(violations, hasLength(2));
        expect(
          violations.every(
            (String violation) =>
                violation.startsWith('[ARCH_RELATIVE_IMPORT]'),
          ),
          isTrue,
        );
      },
    );
  });
}
