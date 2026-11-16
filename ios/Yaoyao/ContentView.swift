import SwiftUI
import Combine
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var brewTarget: Prescription?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.activeTimers.isEmpty {
                        sectionTitle("正在熬")
                        ForEach(store.activeTimers) { t in
                            timerRow(t)
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

                    if !store.logs.isEmpty {
                        sectionTitle("最近记录")
                        VStack(spacing: 0) {
                            ForEach(Array(store.logs.prefix(8))) { log in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(shortDateText(log.date))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 84, alignment: .leading)
                                    Text(log.text).font(.subheadline)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                if log.id != store.logs.prefix(8).last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(cardBackground)
                    }
                }
                .padding(14)
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("熬药记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddPrescriptionSheet() }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .sheet(item: $brewTarget) { p in StartBrewSheet(prescription: p) }
        }
        .overlay(alignment: .top) { toastView }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            store.tick()
        }
    }

    // MARK: - 小组件

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

    private var toastView: some View {
        Group {
            if let b = store.banner {
                Text(b)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .padding(.top, 6)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.easeOut(duration: 0.25)) { store.banner = nil }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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

    private func timerRow(_ t: BrewTimer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.label).font(.headline).lineLimit(1)
                Spacer()
                Text(t.done ? "时间到" : clockText(t.secondsLeft))
                    .font(.system(.title2, design: .rounded))
                    .monospacedDigit()
                    .fontWeight(.bold)
                    .foregroundStyle(t.done ? Color.orange : Color.primary)
            }

            ProgressView(value: t.progress)
                .tint(t.done ? Color.orange : Color.accentColor)

            if t.done {
                HStack(spacing: 10) {
                    Button {
                        withAnimation { store.confirmBrew(t) }
                    } label: {
                        Text("熬好了").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        withAnimation { store.cancelTimer(t) }
                    } label: {
                        Text("不算这次").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Text("到点会响铃 + 振动，回来点「熬好了」记一次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 处方卡片

    private func prescriptionCard(_ p: Prescription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.name).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(p.isBrewedOut ? "已熬完" : "第 \(p.nextBrewIndex) / \(p.totalBrews) 次")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
        .contextMenu {
            Button {
                store.undoDrink(p)
            } label: {
                Label("撤销上一次「喝一碗」", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                store.delete(p)
            } label: {
                Label("删除这副药", systemImage: "trash")
            }
        }
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
                Capsule()
                    .fill(active ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemFill))
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
                store.delete(p)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(cardBackground)
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
                    Text("开始后会把提醒排进系统，锁屏也会响铃振动。")
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
