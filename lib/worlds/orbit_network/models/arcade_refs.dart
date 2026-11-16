/// Arcade games other worlds can invite to (ids match `/arcade/<gameId>` routes).
class ArcadeGameRef {
  const ArcadeGameRef(this.id, this.nameFa, this.nameEn);
  final String id;
  final String nameFa;
  final String nameEn;
}

const List<ArcadeGameRef> kArcadeGames = <ArcadeGameRef>[
  ArcadeGameRef('finger_soccer', 'فوتبال انگشتی', 'Finger Soccer'),
  ArcadeGameRef('carrom', 'کرم', 'Carrom'),
  ArcadeGameRef('billiards', 'بیلیارد', 'Billiards'),
  ArcadeGameRef('backgammon', 'تخته‌نرد', 'Backgammon'),
  ArcadeGameRef('ludo', 'منچ', 'Ludo'),
  ArcadeGameRef('snakes_ladders', 'مار و پله', 'Snakes & Ladders'),
  ArcadeGameRef('uno', 'اونو', 'UNO'),
  ArcadeGameRef('quiz', 'کوییز', 'Quiz'),
  ArcadeGameRef('mafia', 'مافیا', 'Mafia'),
];

ArcadeGameRef? arcadeGame(String? id) {
  for (final g in kArcadeGames) {
    if (g.id == id) return g;
  }
  return null;
}
