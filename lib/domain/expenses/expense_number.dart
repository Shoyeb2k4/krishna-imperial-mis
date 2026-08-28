/// The human-readable expense number: `KI-EXP-26-27-000001`.
///
/// ```
///   KI      Krishna Imperial — the organisation, not a property
///   EXP     the document kind
///   26-27   the Indian financial year, 1 April 2026 … 31 March 2027
///   000001  the sequence within that year
/// ```
///
/// **Organisation-wide, deliberately.** There is no `CCR-` or `HKI-` prefix, because one
/// expense may be allocated across both properties — an electricity bill split between
/// them belongs to neither, and stamping it with one property's prefix would be a small
/// lie printed on every copy of the document.
///
/// **The number is allocated by the server, and only after the record is accepted.** A
/// client never reserves one, not even provisionally: two devices offline for a week
/// would both reserve `000042`, and a financial document with a duplicate reference is
/// worse than one with no reference at all. Offline, an expense is identified by its
/// client-generated UUID and shows its number the moment the server issues one.
///
/// This file therefore contains no allocator. It formats, parses and validates — the
/// things a client legitimately needs in order to display and search a number it was
/// given.
library;

import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// The Indian financial year, 1 April through 31 March.
///
/// Named by its opening year: a business date of 15 June 2026 and one of 10 February 2027
/// are both in the year that opened in 2026, and both print as `26-27`.
final class FinancialYear implements Comparable<FinancialYear> {
  const FinancialYear(this.openingYear);

  /// The year the 1 April fell in.
  final int openingYear;

  /// Which financial year a business date belongs to.
  ///
  /// The business date, not the capture instant: an expense recorded on 2 April for the
  /// trading day of 31 March belongs to the year that is closing, not the one opening.
  factory FinancialYear.of(BusinessDate date) =>
      FinancialYear(date.month >= 4 ? date.year : date.year - 1);

  int get closingYear => openingYear + 1;

  /// `26-27`. Two digits each, because that is how the business writes it.
  String get label =>
      '${_twoDigit(openingYear % 100)}-${_twoDigit(closingYear % 100)}';

  BusinessDate get startsOn => BusinessDate.of(openingYear, 4, 1);
  BusinessDate get endsOn => BusinessDate.of(closingYear, 3, 31);

  bool contains(BusinessDate date) =>
      date.compareTo(startsOn) >= 0 && date.compareTo(endsOn) <= 0;

  FinancialYear get next => FinancialYear(openingYear + 1);
  FinancialYear get previous => FinancialYear(openingYear - 1);

  @override
  int compareTo(FinancialYear other) =>
      openingYear.compareTo(other.openingYear);

  @override
  bool operator ==(Object other) =>
      other is FinancialYear && other.openingYear == openingYear;

  @override
  int get hashCode => openingYear.hashCode;

  @override
  String toString() => 'FY $label';

  static String _twoDigit(int value) => value.toString().padLeft(2, '0');
}

/// One issued expense number.
final class ExpenseNumber implements Comparable<ExpenseNumber> {
  const ExpenseNumber({required this.year, required this.sequence});

  /// The organisation prefix. One organisation, one prefix — never a property's.
  static const String organisationPrefix = 'KI';

  /// The document kind. Revenue and any later document type get their own.
  static const String documentKind = 'EXP';

  static const int sequenceDigits = 6;

  final FinancialYear year;

  /// 1-based within the financial year. Resets on 1 April.
  final int sequence;

  String get formatted =>
      '$organisationPrefix-$documentKind-${year.label}-'
      '${sequence.toString().padLeft(sequenceDigits, '0')}';

  /// Reads a number back, or null if it is not one.
  ///
  /// Lenient about case and surrounding whitespace, because this is what a search box
  /// hands it; strict about everything else, because a number that nearly parses is how
  /// somebody ends up looking at the wrong document.
  static ExpenseNumber? tryParse(String input) {
    final match = _pattern.firstMatch(input.trim().toUpperCase());
    if (match == null) return null;

    final opening = int.parse(match.group(1)!);
    final closing = int.parse(match.group(2)!);
    // `26-27`, never `26-28` and never `26-26`. Two-digit years wrap at the century, so
    // 99-00 is a legitimate pair.
    if ((opening + 1) % 100 != closing) return null;

    return ExpenseNumber(
      // Two digits cannot say which century. This product's history starts well inside
      // the 2000s, and a stored number is only ever read back, never used to date
      // anything — the record carries its own dates.
      year: FinancialYear(2000 + opening),
      sequence: int.parse(match.group(3)!),
    );
  }

  static final RegExp _pattern = RegExp(
    '^$organisationPrefix-$documentKind-(\\d{2})-(\\d{2})-(\\d{$sequenceDigits})\$',
  );

  @override
  int compareTo(ExpenseNumber other) {
    final byYear = year.compareTo(other.year);
    return byYear != 0 ? byYear : sequence.compareTo(other.sequence);
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseNumber &&
      other.year == year &&
      other.sequence == sequence;

  @override
  int get hashCode => Object.hash(year, sequence);

  @override
  String toString() => formatted;
}
