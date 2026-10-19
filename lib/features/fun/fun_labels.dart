// O'yinlar va yutuqlar: server o'zbekcha qaytaradigan yorliqlar (tr() bilan tarjima qilinadi) va ikonkalar.
import 'package:flutter/material.dart';

/// Lug'atda bo'lishi kerak bo'lgan server matnlari (daraja nomlari, nishonlar, XP turlari, o'yinlar, laboratoriyalar).
/// tool/i18n_keys.py shu ro'yxatni ham tekshiradi.
const List<String> funServerLabels = <String>[
  'Yangi boshlovchi',
  'Izlanuvchi',
  'Qiziquvchan',
  'Bilimdon',
  'Zukko',
  'Tadqiqotchi',
  'Ekspert',
  'Ustoz darajasi',
  'Chempion',
  'Afsona',
  'Birinchi qadam',
  'Birinchi testni topshirdi',
  "A'lochi",
  'Testda 100% natija',
  'Test ustasi',
  '10 ta test topshirdi',
  'Kitobxon',
  "10 ta onlayn dars o'tdi",
  'Uch kun ketma-ket',
  "3 kun uzluksiz shug'ullandi",
  'Bir hafta uzluksiz',
  "7 kun uzluksiz shug'ullandi",
  "O'yinchi",
  "10 ta o'yin o'ynadi",
  'Tezkor aql',
  "Viktorina-blitsda 10 ta to'g'ri javob",
  'Yosh olim',
  "Birinchi laboratoriya topshirig'ini bajardi",
  'Laborant',
  "5 ta laboratoriya topshirig'i",
  'Intizomli',
  'Darsga 20 marta vaqtida keldi',
  '500 XP',
  "500 tajriba bali to'pladi",
  '2000 XP',
  "2000 tajriba bali to'pladi",
  'Test',
  'Onlayn dars',
  'Uy vazifasi',
  "O'yin",
  'Laboratoriya',
  'Darsga keldi',
  "O'qituvchidan rag'bat",
  'Viktorina-blits',
  'Juftini top',
  "So'z yig'ish",
  'Matematik mayatnik',
  'Gorizontga burchak ostida otish',
  'Om qonuni',
  'Yupqa linza',
  'Kislota-ishqor titrlash',
  'Kvadrat funksiya grafigi',
  'Mendel qonunlari',
  'Fizika',
  'Kimyo',
  'Matematika',
  'Biologiya',
  "Ip uzunligi va tebranish davri orasidagi bog'lanish.",
  "Boshlang'ich tezlik va burchakka qarab uchish uzoqligi.",
  'Kuchlanish, qarshilik va tok kuchi: ampermetr va voltmetr bilan.',
  'Buyum, linza va tasvir: fokus masofasini aniqlash.',
  "Byuretkadan ishqor tomizib, neytrallanish nuqtasini topish.",
  "a, b, c koeffitsiyentlari parabolani qanday o'zgartiradi.",
  "Punnet katagi: belgining avlodda namoyon bo'lish ehtimoli.",
];

const Map<String, String> gameTitleLabels = <String, String>{
  'quiz': 'Viktorina-blits',
  'match': 'Juftini top',
  'scramble': "So'z yig'ish",
};

IconData gameIcon(String game) {
  switch (game) {
    case 'quiz':
      return Icons.bolt_rounded;
    case 'match':
      return Icons.grid_view_rounded;
    default:
      return Icons.abc_rounded;
  }
}

/// Veb-ikonka nomi (lucide) → Material ikonka.
IconData badgeIcon(String name) {
  switch (name) {
    case 'clipboard-list':
      return Icons.assignment_turned_in_rounded;
    case 'star':
      return Icons.star_rounded;
    case 'award':
      return Icons.military_tech_rounded;
    case 'book':
      return Icons.menu_book_rounded;
    case 'zap':
      return Icons.bolt_rounded;
    case 'sparkle':
      return Icons.auto_awesome_rounded;
    case 'timer':
      return Icons.timer_rounded;
    case 'rocket':
      return Icons.rocket_launch_rounded;
    case 'check-circle':
      return Icons.check_circle_rounded;
    case 'trophy':
      return Icons.emoji_events_rounded;
    default:
      return Icons.workspace_premium_rounded;
  }
}

/// "1:05" ko'rinishidagi vaqt.
String clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
