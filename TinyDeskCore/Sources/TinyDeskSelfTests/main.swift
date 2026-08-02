import Foundation
import TinyDeskCore

private var failures = 0
private var runs = 0

private func check(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: String = #file,
    line: Int = #line
) {
    runs += 1
    if condition() {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)  (\(file):\(line))")
    }
}

let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}()
let now = Date(timeIntervalSince1970: 1_700_000_000)

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

print("Workspace seed")
let seeded = TinyDeskWorkspace.seeded(now: now, calendar: calendar)
check(seeded.schemaVersion == TinyDeskWorkspace.currentSchemaVersion, "工作区 schema 为当前版本")
check(seeded.cards.count == 3, "首次启动创建三张桌面卡片")
check(Set(seeded.cards.map(\.kind)) == Set(DesktopCardKind.allCases), "默认卡片覆盖便签、倒数日、待办")
check(seeded.importantDates.count == 1, "首次启动创建一条重要日期")
check(
    seeded.cards.first(where: { $0.kind == .countdown })?.featuredImportantDateID == seeded.importantDates.first?.id,
    "默认日期卡片关联默认重要日期"
)

print("Countdown")
let today = calendar.startOfDay(for: now)
let tenDaysLater = calendar.date(byAdding: .day, value: 10, to: today)!
let fiveDaysEarlier = calendar.date(byAdding: .day, value: -5, to: today)!
var countdown = DesktopCard.countdown(now: now, calendar: calendar)
countdown.targetDate = tenDaysLater
check(countdown.remainingDays(from: now, calendar: calendar) == 10, "未来日期返回正数天")
countdown.targetDate = fiveDaysEarlier
check(countdown.remainingDays(from: now, calendar: calendar) == -5, "过去日期返回负数天")

print("Important dates")
let reference = date(2025, 12, 31)
let newYear = ImportantDateEvent(
    title: "新年",
    category: .holiday,
    date: ImportantDateComponents(year: nil, month: 1, day: 1),
    recurrence: .yearly,
    createdAt: now,
    updatedAt: now
)
check(newYear.daysUntilOccurrence(from: reference, calendar: calendar) == 1, "每年事件跨年计算下一次日期")
check(newYear.occurs(on: date(2030, 1, 1), calendar: calendar), "每年事件可出现在任意后续年份")

let birthday = ImportantDateEvent(
    title: "家人生日",
    category: .birthday,
    date: ImportantDateComponents(year: nil, month: 1, day: 2),
    recurrence: .yearly,
    startYear: 1990,
    createdAt: now,
    updatedAt: now
)
let nextBirthday = birthday.relevantOccurrence(from: reference, calendar: calendar)!
check(nextBirthday == date(2026, 1, 2), "生日返回下一次发生日期")
check(birthday.anniversaryNumber(for: nextBirthday, calendar: calendar) == 36, "生日年龄按起始年份计算")

let futureAnniversary = ImportantDateEvent(
    title: "未来纪念日",
    category: .anniversary,
    date: ImportantDateComponents(year: nil, month: 6, day: 1),
    recurrence: .yearly,
    startYear: 2030,
    createdAt: now,
    updatedAt: now
)
check(
    futureAnniversary.relevantOccurrence(from: date(2025, 1, 1), calendar: calendar) == date(2030, 6, 1),
    "未来起始年份不会错误回退到当前年份"
)
check(!futureAnniversary.occurs(on: date(2029, 6, 1), calendar: calendar), "起始年份之前不显示周年事件")

let leapDay = ImportantDateEvent(
    title: "闰日",
    date: ImportantDateComponents(year: nil, month: 2, day: 29),
    recurrence: .yearly,
    leapDayPolicy: .february28,
    createdAt: now,
    updatedAt: now
)
check(leapDay.occurrence(inYear: 2025, calendar: calendar) == date(2025, 2, 28), "非闰年可回退到2月28日")
check(leapDay.occurs(on: date(2025, 2, 28), calendar: calendar), "日历在非闰年2月28日显示闰日事件")
check(
    leapDay.date.representativeGregorianDate(from: date(2025, 1, 1), calendar: calendar) == date(2028, 2, 29),
    "编辑闰日事件时保留真实的2月29日"
)
var marchLeapDay = leapDay
marchLeapDay.leapDayPolicy = .march1
check(marchLeapDay.occurrence(inYear: 2025, calendar: calendar) == date(2025, 3, 1), "非闰年也可选择3月1日")
check(marchLeapDay.occurs(on: date(2025, 3, 1), calendar: calendar), "日历按规则在3月1日显示闰日事件")

print("Chinese lunar dates")
let lunarNewYear2025 = ChineseLunarCalendar.occurrence(
    inLunarYear: 2025,
    month: 1,
    day: 1,
    isLeapMonth: false,
    leapMonthPolicy: .regularMonthFallback,
    calendar: calendar
)
check(lunarNewYear2025 == date(2025, 1, 29), "农历 2025 年正月初一正确换算为公历日期")
let lunarNewYearComponents = ChineseLunarCalendar.components(from: date(2025, 1, 29), calendar: calendar)
check(
    lunarNewYearComponents == ChineseLunarCalendar.Components(
        lunarYear: 2025,
        month: 1,
        day: 1,
        isLeapMonth: false
    ),
    "公历日期可反查农历年、月、日和闰月标记"
)

let lunarBirthday = ImportantDateEvent(
    title: "农历生日",
    category: .birthday,
    date: ImportantDateComponents(calendarSystem: .chineseLunar, month: 1, day: 15),
    recurrence: .yearly,
    createdAt: now,
    updatedAt: now
)
check(lunarBirthday.occurrence(inYear: 2025, calendar: calendar) == date(2025, 2, 12), "农历生日可计算当年公历发生日")
check(lunarBirthday.occurs(on: date(2025, 2, 12), calendar: calendar), "农历生日会显示在公历日历正确日期")

if let leapDate = (0..<366)
    .compactMap({ calendar.date(byAdding: .day, value: $0, to: date(2025, 1, 1)) })
    .first(where: { ChineseLunarCalendar.components(from: $0, calendar: calendar).isLeapMonth }) {
    let leapComponents = ChineseLunarCalendar.components(from: leapDate, calendar: calendar)
    let strictLeapBirthday = ImportantDateEvent(
        title: "闰月生日",
        date: ImportantDateComponents(
            calendarSystem: .chineseLunar,
            month: leapComponents.month,
            day: leapComponents.day,
            isLeapMonth: true
        ),
        recurrence: .yearly,
        lunarLeapMonthPolicy: .strictLeapMonth,
        createdAt: now,
        updatedAt: now
    )
    check(strictLeapBirthday.occurs(on: leapDate, calendar: calendar), "闰月生日会在实际闰月当天出现")

    var fallbackLeapBirthday = strictLeapBirthday
    fallbackLeapBirthday.lunarLeapMonthPolicy = .regularMonthFallback
    let strictOccurrence = strictLeapBirthday.occurrence(inYear: 2026, calendar: calendar)
    let fallbackOccurrence = fallbackLeapBirthday.occurrence(inYear: 2026, calendar: calendar)
    check(strictOccurrence == nil, "没有对应闰月时严格规则不会错误补过")
    check(fallbackOccurrence != nil, "没有对应闰月时默认规则按普通月补过")
} else {
    check(false, "测试年份应包含至少一个闰月")
}

let oneTime = ImportantDateEvent(
    title: "一次事件",
    date: ImportantDateComponents(year: 2026, month: 4, day: 5),
    recurrence: .once,
    reminderDaysBefore: 3,
    reminderHour: 8,
    createdAt: now,
    updatedAt: now
)
check(oneTime.storedOccurrence(calendar: calendar) == date(2026, 4, 5), "一次事件保留完整日期")
check(!oneTime.occurs(on: date(2027, 4, 5), calendar: calendar), "一次事件不会在次年重复")

print("Todo")
var todo = DesktopCard.todo(now: now, calendar: calendar)
check(todo.todoItems.first?.scheduledDayOffset(from: now, calendar: calendar) == 0, "新待办默认计划为今天")

let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
let threeDaysEarlier = calendar.date(byAdding: .day, value: -3, to: today)!
let yesterdayTodo = TinyDeskTodoItem(title: "昨日", dueDate: yesterday, createdAt: now)
let olderTodo = TinyDeskTodoItem(title: "更早", dueDate: threeDaysEarlier, createdAt: now)
let legacyTodo = TinyDeskTodoItem(title: "旧数据", createdAt: yesterday)
check(yesterdayTodo.scheduledDayOffset(from: now, calendar: calendar) == -1, "昨日计划可识别为昨日未完成")
check(olderTodo.scheduledDayOffset(from: now, calendar: calendar) == -3, "更早计划可计算逾期天数")
check(legacyTodo.scheduledDayOffset(from: now, calendar: calendar) == -1, "旧待办没有日期时回退到创建日期")

todo.todoItems = [
    TinyDeskTodoItem(title: "完成 A", isCompleted: true, createdAt: now),
    TinyDeskTodoItem(title: "未完成 A", priority: .urgent, createdAt: now),
    TinyDeskTodoItem(title: "完成 B", isCompleted: true, createdAt: now),
    TinyDeskTodoItem(title: "未完成 B", createdAt: now),
]
check(todo.completedTodoCount == 2 && todo.pendingTodoCount == 2, "待办完成与未完成计数正确")
check(
    todo.orderedTodoItems.map(\.title) == ["未完成 A", "未完成 B", "完成 A", "完成 B"],
    "已完成待办稳定移动到列表底部"
)
check(TodoPriority.normal < .important && TodoPriority.important < .urgent, "待办优先级可排序")

print("Persistence contract")
var sticky = DesktopCard.sticky(now: now)
sticky.frame = DesktopCardFrame(x: 40, y: 80, width: 320, height: 280, screenIdentifier: "1")
sticky.surfaceStyle = .opaque
sticky.isPositionLocked = true
sticky.isAlwaysOnTop = true
sticky.noteRichTextData = Data("{\\rtf1 TinyDesk}".utf8)
let linkedSystemDate = ImportantDateEvent(
    title: "系统日历会议",
    category: .other,
    date: ImportantDateComponents(year: 2026, month: 8, day: 3),
    recurrence: .once,
    systemCalendarLink: SystemCalendarLink(
        calendarIdentifier: "system-calendar-id",
        calendarTitle: "工作",
        eventIdentifier: "event-id",
        externalIdentifier: "external-id",
        authority: .systemCalendar,
        isReadOnly: true,
        lastSyncedAt: now
    ),
    createdAt: now,
    updatedAt: now
)
let workspace = TinyDeskWorkspace(
    cards: [sticky, countdown, todo],
    importantDates: [newYear, birthday, oneTime, linkedSystemDate]
)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let encoded = try encoder.encode(workspace)
let decoded = try decoder.decode(TinyDeskWorkspace.self, from: encoded)
check(decoded == workspace, "工作区 JSON 可无损往返")
check(decoded.cards.first?.frame?.screenIdentifier == "1", "窗口位置和屏幕标识会持久化")
check(decoded.cards.first?.resolvedSurfaceStyle == .opaque, "背景风格会持久化")
check(decoded.cards.first?.resolvedIsPositionLocked == true, "位置锁定状态会持久化")
check(decoded.cards.first?.resolvedIsAlwaysOnTop == true, "快捷便签置顶状态会持久化")
check(decoded.cards.first?.noteRichTextData == sticky.noteRichTextData, "便签富文本数据会持久化")
check(
    decoded.importantDates.last?.systemCalendarLink?.authority == .systemCalendar,
    "系统日历来源关联会持久化"
)

if var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
   var legacyCards = legacyObject["cards"] as? [[String: Any]] {
    for index in legacyCards.indices {
        legacyCards[index].removeValue(forKey: "surfaceStyle")
        legacyCards[index].removeValue(forKey: "isPositionLocked")
        legacyCards[index].removeValue(forKey: "isAlwaysOnTop")
        legacyCards[index].removeValue(forKey: "noteRichTextData")
    }
    legacyObject["cards"] = legacyCards
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyWorkspace = try decoder.decode(TinyDeskWorkspace.self, from: legacyData)
    check(
        legacyWorkspace.cards.allSatisfy { $0.resolvedSurfaceStyle == .frosted },
        "旧工作区缺少背景风格时默认使用毛玻璃"
    )
    check(
        legacyWorkspace.cards.allSatisfy { !$0.resolvedIsPositionLocked },
        "旧工作区缺少位置锁时默认允许移动"
    )
    check(
        legacyWorkspace.cards.allSatisfy { !$0.resolvedIsAlwaysOnTop },
        "旧工作区缺少置顶状态时保持桌面层显示"
    )
    check(
        legacyWorkspace.cards.allSatisfy { $0.noteRichTextData == nil },
        "旧工作区缺少富文本数据时保留纯文本便签"
    )
} else {
    check(false, "旧工作区兼容性测试数据可构造")
}

print("Schema migration")
let legacyCountdown = DesktopCard.countdown(now: date(2025, 1, 1), calendar: calendar)
let legacySource = TinyDeskWorkspace(schemaVersion: 1, cards: [legacyCountdown])
let legacyEncoded = try encoder.encode(legacySource)
if var legacyObject = try JSONSerialization.jsonObject(with: legacyEncoded) as? [String: Any] {
    legacyObject.removeValue(forKey: "importantDates")
    if var cards = legacyObject["cards"] as? [[String: Any]] {
        for index in cards.indices {
            cards[index].removeValue(forKey: "importantDateViewMode")
            cards[index].removeValue(forKey: "importantDateCategoryFilter")
            cards[index].removeValue(forKey: "featuredImportantDateID")
        }
        legacyObject["cards"] = cards
    }
    let data = try JSONSerialization.data(withJSONObject: legacyObject)
    let decodedLegacy = try decoder.decode(TinyDeskWorkspace.self, from: data)
    let migrated = decodedLegacy.migratedToCurrentSchema(calendar: calendar)
    check(migrated.schemaVersion == 3, "v1 工作区迁移到 schema 3")
    check(migrated.importantDates.count == 1, "旧倒数日迁移为重要日期事件")
    check(migrated.importantDates.first?.title == legacyCountdown.title, "迁移保留旧倒数日标题")
    check(
        migrated.importantDates.first?.storedOccurrence(calendar: calendar) == calendar.startOfDay(for: legacyCountdown.targetDate),
        "迁移保留旧倒数日目标日期"
    )
    check(
        migrated.cards.first?.featuredImportantDateID == migrated.importantDates.first?.id,
        "迁移后日期卡片关联新事件"
    )
} else {
    check(false, "schema 迁移测试数据可构造")
}

print("")
print("结果: \(runs - failures)/\(runs) 通过, \(failures) 失败")
if failures > 0 {
    print("❌ 有失败断言")
    exit(1)
}
print("✅ 全部通过")
