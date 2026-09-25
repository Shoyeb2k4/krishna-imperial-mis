/// The single place in the application where a reporting date becomes text.
///
/// Money has had one such place since Phase 1 (`money_formatter.dart`). Dates now need
/// one too: the P&L surfaces, the drill-down and the dashboard all print a business date,
/// a range and a server-confirmed instant, and a second month table would be a second
/// answer to *what is this day called* — the drift D-119, D-131 and D-232 each record.
///
/// **Nothing here derives a date.** Every value arrives already decided — a
/// [BusinessDate] the property's own cut-off produced, a [ReportRange] the period planner
/// resolved, an instant the server confirmed — and is only turned into words. No clock is
/// read, no zone is chosen and no arithmetic is done on a day.
library;

import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/timezone.dart' as tz;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `19 Sep 2026`.
String reportDateLabel(BusinessDate d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `19 Sep` — for a position on a chart, where the year is already in the period line.
String reportDayLabel(BusinessDate d) => '${d.day} ${_months[d.month - 1]}';

/// `Sep 2026`.
String reportMonthLabel(BusinessDate d) => '${_months[d.month - 1]} ${d.year}';

/// `19 Sep 2026` for a single day, otherwise `1 Sep 2026 – 19 Sep 2026`.
String reportRangeLabel(ReportRange range) => range.from == range.to
    ? reportDateLabel(range.from)
    : '${reportDateLabel(range.from)} – ${reportDateLabel(range.to)}';

/// A compact range for a chart position: `22–28 Sep`, or `28 Sep – 4 Oct`.
String reportShortRangeLabel(ReportRange range) {
  if (range.from == range.to) return reportDayLabel(range.from);
  return range.from.month == range.to.month && range.from.year == range.to.year
      ? '${range.from.day}–${reportDayLabel(range.to)}'
      : '${reportDayLabel(range.from)} – ${reportDayLabel(range.to)}';
}

/// `19 Sep 2026, 20:30 IST`, in the zone the caller chose to display it in.
///
/// The zone is display only. Nothing is derived from it, and the instant itself is the
/// server-confirmed one.
///
/// `UTC` is the surfaces' fallback when a property's rules cannot be read. The IANA data
/// the app bundles names it `Etc/UTC`, not `UTC`, so it is resolved here rather than
/// looked up — a lookup would throw and take the statement down with it (Phase 7 Slice 6).
String reportInstantLabel(DateTime instant, String zone) {
  final location = zone == 'UTC' ? tz.UTC : tz.getLocation(zone);
  final local = tz.TZDateTime.from(instant, location);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '$hh:$mm ${local.timeZoneName}';
}
