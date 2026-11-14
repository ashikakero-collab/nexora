// Asset lookup helpers (paths generated in assets_gen.dart from the RN asset map).
import '../game/data.dart';
import 'assets_gen.dart';
export 'assets_gen.dart';

String teamImg(Team t) => kTEAM_IMG[teamKey(t)] ?? kTEAM_IMG['club00']!;
String teamImgById(String id) => teamImg(teamById(id));
String ballImg(int i) => kBALL_IMG['b$i'] ?? kBALL_IMG['b0']!;
String fieldImg(int i) => kFIELD_IMG[kFields[i].id]!;
String fieldThumb(int i) => kFIELD_THUMB[kFields[i].id]!;
String ui(String k) => kUI[k]!;
String ui2(String k) => kUI2[k]!;
String menu(String k) => kMENU[k]!;
String oracleImg(String k) => kORACLE[k] ?? kORACLE['idle']!;

/// Art sliced from the owner's UI sheets (tool/slice_sheets.py).
String kit(String k) => 'assets/g/kit/k_$k.webp';
String world(String k) => 'assets/g/kit/w_$k.webp';
const discRing = 'assets/g/kit/disc_ring.webp';
