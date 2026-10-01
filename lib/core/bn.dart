import 'package:intl/intl.dart';

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Converts ASCII digits in [v] to Bengali digits.
String bn(Object v) => v
    .toString()
    .replaceAllMapped(RegExp(r'\d'), (m) => _bnDigits[int.parse(m[0]!)]);

/// Converts Bengali digits typed by the user back to ASCII.
String en(String s) {
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_bnDigits[i], '$i');
  }
  return out;
}

const _months = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];

String bnDate(DateTime d) => '${bn(d.day)} ${_months[d.month - 1]}, ${bn(d.year)}';
String bnDateShort(DateTime d) => '${bn(d.day)} ${_months[d.month - 1]}';
String bnTime(int h, int m) {
  final p = h < 4 ? 'রাত' : h < 12 ? 'সকাল' : h < 16 ? 'দুপুর' : h < 18 ? 'বিকেল' : h < 20 ? 'সন্ধ্যা' : 'রাত';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$p ${bn(hh)}:${bn(m.toString().padLeft(2, '0'))}';
}

String bnMoney(num v) => '৳ ${bn(NumberFormat('#,##,##0', 'en_IN').format(v))}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime? parseIso(String? s) =>
    (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

String relativeDays(DateTime d) {
  final diff = dateOnly(d).difference(dateOnly(DateTime.now())).inDays;
  if (diff == 0) return 'আজ';
  if (diff == 1) return 'আগামীকাল';
  if (diff == -1) return 'গতকাল';
  return diff > 0 ? '${bn(diff)} দিন পর' : '${bn(-diff)} দিন আগে';
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'শুভ রাত্রি';
  if (h < 12) return 'শুভ সকাল';
  if (h < 16) return 'শুভ দুপুর';
  if (h < 18) return 'শুভ বিকেল';
  return 'শুভ সন্ধ্যা';
}
