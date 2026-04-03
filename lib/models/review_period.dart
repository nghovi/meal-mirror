enum ReviewPeriod { day, week, month, year }

extension ReviewPeriodX on ReviewPeriod {
  String get label {
    switch (this) {
      case ReviewPeriod.day:
        return 'Day';
      case ReviewPeriod.week:
        return 'Week';
      case ReviewPeriod.month:
        return 'Month';
      case ReviewPeriod.year:
        return 'Year';
    }
  }
}
