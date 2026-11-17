import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String kShots = '/workspace/work/redesign_shots';
final GlobalKey kShotKey = GlobalKey();
bool _fontsLoaded = false;

Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  const String sdk = '/workspace/work/flutter_sdk/bin/cache/artifacts/material_fonts';
  Future<void> fam(String name, List<String> files) async {
    final FontLoader l = FontLoader(name);
    for (final String f in files) {
      final List<int> b = File(f).readAsBytesSync();
      l.addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await l.load();
  }
  final List<String> rob = <String>[
    '$sdk/Roboto-Regular.ttf', '$sdk/Roboto-Bold.ttf', '$sdk/Roboto-Medium.ttf', '$sdk/Roboto-Black.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
  await fam('Roboto', rob);
  await fam('FlutterTest', rob);
  const String a = '/workspace/work/nexora_redesign/assets/fonts';
  await fam('ChakraPetch', <String>['$a/ChakraPetch-Regular.ttf', '$a/ChakraPetch-SemiBold.ttf', '$a/ChakraPetch-Bold.ttf']);
  await fam('Estedad', <String>['$a/Estedad-Regular.ttf', '$a/Estedad-Medium.ttf', '$a/Estedad-Bold.ttf', '$a/Estedad-Black.ttf']);
  await fam('Lalezar', <String>['$a/Lalezar-Regular.ttf']);
  await fam('MaterialIcons', <String>['$sdk/MaterialIcons-Regular.otf']);
}

void phone(WidgetTester tester, {double w = 390, double h = 844, double dpr = 2}) {
  tester.view.physicalSize = Size(w * dpr, h * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget shotApp(Widget child, {ThemeData? theme}) => ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? ThemeData.dark(useMaterial3: true).copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto')),
        home: RepaintBoundary(key: kShotKey, child: Scaffold(backgroundColor: Colors.black, body: child)),
      ),
    );

/// Pumps frames with real time so image decodes finish.
Future<void> settle(WidgetTester tester, {int frames = 30, int realMs = 60}) async {
  for (int i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: realMs)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> precacheAll(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final Element e in find.byType(Image).evaluate()) {
      final Image img = e.widget as Image;
      await precacheImage(img.image, e);
    }
  });
}

Future<void> shoot(WidgetTester tester, String path) async {
  await precacheAll(tester);
  await settle(tester, frames: 6);
  final RenderRepaintBoundary rb = kShotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image im = await rb.toImage(pixelRatio: tester.view.devicePixelRatio);
    final ByteData? bd = await im.toByteData(format: ui.ImageByteFormat.png);
    final File f = File('$kShots/$path');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bd!.buffer.asUint8List());
  });
}
