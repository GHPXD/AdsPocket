import 'package:ads_pocket/core/longevity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = CivilDate.of(2026, 10, 28)!;

  test('civil dates are strict', () {
    expect(CivilDate.of(2026, 2, 29), isNull);
    expect(CivilDate.of(2028, 2, 29), isNotNull);
    expect(CivilDate.tryParse('2026-10-12'), CivilDate.of(2026, 10, 12));
    expect(CivilDate.tryParse('2026-13-01'), isNull);
    expect(CivilDate.tryParse('12/10/2026'), isNull);
    expect(CivilDate.of(2026, 10, 2)!.label, '02/10/2026');
  });

  test('age counts civil days and the exact limit matches', () {
    final start = today.addDays(-14);
    expect(ageInDays(start, today), 14);
    expect(const LongevityFilter(minDays: 14).matches(start, today), isTrue);
    expect(
      const LongevityFilter(minDays: 14).matches(today.addDays(-13), today),
      isFalse,
    );
    expect(const LongevityFilter(minDays: 0).matches(today, today), isTrue);
  });

  test('every preset filters by its own threshold', () {
    for (final days in LongevityFilter.presets.whereType<int>()) {
      final f = LongevityFilter(minDays: days);
      expect(f.matches(today.addDays(-days), today), isTrue, reason: '$days');
      expect(
        f.matches(today.addDays(-days + 1), today),
        isFalse,
        reason: '$days',
      );
    }
    expect(LongevityFilter.presets, [null, 3, 7, 14, 21, 30, 60, 90]);
  });

  test('no filter keeps everything, including future and undated', () {
    const f = LongevityFilter();
    expect(f.active, isFalse);
    expect(f.matches(null, today), isTrue);
    expect(f.matches(today.addDays(5), today), isTrue);
  });

  test('unknown date follows the include toggle', () {
    expect(const LongevityFilter(minDays: 7).matches(null, today), isTrue);
    expect(
      const LongevityFilter(
        minDays: 7,
        includeUndated: false,
      ).matches(null, today),
      isFalse,
    );
  });

  test('future start dates never pass an age filter', () {
    final future = today.addDays(3);
    expect(ageInDays(future, today), -3);
    expect(ageLabel(-3), 'Data futura');
    expect(const LongevityFilter(minDays: 0).matches(future, today), isFalse);
  });

  test('custom period is bounded to 0..365', () {
    expect(LongevityFilter.validDays(0), 0);
    expect(LongevityFilter.validDays(365), 365);
    expect(() => LongevityFilter.validDays(366), throwsFormatException);
    expect(() => LongevityFilter.validDays(-1), throwsFormatException);
  });

  test('day change: 23:59 and 00:01 are different civil days', () {
    final start = CivilDate.of(2026, 10, 1)!;
    final late = CivilDate.today(DateTime(2026, 10, 15, 23, 59));
    final next = CivilDate.today(DateTime(2026, 10, 16, 0, 1));
    expect(ageInDays(start, late), 14);
    expect(ageInDays(start, next), 15);
  });

  test('daylight saving transitions do not shift the age', () {
    // Brazil 2018-11-04 and US 2026-03-08 / 2026-11-01 transitions.
    expect(CivilDate.of(2018, 11, 3)!.daysUntil(CivilDate.of(2018, 11, 5)!), 2);
    expect(CivilDate.of(2026, 3, 7)!.daysUntil(CivilDate.of(2026, 3, 9)!), 2);
    expect(
      CivilDate.of(2026, 10, 31)!.daysUntil(CivilDate.of(2026, 11, 2)!),
      2,
    );
    // Calendar fields of a UTC instant are used as-is, never re-zoned.
    expect(
      CivilDate.fromDateTime(DateTime.utc(2026, 10, 28, 23, 30)),
      CivilDate.of(2026, 10, 28),
    );
  });

  test('status labels and stale verification', () {
    expect(AdStatus.active.label, 'Ativo confirmado');
    expect(AdStatus.inactive.label, 'Inativo');
    expect(AdStatus.unknown.label, 'Desconhecido');
    final now = DateTime(2026, 10, 28, 12);
    expect(isStaleCheck(null, now), isTrue);
    expect(isStaleCheck(DateTime(2026, 10, 25), now), isFalse);
    expect(isStaleCheck(DateTime(2026, 10, 20), now), isTrue);
  });
}
