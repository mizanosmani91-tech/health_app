import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/core/bn.dart';
import 'package:health_app/data/models.dart';
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
}
