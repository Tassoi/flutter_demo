import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_template/shared/assets/generated/template_icons.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final FontLoader loader = FontLoader(TemplateIcons.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/template_icons.otf'));
    await loader.load();
  });

  test('生成映射保持固定 family 与 codepoint', () {
    expect(TemplateIcons.fontFamily, 'TemplateIcons');
    expect(TemplateIcons.language.fontFamily, TemplateIcons.fontFamily);
    expect(TemplateIcons.language.codePoint, 0xE000);
    expect(TemplateIcons.language.matchTextDirection, isFalse);
    expect(TemplateIcons.check.fontFamily, TemplateIcons.fontFamily);
    expect(TemplateIcons.check.codePoint, 0xE001);
    expect(TemplateIcons.check.matchTextDirection, isFalse);
  });

  testWidgets('已注册 OTF 能渲染两个非空且不同的字形', (tester) async {
    const Key languageKey = Key('template-language-glyph');
    const Key checkKey = Key('template-check-glyph');

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          color: Colors.white,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _GlyphSample(
                boundaryKey: languageKey,
                icon: TemplateIcons.language,
              ),
              _GlyphSample(boundaryKey: checkKey, icon: TemplateIcons.check),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Uint8List languagePixels = await _capturePixels(tester, languageKey);
    final Uint8List checkPixels = await _capturePixels(tester, checkKey);

    expect(_countDarkPixels(languagePixels), greaterThan(50));
    expect(_countDarkPixels(checkPixels), greaterThan(50));
    expect(checkPixels, isNot(orderedEquals(languagePixels)));
    expect(tester.takeException(), isNull);
  });
}

/// 为像素测试提供固定尺寸、背景和重绘边界，不承担业务语义。
final class _GlyphSample extends StatelessWidget {
  const _GlyphSample({required this.boundaryKey, required this.icon});

  final Key boundaryKey;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundaryKey,
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox.square(
          dimension: 64,
          child: Icon(icon, size: 48, color: Colors.black),
        ),
      ),
    );
  }
}

Future<Uint8List> _capturePixels(WidgetTester tester, Key key) async {
  final RenderRepaintBoundary boundary = tester.renderObject(find.byKey(key));
  // 引擎的栅格化与像素读取使用真实异步事件；若留在 Widget 测试的
  // FakeAsync 区域，Future 不会自行推进，整套测试会在此无限等待。
  final Uint8List? pixels = await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw StateError('无法读取图标字体测试像素。');
      }
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
  if (pixels == null) {
    throw StateError('图标字体像素捕获未返回结果。');
  }
  return pixels;
}

int _countDarkPixels(Uint8List pixels) {
  int count = 0;
  for (int offset = 0; offset < pixels.length; offset += 4) {
    if (pixels[offset + 3] > 0 &&
        pixels[offset] < 80 &&
        pixels[offset + 1] < 80 &&
        pixels[offset + 2] < 80) {
      count += 1;
    }
  }
  return count;
}
