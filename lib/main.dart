// NEXORA (Flutter port) entry point: boot services, then the app shell (lib/app/shell.dart, port of App.tsx).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/shell.dart';
import 'core/sound.dart';
import 'core/store.dart';
import 'net/auth.dart';
import 'net/discs.dart';
import 'net/supabase.dart';
import 'oracle/oracle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([Store.i.load(), initSupabase()]);
  Auth.i.init();
  Discs.i.init();
  Sound.init();
  Oracle.i.init();
  runApp(const NexoraApp());
}
