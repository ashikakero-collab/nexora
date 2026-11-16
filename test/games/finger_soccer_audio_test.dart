import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/ui/bm_audio.dart';

void main() {
  test('every BERMUDA sound the finger soccer plays exists and is bundled', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('- assets/$kBmSfxDir'), isTrue, reason: 'assets/$kBmSfxDir must be declared in pubspec.yaml');
    final List<String> files = bmSoundFiles();
    // game.js SFXF (12 samples) + 4 rendered tone() blips, 2 crowd ambience clips, menu music
    expect(kBmSfx.length, 16);
    expect(kBmCrowd.keys, containsAll(<String>['crowd-02.mp3', 'crowd-03.mp3']));
    for (final String f in files) {
      final File file = File('assets/$kBmSfxDir$f');
      expect(file.existsSync(), isTrue, reason: 'missing sound asset ${file.path}');
      expect(file.lengthSync(), greaterThan(500), reason: 'empty sound asset ${file.path}');
    }
  });

  test('goal announcer voice is off by default; sounds are not muted by default', () {
    final BmAudio a = BmAudio(enabled: false);
    expect(a.announcer, isFalse);
    expect(a.muted, isFalse);
    a.sfx('goal');
    a.frame(1);
    a.dispose();
  });
}
