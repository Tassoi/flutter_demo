import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../../tool/generate_branding.dart';

void main() {
  late BrandingInputs projectInputs;
  late BrandingOutputs firstOutputs;
  late BrandingOutputs secondOutputs;

  setUpAll(() async {
    projectInputs = readBrandingInputs(Directory.current);
    firstOutputs = await buildBrandingOutputs(projectRoot: Directory.current);
    secondOutputs = await buildBrandingOutputs(projectRoot: Directory.current);
  });

  group('品牌源输入预检', () {
    test('真实中性占位源满足尺寸、透明度、权利和唯一配置契约', () {
      expect(validateBrandingInputs(projectInputs), isEmpty);
      expect(projectInputs.sourceImages.keys, <String>{
        'app_icon.png',
        'app_icon_foreground.png',
        'app_icon_background.png',
        'app_icon_monochrome.png',
        'splash_logo.png',
      });
      expect(projectInputs.hasMonochrome, isTrue);
      expect(projectInputs.licenseSource, contains('不得被描述为任何下游项目的正式品牌'));
    });

    test('拒绝伪 PNG、透明完整图和越过 Adaptive Icon 安全区的像素', () {
      final Map<String, Uint8List> fakePng = Map<String, Uint8List>.of(
        projectInputs.sourceImages,
      )..['app_icon.png'] = Uint8List.fromList(<int>[1, 2, 3]);
      final image.Image transparentIcon = image
          .decodePng(projectInputs.sourceImages['app_icon.png']!)!
          .convert(numChannels: 4);
      transparentIcon.setPixelRgba(0, 0, 0, 0, 0, 0);
      final Map<String, Uint8List> alphaSources = Map<String, Uint8List>.of(
          projectInputs.sourceImages,
        )
        ..['app_icon.png'] = Uint8List.fromList(
          image.encodePng(transparentIcon),
        );
      final image.Image unsafeForeground =
          image.decodePng(
            projectInputs.sourceImages['app_icon_foreground.png']!,
          )!;
      unsafeForeground.setPixelRgba(0, 0, 255, 255, 255, 255);
      final Map<String, Uint8List> unsafeSources = Map<String, Uint8List>.of(
          projectInputs.sourceImages,
        )
        ..['app_icon_foreground.png'] = Uint8List.fromList(
          image.encodePng(unsafeForeground),
        );

      expect(
        _violationCodes(
          validateBrandingInputs(_replaceInputs(projectInputs, fakePng)),
        ),
        contains('[BRANDING_PNG_FORMAT]'),
      );
      expect(
        _violationCodes(
          validateBrandingInputs(_replaceInputs(projectInputs, alphaSources)),
        ),
        contains('[BRANDING_IMAGE_ALPHA]'),
      );
      expect(
        _violationCodes(
          validateBrandingInputs(_replaceInputs(projectInputs, unsafeSources)),
        ),
        contains('[BRANDING_ADAPTIVE_SAFE_ZONE]'),
      );
    });

    test('单色图可以成组省略，但彩色单色层和残留配置会失败', () {
      final Map<String, Uint8List> optionalSources = Map<String, Uint8List>.of(
        projectInputs.sourceImages,
      )..remove('app_icon_monochrome.png');
      final String optionalConfiguration = projectInputs.launcherConfiguration
          .replaceFirst(
            '  adaptive_icon_monochrome: '
                'assets/branding/app_icon_monochrome.png\n',
            '',
          );
      final BrandingInputs optional = _replaceInputs(
        projectInputs,
        optionalSources,
        launcherConfiguration: optionalConfiguration,
      );
      expect(validateBrandingInputs(optional), isEmpty);

      final image.Image coloredMonochrome =
          image.decodePng(
            projectInputs.sourceImages['app_icon_monochrome.png']!,
          )!;
      coloredMonochrome.setPixelRgba(256, 256, 255, 0, 0, 255);
      final Map<String, Uint8List> coloredSources = Map<String, Uint8List>.of(
          projectInputs.sourceImages,
        )
        ..['app_icon_monochrome.png'] = Uint8List.fromList(
          image.encodePng(coloredMonochrome),
        );

      expect(
        _violationCodes(
          validateBrandingInputs(_replaceInputs(projectInputs, coloredSources)),
        ),
        contains('[BRANDING_MONOCHROME_COLOR]'),
      );
      expect(
        _violationCodes(
          validateBrandingInputs(
            _replaceInputs(projectInputs, optionalSources),
          ),
        ),
        contains('[BRANDING_LAUNCHER_CONFIG]'),
      );
    });

    test('缺少权利声明或启用非目标平台会在上游工具前失败', () {
      final BrandingInputs missingLicense = BrandingInputs(
        sourceImages: projectInputs.sourceImages,
        licenseSource: '',
        launcherConfiguration: projectInputs.launcherConfiguration,
        splashConfiguration: projectInputs.splashConfiguration,
        pubspecSource: projectInputs.pubspecSource,
      );
      final BrandingInputs webEnabled = _replaceInputs(
        projectInputs,
        projectInputs.sourceImages,
        splashConfiguration: projectInputs.splashConfiguration.replaceFirst(
          '  web: false',
          '  web: true',
        ),
      );

      expect(
        _violationCodes(validateBrandingInputs(missingLicense)),
        contains('[BRANDING_LICENSE_MISSING]'),
      );
      expect(
        _violationCodes(validateBrandingInputs(webEnabled)),
        contains('[BRANDING_SPLASH_VALUE]'),
      );
    });
  });

  group('隔离生成与平台清单', () {
    test('连续两次生成的 73 个文件逐字节一致', () {
      expect(firstOutputs.files.length, 73);
      expect(
        secondOutputs.files.keys,
        unorderedEquals(firstOutputs.files.keys),
      );
      for (final String path in firstOutputs.files.keys) {
        expect(
          secondOutputs.files[path],
          orderedEquals(firstOutputs.files[path]!),
          reason: path,
        );
      }
      for (final String path in <String>[
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        expect(
          utf8.decode(firstOutputs.files[path]!),
          isNot(matches(RegExp(r'[ \t]+$', multiLine: true))),
          reason: '$path 不得保留上游生成的行尾空白。',
        );
      }
      expect(validateBrandingOutputs(firstOutputs), isEmpty);
    });

    test('所有环境只引用公共 Android/iOS 品牌资源', () {
      expect(validateBrandingPlatformContract(Directory.current), isEmpty);
      expect(
        firstOutputs.files.keys,
        everyElement(
          isNot(
            anyOf(contains('/dev/'), contains('/staging/'), contains('/prod/')),
          ),
        ),
      );
      expect(
        firstOutputs.files,
        contains('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'),
      );
      expect(
        firstOutputs.files,
        contains(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
        ),
      );
    });
  });

  group('事务恢复与只读漂移检查', () {
    test('第二个目标安装失败会恢复全部旧字节且不留事务目录', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-branding-rollback-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}${Platform.pathSeparator}.dart_tool').createSync();
      _writeOutputs(root, firstOutputs);
      final List<String> paths = firstOutputs.files.keys.toList()..sort();
      File(_path(root, paths[0])).writeAsBytesSync(<int>[1, 2, 3]);
      File(_path(root, paths[1])).writeAsBytesSync(<int>[4, 5, 6]);
      final Map<String, Uint8List> before = _snapshotOutputs(root, paths);
      var installCount = 0;

      expect(
        () => replaceBrandingOutputs(
          projectRoot: root,
          outputs: firstOutputs,
          beforeInstall: (String _) {
            installCount += 1;
            if (installCount == 2) {
              throw const FileSystemException('injected install failure');
            }
          },
        ),
        throwsA(
          isA<BrandingGenerationException>().having(
            (BrandingGenerationException error) => error.violations,
            'violations',
            contains(startsWith('[BRANDING_INSTALL_FAILED]')),
          ),
        ),
      );

      final Map<String, Uint8List> after = _snapshotOutputs(root, paths);
      for (final String path in paths) {
        expect(after[path], orderedEquals(before[path]!), reason: path);
      }
      expect(
        Directory(
          '${root.path}${Platform.pathSeparator}.dart_tool',
        ).listSync().whereType<Directory>().where(
          (Directory entry) => entry.path.contains('branding_install_'),
        ),
        isEmpty,
      );
    });

    test('匹配检查零写入，篡改单文件后只报告该路径过期', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-branding-check-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      _copyPlatformBase(Directory.current, root);
      _writeOutputs(root, firstOutputs);
      final Map<String, DateTime> mtimes = <String, DateTime>{
        for (final String path in firstOutputs.files.keys)
          path: File(_path(root, path)).lastModifiedSync(),
      };

      expect(
        findBrandingOutputDrift(projectRoot: root, expected: firstOutputs),
        isEmpty,
      );
      for (final MapEntry<String, DateTime> entry in mtimes.entries) {
        expect(File(_path(root, entry.key)).lastModifiedSync(), entry.value);
      }

      const String stalePath =
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png';
      File(_path(root, stalePath)).writeAsBytesSync(<int>[9, 8, 7]);
      final List<String> violations = findBrandingOutputDrift(
        projectRoot: root,
        expected: firstOutputs,
      );
      expect(violations, contains('[BRANDING_OUTPUT_STALE] $stalePath 已过期。'));
      expect(
        violations.where((String value) => value.contains('已过期')),
        hasLength(1),
      );
    });

    test('受管 Asset Catalog 的未知文件会失败而不会被自动删除', () {
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-branding-extra-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      _copyPlatformBase(Directory.current, root);
      _writeOutputs(root, firstOutputs);
      const String extraPath =
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/hand-edited.png';
      File(_path(root, extraPath))
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1]);

      expect(
        findBrandingOutputDrift(projectRoot: root, expected: firstOutputs),
        contains(startsWith('[BRANDING_OUTPUT_UNEXPECTED]')),
      );
      expect(File(_path(root, extraPath)).existsSync(), isTrue);
    });

    test('符号链接产物在读取或安装前失败且不触碰链接目标', () {
      const String linkedDirectoryPath = 'ios/Runner/Assets.xcassets';
      const String linkedPath =
          '$linkedDirectoryPath/AppIcon.appiconset/Contents.json';
      const String privateExternalName = 'private-external-name.txt';
      final Directory root = Directory.systemTemp.createTempSync(
        'flutter-template-branding-symlink-',
      );
      final Directory externalRoot = Directory.systemTemp.createTempSync(
        'flutter-template-branding-symlink-target-',
      );
      String? windowsJunctionPath;
      addTearDown(() {
        final String? junctionPath = windowsJunctionPath;
        if (junctionPath != null) {
          Process.runSync('cmd.exe', <String>[
            '/d',
            '/c',
            'rmdir',
            junctionPath,
          ]);
        } else {
          final Link outputLink = Link(_path(root, linkedDirectoryPath));
          if (outputLink.existsSync()) {
            outputLink.deleteSync();
          }
        }
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
        if (externalRoot.existsSync()) {
          externalRoot.deleteSync(recursive: true);
        }
      });
      _copyPlatformBase(Directory.current, root);
      _writeOutputs(root, firstOutputs);
      final Directory linkedDirectory = Directory(
        _path(root, linkedDirectoryPath),
      )..deleteSync(recursive: true);
      for (final MapEntry<String, Uint8List> entry in firstOutputs.files.entries
          .where(
            (MapEntry<String, Uint8List> entry) => entry.key.startsWith(
              '$linkedDirectoryPath/AppIcon.appiconset/',
            ),
          )) {
        final String relativePath = entry.key.substring(
          linkedDirectoryPath.length + 1,
        );
        File(_path(externalRoot, relativePath))
          ..createSync(recursive: true)
          ..writeAsBytesSync(entry.value);
      }
      File(
        _path(externalRoot, 'AppIcon.appiconset/$privateExternalName'),
      ).writeAsBytesSync(<int>[1, 2, 3]);
      final File externalTarget = File(
        _path(externalRoot, 'AppIcon.appiconset/Contents.json'),
      );
      try {
        Link(linkedDirectory.path).createSync(externalRoot.path);
      } on FileSystemException catch (error) {
        if (!Platform.isWindows) {
          markTestSkipped('当前平台不允许创建测试符号链接：${error.osError?.errorCode}');
          return;
        }
        final String junctionPath = linkedDirectory.path;
        final ProcessResult junction = Process.runSync('cmd.exe', <String>[
          '/d',
          '/c',
          'mklink',
          '/J',
          junctionPath,
          externalRoot.path,
        ]);
        if (junction.exitCode != 0) {
          markTestSkipped(
            '当前 Windows 环境不允许创建测试目录联接：'
            '${junction.stdout}${junction.stderr}',
          );
          return;
        }
        windowsJunctionPath = junctionPath;
      }
      final Uint8List externalBytes = externalTarget.readAsBytesSync();

      final List<String> drift = findBrandingOutputDrift(
        projectRoot: root,
        expected: firstOutputs,
      );
      expect(drift, contains(startsWith('[BRANDING_OUTPUT_PATH] $linkedPath')));
      expect(drift.join('\n'), isNot(contains(privateExternalName)));
      expect(
        () => replaceBrandingOutputs(projectRoot: root, outputs: firstOutputs),
        throwsA(
          isA<BrandingGenerationException>()
              .having(
                (BrandingGenerationException error) => error.violations,
                'violations',
                contains(startsWith('[BRANDING_OUTPUT_PATH] $linkedPath')),
              )
              .having(
                (BrandingGenerationException error) =>
                    error.violations.join('\n'),
                'external filenames',
                isNot(contains(privateExternalName)),
              ),
        ),
      );
      expect(externalTarget.readAsBytesSync(), orderedEquals(externalBytes));
      expect(File(_path(root, linkedPath)).existsSync(), isTrue);
      expect(
        Directory(
          '${root.path}${Platform.pathSeparator}.dart_tool',
        ).existsSync(),
        isFalse,
      );
    });
  });
}

BrandingInputs _replaceInputs(
  BrandingInputs original,
  Map<String, Uint8List> sourceImages, {
  String? launcherConfiguration,
  String? splashConfiguration,
}) {
  return BrandingInputs(
    sourceImages: sourceImages,
    licenseSource: original.licenseSource,
    launcherConfiguration:
        launcherConfiguration ?? original.launcherConfiguration,
    splashConfiguration: splashConfiguration ?? original.splashConfiguration,
    pubspecSource: original.pubspecSource,
  );
}

Set<String> _violationCodes(List<String> violations) {
  return violations
      .map((String violation) => violation.split(' ').first)
      .toSet();
}

void _writeOutputs(Directory root, BrandingOutputs outputs) {
  for (final MapEntry<String, Uint8List> entry in outputs.files.entries) {
    final File file = File(_path(root, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.value);
  }
}

Map<String, Uint8List> _snapshotOutputs(
  Directory root,
  Iterable<String> paths,
) {
  return <String, Uint8List>{
    for (final String path in paths)
      path: Uint8List.fromList(File(_path(root, path)).readAsBytesSync()),
  };
}

void _copyPlatformBase(Directory sourceRoot, Directory targetRoot) {
  const List<String> files = <String>[
    'android/app/src/main/AndroidManifest.xml',
    'android/app/src/main/res/drawable/launch_background.xml',
    'android/app/src/main/res/drawable-v21/launch_background.xml',
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
    'ios/Runner.xcodeproj/project.pbxproj',
    'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    'ios/Runner/Info.plist',
  ];
  for (final String path in files) {
    final File target = File(_path(targetRoot, path));
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(File(_path(sourceRoot, path)).readAsBytesSync());
  }
  for (final String directory in <String>[
    'ios/Runner/Assets.xcassets/AppIcon.appiconset',
    'ios/Runner/Assets.xcassets/LaunchImage.imageset',
  ]) {
    Directory(_path(targetRoot, directory)).createSync(recursive: true);
  }
}

String _path(Directory root, String relativePath) {
  return '${root.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}';
}
