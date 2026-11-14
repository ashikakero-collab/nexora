// Dev-only UI snapshots: flutter test tool/snap/ui_snap_test.dart -> /tmp/nx_ui_<name>_<w>x<h>.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/intro/intro.dart';
import 'package:nexora/screens/home.dart';
import 'package:nexora/screens/play.dart';
import 'package:nexora/screens/team.dart';
import 'package:nexora/ui/chrome.dart';
import 'package:nexora/ui/v4.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _fonts() async {
  for (final (f, a) in [('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf'), ('Orbitron', 'assets/fonts/Orbitron-VF.ttf'), ('Exo2', 'assets/fonts/Exo2-VF.ttf'), ('Oxanium', 'assets/fonts/Oxanium-VF.ttf')]) {
    final l = FontLoader(f)..addFont(rootBundle.load(a));
    await l.load();
  }
}

final _rb = GlobalKey();

Future<void> _snap(WidgetTester t, String name, Widget w, Size phys, double dpr, {Duration settle = const Duration(milliseconds: 1500)}) async {
  t.view.physicalSize = phys;
  t.view.devicePixelRatio = dpr;
  await t.pumpWidget(RepaintBoundary(key: _rb, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Exo2'), home: w)));
  await t.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 50));
    }
  });
  await t.pump(settle);
  await t.runAsync(() async {
    final ro = _rb.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final im = await ro.toImage(pixelRatio: 1);
    final bd = await im.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/nx_ui_${name}_${phys.width.round()}x${phys.height.round()}.png').writeAsBytesSync(bd!.buffer.asUint8List());
  });
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

Widget _home() => Builder(builder: (ctx) {
      final ins = MediaQuery.paddingOf(ctx);
      return Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: SpaceBg()),
          Positioned.fill(
              child: HomeScreen(top: ins.top + 66, bottom: kNavH + 14, onWorld: (_) {}, onQuick: () {}, onDaily: () {}, onChest: () {}, dailyReady: true, chestReady: false)),
          Positioned(left: 0, right: 0, top: 0, child: Hud(onProfile: () {}, onShop: () {}, onDaily: () {}, onOracle: () {}, dailyReady: true)),
          Positioned(left: 0, right: 0, bottom: 0, child: NeonNavBar(tab: NavTab.home, onTab: (_) {})),
        ]),
      );
    });

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
    await _fonts();
  });
  for (final (phys, dpr) in [(const Size(1080, 2400), 2.75), (const Size(720, 1280), 2.0)]) {
    testWidgets('home ${phys.width}', (t) async => _snap(t, 'home', _home(), phys, dpr));
    testWidgets('play ${phys.width}', (t) async => _snap(t, 'play', PlayScreen(onMode: (_) {}, onOnline: (_) {}), phys, dpr));
    testWidgets('team ${phys.width}', (t) async => _snap(t, 'team', const TeamScreen(), phys, dpr));
  }
  testWidgets('intro', (t) async => _snap(t, 'intro', Intro(onDone: () {}), const Size(1080, 2400), 2.75, settle: const Duration(milliseconds: 4300)));
}
