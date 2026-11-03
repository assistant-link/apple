import Foundation

enum TimeCaption {
  /// "Today 8:05 AM", "Yesterday 8:05 AM", or the date and time for anything older.
  static func text(
    for date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let style = Date.FormatStyle(
      locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    let time = date.formatted(style.hour().minute())
    if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "Yesterday \(time)"
    }
    return date.formatted(style.month(.abbreviated).day().hour().minute())
  }
}
