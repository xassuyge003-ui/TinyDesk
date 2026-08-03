import Foundation

/// 基于 Foundation 中国农历的纯本地日期换算。
///
/// `Calendar(identifier: .chinese)` 的年份是六十甲子循环，不能直接拿公历年份构造；
/// 因此这里以日粒度检索指定农历年或公历年。重要日期数量通常很小，优先保证闰月和小月
/// 的语义正确，并避免引入第三方历法数据库。
public enum ChineseLunarCalendar {
    public struct Components: Sendable, Equatable {
        public var lunarYear: Int
        public var month: Int
        public var day: Int
        public var isLeapMonth: Bool

        public init(lunarYear: Int, month: Int, day: Int, isLeapMonth: Bool) {
            self.lunarYear = lunarYear
            self.month = month
            self.day = day
            self.isLeapMonth = isLeapMonth
        }
    }

    public static func components(
        from gregorianDate: Date,
        calendar: Calendar = .current
    ) -> Components {
        let lunar = chineseCalendar(timeZone: calendar.timeZone)
        let values = lunar.dateComponents([.month, .day, .isLeapMonth], from: gregorianDate)
        return Components(
            lunarYear: lunarYear(containing: gregorianDate, calendar: calendar),
            month: values.month ?? 1,
            day: values.day ?? 1,
            isLeapMonth: values.isLeapMonth == true
        )
    }

    public static func occurrence(
        inGregorianYear year: Int,
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        leapMonthPolicy: ImportantDateLunarLeapMonthPolicy,
        calendar: Calendar = .current
    ) -> Date? {
        guard let start = gregorianDate(year: year, month: 1, day: 1, calendar: calendar),
              let end = gregorianDate(year: year + 1, month: 1, day: 1, calendar: calendar)
        else { return nil }

        if let exact = date(
            between: start,
            and: end,
            month: month,
            day: day,
            isLeapMonth: isLeapMonth,
            calendar: calendar
        ) {
            return exact
        }

        guard isLeapMonth, leapMonthPolicy == .regularMonthFallback else { return nil }
        return date(
            between: start,
            and: end,
            month: month,
            day: day,
            isLeapMonth: false,
            calendar: calendar
        )
    }

    /// `lunarYear` 为农历正月初一所在的公历年份，例如 2026 农历年。
    public static func occurrence(
        inLunarYear lunarYear: Int,
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        leapMonthPolicy: ImportantDateLunarLeapMonthPolicy,
        calendar: Calendar = .current
    ) -> Date? {
        guard let start = lunarNewYear(in: lunarYear, calendar: calendar),
              let end = lunarNewYear(in: lunarYear + 1, calendar: calendar)
        else { return nil }

        if let exact = date(
            between: start,
            and: end,
            month: month,
            day: day,
            isLeapMonth: isLeapMonth,
            calendar: calendar
        ) {
            return exact
        }

        guard isLeapMonth, leapMonthPolicy == .regularMonthFallback else { return nil }
        return date(
            between: start,
            and: end,
            month: month,
            day: day,
            isLeapMonth: false,
            calendar: calendar
        )
    }

    public static func displayText(month: Int, day: Int, isLeapMonth: Bool) -> String {
        let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        let dayNames = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
        ]
        let safeMonth = monthNames.indices.contains(month - 1) ? monthNames[month - 1] : "(month)"
        let safeDay = dayNames.indices.contains(day - 1) ? dayNames[day - 1] : "(day)日"
        return "农历\(isLeapMonth ? "闰" : "")\(safeMonth)月\(safeDay)"
    }

    private static func date(
        between start: Date,
        and end: Date,
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        calendar: Calendar
    ) -> Date? {
        let lunar = chineseCalendar(timeZone: calendar.timeZone)
        var current = calendar.startOfDay(for: start)
        var lastMatchingMonthDay: Date?

        while current < end {
            let values = lunar.dateComponents([.month, .day, .isLeapMonth], from: current)
            if values.month == month, values.isLeapMonth == isLeapMonth {
                if values.day == day { return current }
                if (values.day ?? 0) < day { lastMatchingMonthDay = current }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // 农历小月没有三十时，默认使用该月最后一天。
        return lastMatchingMonthDay
    }

    private static func lunarYear(containing date: Date, calendar: Calendar) -> Int {
        let gregorianYear = calendar.component(.year, from: date)
        guard let currentYearNewYear = lunarNewYear(in: gregorianYear, calendar: calendar) else {
            return gregorianYear
        }
        return date >= currentYearNewYear ? gregorianYear : gregorianYear - 1
    }

    private static func lunarNewYear(in gregorianYear: Int, calendar: Calendar) -> Date? {
        guard let start = gregorianDate(year: gregorianYear, month: 1, day: 1, calendar: calendar),
              let end = gregorianDate(year: gregorianYear, month: 4, day: 1, calendar: calendar)
        else { return nil }

        let lunar = chineseCalendar(timeZone: calendar.timeZone)
        var current = start
        while current < end {
            let values = lunar.dateComponents([.month, .day, .isLeapMonth], from: current)
            if values.month == 1, values.day == 1, values.isLeapMonth != true {
                return current
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return nil
    }

    private static func gregorianDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }

    private static func chineseCalendar(timeZone: TimeZone) -> Calendar {
        var value = Calendar(identifier: .chinese)
        value.timeZone = timeZone
        return value
    }
}
