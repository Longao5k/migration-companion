class ProcessingTimeEstimate {
  const ProcessingTimeEstimate({
    required this.category,
    required this.displayValue,
    required this.asOf,
    required this.sourceUrl,
    this.approximateDays,
    this.note,
  });

  final String category;
  final String displayValue;
  final DateTime asOf;
  final String sourceUrl;
  final int? approximateDays;
  final String? note;
}

abstract final class ProcessingTimes {
  static const sourceUrl =
      'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-processing-times';

  /// Current headline medians published by Home Affairs for July 2026.
  /// These are program-category medians, not a promise for an individual case.
  static ProcessingTimeEstimate? forVisaType(String visaType) {
    final code = RegExp(r'\b(\d{3})(?:/\d{3})?\b')
        .firstMatch(visaType)
        ?.group(1);
    if (code == null) return null;
    if (const {'189', '190', '191', '186', '858'}.contains(code)) {
      return ProcessingTimeEstimate(
        category: 'Skilled (Permanent)',
        displayValue: '8 months',
        approximateDays: 243,
        asOf: DateTime(2026, 7),
        sourceUrl: sourceUrl,
      );
    }
    if (code == '482') {
      return ProcessingTimeEstimate(
        category: 'Skilled (Temporary)',
        displayValue: '98 days',
        approximateDays: 98,
        asOf: DateTime(2026, 7),
        sourceUrl: sourceUrl,
      );
    }
    if (code == '500') {
      return ProcessingTimeEstimate(
        category: 'Student',
        displayValue: '21 days',
        approximateDays: 21,
        asOf: DateTime(2026, 7),
        sourceUrl: sourceUrl,
      );
    }
    if (code == '600') {
      return ProcessingTimeEstimate(
        category: 'Visitor (combined subclasses)',
        displayValue: 'Less than 1 day',
        asOf: DateTime(2026, 7),
        sourceUrl: sourceUrl,
        note: 'Subclass 600 can take significantly longer than the combined visitor median.',
      );
    }
    if (const {'309', '820'}.contains(code)) {
      return ProcessingTimeEstimate(
        category: 'Partner (Provisional/Temporary)',
        displayValue: '23 months',
        approximateDays: 700,
        asOf: DateTime(2026, 7),
        sourceUrl: sourceUrl,
      );
    }
    return null;
  }
}
