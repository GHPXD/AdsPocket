/// Calendar date without time or timezone. Age is computed on civil days, so
/// daylight saving changes and the device timezone never shift the result.
class CivilDate implements Comparable<CivilDate> {
  const CivilDate._(this.year, this.month, this.day);
  final int year, month, day;

  static CivilDate? of(int year, int month, int day) {
    if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final check = DateTime.utc(year, month, day);
    return check.month == month && check.day == day
        ? CivilDate._(year, month, day)
        : null;
  }

  /// Uses the calendar fields of [time] as given (local time stays local).
  factory CivilDate.fromDateTime(DateTime time) =>
      CivilDate._(time.year, time.month, time.day);
  factory CivilDate.today([DateTime? now]) =>
      CivilDate.fromDateTime(now ?? DateTime.now());

  /// Strict `YYYY-MM-DD`.
  static CivilDate? tryParse(String? text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text ?? '');
    if (m == null) return null;
    return of(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  DateTime get _utc => DateTime.utc(year, month, day);
  int daysUntil(CivilDate other) => other._utc.difference(_utc).inDays;
  CivilDate addDays(int days) =>
      CivilDate.fromDateTime(_utc.add(Duration(days: days)));
  DateTime toLocalDateTime() => DateTime(year, month, day);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';
  String get label => '${_two(day)}/${_two(month)}/$year';
  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  int compareTo(CivilDate other) => _utc.compareTo(other._utc);
  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() => toIso();
}

/// Days since the start date. Negative means a future (invalid) start date.
int? ageInDays(CivilDate? start, CivilDate today) => start?.daysUntil(today);

enum AdStatus {
  active('Ativo confirmado'),
  inactive('Inativo'),
  unknown('Desconhecido');

  const AdStatus(this.label);
  final String label;
}

/// Local filter over catalogued references only; never the remote Library.
class LongevityFilter {
  const LongevityFilter({this.minDays, this.includeUndated = true});
  static const presets = <int?>[null, 3, 7, 14, 21, 30, 60, 90];
  static const maxDays = 365;
  final int? minDays;
  final bool includeUndated;
  bool get active => minDays != null;

  static int? validDays(int? days) {
    if (days == null) return null;
    if (days < 0 || days > maxDays) {
      throw const FormatException('Use um período entre 0 e 365 dias.');
    }
    return days;
  }

  bool matches(CivilDate? start, CivilDate today) {
    if (minDays == null) return true;
    final age = ageInDays(start, today);
    if (age == null) return includeUndated;
    return age >= 0 && age >= minDays!;
  }
}

/// A status confirmation older than [days] should be checked again.
bool isStaleCheck(DateTime? checkedAt, DateTime now, {int days = 7}) =>
    checkedAt == null ||
    CivilDate.fromDateTime(
          checkedAt.toLocal(),
        ).daysUntil(CivilDate.fromDateTime(now.toLocal())) >
        days;

String ageLabel(int? age) => switch (age) {
  null => 'Sem data',
  < 0 => 'Data futura',
  0 => 'Hoje',
  1 => '1 dia',
  _ => '$age dias',
};
