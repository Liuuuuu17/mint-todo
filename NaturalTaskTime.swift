import Foundation

/// Local recognition with exact spans for extracting schedule text from a task title.
struct NaturalTaskTime: Equatable {
    var start: Date?
    var end: Date
    var dateOnly: Bool

    func label(calendar: Calendar = .current) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "zh_CN")
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.dateFormat = "M月d日 EEEE"
        if dateOnly { return date.string(from: end) }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "zh_CN")
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "HH:mm"
        guard let start else { return date.string(from: end) + " " + clock.string(from: end) }
        let endLabel = calendar.isDate(start, inSameDayAs: end) ? clock.string(from: end) : date.string(from: end) + " " + clock.string(from: end)
        return date.string(from: start) + " " + clock.string(from: start) + "–" + endLabel
    }

    static func parse(_ source: String, now: Date = Date(), calendar: Calendar = .current) -> Self? {
        recognize(source, now: now, calendar: calendar)?.time
    }

    static func extract(_ source: String, now: Date = Date(), calendar: Calendar = .current) -> (time: Self, title: String)? {
        guard let result = recognize(source, now: now, calendar: calendar) else { return nil }
        let text = source.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? source
        var merged: [NSRange] = []
        for range in result.ranges.sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        let title = NSMutableString(string: text)
        for range in merged.reversed() { title.deleteCharacters(in: range) }
        let cleaned = (title as String)
            .replacingOccurrences(of: #"[（(]\s*[)）]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。:：;；-—–")))
        // Time-only input must stay editable rather than creating an empty task.
        return (result.time, cleaned.isEmpty ? source : cleaned)
    }

    private static func recognize(_ source: String, now: Date, calendar: Calendar) -> (time: Self, ranges: [NSRange])? {
        let text = source.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? source
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        func part(_ match: NSTextCheckingResult, _ group: Int) -> String {
            guard let range = Range(match.range(at: group), in: text) else { return "" }
            return String(text[range])
        }
        let today = calendar.startOfDay(for: now)
        var day = today
        var foundDay = false
        var ranges: [NSRange] = []
        // Validate explicit dates rather than allowing Calendar to normalize impossible days.
        let explicit = matches(#"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]?|(?<!\d)(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?!\d)"#)
        guard explicit.count <= 1 else { return nil }
        if let match = explicit.first {
            let numeric = !part(match, 4).isEmpty
            let yearText = part(match, numeric ? 4 : 1)
            let year = Int(yearText) ?? calendar.component(.year, from: now)
            guard let month = Int(part(match, numeric ? 5 : 2)), let date = Int(part(match, numeric ? 6 : 3)) else { return nil }
            func validated(_ year: Int) -> Date? {
                guard let value = calendar.date(from: DateComponents(year: year, month: month, day: date)),
                      calendar.component(.year, from: value) == year,
                      calendar.component(.month, from: value) == month,
                      calendar.component(.day, from: value) == date else { return nil }
                return value
            }
            guard let value = validated(year) else { return nil }
            day = value
            if yearText.isEmpty && day < today {
                guard let value = validated(year + 1) else { return nil }
                day = value
            }
            ranges.append(match.range)
            foundDay = true
        } else if let match = matches("大后天|后天|明天|今天|今日|明日|今晚|今早|明早|明晚").first {
            let word = part(match, 0)
            let offset = ["大后天": 3, "后天": 2, "明天": 1, "明日": 1, "明早": 1, "明晚": 1][word] ?? 0
            day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            ranges.append(match.range)
            foundDay = true
        } else if let match = matches("(下下|下|本|这)?(?:周|星期|礼拜)([一二三四五六日天])").first {
            let prefix = part(match, 1)
            let weekday = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1][part(match, 2)]!
            let current = calendar.component(.weekday, from: today)
            let mondayOffset = (current + 5) % 7
            let targetOffset = (weekday + 5) % 7
            var delta = targetOffset - mondayOffset
            if prefix == "下" { delta += 7 }
            else if prefix == "下下" { delta += 14 }
            else if prefix.isEmpty && delta < 0 { delta += 7 }
            day = calendar.date(byAdding: .day, value: delta, to: today) ?? today
            ranges.append(match.range)
            foundDay = true
        }
        let clocks = matches(#"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|晚间|今晚|今早|明早|明晚)?\s*([0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})(?:[:：]([0-9]{1,2})|[点时](半|一刻|三刻|[0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})?分?)"#)
        guard clocks.count <= 2 else { return nil }
        if clocks.isEmpty {
            guard foundDay, let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) else { return nil }
            return (Self(start: nil, end: end, dateOnly: true), ranges)
        }
        func clock(_ match: NSTextCheckingResult, inheritedPeriod: String = "") -> Date? {
            guard var hour = number(part(match, 2)) else { return nil }
            let minuteWord = part(match, 3).isEmpty ? part(match, 4) : part(match, 3)
            let minute: Int
            switch minuteWord {
            case "": minute = 0
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default: guard let value = number(minuteWord) else { return nil }; minute = value
            }
            let period = part(match, 1).isEmpty ? inheritedPeriod : part(match, 1)
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            if !period.isEmpty {
                guard hour <= 12 else { return nil }
                if ["下午", "傍晚", "晚上", "晚间", "今晚", "明晚"].contains(period), hour < 12 { hour += 12 }
                else if period == "中午", hour < 11 { hour += 12 }
                else if ["凌晨", "早上", "早晨", "上午", "今早", "明早"].contains(period), hour == 12 { hour = 0 }
            }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        guard let first = clock(clocks[0]) else { return nil }
        guard clocks.count == 2 else { return (Self(start: nil, end: first, dateOnly: false), ranges + [clocks[0].range]) }
        let gap = NSRange(location: NSMaxRange(clocks[0].range), length: clocks[1].range.location - NSMaxRange(clocks[0].range))
        guard let gapRange = Range(gap, in: text),
              String(text[gapRange]).trimmingCharacters(in: .whitespaces).range(of: #"^(到|至|[-—–~～])$"#, options: .regularExpression) != nil,
              var end = clock(clocks[1], inheritedPeriod: part(clocks[0], 1)) else { return nil }
        if end <= first {
            guard calendar.component(.hour, from: first) >= 18, calendar.component(.hour, from: end) < 8,
                  let next = calendar.date(byAdding: .day, value: 1, to: end) else { return nil }
            end = next
        }
        return (Self(start: first, end: end, dateOnly: false), ranges + [NSUnionRange(clocks[0].range, clocks[1].range)])
    }

    private static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let ten = text.firstIndex(of: "十") {
            let left = String(text[..<ten]), right = String(text[text.index(after: ten)...])
            guard left.count <= 1, right.count <= 1 else { return nil }
            let tens = left.isEmpty ? 1 : left.first.flatMap { digits[$0] }
            let ones = right.isEmpty ? 0 : right.first.flatMap { digits[$0] }
            guard let tens, let ones else { return nil }
            return tens * 10 + ones
        }
        return text.count == 1 ? text.first.flatMap { digits[$0] } : nil
    }
}
