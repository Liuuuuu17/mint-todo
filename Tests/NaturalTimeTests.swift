import Foundation
import AppKit

enum NaturalTimeTests {
    @MainActor static func run(_ check: (Bool, String) throws -> Void) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        func date(_ y: Int = 2026, _ m: Int = 10, _ d: Int = 27, _ h: Int = 12, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
        }
        let now = date()
        func parse(_ text: String) -> NaturalTaskTime? { NaturalTaskTime.parse(text, now: now, calendar: calendar) }
        let wednesday = parse("周三团建")
        try check(wednesday?.end == date(2026, 10, 28, 23, 59) && wednesday?.dateOnly == true, "weekday becomes concrete date")
        try check(parse("下周三团建")?.end == date(2026, 11, 4, 23, 59), "next week uses calendar week")
        try check(parse("星期一交报告")?.end == date(2026, 11, 2, 23, 59), "past bare weekday means next occurrence")
        try check(parse("今天下午两点30到四点30总台ai培训") == NaturalTaskTime(start: date(2026, 10, 27, 14, 30), end: date(2026, 10, 27, 16, 30), dateOnly: false), "Chinese range inherits afternoon")
        try check(parse("明天下午两点半到四点半培训")?.end == date(2026, 10, 28, 16, 30), "tomorrow and half hour")
        try check(parse("10月28日 14:30-16:30 培训")?.start == date(2026, 10, 28, 14, 30), "explicit date and numeric range")
        try check(parse("明早八点开会")?.end == date(2026, 10, 28, 8), "tomorrow morning")
        try check(parse("今晚八点开会")?.end == date(2026, 10, 27, 20), "tonight")
        try check(parse("晚上十一点到凌晨一点值班")?.end == date(2026, 10, 28, 1), "overnight interval")
        try check(parse("下午三点一刻开会")?.end == date(2026, 10, 27, 15, 15), "quarter hour")
        try check(parse("2027-01-02 09:15 开会")?.end == date(2027, 1, 2, 9, 15), "explicit year")
        try check(parse("1月2日开会")?.end == date(2027, 1, 2, 23, 59), "yearless date rolls forward")
        try check(parse("2026年2月30日开会") == nil, "invalid calendar date rejected")
        try check(parse("明天25点开会") == nil, "invalid hour rejected")
        try check(parse("明天14:70开会") == nil, "invalid minute rejected")
        try check(parse("下午四点到三点开会") == nil, "backwards afternoon interval rejected")
        try check(parse("两点开会四点散步") == nil, "separate events are not one range")
        try check(parse("10月27日到10月28日出差") == nil, "ambiguous multiple dates rejected")
        try check(parse("整理资料123") == nil, "ordinary titles unchanged")
        func extract(_ text: String) -> String? { NaturalTaskTime.extract(text, now: now, calendar: calendar)?.title }
        try check(extract("明天下午2:30到4:30培训") == "培训", "schedule removed from new task title")
        try check(extract("周三团建") == "团建", "weekday removed from title")
        try check(extract("培训 明天下午2:30到4:30") == "培训", "trailing schedule removed")
        try check(extract("明天下午2:30到4:30") == "明天下午2:30到4:30", "time-only input remains editable")
        try check(extract("明天下午2:30到4:30培训第2阶段") == "培训第2阶段", "unrelated numbers preserved")
        try check(extract("今晚八点开会") == "开会", "overlapping date and clock spans merged")
        try check(extract("明天（14:30-16:30）培训") == "培训", "empty schedule parentheses removed")
        try check(extract("明天25点培训") == nil, "invalid schedule never strips text")
        try check(extract("整理资料123") == nil, "ordinary titles not stripped")
        try check(NaturalTaskTime.extract("明天下午2:30到4:30培训", now: now, calendar: calendar)?.time == parse("明天下午2:30到4:30培训"), "title extraction preserves schedule")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TaskStore(folder: folder, watch: false)
        var task = Todo(title: "今天下午两点半到四点半培训", category: "工作", dueAt: date(2026, 10, 27, 16, 30))
        task.scheduledStartAt = date(2026, 10, 27, 14, 30)
        task.dueDateOnly = false
        task.repeatRule = .daily
        try check(store.saveEdited(task), "time range saves")
        let reopened = TaskStore(folder: folder, watch: false)
        try check(reopened.tasks.first?.scheduledStartAt == task.scheduledStartAt && reopened.tasks.first?.title == task.title, "range and original text survive restart")
        store.setStatus(task, .completed, now: date(2026, 10, 27, 17))
        store.refreshRecurring(now: date(2026, 10, 28, 9), calendar: calendar)
        try check(store.tasks.last?.scheduledStartAt == date(2026, 10, 28, 14, 30) && store.tasks.last?.dueAt == date(2026, 10, 28, 16, 30), "repeating range preserves duration")
        try check(wednesday?.label(calendar: calendar).contains("10月28日") == true, "readable calendar date")
    }
}
