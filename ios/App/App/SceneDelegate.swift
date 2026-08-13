import UIKit
import Capacitor
import SwiftUI
import AVFoundation

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = UIHostingController(rootView: NativeRootView())
        window?.makeKeyAndVisible()
        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

private struct NativeRootView: View {
    @StateObject private var session = NativeSession()

    var body: some View {
        Group {
            if session.loggedIn { NativeTabView().environmentObject(session) }
            else { NativeLoginView().environmentObject(session) }
        }
        .tint(Color(red: 0.08, green: 0.49, blue: 0.96))
    }
}

private struct NativeLoginView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var account = "admin"
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 54)).foregroundStyle(.blue)
                Text("内部管理 App").font(.title.bold())
                Text("原生 iOS 工作台").foregroundStyle(.secondary)
                VStack(spacing: 14) {
                    TextField("账号", text: $account)
                        .textContentType(.username).textInputAutocapitalization(.never)
                        .nativeField()
                    SecureField("密码", text: $password)
                        .textContentType(.password).nativeField()
                    Button(session.loading ? "登录中..." : "登录") {
                        Task { await session.login(username: account, password: password) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(session.loading || account.isEmpty || password.isEmpty)
                    if let error = session.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                Spacer()
            }
            .padding(22).background(Color(.systemGroupedBackground)).navigationBarHidden(true)
        }
    }
}

private struct NativeTabView: View {
    var body: some View {
        TabView {
            NativeHomeView().tabItem { Label("首页", systemImage: "house") }
            NativeTaskView().tabItem { Label("任务", systemImage: "checklist") }
            NativeLedgerView().tabItem { Label("记账", systemImage: "wallet.pass") }
            NativeLinksView().tabItem { Label("链接", systemImage: "link") }
            NativeMineView().tabItem { Label("我的", systemImage: "person") }
        }
    }
}

private struct NativeHomeView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var message = ""
    @State private var messages = [ChatMessage(text: "你好！请告诉我需要处理什么问题。", sent: false)]
    @State private var sending = false
    @State private var models: [AIModel] = []
    @State private var selectedModel = ""
    @State private var audioModel = ""
    @StateObject private var recorder = NativeAudioRecorder()
    @State private var voiceError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { item in
                            HStack {
                                if item.sent { Spacer(minLength: 50) }
                                Text(item.text).padding(14)
                                    .foregroundStyle(item.sent ? Color.white : Color.primary)
                                    .background(item.sent ? Color.blue : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                                if !item.sent { Spacer(minLength: 50) }
                            }
                        }
                        if sending { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                    }.padding()
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        Image(systemName: recorder.recording ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 34)).foregroundStyle(recorder.recording ? .red : .blue)
                    }.disabled(recorder.transcribing)
                    TextField("给 AI 发消息...", text: $message, axis: .vertical)
                        .lineLimit(1...4).nativeField()
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                        .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
                if recorder.transcribing { Label("正在转写语音...", systemImage: "waveform").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8) }
                if let voiceError { Text(voiceError).font(.caption).foregroundStyle(.red).padding(.horizontal).padding(.bottom, 8) }
            }
            .navigationTitle("AI 工作台").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(models.filter { $0.modelType != "audio" }) { model in
                            Button { selectedModel = model.id } label: { if selectedModel == model.id { Label(model.name, systemImage: "checkmark") } else { Text(model.name) } }
                        }
                    } label: { Label(models.first(where: { $0.id == selectedModel })?.name ?? "选择模型", systemImage: "cpu") }
                }
            }
            .task { await loadModels() }
        }
    }

    private func send() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        messages.append(ChatMessage(text: value, sent: true)); message = ""; sending = true
        Task {
            let answer = await session.chat(value, modelID: selectedModel) ?? "服务没有返回内容。"
            messages.append(ChatMessage(text: answer, sent: false)); sending = false
        }
    }

    private func loadModels() async {
        do {
            let result: AIModelsResponse = try await session.get("ai-api/models")
            models = result.models.filter { $0.enabled != 0 && $0.hidden != 1 }
            if selectedModel.isEmpty { selectedModel = models.first(where: { $0.modelType != "audio" })?.id ?? "" }
            audioModel = models.first(where: { $0.modelType == "audio" })?.id ?? ""
        } catch { voiceError = session.message(for: error) }
    }

    private func toggleRecording() async {
        voiceError = nil
        if recorder.recording {
            guard let recording = recorder.stop() else { return }
            recorder.transcribing = true; defer { recorder.transcribing = false }
            do {
                let response: TranscriptionResponse = try await session.send("ai-api/audio/transcriptions", method: "POST", body: ["filename": "recording.m4a", "data": recording.base64EncodedString(), "model_id": audioModel])
                message = [message, response.text].filter { !$0.isEmpty }.joined(separator: " ")
            } catch { voiceError = session.message(for: error) }
        } else {
            do { try await recorder.start() } catch { voiceError = "无法使用麦克风，请在系统设置中允许麦克风权限。" }
        }
    }
}

private struct NativeTaskView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var records: [TaskRecord] = []
    @State private var summary: TaskSummary?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var editing: TaskRecord?
    @State private var showingForm = false

    private var filtered: [TaskRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { "\($0.orderNo) \($0.shopName) \($0.ownerName) \($0.note ?? "")".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section {
                        HStack {
                            Metric(title: "任务", value: "\(summary.totalRecords)")
                            Metric(title: "待签收", value: "\(summary.pendingSignedCount)")
                            Metric(title: "待结算", value: "\(summary.pendingSettlementCount)")
                        }
                        HStack {
                            Text("本金合计").foregroundStyle(.secondary)
                            Spacer(); Text(money(summary.principalTotal)).fontWeight(.semibold)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section("任务记录") {
                    ForEach(filtered) { item in
                        NavigationLink {
                            TaskDetail(item: item) { await load() }
                        } label: { VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.shopName).font(.headline); Spacer(); Text(money(item.principalAmount)).fontWeight(.semibold) }
                            Text("\(item.orderNo) · \(item.ownerName)").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                StatusBadge(text: item.signedStatus == "completed" ? "已签收" : "待签收", done: item.signedStatus == "completed")
                                StatusBadge(text: item.settlementStatus == "completed" ? "已结算" : "待结算", done: item.settlementStatus == "completed")
                                Spacer(); Text(shortDate(item.taskTime)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4) }
                        .swipeActions(edge: .leading) { Button("编辑") { editing = item; showingForm = true }.tint(.blue) }
                    }
                }
            }
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索订单、店铺或负责人")
            .refreshable { await load() }
            .navigationTitle("任务")
            .toolbar { Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showingForm) { TaskForm(item: editing) { await load() } }
            .task { if records.isEmpty { await load() } }
        }
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            async let fetchedRecords: [TaskRecord] = session.get("task-bookkeeping/records")
            async let fetchedSummary: TaskSummary = session.get("task-bookkeeping/summary")
            records = try await fetchedRecords; summary = try await fetchedSummary
        } catch { self.error = session.message(for: error) }
    }
}

private struct NativeLedgerView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var records: [CompanyExpense] = []
    @State private var summary: ExpenseSummary?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var deleting: CompanyExpense?
    @State private var editing: CompanyExpense?
    @State private var showingForm = false

    private var filtered: [CompanyExpense] {
        guard !query.isEmpty else { return records }
        return records.filter { "\($0.expenseNo) \($0.category) \($0.paymentAccount) \($0.description) \($0.submitterName)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("本月消费").font(.caption).foregroundStyle(.secondary)
                            Text(money(summary.monthTotal)).font(.title.bold())
                            HStack { Metric(title: "本月笔数", value: "\(summary.monthRecordCount)"); Metric(title: "待报销", value: money(summary.pendingReimbursementTotal)) }
                        }.padding(.vertical, 5)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section("流水") {
                    ForEach(filtered) { item in
                        NavigationLink { ExpenseDetail(item: item) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.paymentType == "company" ? "building.columns" : "person.crop.circle")
                                    .frame(width: 34, height: 34).background(Color.blue.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.category).fontWeight(.medium)
                                    Text("\(item.paymentAccount) · \(item.submitterName)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) { Text(money(item.amount)).fontWeight(.semibold); Text(item.expenseDate).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { deleting = item }
                            Button("编辑") { editing = item; showingForm = true }.tint(.blue)
                        }
                    }
                }
            }
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索分类、账户或说明")
            .refreshable { await load() }.navigationTitle("公司记账")
            .task { if records.isEmpty { await load() } }
            .toolbar { Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showingForm) { ExpenseForm(item: editing) { await load() } }
            .confirmationDialog("确定删除这条记账记录吗？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let item = deleting { Task { await remove(item) } } }
                Button("取消", role: .cancel) { deleting = nil }
            }
        }
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            async let fetchedRecords: [CompanyExpense] = session.get("company-expenses")
            async let fetchedSummary: ExpenseSummary = session.get("company-expenses/summary")
            records = try await fetchedRecords; summary = try await fetchedSummary
        } catch { self.error = session.message(for: error) }
    }

    private func remove(_ item: CompanyExpense) async {
        do { try await session.delete("company-expenses/\(item.id)"); records.removeAll { $0.id == item.id }; deleting = nil }
        catch { self.error = session.message(for: error); deleting = nil }
    }
}

private struct NativeLinksView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var records: [SavedLink] = []
    @State private var query = ""
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var deleting: SavedLink?
    @State private var editing: SavedLink?
    @State private var showingForm = false
    private let pageSize = 15

    private var filtered: [SavedLink] {
        let rows = query.isEmpty ? records : records.filter { "\($0.title) \($0.url ?? "") \($0.category ?? "") \($0.description ?? "") \($0.authorUsername)".localizedCaseInsensitiveContains(query) }
        return rows.sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 9) {
                            Text(String(item.authorUsername.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Color.blue, in: Circle())
                            VStack(alignment: .leading) { Text(item.authorUsername).font(.subheadline.bold()); Text(shortDate(item.createdAt)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                            Menu {
                                Button("编辑") { editing = item; showingForm = true }
                                Button(item.isPinned ? "取消置顶" : "置顶") { Task { await togglePin(item) } }
                                Button("删除", role: .destructive) { deleting = item }
                            } label: { Image(systemName: "ellipsis") }
                        }
                        Text(item.title).font(.headline)
                        if let description = item.description, !description.isEmpty { Text(description).lineLimit(4).foregroundStyle(.secondary) }
                        if let url = item.url, let destination = URL(string: url) { Link(destination: destination) { Label(destination.host ?? url, systemImage: "safari") }.font(.subheadline) }
                        if !item.images.isEmpty { Label("\(item.images.count) 张图片", systemImage: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                if hasMore && query.isEmpty {
                    Button { Task { await loadMore() } } label: { HStack { Spacer(); if loadingMore { ProgressView() } else { Text("加载更多") }; Spacer() } }.disabled(loadingMore)
                }
            }
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索标题、用户或正文")
            .refreshable { await load() }.navigationTitle("链接广场")
            .task { if records.isEmpty { await load() } }
            .toolbar { Button { editing = nil; showingForm = true } label: { Image(systemName: "square.and.pencil") } }
            .sheet(isPresented: $showingForm) { LinkForm(item: editing) { await load() } }
            .confirmationDialog("确定删除这个帖子吗？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let item = deleting { Task { await remove(item) } } }
                Button("取消", role: .cancel) { deleting = nil }
            }
        }
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { records = try await session.get("saved-links?offset=0&limit=\(pageSize)"); hasMore = records.count == pageSize }
        catch { self.error = session.message(for: error) }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }; loadingMore = true; defer { loadingMore = false }
        do {
            let more: [SavedLink] = try await session.get("saved-links?offset=\(records.count)&limit=\(pageSize)")
            let ids = Set(records.map(\.id)); records.append(contentsOf: more.filter { !ids.contains($0.id) }); hasMore = more.count == pageSize
        } catch { self.error = session.message(for: error) }
    }

    private func togglePin(_ item: SavedLink) async {
        do {
            let updated: SavedLink = try await session.send("saved-links/\(item.id)/pin", method: item.isPinned ? "DELETE" : "POST")
            if let index = records.firstIndex(where: { $0.id == updated.id }) { records[index] = updated }
        } catch { self.error = session.message(for: error) }
    }

    private func remove(_ item: SavedLink) async {
        do { try await session.delete("saved-links/\(item.id)"); records.removeAll { $0.id == item.id }; deleting = nil }
        catch { self.error = session.message(for: error); deleting = nil }
    }
}

private struct TaskDetail: View {
    @EnvironmentObject private var session: NativeSession
    @State var item: TaskRecord
    let onChange: () async -> Void
    @State private var error: String?
    @State private var updating = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section("任务信息") {
                LabeledContent("订单号", value: item.orderNo); LabeledContent("店铺", value: item.shopName)
                LabeledContent("负责人", value: item.ownerName); LabeledContent("任务时间", value: shortDate(item.taskTime))
                LabeledContent("刷单数量", value: "\(item.orderCount)")
            }
            Section("金额") {
                LabeledContent("本金", value: money(item.principalAmount)); LabeledContent("佣金", value: money(item.commissionAmount)); LabeledContent("礼品", value: money(item.giftAmount))
            }
            Section("状态") {
                Toggle("已签收", isOn: Binding(get: { item.signedStatus == "completed" }, set: { value in Task { await update("signed_status", value) } })).disabled(updating)
                Toggle("已结算", isOn: Binding(get: { item.settlementStatus == "completed" }, set: { value in Task { await update("settlement_status", value) } })).disabled(updating)
            }
            if let note = item.note, !note.isEmpty { Section("备注") { Text(note) } }
        }.navigationTitle(item.shopName).navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ field: String, _ done: Bool) async {
        updating = true; defer { updating = false }
        do {
            let _: EmptyResponse = try await session.send("task-bookkeeping/records/batch-status", method: "PATCH", body: ["record_ids": [item.id], "field": field, "value": done ? "completed" : "pending"], allowEmpty: true)
            let refreshed: TaskRecord = try await session.get("task-bookkeeping/records/\(item.id)"); item = refreshed; await onChange()
        } catch { self.error = session.message(for: error) }
    }
}

private struct TaskForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: TaskRecord?
    let onSave: () async -> Void
    @State private var shopName: String
    @State private var ownerName: String
    @State private var principal: String
    @State private var orderCount: Int
    @State private var commission: String
    @State private var gift: String
    @State private var signed: Bool
    @State private var settled: Bool
    @State private var note: String
    @State private var saving = false
    @State private var error: String?

    init(item: TaskRecord?, onSave: @escaping () async -> Void) {
        self.item = item; self.onSave = onSave
        _shopName = State(initialValue: item?.shopName ?? ""); _ownerName = State(initialValue: item?.ownerName ?? "")
        _principal = State(initialValue: item.map { String($0.principalAmount) } ?? "0")
        _orderCount = State(initialValue: item?.orderCount ?? 1); _commission = State(initialValue: item.map { String($0.commissionAmount) } ?? "0")
        _gift = State(initialValue: item.map { String($0.giftAmount) } ?? "0"); _signed = State(initialValue: item?.signedStatus == "completed")
        _settled = State(initialValue: item?.settlementStatus == "completed"); _note = State(initialValue: item?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                Section("基本信息") { TextField("店铺名称", text: $shopName); TextField("负责人", text: $ownerName); Stepper("刷单数量：\(orderCount)", value: $orderCount, in: 1...9999) }
                Section("金额") {
                    TextField("本金", text: $principal).keyboardType(.decimalPad); TextField("佣金", text: $commission).keyboardType(.decimalPad); TextField("礼品花费", text: $gift).keyboardType(.decimalPad)
                }
                Section("状态") { Toggle("已签收", isOn: $signed); Toggle("已结算", isOn: $settled) }
                Section("备注") { TextField("任务说明", text: $note, axis: .vertical).lineLimit(3...8) }
            }
            .navigationTitle(item == nil ? "新增任务" : "编辑任务").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving || shopName.isEmpty || ownerName.isEmpty) } }
        }
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let taskTime: Any = item?.taskTime ?? NSNull()
        let taskNote: Any = note.isEmpty ? NSNull() : note
        let body: [String: Any] = ["task_time": taskTime, "shop_name": shopName, "owner_name": ownerName, "principal_amount": Double(principal) ?? 0, "order_count": orderCount, "commission_amount": Double(commission) ?? 0, "gift_amount": Double(gift) ?? 0, "signed_status": signed ? "completed" : "pending", "settlement_status": settled ? "completed" : "pending", "note": taskNote]
        do { let _: TaskRecord = try await session.send(item.map { "task-bookkeeping/records/\($0.id)" } ?? "task-bookkeeping/records", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() }
        catch { self.error = session.message(for: error) }
    }
}

private struct ExpenseForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: CompanyExpense?; let onSave: () async -> Void
    @State private var amount: String; @State private var category: String; @State private var account: String
    @State private var scope: String; @State private var description: String; @State private var employeePaid: Bool
    @State private var saving = false; @State private var error: String?
    private let categories = ["办公用品", "快递物流", "餐饮招待", "差旅交通", "软件服务", "广告推广", "采购货款", "其他消费"]

    init(item: CompanyExpense?, onSave: @escaping () async -> Void) {
        self.item = item; self.onSave = onSave; _amount = State(initialValue: item.map { String($0.amount) } ?? "")
        _category = State(initialValue: item?.category ?? "办公用品"); _account = State(initialValue: item?.paymentAccount ?? "公司卡")
        _scope = State(initialValue: item?.expenseScope ?? "公共费用"); _description = State(initialValue: item?.description ?? "")
        _employeePaid = State(initialValue: item?.paymentType == "employee")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                Section("金额") { TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.title2.bold()) }
                Section("消费信息") { Picker("分类", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }; TextField("消费说明", text: $description); Toggle("员工垫付", isOn: $employeePaid) }
                Section("补充信息") { TextField("付款账户", text: $account); TextField("费用归属", text: $scope) }
            }
            .navigationTitle(item == nil ? "记一笔" : "编辑记账").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving || (Double(amount) ?? 0) <= 0) } }
        }
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = ["expense_date": item?.expenseDate ?? formatter.string(from: Date()), "amount": Double(amount) ?? 0, "category": category, "payment_type": employeePaid ? "employee" : "company", "payment_account": account.isEmpty ? "公司卡" : account, "expense_scope": scope.isEmpty ? "公共费用" : scope, "description": description.isEmpty ? category : description]
        do { let _: CompanyExpense = try await session.send(item.map { "company-expenses/\($0.id)" } ?? "company-expenses", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() }
        catch { self.error = session.message(for: error) }
    }
}

private struct LinkForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: SavedLink?; let onSave: () async -> Void
    @State private var title: String; @State private var category: String; @State private var url: String
    @State private var description: String; @State private var pinned: Bool; @State private var saving = false; @State private var error: String?

    init(item: SavedLink?, onSave: @escaping () async -> Void) {
        self.item = item; self.onSave = onSave; _title = State(initialValue: item?.title ?? ""); _category = State(initialValue: item?.category ?? "")
        _url = State(initialValue: item?.url ?? ""); _description = State(initialValue: item?.description ?? ""); _pinned = State(initialValue: item?.isPinned ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                Section("帖子") { TextField("标题", text: $title); TextField("分类", text: $category); TextField("https://", text: $url).keyboardType(.URL).textInputAutocapitalization(.never); Toggle("置顶", isOn: $pinned) }
                Section("正文") { TextField("输入正文内容", text: $description, axis: .vertical).lineLimit(8...16) }
            }
            .navigationTitle(item == nil ? "发布帖子" : "编辑帖子").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "发布中..." : "保存") { Task { await save() } }.disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty) } }
        }
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let savedCategory: Any = category.isEmpty ? NSNull() : category
        let savedDescription: Any = description.isEmpty ? NSNull() : description
        let savedURL: Any = url.isEmpty ? NSNull() : url
        let body: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "category": savedCategory, "description": savedDescription, "url": savedURL, "is_pinned": pinned, "sort_order": 0]
        do { let _: SavedLink = try await session.send(item.map { "saved-links/\($0.id)" } ?? "saved-links", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() }
        catch { self.error = session.message(for: error) }
    }
}

private struct NativeMineView: View {
    @EnvironmentObject private var session: NativeSession
    var body: some View {
        NavigationStack {
            List {
                Section("账户") { Label(session.username, systemImage: "person.circle") }
                Section("AI 管理") {
                    NavigationLink { NativeModelsView() } label: { Label("模型", systemImage: "cpu") }
                    NavigationLink { NativeKnowledgeView() } label: { Label("知识库", systemImage: "books.vertical") }
                }
                Section { Button("退出登录", role: .destructive) { Task { await session.logout() } } }
            }
                .navigationTitle("我的")
        }
    }
}

private struct NativeModelsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var models: [AIModel] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(models) { model in
                HStack(spacing: 12) {
                    Image(systemName: model.modelType == "audio" ? "waveform" : model.modelType == "image" ? "photo" : "cpu")
                        .frame(width: 34, height: 34).background(Color.blue.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) { Text(model.name).fontWeight(.medium); Text(model.baseModel).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(model.modelType ?? "chat").font(.caption).foregroundStyle(.secondary)
                    Circle().fill(model.enabled == 0 ? Color.gray : Color.green).frame(width: 8, height: 8)
                }.padding(.vertical, 3)
            }
        }
        .overlay { if loading && models.isEmpty { ProgressView() } }
        .navigationTitle("AI 模型").refreshable { await load() }.task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { let response: AIModelsResponse = try await session.get("ai-api/models"); models = response.models }
        catch { self.error = session.message(for: error) }
    }
}

private struct NativeKnowledgeView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var collections: [KnowledgeCollection] = []
    @State private var files: [KnowledgeFile] = []
    @State private var query = ""
    @State private var newName = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section("新建知识集合") {
                HStack { TextField("集合名称", text: $newName); Button("创建") { Task { await create() } }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            Section("集合") {
                ForEach(collections) { item in HStack { Label(item.name, systemImage: "folder"); Spacer(); Text("\(files.filter { $0.knowledgeID == item.id }.count) 个文件").font(.caption).foregroundStyle(.secondary) } }
            }
            Section("文件") {
                ForEach(files.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { file in
                    VStack(alignment: .leading, spacing: 4) { Text(file.name); Text(file.status ?? "已导入").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .overlay { if loading && collections.isEmpty && files.isEmpty { ProgressView() } }
        .navigationTitle("知识库").searchable(text: $query, prompt: "搜索文件")
        .refreshable { await load() }.task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            async let collectionRequest: KnowledgeResponse = session.get("ai-api/knowledge")
            async let fileRequest: KnowledgeFilesResponse = session.get("ai-api/files")
            let (collectionResult, fileResult) = try await (collectionRequest, fileRequest)
            collections = collectionResult.knowledge; files = fileResult.files
        } catch { self.error = session.message(for: error) }
    }

    private func create() async {
        do { let _: EmptyResponse = try await session.send("ai-api/knowledge", method: "POST", body: ["name": newName], allowEmpty: true); newName = ""; await load() }
        catch { self.error = session.message(for: error) }
    }
}

private struct ExpenseDetail: View {
    let item: CompanyExpense
    var body: some View {
        List {
            LabeledContent("金额", value: money(item.amount)); LabeledContent("分类", value: item.category)
            LabeledContent("付款账户", value: item.paymentAccount); LabeledContent("消费日期", value: item.expenseDate)
            LabeledContent("提交人", value: item.submitterName); LabeledContent("消费范围", value: item.expenseScope)
            Section("说明") { Text(item.description.isEmpty ? "无" : item.description) }
        }.navigationTitle(item.expenseNo).navigationBarTitleDisplayMode(.inline)
    }
}

private struct Metric: View {
    let title: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.75) }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct StatusBadge: View {
    let text: String; let done: Bool
    var body: some View { Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(done ? .green : .orange).background((done ? Color.green : Color.orange).opacity(0.12), in: Capsule()) }
}

private extension View {
    func nativeField() -> some View { padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct ChatMessage: Identifiable { let id = UUID(); let text: String; let sent: Bool }

private struct AIModel: Codable, Identifiable {
    let id: String; let name: String; let baseModel: String; let modelType: String?; let enabled: Int; let hidden: Int?
    enum CodingKeys: String, CodingKey { case id, name, enabled, hidden; case baseModel = "base_model"; case modelType = "model_type" }
}
private struct AIModelsResponse: Codable { let models: [AIModel] }
private struct TranscriptionResponse: Codable { let text: String }
private struct KnowledgeCollection: Codable, Identifiable { let id: String; let name: String; let description: String? }
private struct KnowledgeFile: Codable, Identifiable {
    let id: String; let name: String; let knowledgeID: String?; let status: String?
    enum CodingKeys: String, CodingKey { case id, name, status; case knowledgeID = "knowledge_id" }
}
private struct KnowledgeResponse: Codable { let knowledge: [KnowledgeCollection] }
private struct KnowledgeFilesResponse: Codable { let files: [KnowledgeFile] }

@MainActor private final class NativeAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var transcribing = false
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { throw NativeAPIError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        let audioRecorder = try AVAudioRecorder(url: url, settings: settings); audioRecorder.delegate = self
        guard audioRecorder.record() else { throw NativeAPIError.invalidResponse }
        recorder = audioRecorder; fileURL = url; recording = true
    }

    func stop() -> Data? {
        recorder?.stop(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL else { return nil }
        let data = try? Data(contentsOf: url); try? FileManager.default.removeItem(at: url)
        recorder = nil; fileURL = nil; return data
    }
}

private struct TaskRecord: Codable, Identifiable {
    let id: Int; let orderNo: String; let taskTime: String?; let shopName: String; let ownerName: String
    let principalAmount: Double; let orderCount: Int; let commissionAmount: Double; let giftAmount: Double
    let signedStatus: String; let settlementStatus: String; let note: String?
    enum CodingKeys: String, CodingKey { case id, note; case orderNo = "order_no"; case taskTime = "task_time"; case shopName = "shop_name"; case ownerName = "owner_name"; case principalAmount = "principal_amount"; case orderCount = "order_count"; case commissionAmount = "commission_amount"; case giftAmount = "gift_amount"; case signedStatus = "signed_status"; case settlementStatus = "settlement_status" }
}

private struct TaskSummary: Codable {
    let totalRecords: Int; let principalTotal: Double; let pendingSignedCount: Int; let pendingSettlementCount: Int
    enum CodingKeys: String, CodingKey { case totalRecords = "total_records"; case principalTotal = "principal_total"; case pendingSignedCount = "pending_signed_count"; case pendingSettlementCount = "pending_settlement_count" }
}

private struct CompanyExpense: Codable, Identifiable {
    let id: Int; let expenseNo: String; let expenseDate: String; let amount: Double; let category: String
    let paymentType: String; let paymentAccount: String; let expenseScope: String; let description: String; let submitterName: String
    enum CodingKeys: String, CodingKey { case id, amount, category, description; case expenseNo = "expense_no"; case expenseDate = "expense_date"; case paymentType = "payment_type"; case paymentAccount = "payment_account"; case expenseScope = "expense_scope"; case submitterName = "submitter_name" }
}

private struct ExpenseSummary: Codable {
    let monthTotal: Double; let monthRecordCount: Int; let pendingReimbursementTotal: Double
    enum CodingKeys: String, CodingKey { case monthTotal = "month_total"; case monthRecordCount = "month_record_count"; case pendingReimbursementTotal = "pending_reimbursement_total" }
}

private struct SavedLinkImage: Codable { let url: String; let name: String? }
private struct SavedLink: Codable, Identifiable {
    let id: Int; let title: String; let url: String?; let category: String?; let description: String?
    let isPinned: Bool; let authorUsername: String; let images: [SavedLinkImage]; let createdAt: String; let updatedAt: String
    enum CodingKeys: String, CodingKey { case id, title, url, category, description, images; case isPinned = "is_pinned"; case authorUsername = "author_username"; case createdAt = "created_at"; case updatedAt = "updated_at" }
}

private enum NativeAPIError: Error { case invalidResponse; case microphoneDenied; case server(Int, String) }

@MainActor private final class NativeSession: ObservableObject {
    @Published var loggedIn = false
    @Published var loading = false
    @Published var error: String?
    @Published var username = "管理员"
    private let origin = URL(string: "https://xiaoxu666.asia")!
    private let decoder: JSONDecoder = { let value = JSONDecoder(); value.keyDecodingStrategy = .useDefaultKeys; return value }()

    func login(username: String, password: String) async {
        loading = true; error = nil; defer { loading = false }
        do {
            let body: [String: Any] = ["username": username, "password": password, "totp_code": NSNull(), "captcha_id": NSNull(), "captcha_code": NSNull()]
            let _: EmptyResponse = try await send("auth/login", method: "POST", body: body, allowEmpty: true)
            self.username = username; loggedIn = true
        } catch { self.error = "登录失败，请检查账号、密码和网络。" }
    }

    func get<T: Decodable>(_ path: String) async throws -> T { try await send(path, method: "GET") }

    func send<T: Decodable>(_ path: String, method: String, body: [String: Any]? = nil, allowEmpty: Bool = false) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw NativeAPIError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NativeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String ?? "请求失败"
            if http.statusCode == 401 { loggedIn = false }
            throw NativeAPIError.server(http.statusCode, detail)
        }
        if allowEmpty { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(path, method: "DELETE", allowEmpty: true)
    }

    func chat(_ question: String, modelID: String = "") async -> String? {
        do {
            var body: [String: Any] = ["question": question]
            if !modelID.isEmpty { body["model_id"] = modelID }
            let response: ChatResponse = try await send("ai-api/chat", method: "POST", body: body)
            return response.content ?? response.answer ?? response.response
        } catch { return message(for: error) }
    }

    func logout() async {
        let _: EmptyResponse? = try? await send("auth/logout", method: "POST", allowEmpty: true)
        loggedIn = false
    }

    func message(for error: Error) -> String {
        if case let NativeAPIError.server(_, detail) = error { return detail }
        return "数据加载失败，请检查网络后重试。"
    }
}

private struct EmptyResponse: Codable {}
private struct ChatResponse: Codable { let content: String?; let answer: String?; let response: String? }
private func money(_ value: Double) -> String { String(format: "¥ %.2f", value) }
private func shortDate(_ value: String?) -> String { guard let value else { return "-" }; return String(value.replacingOccurrences(of: "T", with: " ").prefix(16)) }
