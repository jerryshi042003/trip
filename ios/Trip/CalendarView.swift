import SwiftUI

// Calendar for the Plan screen, marked from the free-text plan dates (same rules as the website).
// "Fri Nov 20", "Nov 30 – Dec 4", "Dec 15 – 19" are exact; anything else naming a day
// ("By Dec 20", "Dec 14 or ~Dec 5") is shown dashed as not firm. The rest is listed as undated.

struct PlanSpan {
    let start: Date
    let end: Date
    let tentative: Bool
}

enum PlanDates {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let exact = try! NSRegularExpression(
        pattern: #"^(?:[A-Za-z]{3,9}\.?,?\s+)?([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:\s*[–—-]\s*(?:([A-Za-z]{3,9})\.?\s+)?(\d{1,2}))?$"#)
    private static let loose = try! NSRegularExpression(pattern: #"([A-Za-z]{3,9})\.?\s+(\d{1,2})\b"#)

    static var cal: Calendar { Calendar(identifier: .gregorian) }

    private static func month(_ s: String) -> Int? {
        months.firstIndex(of: String(s.prefix(3)).lowercased())
    }

    /// Dates carry no year: pick the year that keeps them near when trip.json was last updated.
    private static func date(_ month: Int, _ day: Int, ref: Date) -> Date? {
        let refMonth = cal.component(.month, from: ref) - 1
        var year = cal.component(.year, from: ref)
        if month - refMonth < -5 { year += 1 } else if month - refMonth > 6 { year -= 1 }
        return cal.date(from: DateComponents(year: year, month: month + 1, day: day))
    }

    static func parse(_ raw: String, ref: Date) -> PlanSpan? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        if let m = exact.firstMatch(in: s, range: full),
           let m1 = group(m, 1).flatMap(month), let d1 = group(m, 2).flatMap(Int.init),
           let start = date(m1, d1, ref: ref) {
            let m2 = group(m, 3).map(month) ?? m1
            if let m2, let d2 = group(m, 4).flatMap(Int.init), let end = date(m2, d2, ref: ref) {
                return PlanSpan(start: start, end: max(start, end), tentative: false)
            }
            if group(m, 3) == nil { return PlanSpan(start: start, end: start, tentative: false) }
        }
        for m in loose.matches(in: s, range: full) {
            if let mo = group(m, 1).flatMap(month), let d = group(m, 2).flatMap(Int.init), let day = date(mo, d, ref: ref) {
                return PlanSpan(start: day, end: day, tentative: true)
            }
        }
        return nil
    }

    static func ref(_ data: TripData?) -> Date {
        if let u = data?.updated {
            let f = DateFormatter()
            f.calendar = cal
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: u) { return d }
        }
        return Date()
    }
}

enum CityColor {
    static func of(_ city: String?) -> Color {
        switch city?.lowercased() {
        case "manila": .blue
        case "cebu": .teal
        case "siargao": .orange
        case "tokyo": .pink
        default: .gray
        }
    }
}

struct TripCalendar: View {
    struct Entry: Identifiable {
        let id: String
        let item: PlanItem
        let span: PlanSpan
        let city: String?
        var lane = 0
    }

    let data: TripData
    let traveler: Traveler
    @State private var selected: Date?

    private var cal: Calendar { PlanDates.cal }
    private var ref: Date { PlanDates.ref(data) }

    private var entries: [Entry] {
        let places = Dictionary(uniqueKeysWithValues: data.places.map { ($0.id, $0) })
        var list = traveler.plan.compactMap { item -> Entry? in
            guard let span = PlanDates.parse(item.date, ref: ref) else { return nil }
            return Entry(id: item.id, item: item, span: span, city: item.place.flatMap { places[$0]?.city })
        }.sorted { $0.span.start < $1.span.start }
        var laneEnds: [Date] = []
        for i in list.indices {
            var l = 0
            while l < laneEnds.count && laneEnds[l] >= list[i].span.start { l += 1 }
            if l == laneEnds.count { laneEnds.append(list[i].span.end) } else { laneEnds[l] = list[i].span.end }
            list[i].lane = l
        }
        return list
    }

    /// Months covered by both travelers' dates, so switching traveler keeps the same months.
    private var monthStarts: [Date] {
        let spans = data.travelers.values.flatMap { $0.plan.compactMap { PlanDates.parse($0.date, ref: ref) } }
        guard let first = spans.map(\.start).min(), let last = spans.map(\.end).max(),
              var m = cal.date(from: cal.dateComponents([.year, .month], from: first)) else { return [] }
        var out: [Date] = []
        while m <= last {
            out.append(m)
            m = cal.date(byAdding: .month, value: 1, to: m)!
        }
        return out
    }

    var body: some View {
        let entries = entries
        let lanes = max(1, (entries.map(\.lane).max() ?? 0) + 1)
        VStack(alignment: .leading, spacing: 18) {
            ForEach(monthStarts, id: \.self) { month in
                MonthGrid(month: month, entries: entries, lanes: lanes, selected: $selected)
                if let s = selected, cal.isDate(s, equalTo: month, toGranularity: .month) {
                    let on = entries.filter { $0.span.start <= s && s <= $0.span.end }
                    if !on.isEmpty { DayDetail(day: s, entries: on) }
                }
            }
            legend(entries)
            let undated = traveler.plan.filter { PlanDates.parse($0.date, ref: ref) == nil }
            if !undated.isEmpty {
                Text("No date yet: " + undated.map(\.title).joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: traveler.name) { _, _ in selected = nil }
    }

    @ViewBuilder private func legend(_ entries: [Entry]) -> some View {
        let cities = entries.compactMap(\.city).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        HStack(spacing: 14) {
            ForEach(cities, id: \.self) { c in
                Label { Text(c) } icon: { RoundedRectangle(cornerRadius: 3).fill(CityColor.of(c)).frame(width: 10, height: 10) }
            }
            if entries.contains(where: \.span.tentative) {
                Label { Text("Not firm") } icon: { DashBar(color: .gray).frame(width: 12, height: 5) }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

private struct MonthGrid: View {
    let month: Date
    let entries: [TripCalendar.Entry]
    let lanes: Int
    @Binding var selected: Date?

    private var cal: Calendar { PlanDates.cal }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let lead = cal.component(.weekday, from: month) - 1
        let count = cal.range(of: .day, in: .month, for: month)!.count
        VStack(alignment: .leading, spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, w in
                    Text(w).font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...count, id: \.self) { n in
                    let day = cal.date(byAdding: .day, value: n - 1, to: month)!
                    DayCell(day: day, last: n == count, entries: entries, lanes: lanes, selected: $selected)
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let last: Bool
    let entries: [TripCalendar.Entry]
    let lanes: Int
    @Binding var selected: Date?

    private var cal: Calendar { PlanDates.cal }

    var body: some View {
        let on = entries.filter { $0.span.start <= day && day <= $0.span.end }
        let weekday = cal.component(.weekday, from: day)
        let isToday = cal.isDateInToday(day)
        let isPast = day < cal.startOfDay(for: Date())
        let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let n = cal.component(.day, from: day)
        Button {
            selected = isSel ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(n)")
                    .font(.footnote.monospacedDigit().weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color(.systemBackground) : isPast ? .secondary : .primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isToday ? Color.accentColor : .clear))
                ForEach(0..<lanes, id: \.self) { lane in
                    if let e = on.first(where: { $0.lane == lane }) {
                        let l = cal.isDate(day, inSameDayAs: e.span.start) || weekday == 1 || n == 1
                        let r = cal.isDate(day, inSameDayAs: e.span.end) || weekday == 7 || last
                        bar(e, left: l, right: r)
                    } else {
                        Color.clear.frame(height: 5)
                    }
                }
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? Color(.tertiarySystemFill) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(on.isEmpty)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            + (on.isEmpty ? "" : ": " + on.map(\.item.title).joined(separator: ", ")))
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    @ViewBuilder private func bar(_ e: TripCalendar.Entry, left: Bool, right: Bool) -> some View {
        let color = CityColor.of(e.city)
        Group {
            if e.span.tentative {
                DashBar(color: color)
            } else {
                UnevenRoundedRectangle(topLeadingRadius: left ? 3 : 0, bottomLeadingRadius: left ? 3 : 0,
                                       bottomTrailingRadius: right ? 3 : 0, topTrailingRadius: right ? 3 : 0)
                    .fill(color)
            }
        }
        .frame(height: 5)
        .padding(.leading, left ? 4 : 0)
        .padding(.trailing, right ? 4 : 0)
    }
}

private struct DashBar: View {
    let color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: g.size.height, dash: [3, 2]))
        }
    }
}

private struct DayDetail: View {
    let day: Date
    let entries: [TripCalendar.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(entries) { e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(CityColor.of(e.city)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.item.title)
                        Text([e.item.date, e.item.sub].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
