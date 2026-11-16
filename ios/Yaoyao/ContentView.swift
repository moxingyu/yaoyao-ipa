import SwiftUI
import Combine
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var store: Store
    @StateObject private var alarm = AlarmEngine.shared

    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showClearLogs = false
    @State private var brewTarget: Prescription?
    @State private var renaming: Prescription?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.activeTimers.isEmpty {
                        sectionTitle("正在熬")
                        ForEach(store.activeTimers) { t in
                            timerCard(t)
                        }
                    }

                    if store.activePrescriptions.isEmpty && store.finishedPrescriptions.isEmpty {
                        emptyCard
                    } else if !store.activePrescriptions.isEmpty {
                        sectionTitle("在喝的")
                        ForEach(store.activePrescriptions) { p in
                            prescriptionCard(p)
                        }
                    }

                    if !store.finishedPrescriptions.isEmpty {
                        sectionTitle("已喝完")
                        ForEach(store.finishedPrescriptions) { p in
                            finishedCard(p)
                        }
                    }

                    logsSection
                }
                .padding(14)
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("熬药记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showAdd) { AddPrescriptionSheet() }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .sheet(item: $brewTarget) { p in StartBrewSheet(prescription: p) }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                ringingBar
                toastView
            }
        }
        .alert("重命名这副药", isPresented: renameBinding) {
            TextField("药名", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let p = renaming { store.rename(p, to: renameText) }
                renaming = nil
            }
        }
        .alert("清空全部流水账？", isPresented: $showClearLogs) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clearLogs() }
        } message: {
            Text("只清记录，药和次数不受影响。")
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            store.tick()
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    // MARK: - 通用小组件

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var ringingBar: some View {
        if alarm.ringing {
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("闹铃正在响").font(.subheadline.weight(.bold))
                    Text(alarm.ringingTitles.joined(separator: " · "))
                        .font(.caption).opacity(0.9).lineLimit(1)
                }
                Spacer()
                Button {
                    alarm.stopAlarm()
                } label: {
                    Text("停止")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red))
            .padding(.horizontal, 14)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let b = store.banner {
            Text(b)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.horizontal, 14)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.25)) { store.banner = nil }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("还没有药").font(.headline)
            Text("点右上角 + 新增一副，填上药名和一共要熬几次。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(cardBackground)
    }

    // MARK: - 倒计时卡片

    private func timerCard(_ t: BrewTimer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ringView(t)
                VStack(alignment: .leading, spacing: 7) {
                    Text(t.label).font(.headline).lineLimit(1)
                    Text(t.done ? "时间到，去关火" : "预计 \(hourMinute(t.end)) 完成")
                        .font(.caption)
                        .foregroundStyle(t.done ? Color.orange : Color.secondary)

                    HStack(spacing: 8) {
                        Button {
                            withAnimation { store.confirmBrew(t) }
                        } label: {
                            Text("熬好了")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            withAnimation { store.cancelTimer(t) }
                        } label: {
                            Text("不算这次")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func ringView(_ t: BrewTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let left = t.secondsLeft
            let progress = t.progress
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .systemFill), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, max(0.002, progress)))
                    .stroke(
                        t.done ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.accentColor),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
                VStack(spacing: 0) {
                    Text(clockText(left))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(t.done ? "到点" : "剩余")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)
        }
    }

    // MARK: - 处方卡片

    private func prescriptionCard(_ p: Prescription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(p.name).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(p.isBrewedOut ? "已熬完" : "第 \(p.nextBrewIndex) / \(p.totalBrews) 次")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Menu {
                    Button {
                        renameText = p.name
                        renaming = p
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button {
                        store.undoDrink(p)
                    } label: {
                        Label("撤销一次喝药", systemImage: "arrow.uturn.backward")
                    }
                    Divider()
                    Button(role: .destructive) {
                        withAnimation { store.delete(p) }
                    } label: {
                        Label("删除这副药", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
            }

            HStack(spacing: 7) {
                ForEach(0..<p.totalBrews, id: \.self) { i in
                    Circle()
                        .fill(dotColor(index: i, p: p))
                        .frame(width: 15, height: 15)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                pill("待喝 \(p.waiting) 碗", active: p.waiting > 0)
                pill("还剩 \(p.remaining) 次", active: p.remaining > 0)
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    brewTarget = p
                } label: {
                    Label(p.isBrewedOut ? "已熬完" : "熬第 \(p.nextBrewIndex) 次", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(p.isBrewedOut)

                Button {
                    withAnimation { store.drink(p) }
                } label: {
                    Label("喝一碗", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(p.waiting == 0)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(cardBackground)
    }

    private func dotColor(index: Int, p: Prescription) -> Color {
        if index < p.drunk { return .accentColor }
        if index < p.brewed { return Color.accentColor.opacity(0.4) }
        return Color(uiColor: .systemFill)
    }

    private func pill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(active ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemFill))
            )
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    private func finishedCard(_ p: Prescription) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.subheadline.weight(.semibold))
                Text("共 \(p.totalBrews) 次，已全部喝完").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                withAnimation { store.delete(p) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - 流水账

    @ViewBuilder
    private var logsSection: some View {
        if !store.logs.isEmpty {
            HStack {
                Text("最近记录").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("清空") { showClearLogs = true }
                    .font(.footnote)
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(store.logs.prefix(10))) { log in
                    HStack(alignment: .top, spacing: 10) {
                        Text(shortDateText(log.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 82, alignment: .leading)
                        Text(log.text).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 9)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation { store.deleteLog(log) }
                        } label: {
                            Label("删除这条记录", systemImage: "trash")
                        }
                    }
                    if log.id != Array(store.logs.prefix(10)).last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(cardBackground)
        }
    }
}

// MARK: - 新增一副药

struct AddPrescriptionSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var total = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("药名") {
                    TextField("比如：补气血 2 号", text: $name)
                }
                Section {
                    Stepper("一共 \(total) 次", value: $total, in: 1...12)
                } header: {
                    Text("这副药要熬几次")
                } footer: {
                    Text("熬几次就是喝几次。喝完就把这副划掉。")
                }
            }
            .navigationTitle("新增一副药")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.addPrescription(name: name, total: total)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 开始熬

struct StartBrewSheet: View {
    let prescription: Prescription
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30

    private let presets = [15, 20, 30, 40, 45, 60, 90]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("时长")
                        Spacer()
                        Text("\(minutes) 分钟")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Stepper("", value: $minutes, in: 5...240, step: 5)
                        .labelsHidden()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { m in
                                Button {
                                    minutes = m
                                } label: {
                                    Text("\(m) 分")
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule().fill(minutes == m
                                                ? Color.accentColor
                                                : Color(uiColor: .systemFill))
                                        )
                                        .foregroundStyle(minutes == m ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("熬「\(prescription.name)」第 \(prescription.nextBrewIndex) 次")
                } footer: {
                    Text("开始后即使锁屏、切到别的 App，到点也会像闹钟一样响铃。")
                }

                Section {
                    Button {
                        store.startBrew(prescription, minutes: minutes)
                        dismiss()
                    } label: {
                        Text("开始倒计时")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("开始熬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @EnvironmentObject var store: Store
    @StateObject private var alarm = AlarmEngine.shared
    @Environment(\.dismiss) private var dismiss
    @State private var authText = "检查中…"
    @State private var showClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        DatePicker("第 \(i + 1) 次", selection: binding(i), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("每天喝药的提醒时间")
                } footer: {
                    Text("只在还有药没喝完的时候才会提醒。")
                }

                Section {
                    Button {
                        alarm.startAlarm(title: "测试")
                    } label: {
                        Label("响铃测试（可以锁屏试）", systemImage: "bell.badge")
                    }
                    if alarm.ringing {
                        Button(role: .destructive) {
                            alarm.stopAlarm()
                        } label: {
                            Label("停止响铃", systemImage: "stop.circle")
                        }
                    }
                } header: {
                    Text("响铃")
                } footer: {
                    Text("测试时会像闹钟一样连续响，锁屏也在响。别在安静场合点。")
                }

                Section("通知") {
                    Text(authText).font(.footnote).foregroundStyle(.secondary)
                    Button("申请通知权限") { store.requestNotificationPermission() }
                    Button("重新排一次提醒") { store.scheduleDrinkReminders() }
                }

                Section {
                    Button("清空所有记录", role: .destructive) { showClear = true }
                }

                Section {
                    Text("数据只存在这台手机里，不上传。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                switch s.authorizationStatus {
                case .authorized, .provisional:
                    authText = "通知已开启，到点会响铃振动。"
                case .denied:
                    authText = "通知被关掉了：去 iPhone 设置 > 通知 > 熬药记录，打开允许通知和声音。"
                default:
                    authText = "还没开通知权限，点下面的按钮开。"
                }
            }
            .alert("确定清空所有记录？", isPresented: $showClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { store.clearAll() }
            }
        }
    }

    private func binding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let m = index < store.drinkMinutes.count ? store.drinkMinutes[index] : 480
                var c = DateComponents()
                c.hour = m / 60
                c.minute = m % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var arr = store.drinkMinutes
                let value = (c.hour ?? 8) * 60 + (c.minute ?? 0)
                if index < arr.count { arr[index] = value }
                store.drinkMinutes = arr
            }
        )
    }
}
