import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/core/bn.dart';
import 'package:health_app/data/models.dart';
import 'package:health_app/data/prescription_draft.dart';
import 'package:health_app/features/owner/scan_page.dart';

void main() {
  test('Bengali digit helpers round-trip', () {
    expect(bn(2024), '২০২৪');
    expect(en('১২৩'), '123');
  });

  test('Medicine days-left counts down from the start date', () {
    final today = DateTime.now();
    final m = Medicine(
      memberId: 1, name: 'নাপা', boughtDays: 5, prescribedDays: 10,
      startDate: DateTime(today.year, today.month, today.day).subtract(const Duration(days: 3)),
    );
    expect(m.daysLeft, 2);
    expect(m.toBuyDays, 5);
    expect(m.needsRebuy, isTrue);
  });

  test('product barcode check digit accepts real packs and rejects misreads', () {
    // Photographed medicine packs (Square 894..., another maker 890...)
    expect(validProductCode('8940001285711'), isTrue);
    expect(validProductCode('8940001280631'), isTrue);
    expect(validProductCode('8906144634380'), isTrue);
    // one digit off, wrong length, non-digits
    expect(validProductCode('8940001285712'), isFalse);
    expect(validProductCode('894000128571'), isFalse);
    expect(validProductCode('89400012857AB'), isFalse);
  });

  test('prescription draft: unsure medicines need confirmation before saving', () {
    final d = PrescriptionDraft.fromJson({
      'readable': true, 'nextVisitDate': '2026-10-20',
      'medicines': [
        {'name': 'Napa 500', 'strength': null, 'form': null, 'morning': 1, 'noon': 0, 'night': 1, 'meal': 'after', 'days': 5, 'note': null, 'uncertain': false},
        {'name': 'Mystery', 'morning': 1, 'noon': null, 'night': 1, 'days': null, 'uncertain': true},
      ],
      'tests': [{'name': 'OPG', 'uncertain': false}],
    });
    expect(d.nextVisit, DateTime(2026, 10, 20));
    expect(d.medicines[0].ready, isTrue);
    expect(d.medicines[1].ready, isFalse);
    expect(d.canSave, isFalse);
    final m = d.medicines[1]..days = 3..noon = 0..confirmed = true;
    expect(m.ready, isTrue);
    expect(d.canSave, isTrue);
    final med = d.medicines[0].toMedicine(1, 2, DateTime(2026, 10, 2));
    expect([med.morning, med.noon, med.night, med.prescribedDays, med.boughtDays], [true, false, true, 5, 0]);
  });
}
