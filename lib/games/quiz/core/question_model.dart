/// NEXORA Quiz question model (pure Dart).
enum QuizCategory { space, science, geography, history, sports, technology, iran, general, media }

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.fa,
    required this.en,
    required this.optionsFa,
    required this.optionsEn,
    required this.correct,
  });

  /// Unique, e.g. 'space_001'.
  final String id;
  final QuizCategory category;

  /// 1 easy, 2 medium, 3 hard.
  final int difficulty;
  final String fa;
  final String en;

  /// Exactly 4 options each, same order in both languages.
  final List<String> optionsFa;
  final List<String> optionsEn;

  /// Index 0..3 of the correct option.
  final int correct;
}

String quizCategoryNameFa(QuizCategory c) => switch (c) {
      QuizCategory.space => 'فضا و نجوم',
      QuizCategory.science => 'علوم',
      QuizCategory.geography => 'جغرافیا',
      QuizCategory.history => 'تاریخ',
      QuizCategory.sports => 'ورزش',
      QuizCategory.technology => 'فناوری',
      QuizCategory.iran => 'ایران و فرهنگ پارسی',
      QuizCategory.general => 'دانش عمومی',
      QuizCategory.media => 'فیلم و بازی',
    };

String quizCategoryNameEn(QuizCategory c) => switch (c) {
      QuizCategory.space => 'Space & Astronomy',
      QuizCategory.science => 'Science',
      QuizCategory.geography => 'Geography',
      QuizCategory.history => 'History',
      QuizCategory.sports => 'Sports',
      QuizCategory.technology => 'Technology',
      QuizCategory.iran => 'Iran & Persian culture',
      QuizCategory.general => 'General knowledge',
      QuizCategory.media => 'Movies & Games',
    };
