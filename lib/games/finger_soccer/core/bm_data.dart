// GENERATED from BERMUDA_NXG www/js/game.js — do not retune. Values are copied 1:1.
// ignore_for_file: lines_longer_than_80_chars

class BmField {
  const BmField(this.id, this.name, this.w0, this.h0, this.l0, this.r0, this.t0, this.b0, this.cs0, this.g0, this.gs);
  final String id, name, gs;
  /// Raw image-space values (before FS scale).
  final int w0, h0, l0, r0, t0, b0, cs0, g0;
}

const List<BmField> kBmFieldsRaw = <BmField>[
  BmField('forest', 'Forest', 1086, 1448, 195, 890, 127, 1311, 702, 130, 'wood'),
  BmField('ice', 'Ice', 1086, 1448, 190, 895, 134, 1308, 700, 132, 'ice'),
  BmField('ocean', 'Ocean', 1086, 1448, 191, 897, 108, 1313, 701, 132, 'blue'),
  BmField('street', 'Street', 1086, 1448, 182, 902, 157, 1313, 706, 134, 'gold'),
  BmField('streetarena', 'Street Arena', 1086, 1448, 194, 888, 117, 1309, 702, 130, 'rope'),
  BmField('lava', 'Lava', 1086, 1448, 200, 884, 127, 1305, 699, 128, 'black'),
  BmField('stadium', 'Stadium', 1086, 1448, 196, 888, 115, 1311, 701, 129, 'white'),
  BmField('checker', 'Checker', 1086, 1448, 193, 890, 102, 1353, 704, 130, 'red'),
  BmField('futsal', 'Futsal', 1086, 1448, 190, 895, 104, 1318, 697, 132, 'gold'),
  BmField('arena', 'Arena', 1086, 1448, 199, 884, 118, 1313, 694, 128, 'red'),
  BmField('arena2', 'Grand Arena', 1086, 1448, 164, 921, 135, 1302, 703, 134, 'gold'),
  BmField('desert', 'Desert', 1086, 1448, 163, 920, 84, 1315, 694, 134, 'black'),
  BmField('grove', 'Grove', 1086, 1448, 172, 918, 108, 1320, 695, 134, 'rope'),
  BmField('pool', 'Pool', 1086, 1448, 160, 925, 98, 1312, 697, 134, 'white'),
  BmField('neon', 'Neon Tech', 1024, 1536, 141, 883, 131, 1385, 745, 139, 'black'),
  BmField('royal', 'Royal', 1024, 1536, 148, 877, 147, 1350, 730, 136, 'gold'),
  BmField('mahogany', 'Mahogany', 1024, 1536, 97, 925, 90, 1393, 729, 155, 'wood'),
  BmField('leather', 'Leather', 1024, 1536, 99, 925, 99, 1405, 730, 154, 'gold'),
  BmField('aqua', 'Aquarium', 1024, 1536, 122, 905, 122, 1390, 742, 146, 'blue'),
  BmField('asphalt', 'Asphalt', 1024, 1536, 97, 925, 113, 1417, 742, 155, 'rope'),
  BmField('court', 'Court', 1024, 1536, 118, 907, 115, 1377, 715, 148, 'white'),
  BmField('cyberbox', 'Cyber Box', 1024, 1536, 118, 906, 108, 1378, 706, 147, 'black'),
  BmField('realmadrid', 'Real Madrid', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'black'),
  BmField('psg', 'Paris SG', 1086, 1448, 204, 881, 115, 1296, 666, 130, 'red'),
  BmField('acmilan', 'AC Milan', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'white'),
  BmField('barcelona', 'FC Barcelona', 1086, 1448, 194, 889, 101, 1329, 721, 130, 'gold'),
  BmField('persepolis', 'Persepolis', 1152, 1536, 207, 943, 135, 1410, 770, 130, 'white'),
  BmField('esteghlal', 'Esteghlal', 1086, 1448, 195, 890, 100, 1322, 690, 130, 'gold'),
  BmField('mancity', 'Man City', 1086, 1448, 195, 889, 102, 1329, 719, 130, 'red'),
];

/// Goal art: [width, height, left post centre, right post centre] (fractions of width).
const Map<String, List<double>> kBmGS = <String, List<double>>{
  'white': <double>[840, 307, 0.0491, 0.9522],
  'wood': <double>[840, 306, 0.0474, 0.9519],
  'ice': <double>[840, 305, 0.0535, 0.9429],
  'black': <double>[840, 235, 0.0521, 0.9527],
  'rope': <double>[840, 246, 0.0493, 0.9528],
  'gold': <double>[840, 237, 0.0431, 0.9521],
  'red': <double>[840, 233, 0.0502, 0.9509],
  'blue': <double>[840, 236, 0.0452, 0.9526],
};

const List<List<Object>> kBmCats = <List<Object>>[
  <Object>['club', 'Clubs', <String>["Real Madrid", "Barcelona", "Manchester City", "Manchester United", "Liverpool", "Arsenal", "Chelsea", "Bayern Munich", "Borussia Dortmund", "Paris Saint-Germain", "Inter Milan", "AC Milan", "Juventus", "Atletico Madrid", "Ajax", "Benfica", "Porto", "Boca Juniors", "River Plate", "Flamengo", "Al Nassr", "Al Hilal", "Roma", "Besiktas", "Tottenham", "Marseille", "Napoli", "Sporting CP", "Sevilla", "Valencia", "PSV"]],
  <Object>['nat', 'National', <String>["Argentina", "Brazil", "France", "Germany", "Portugal", "Spain", "Italy", "England", "Netherlands", "Belgium", "Uruguay", "Sweden", "Poland", "Denmark", "Croatia", "Switzerland", "Mexico", "USA", "Japan", "South Korea", "Australia", "Senegal", "Morocco", "Tunisia", "Egypt", "Iceland", "Iran", "Qatar", "Saudi Arabia", "Colombia"]],
  <Object>['car', 'Cars', <String>["Lamborghini", "Ferrari", "Rolls-Royce", "Mercedes-Benz", "BMW", "Porsche", "Maserati", "Aston Martin", "Bentley", "Bugatti", "Lexus", "Cadillac", "McLaren", "Tesla"]],
  <Object>['lux', 'Luxury', <String>["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski"]],
  <Object>['spt', 'Sports', <String>["Nike", "Adidas", "Puma", "Under Armour", "New Balance", "Reebok", "Jordan", "Asics", "Wilson", "Speedo", "Converse", "Vans", "NBA", "Umbro"]],
];

class BmTrail {
  const BmTrail(this.k, this.c);
  final String k;
  final List<int> c;
}

const List<BmTrail> kBmTR = <BmTrail>[
  BmTrail('bolt', <int>[0xFF19B4FF,0xFF8FE6FF,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFFFF7BD5,0xFF7BD7FF,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF2FE0D0,0xFF9FF7EF,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFF5CB6FF,0xFFBFE3FF,0xFFFFFFFF]),
  BmTrail('smoke', <int>[0xFFE8ECF2,0xFF9AA3B0,0xFFFFFFFF]),
  BmTrail('rainbow', <int>[0xFFFF5B5B,0xFFFFD23A,0xFF5BFF8A,0xFF5BD0FF,0xFFC05BFF]),
  BmTrail('neon', <int>[0xFF4DFF2A,0xFFB6FF9A,0xFFFFFFFF]),
  BmTrail('yin', <int>[0xFFFFFFFF,0xFF9B5CFF,0xFF000000]),
  BmTrail('fire', <int>[0xFFFF8A1F,0xFFFFD24A,0xFFFFF3C4]),
  BmTrail('blade', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFFDBE7FF,0xFF8FB0FF,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFFFF6A1F,0xFFFFB347,0xFFFFF0C8]),
  BmTrail('plasma', <int>[0xFF2F8BFF,0xFF7FC6FF,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFFD9915B,0xFFF2C9A0,0xFFFFF4E6]),
  BmTrail('star', <int>[0xFF2F7BFF,0xFF8FD0FF,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF9B5CFF,0xFFE0B8FF,0xFFFFFFFF]),
  BmTrail('fire', <int>[0xFFE0A82E,0xFFFFE08A,0xFFFFF7D6]),
  BmTrail('bolt', <int>[0xFF2F6BFF,0xFF7FB4FF,0xFFFFFFFF]),
  BmTrail('neon', <int>[0xFF2F8BFF,0xFFE8B84A,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFF1FD6A0,0xFF3B9BFF,0xFFFFFFFF]),
  BmTrail('blade', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('plasma', <int>[0xFF18D8C0,0xFF9FF5E6,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFF2F5BFF,0xFFFFC83A,0xFFFFF3C4]),
  BmTrail('yin', <int>[0xFFFFFFFF,0xFFE0A82E,0xFF000000]),
  BmTrail('smoke', <int>[0xFFFF4A4A,0xFF9AA3B0,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFFE0A82E,0xFFFFF0B0,0xFFFFFFFF]),
  BmTrail('plasma', <int>[0xFF2F8BFF,0xFFC0C8D8,0xFFFFFFFF]),
  BmTrail('ghost', <int>[0xFF9B5CFF,0xFFFFFFFF,0xFFFFFFFF]),
  BmTrail('neon', <int>[0xFF4DFF2A,0xFFC0C8D8,0xFFFFFFFF]),
  BmTrail('blade', <int>[0xFFE8B84A,0xFF2F6BFF,0xFFFFFFFF]),
  BmTrail('fire', <int>[0xFFFF2B3A,0xFFFF8A92,0xFFFFFFFF]),
  BmTrail('ember', <int>[0xFFFF8A1F,0xFFFFD24A,0xFFFFFFFF]),
  BmTrail('wave', <int>[0xFF3B9BFF,0xFF2FE08A,0xFFFFFFFF]),
  BmTrail('prism', <int>[0xFFFF4A7A,0xFF9B5CFF,0xFFFFFFFF]),
  BmTrail('bolt', <int>[0xFF2F6BFF,0xFFFFFFFF,0xFFFFFFFF]),
  BmTrail('star', <int>[0xFFFFD56B,0xFFFFFFFF,0xFFFFFFFF]),
];

const List<String> kBmTRN = <String>["Bolt", "Prism", "Wave", "Starlight", "Smoke", "Rainbow", "Neon", "Yin", "Fire", "Blade", "Ghost", "Ember", "Plasma", "Copper Ghost", "Stardust", "Twilight", "Gold Flame", "Thunder", "Cobalt Neon", "Aurora", "Crimson Blade", "Teal Storm", "Royal Ember", "Gold Yin", "Red Smoke", "Gilded Star", "Noir Chrome", "Violet Strike", "Emerald Edge", "Royal Blue Gold", "Crimson Noir", "Blaze Orange", "Aqua Wave", "Sunset Pro", "Elite Cobalt", "Crown Luxury"];

const List<String> kBmBallN = <String>["Bolt", "Prism", "Wave", "Starlight", "Classic", "Rainbow", "Neon", "Yin", "Fire", "Blade", "Ghost", "Ember", "Plasma", "Noir Copper", "Space Modern", "Purple Sky", "Black Lux", "Electron", "Cobalt Gold", "Aurora", "Crimson", "Teal Storm", "Royal Gold", "Gold Rush", "Classic Red", "Luxury", "Noir Chrome", "Violet Strike", "Emerald Edge", "Royal Blue Gold", "Crimson Noir", "Blaze Orange", "Aqua Wave", "Sunset Pro", "Elite Cobalt", "Crown Luxury"];

class BmFa {
  const BmFa(this.k, this.c, this.g);
  final int k;
  final List<int> c;
  final double g;
}

const Map<String, BmFa> kBmFA = <String, BmFa>{
  'forest': BmFa(2, <int>[0xFF6FD36B,0xFFB8F5A0,0xFF2E8B3A], 130),
  'ice': BmFa(1, <int>[0xFFE8FBFF,0xFF9FE8FF,0xFFFFFFFF], 30),
  'ocean': BmFa(4, <int>[0xFFBFF3FF,0xFF5CD0FF,0xFFFFFFFF], -140),
  'street': BmFa(5, <int>[0xFFFF2BD6,0xFFFFE14A,0xFF2BF0FF], 0),
  'streetarena': BmFa(5, <int>[0xFFFFB02B,0xFFFF3B6B,0xFFFFFFFF], 0),
  'lava': BmFa(0, <int>[0xFFFF5A1F,0xFFFFB347,0xFFFFE08A], -220),
  'stadium': BmFa(1, <int>[0xFFFFD86B,0xFFFFFFFF,0xFFFFE9A8], 0),
  'checker': BmFa(3, <int>[0xFFFFFFFF,0xFF9AA3B0,0xFFFF4040], 0),
  'futsal': BmFa(5, <int>[0xFFFFCF8A,0xFFFFFFFF,0xFFFFA14A], 0),
  'arena': BmFa(5, <int>[0xFF7FB8FF,0xFFFFFFFF,0xFF3B7BFF], 0),
  'arena2': BmFa(1, <int>[0xFFC79BFF,0xFFFFFFFF,0xFF7B4BFF], 0),
  'desert': BmFa(0, <int>[0xFFE8C689,0xFFC99A54,0xFFFFF0C8], 60),
  'grove': BmFa(0, <int>[0xFFD8FF6A,0xFFFFFFA0,0xFF9CF06A], -30),
  'pool': BmFa(0, <int>[0xFF9FE9FF,0xFFE6FBFF,0xFF4CC7FF], 380),
  'neon': BmFa(5, <int>[0xFF7DFF3A,0xFFD6FF9A,0xFFFFFFFF], 0),
  'royal': BmFa(1, <int>[0xFFFFD86B,0xFFFFF3C4,0xFFFF9A3A], 0),
  'mahogany': BmFa(1, <int>[0xFFFFCF8A,0xFFFFF0C8,0xFFD9923A], -20),
  'leather': BmFa(0, <int>[0xFFD9A066,0xFFFFD9A0,0xFF8A5A2A], -30),
  'aqua': BmFa(4, <int>[0xFFBFF3FF,0xFF5CD0FF,0xFFFFFFFF], -150),
  'asphalt': BmFa(5, <int>[0xFFFFE14A,0xFFFFFFFF,0xFFFFB02B], 0),
  'court': BmFa(5, <int>[0xFFFFFFFF,0xFFFFCF8A,0xFF4AA8FF], 0),
  'cyberbox': BmFa(5, <int>[0xFFFF3B3B,0xFF3B8BFF,0xFFFFFFFF], 0),
  'realmadrid': BmFa(1, <int>[0xFFFFFFFF,0xFFFFD86B,0xFF3B6BFF], 0),
  'psg': BmFa(5, <int>[0xFFFF2B3A,0xFF3B6BFF,0xFFFFFFFF], 0),
  'acmilan': BmFa(5, <int>[0xFFFF2B3A,0xFFFFFFFF,0xFF111111], 0),
  'barcelona': BmFa(5, <int>[0xFFFF2B5A,0xFF3B6BFF,0xFFFFD86B], 0),
  'persepolis': BmFa(5, <int>[0xFFFF2B3A,0xFFFFD86B,0xFFFFFFFF], 0),
  'esteghlal': BmFa(1, <int>[0xFF3B8BFF,0xFFFFFFFF,0xFFFFD86B], 0),
  'mancity': BmFa(1, <int>[0xFF7FD0FF,0xFFFFFFFF,0xFF3B8BFF], 0),
};
