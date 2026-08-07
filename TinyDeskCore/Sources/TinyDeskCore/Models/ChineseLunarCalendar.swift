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
        occurrences(
            inGregorianYear: year,
            month: month,
            day: day,
            isLeapMonth: isLeapMonth,
            leapMonthPolicy: leapMonthPolicy,
            calendar: calendar
        ).min()
    }

    /// 返回目标公历年内该农历月日的全部发生日。
    ///
    /// 冬月/腊月可能跨公历年：例如腊月既可能出现在年初（上一农历年），
    /// 也可能出现在年末（本农历年），同一年内可能有两个发生日。
    /// 供 `occurs(on:)` 判断任意一天是否是发生日。
    public static func occurrences(
        inGregorianYear year: Int,
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        leapMonthPolicy: ImportantDateLunarLeapMonthPolicy,
        calendar: Calendar = .current
    ) -> [Date] {
        guard let start = gregorianDate(year: year, month: 1, day: 1, calendar: calendar),
              let end = gregorianDate(year: year + 1, month: 1, day: 1, calendar: calendar)
        else { return [] }

        // 目标农历月可能跨公历年：冬月/腊月会落在次年 1 月，而窗口内 1 月初
        // 出现的冬月/腊月属于上一农历年。因此按相邻农历年逐一扫描，
        // 再过滤出落在目标公历年窗口内的日期，避免错配或把小月回退误用。
        var candidates: [Date] = []
        for lunarYear in (year - 1)...(year + 1) {
            guard let newYear = lunarNewYear(in: lunarYear, calendar: calendar),
                  let nextNewYear = lunarNewYear(in: lunarYear + 1, calendar: calendar)
            else { continue }
            guard let exact = date(
                between: newYear,
                and: nextNewYear,
                month: month,
                day: day,
                isLeapMonth: isLeapMonth,
                calendar: calendar
            ), exact >= start, exact < end else { continue }
            candidates.append(exact)
        }

        if !candidates.isEmpty {
            return candidates.sorted()
        }

        guard isLeapMonth, leapMonthPolicy == .regularMonthFallback else { return [] }
        // 该公历年内没有对应的闰月时，按同名普通月补过，仍限制在目标公历年窗口内。
        var fallbackCandidates: [Date] = []
        for lunarYear in (year - 1)...(year + 1) {
            guard let newYear = lunarNewYear(in: lunarYear, calendar: calendar),
                  let nextNewYear = lunarNewYear(in: lunarYear + 1, calendar: calendar)
            else { continue }
            guard let fallback = date(
                between: newYear,
                and: nextNewYear,
                month: month,
                day: day,
                isLeapMonth: false,
                calendar: calendar
            ), fallback >= start, fallback < end else { continue }
            fallbackCandidates.append(fallback)
        }
        return fallbackCandidates.sorted()
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
        let gregorian = gregorianCalendar(timeZone: calendar.timeZone)
        let gregorianYear = gregorian.component(.year, from: date)
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
        // 年份语义固定为公历绝对年；仅沿用传入日历的时区，避免佛历/和历等纪年错位。
        let gregorian = gregorianCalendar(timeZone: calendar.timeZone)
        var components = DateComponents()
        components.calendar = gregorian
        components.timeZone = gregorian.timeZone
        components.year = year
        components.month = month
        components.day = day
        return gregorian.date(from: components).map(gregorian.startOfDay(for:))
    }

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    private static func chineseCalendar(timeZone: TimeZone) -> Calendar {
        var value = Calendar(identifier: .chinese)
        value.timeZone = timeZone
        return value
    }
}
