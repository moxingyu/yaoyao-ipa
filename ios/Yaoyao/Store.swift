import Foundation
import SwiftUI
import UserNotifications
import AudioToolbox
import Combine

final class Store: ObservableObject {

    @Published var prescriptions: [Prescription] = [] { didSet { save() } }
    @Published var timers: [BrewTimer] = [] { didSet { save() } }
    @Published var logs: [LogEntry] = [] { didSet { save() } }
    @Published var drinkMinutes: [Int] = [480, 750, 1080] {
        didSet { save(); scheduleDrinkReminders() }
    }
    @Published var banner: String? = nil

    private let stateKey = "yaoyao.state.v1"
    private var lastScheduleDay: String = ""

    struct Snapshot: Codable {
        var prescriptions: [Prescription] = []
        var timers: [BrewTimer] = []
        var logs: [LogEntry] = []
        var drinkMinutes: [Int] = [480, 750, 1080]
    }

    init() {
        load()
    }

    // MARK: - 派生数据

    var activePrescriptions: [Prescription] {
        prescriptions.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
    }

    var finishedPrescriptions: [Prescription] {
        prescriptions.filter { $0.isDone }.sorted { $0.createdAt > $1.createdAt }
    }

    var activeTimers: [BrewTimer] {
        timers.sorted { $0.end < $1.end }
    }

    // MARK: - 启动

    func bootstrap() {
        requestNotificationPermission()
        for t in timers where !t.done && Date() >= t.end {
            if let i = timers.firstIndex(where: { $0.id == t.id }) {
                timers[i].done = true
            }
        }
        if timers.contains(where: { !$0.done }) {
            AlarmEngine.shared.startKeepAlive()
        }
        scheduleDrinkReminders()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - 处方

    func addPrescription(name: String, total: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Prescription(name: trimmed.isEmpty ? "这副药" : trimmed, totalBrews: max(1, total))
        prescriptions.append(p)
        addLog("新建：\(p.name)，共 \(p.totalBrews) 次")
        scheduleDrinkReminders()
    }

    func rename(_ p: Prescription, to newName: String) {
        guard let i = prescriptions.firstIndex(where: { $0.id == p.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let old = prescriptions[i].name
        prescriptions[i].name = trimmed
        addLog("改名：\(old) → \(trimmed)")
    }

    func drink(_ p: Prescription) {
        guard let i = prescriptions.firstIndex(where: { $0.id == p.id }) else { return }
        guard prescriptions[i].waiting > 0 else {
            banner = "还没熬好，先熬一锅"
            return
        }
        prescriptions[i].drunk += 1
        addLog("\(prescriptions[i].name) 喝掉第 \(prescriptions[i].drunk) 次")
        if prescriptions[i].isDone {
            addLog("🎉 \(prescriptions[i].name) 这副喝完了")
            banner = "\(prescriptions[i].name) 喝完了，记得安排下一副"
        }
        scheduleDrinkReminders()
    }

    func undoDrink(_ p: Prescription) {
        guard let i = prescriptions.firstIndex(where: { $0.id == p.id }) else { return }
        guard prescriptions[i].drunk > 0 else { return }
        prescriptions[i].drunk -= 1
        addLog("\(prescriptions[i].name) 撤销一次喝药")
    }

    func delete(_ p: Prescription) {
        prescriptions.removeAll { $0.id == p.id }
        timers.removeAll { $0.prescriptionID == p.id }
        addLog("删除：\(p.name)")
        syncKeepAlive()
    }

    // MARK: - 倒计时

    func startBrew(_ p: Prescription, minutes: Int) {
        let now = Date()
        let t = BrewTimer(
            prescriptionID: p.id,
            label: p.name,
            duration: minutes * 60,
            start: now,
            end: now.addingTimeInterval(Double(minutes * 60))
        )
        timers.append(t)
        scheduleTimerNotification(t)
        AlarmEngine.shared.startKeepAlive()
        addLog("开火：\(p.name) 第 \(p.nextBrewIndex) 次，\(minutes) 分钟")
    }

    func cancelTimer(_ t: BrewTimer) {
        timers.removeAll { $0.id == t.id }
        removeNotification("timer-\(t.id.uuidString)")
        AlarmEngine.shared.stopAlarm(title: t.label)
        addLog("取消倒计时：\(t.label)")
        syncKeepAlive()
    }

    /// 倒计时结束后用户确认「熬好了」
    func confirmBrew(_ t: BrewTimer) {
        timers.removeAll { $0.id == t.id }
        removeNotification("timer-\(t.id.uuidString)")
        AlarmEngine.shared.stopAlarm(title: t.label)
        guard let pid = t.prescriptionID,
              let i = prescriptions.firstIndex(where: { $0.id == pid }) else {
            syncKeepAlive()
            return
        }
        prescriptions[i].brewed = min(prescriptions[i].totalBrews, prescriptions[i].brewed + 1)
        addLog("\(prescriptions[i].name) 熬好第 \(prescriptions[i].brewed) 次")
        banner = "\(prescriptions[i].name) 第 \(prescriptions[i].brewed) 次记上了"
        syncKeepAlive()
    }

    /// 每秒调用一次：检查有没有到点
    func tick() {
        let now = Date()
        var firedLabels: [String] = []
        for t in timers where !t.done && now >= t.end {
            if let i = timers.firstIndex(where: { $0.id == t.id }) {
                timers[i].done = true
                firedLabels.append(t.label)
            }
        }
        if !firedLabels.isEmpty {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            for label in firedLabels {
                AlarmEngine.shared.startAlarm(title: label)
            }
            banner = firedLabels.count > 1
                ? "「\(firedLabels.joined(separator: "」「"))」都到点了"
                : "熬药时间到，去关火"
        }
        AlarmEngine.shared.refreshIfFinished()

        let dayKey = Calendar.current.startOfDay(for: now).description
        if dayKey != lastScheduleDay {
            lastScheduleDay = dayKey
            scheduleDrinkReminders()
        }
    }

    private func syncKeepAlive() {
        if timers.contains(where: { !$0.done }) {
            AlarmEngine.shared.startKeepAlive()
        } else if !AlarmEngine.shared.ringing {
            AlarmEngine.shared.stopKeepAlive()
        }
    }

    // MARK: - 通知

    /// 用 25 秒短铃当通知声音：锁屏时能连着响 30 秒，不会只"叮"一声
    private func alarmSound() -> UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName("alarm.m4a"))
    }

    private func scheduleTimerNotification(_ t: BrewTimer) {
        let content = UNMutableNotificationContent()
        content.title = "熬药时间到"
        content.body = "「\(t.label)」已经 \(t.duration / 60) 分钟，该关火了。"
        content.sound = alarmSound()
        content.interruptionLevel = .timeSensitive
        let interval = max(1, t.end.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "timer-\(t.id.uuidString)", content: content, trigger: trigger)
        )
    }

    /// 排未来 3 天的喝药提醒（只在还有药没喝完时才排）
    func scheduleDrinkReminders() {
        let center = UNUserNotificationCenter.current()
        var ids: [String] = []
        for d in 0..<3 {
            for i in 0..<drinkMinutes.count {
                ids.append("drink-\(d)-\(i)")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard !activePrescriptions.isEmpty else { return }

        let cal = Calendar.current
        let now = Date()
        for d in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: d, to: now) else { continue }
            for (i, minutes) in drinkMinutes.enumerated() {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                guard let fire = cal.date(from: comps), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "该喝药了"
                content.body = "\(timeText(minutes)) 这一碗，别忘了。"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, fire.timeIntervalSinceNow), repeats: false)
                center.add(UNNotificationRequest(identifier: "drink-\(d)-\(i)", content: content, trigger: trigger))
            }
        }
    }

    private func removeNotification(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - 记账

    func addLog(_ text: String) {
        logs.insert(LogEntry(text: text), at: 0)
        if logs.count > 200 { logs = Array(logs.prefix(200)) }
    }

    func deleteLog(_ log: LogEntry) {
        logs.removeAll { $0.id == log.id }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func clearAll() {
        prescriptions = []
        timers = []
        logs = []
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        AlarmEngine.shared.stopAlarm()
        AlarmEngine.shared.stopKeepAlive()
    }

    // MARK: - 存取

    private func save() {
        let snap = Snapshot(prescriptions: prescriptions, timers: timers, logs: logs, drinkMinutes: drinkMinutes)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        prescriptions = snap.prescriptions
        timers = snap.timers
        logs = snap.logs
        if snap.drinkMinutes.count == 3 { drinkMinutes = snap.drinkMinutes }
    }
}
