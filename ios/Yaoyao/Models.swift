import Foundation

/// 一副药
struct Prescription: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// 这副药一共熬几次（= 一共喝几次）
    var totalBrews: Int
    /// 已熬次数
    var brewed: Int = 0
    /// 已喝次数
    var drunk: Int = 0
    var createdAt: Date = Date()

    /// 熬好但还没喝的碗数
    var waiting: Int { max(0, brewed - drunk) }
    /// 还剩几次没喝
    var remaining: Int { max(0, totalBrews - drunk) }
    /// 下次该熬第几次
    var nextBrewIndex: Int { min(brewed + 1, totalBrews) }
    var isBrewedOut: Bool { brewed >= totalBrews }
    var isDone: Bool { drunk >= totalBrews }
}

/// 一个正在跑的倒计时
struct BrewTimer: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var prescriptionID: UUID?
    var label: String
    /// 总时长（秒）
    var duration: Int
    var start: Date
    var end: Date
    /// 已经响过铃、等用户确认
    var done: Bool = false

    var secondsLeft: Int { max(0, Int(end.timeIntervalSinceNow.rounded())) }

    var progress: Double {
        guard duration > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / Double(duration)))
    }
}

/// 一条流水账
struct LogEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var text: String
}

/// 秒 -> "12:34"
func clockText(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}

/// 分钟数 -> "08:00"
func timeText(_ minutesOfDay: Int) -> String {
    String(format: "%02d:%02d", minutesOfDay / 60, minutesOfDay % 60)
}

func shortDateText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "M月d日 HH:mm"
    return f.string(from: date)
}
