import UIKit
import Capacitor
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import WebKit

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
        .task { await session.restoreSession() }
    }
}

private struct NativeLoginView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var account = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var totpCode = ""
    @State private var captchaCode = ""

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
                    HStack(spacing: 8) {
                        if showsPassword {
                            TextField("密码", text: $password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } else {
                            SecureField("密码", text: $password).textContentType(.password)
                        }
                        Button { showsPassword.toggle() } label: { Image(systemName: showsPassword ? "eye.slash" : "eye") }.accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
                    }.nativeField()
                    if session.needsTOTP { TextField("请输入6位动态验证码", text: $totpCode).keyboardType(.numberPad).textContentType(.oneTimeCode).nativeField() }
                    if let imageData = session.captchaImageData {
                        HStack { CaptchaWebView(data: imageData).frame(width: 132, height: 44); TextField("图形验证码", text: $captchaCode).textInputAutocapitalization(.never).nativeField(); Button { Task { await session.loadCaptcha() } } label: { Image(systemName: "arrow.clockwise") } }
                    }
                    Button(session.loading ? "登录中..." : "登录") {
                        Task { await session.login(username: account, password: password, totpCode: totpCode, captchaCode: captchaCode) }
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
    @State private var selected = 0
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selected {
                case 1: NativeTaskView()
                case 2: NativeLedgerView()
                case 3: NativeLinksView()
                case 4: NativeMineView()
                default: NativeHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            NativeBottomBar(selected: $selected)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct NativeBottomBar: View {
    @Binding var selected: Int
    private let items: [(String, String)] = [("首页", "house"), ("任务", "checklist"), ("记账", "wallet.pass"), ("链接", "link"), ("我的", "person")]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                Button { selected = index } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[index].1).font(.system(size: 19, weight: selected == index ? .semibold : .regular))
                        Text(items[index].0).font(.system(size: 10, weight: selected == index ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .foregroundStyle(selected == index ? Color.blue : Color(.secondaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct NativeHomeView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var message = ""
    @State private var chats: [AIChat] = []
    @State private var activeChatID = ""
    @State private var sending = false
    @State private var models: [AIModel] = []
    @State private var selectedModel = ""
    @State private var audioModel = ""
    @StateObject private var recorder = NativeAudioRecorder()
    @State private var voiceError: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var showingHistory = false
    @State private var deletingChat: AIChat?

    private var activeIndex: Int? { chats.firstIndex { $0.id == activeChatID } }
    private var activeChat: AIChat? { activeIndex.map { chats[$0] } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("首页").font(.system(size: 25, weight: .bold)); Spacer(); Button { showingHistory = true } label: { Image(systemName: "moon") }; Button { } label: { Image(systemName: "bell.badge.fill") }; Button { } label: { Image(systemName: "magnifyingglass") } }.padding(.horizontal, 16)
                    HStack { Text("常用功能").font(.headline); Spacer(); Text("自定义").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 16)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        HomeShortcut("生意参谋", "chart.bar", .teal); HomeShortcut("任务记录", "doc.text", .indigo); HomeShortcut("店铺账号", "storefront", .mint); HomeShortcut("仓储管理", "cube.box", .orange); HomeShortcut("链接广场", "link", .blue); HomeShortcut("全部功能", "circle.grid.3x3", .gray)
                    }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                    HStack { Text("经营数据").font(.headline); Spacer(); Text("实时同步").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 16)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) { HomeMetric("公司消费", "¥37284.34"); HomeMetric("累计利润", "¥80538.54"); HomeMetric("当月钉钉利润", "¥15377.97"); HomeMetric("待签收", "4"); HomeMetric("库存数量", "1356"); HomeMetric("库存成本", "¥121499.42") }.padding(1).background(Color(.separator)).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                    HStack { Text("钉钉月度利润").font(.headline); Spacer(); Text("查看趋势 ›").font(.caption).foregroundStyle(.blue) }.padding(.horizontal, 16)
                    HStack(alignment: .bottom, spacing: 18) { ForEach([72, 34, 68, 42, 55, 76], id: \.self) { height in RoundedRectangle(cornerRadius: 5).fill(.blue).frame(maxWidth: .infinity).frame(height: CGFloat(height)) } }.frame(height: 95, alignment: .bottom).padding(16).background(.background, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                    HStack { Text("待办提醒").font(.headline); Spacer(); Text("查看全部").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 16)
                    VStack(spacing: 0) { HomeTodo(color: .orange, title: "待签收任务", detail: "需要及时处理任务状态", value: "4"); Divider(); HomeTodo(color: .red, title: "待结算任务", detail: "等待结算的任务", value: "30") }.background(.background, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                }.padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .task { await loadModels(); await loadChats() }
        }
    }

    /* AI chat actions remain available to the home view. */
    /* legacy chat presentation removed; the dashboard is the home body. */
    private var legacyChatBody: some View { EmptyView() }
    /*
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if activeChat?.messages.isEmpty != false {
                            VStack(spacing: 10) { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.blue); Text("开始新对话").font(.headline); Text("输入问题或使用麦克风开始").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.top, 80)
                        }
                        ForEach(activeChat?.messages ?? []) { item in
                            HStack {
                                if item.role == "user" { Spacer(minLength: 50) }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.content.isEmpty ? "..." : item.content).textSelection(.enabled)
                                    if item.role == "assistant" && !sending {
                                        HStack { Button { UIPasteboard.general.string = item.content } label: { Image(systemName: "doc.on.doc") }; Button { regenerate(before: item.id) } label: { Image(systemName: "arrow.clockwise") } }.font(.caption)
                                    }
                                }
                                .padding(14).foregroundStyle(item.role == "user" ? Color.white : Color.primary)
                                .background(item.role == "user" ? Color.blue : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                                if item.role != "user" { Spacer(minLength: 50) }
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
                    Button(action: sending ? stop : send) { Image(systemName: sending ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 34)) }
                        .disabled(!sending && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingHistory = true } label: { Image(systemName: "sidebar.left") }
                    Button(action: createChat) { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    List {
                        ForEach(chats.sorted { $0.updatedAt > $1.updatedAt }) { chat in
                            Button { activeChatID = chat.id; selectedModel = chat.modelID ?? selectedModel; showingHistory = false } label: {
                                VStack(alignment: .leading, spacing: 4) { Text(chat.title).foregroundStyle(.primary); Text(shortTimestamp(chat.updatedAt)).font(.caption).foregroundStyle(.secondary) }
                            }.swipeActions { Button("删除", role: .destructive) { deletingChat = chat } }
                        }
                    }.navigationTitle("历史会话").toolbar { Button("关闭") { showingHistory = false } }
                }
            }
            .confirmationDialog("确定删除这个会话吗？", isPresented: Binding(get: { deletingChat != nil }, set: { if !$0 { deletingChat = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let chat = deletingChat { Task { await delete(chat) } } }; Button("取消", role: .cancel) { deletingChat = nil }
            }
            .task { await loadModels(); await loadChats() }
        }
    }
    */

    private func send() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if activeIndex == nil { createChat() }
        guard let index = activeIndex else { return }
        chats[index].messages.append(AIChatMessage(id: UUID().uuidString, role: "user", content: value))
        let answerID = UUID().uuidString
        chats[index].messages.append(AIChatMessage(id: answerID, role: "assistant", content: ""))
        if chats[index].messages.count == 2 { chats[index].title = String(value.prefix(24)) }
        chats[index].modelID = selectedModel; chats[index].updatedAt = Date().timeIntervalSince1970
        message = ""; sending = true
        streamTask = Task {
            do {
                try await session.streamChat(value, modelID: selectedModel) { chunk in
                    guard let chatIndex = chats.firstIndex(where: { $0.id == activeChatID }), let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == answerID }) else { return }
                    chats[chatIndex].messages[messageIndex].content += chunk
                }
            } catch is CancellationError { }
            catch { if let chatIndex = chats.firstIndex(where: { $0.id == activeChatID }), let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == answerID }) { chats[chatIndex].messages[messageIndex].content = session.message(for: error) } }
            sending = false; await saveActiveChat()
        }
    }

    private func stop() { streamTask?.cancel(); streamTask = nil; sending = false; Task { await saveActiveChat() } }

    private func regenerate(before messageID: String) {
        guard let index = activeIndex, let answerIndex = chats[index].messages.firstIndex(where: { $0.id == messageID }), answerIndex > 0 else { return }
        let question = chats[index].messages[..<answerIndex].last(where: { $0.role == "user" })?.content ?? ""
        chats[index].messages.removeSubrange((answerIndex - 1)...answerIndex); message = question; send()
    }

    private func createChat() {
        let now = Date().timeIntervalSince1970
        let chat = AIChat(id: "chat-\(UUID().uuidString)", title: "新对话", messages: [], modelID: selectedModel, favorite: false, archived: false, folder: "", createdAt: now, updatedAt: now)
        chats.insert(chat, at: 0); activeChatID = chat.id
    }

    private func loadChats() async {
        do {
            let result: AIChatsResponse = try await session.get("ai-api/chats")
            chats = result.chats
            if let first = chats.first(where: { !$0.archived }) ?? chats.first { activeChatID = first.id; if let model = first.modelID, !model.isEmpty { selectedModel = model } } else { createChat() }
        } catch { voiceError = session.message(for: error); if chats.isEmpty { createChat() } }
    }

    private func saveActiveChat() async {
        guard let chat = activeChat else { return }
        let messages = chat.messages.map { ["id": $0.id, "role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["id": chat.id, "title": chat.title, "messages": messages, "model_id": chat.modelID ?? "", "favorite": chat.favorite, "archived": chat.archived, "folder": chat.folder, "created_at": Int(chat.createdAt)]
        let _: EmptyResponse? = try? await session.send("ai-api/chats/save", method: "POST", body: body, allowEmpty: true)
    }

    private func delete(_ chat: AIChat) async {
        let _: EmptyResponse? = try? await session.send("ai-api/chats/delete", method: "POST", body: ["id": chat.id], allowEmpty: true)
        chats.removeAll { $0.id == chat.id }; deletingChat = nil
        if activeChatID == chat.id { activeChatID = chats.first?.id ?? ""; if chats.isEmpty { createChat() } }
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
    @State private var importing = false; @State private var attachment: URL?
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
                Section("票据") { Button(attachment?.lastPathComponent ?? "选择图片或 PDF") { importing = true } }
            }
            .navigationTitle(item == nil ? "记一笔" : "编辑记账").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving || (Double(amount) ?? 0) <= 0) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in attachment = try? result.get() }
        }
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = ["expense_date": item?.expenseDate ?? formatter.string(from: Date()), "amount": Double(amount) ?? 0, "category": category, "payment_type": employeePaid ? "employee" : "company", "payment_account": account.isEmpty ? "公司卡" : account, "expense_scope": scope.isEmpty ? "公共费用" : scope, "description": description.isEmpty ? category : description]
        do { let saved: CompanyExpense = try await session.send(item.map { "company-expenses/\($0.id)" } ?? "company-expenses", method: item == nil ? "POST" : "PUT", body: body); if let attachment { guard attachment.startAccessingSecurityScopedResource() else { throw NativeAPIError.invalidResponse }; defer { attachment.stopAccessingSecurityScopedResource() }; let data = try Data(contentsOf: attachment); let _: CompanyExpense = try await session.upload(path: "company-expenses/\(saved.id)/attachment", field: "attachment", filename: attachment.lastPathComponent, data: data, mime: attachment.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg") }; await onSave(); dismiss() }
        catch { self.error = session.message(for: error) }
    }
}

private struct LinkForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: SavedLink?; let onSave: () async -> Void
    @State private var title: String; @State private var category: String; @State private var url: String
    @State private var description: String; @State private var pinned: Bool; @State private var saving = false; @State private var error: String?
    @State private var importing = false; @State private var images: [URL] = []

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
                Section("配图") { Button(images.isEmpty ? "选择图片" : "已选择 \(images.count) 张") { importing = true } }
            }
            .navigationTitle(item == nil ? "发布帖子" : "编辑帖子").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "发布中..." : "保存") { Task { await save() } }.disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in images = (try? result.get()) ?? [] }
        }
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let savedCategory: Any = category.isEmpty ? NSNull() : category
        let savedDescription: Any = description.isEmpty ? NSNull() : description
        let savedURL: Any = url.isEmpty ? NSNull() : url
        let body: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "category": savedCategory, "description": savedDescription, "url": savedURL, "is_pinned": pinned, "sort_order": 0]
        do { let saved: SavedLink = try await session.send(item.map { "saved-links/\($0.id)" } ?? "saved-links", method: item == nil ? "POST" : "PUT", body: body); if !images.isEmpty { var files: [MultipartFile] = []; for image in images { guard image.startAccessingSecurityScopedResource() else { continue }; defer { image.stopAccessingSecurityScopedResource() }; files.append(MultipartFile(field: "images", filename: image.lastPathComponent, data: try Data(contentsOf: image), mime: "image/jpeg")) }; if !files.isEmpty { let _: SavedLink = try await session.uploadMany(path: "saved-links/\(saved.id)/images/append", files: files) } }; await onSave(); dismiss() }
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
                    NavigationLink { NativeCapabilitiesView() } label: { Label("AI 能力", systemImage: "wand.and.stars") }
                    NavigationLink { NativeOperationsView() } label: { Label("AI 运营", systemImage: "chart.bar.xaxis") }
                }
                Section("业务管理") {
                    NavigationLink { NativeWarehouseView() } label: { Label("仓储管理", systemImage: "shippingbox") }
                    NavigationLink { NativeShopsView() } label: { Label("店铺档案", systemImage: "storefront") }
                    NavigationLink { NativeOwnersView() } label: { Label("负责人", systemImage: "person.2") }
                    NavigationLink { NativeUsersView() } label: { Label("账号与权限", systemImage: "person.badge.key") }
                    NavigationLink { NativeLicensesView() } label: { Label("授权码", systemImage: "key") }
                    NavigationLink { NativePeerShopsView() } label: { Label("同行店铺", systemImage: "building.2") }
                    NavigationLink { NativeLicenseRecordsView() } label: { Label("执照档案", systemImage: "doc.text") }
                    NavigationLink { NativeAccountUsageView() } label: { Label("账号使用", systemImage: "person.text.rectangle") }
                    NavigationLink { NativeDevicesView() } label: { Label("手机设备", systemImage: "iphone") }
                }
                Section { Button("退出登录", role: .destructive) { Task { await session.logout() } } }
            }
                .navigationTitle("我的")
        }
    }
}

private struct NativeShopsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var fields: [ShopField] = []; @State private var records: [ShopRecord] = []; @State private var query = ""; @State private var loading = false; @State private var error: String?
    @State private var editing: ShopRecord?; @State private var showingForm = false
    private var visibleFields: [ShopField] { fields.filter(\.isVisible).sorted { $0.sortOrder < $1.sortOrder } }
    private var filtered: [ShopRecord] { query.isEmpty ? records : records.filter { $0.values.values.map(\.display).joined(separator: " ").localizedCaseInsensitiveContains(query) } }
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(filtered) { record in NavigationLink { ShopDetail(record: record, fields: visibleFields) } label: { VStack(alignment: .leading, spacing: 5) { Text(title(record)).fontWeight(.medium); Text(visibleFields.prefix(3).compactMap { field in record.values[field.fieldName].map { "\(field.label)：\($0.display)" } }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(record) } }; Button("编辑") { editing = record; showingForm = true }.tint(.blue) } } }.navigationTitle("店铺档案").searchable(text: $query).overlay { if loading && records.isEmpty { ProgressView() } }.task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showingForm) { ShopForm(item: editing, fields: visibleFields) { await load() } } }
    private func title(_ record: ShopRecord) -> String { for key in ["shop_name", "store_name", "name"] { if let value = record.values[key], !value.display.isEmpty { return value.display } }; return visibleFields.compactMap { record.values[$0.fieldName]?.display }.first ?? "店铺 #\(record.id)" }
    private func load() async { loading = true; defer { loading = false }; do { async let fieldRequest: [ShopField] = session.get("custom-fields"); async let recordRequest: [ShopRecord] = session.get("shop-records"); let result = try await (fieldRequest, recordRequest); fields = result.0; records = result.1 } catch { self.error = session.message(for: error) } }
    private func remove(_ record: ShopRecord) async { do { try await session.delete("shop-records/\(record.id)"); records.removeAll { $0.id == record.id } } catch { self.error = session.message(for: error) } }
}

private struct ShopDetail: View { let record: ShopRecord; let fields: [ShopField]; var body: some View { List { ForEach(fields) { field in LabeledContent(field.label, value: record.values[field.fieldName]?.display ?? "-") } }.navigationTitle("店铺详情").navigationBarTitleDisplayMode(.inline) } }

private struct ShopForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss
    let item: ShopRecord?; let fields: [ShopField]; let onSave: () async -> Void
    @State private var values: [String: String]; @State private var saving = false; @State private var error: String?
    init(item: ShopRecord?, fields: [ShopField], onSave: @escaping () async -> Void) { self.item = item; self.fields = fields; self.onSave = onSave; _values = State(initialValue: Dictionary(uniqueKeysWithValues: fields.map { ($0.fieldName, item?.values[$0.fieldName]?.display == "-" ? "" : item?.values[$0.fieldName]?.display ?? "") })) }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; ForEach(fields) { field in TextField(field.label + (field.required ? " *" : ""), text: Binding(get: { values[field.fieldName] ?? "" }, set: { values[field.fieldName] = $0 })).keyboardType(field.fieldType == "number" ? .decimalPad : .default) } }.navigationTitle(item == nil ? "新增店铺" : "编辑店铺").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving) } } } }
    private func save() async { for field in fields where field.required && (values[field.fieldName] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.error = "请填写\(field.label)"; return }; saving = true; defer { saving = false }; var payload: [String: Any] = [:]; for field in fields { let value = values[field.fieldName] ?? ""; payload[field.fieldName] = field.fieldType == "number" && !value.isEmpty ? (Double(value) ?? 0) : value }; do { let _: ShopRecord = try await session.send(item.map { "shop-records/\($0.id)" } ?? "shop-records", method: item == nil ? "POST" : "PUT", body: ["values": payload]); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeOwnersView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var owners: [TaskOwner] = []; @State private var query = ""; @State private var newName = ""; @State private var showingAdd = false; @State private var error: String?
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(owners.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { owner in Label(owner.name, systemImage: "person.circle").swipeActions { Button("删除", role: .destructive) { Task { await remove(owner) } } } } }.navigationTitle("负责人").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }.alert("新增负责人", isPresented: $showingAdd) { TextField("负责人名称", text: $newName); Button("保存") { Task { await add() } }; Button("取消", role: .cancel) {} } }
    private func load() async { do { owners = try await session.get("task-bookkeeping/owners") } catch { self.error = session.message(for: error) } }
    private func add() async { let name = newName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; do { let _: TaskOwner = try await session.send("task-bookkeeping/owners", method: "POST", body: ["name": name]); newName = ""; await load() } catch { self.error = session.message(for: error) } }
    private func remove(_ owner: TaskOwner) async { do { try await session.delete("task-bookkeeping/owners/\(owner.id)"); await load() } catch { self.error = session.message(for: error) } }
}

private struct NativeUsersView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var users: [AdminUserRecord] = []; @State private var query = ""; @State private var error: String?
    @State private var editing: AdminUserRecord?; @State private var showingForm = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(users.filter { query.isEmpty || "\($0.username) \($0.displayName ?? "")".localizedCaseInsensitiveContains(query) }) { user in HStack { VStack(alignment: .leading) { Text((user.displayName?.isEmpty == false ? user.displayName : nil) ?? user.username).fontWeight(.medium); Text("\(user.username) · \(roleLabel(user.role))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("", isOn: Binding(get: { user.isActive }, set: { active in Task { await toggle(user, active) } })).labelsHidden() }.contentShape(Rectangle()).onTapGesture { editing = user; showingForm = true } } }.navigationTitle("账号与权限").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showingForm) { UserAccessForm(item: editing) { await load() } } }
    private func load() async { do { users = try await session.get("admin-users") } catch { self.error = session.message(for: error) } }
    private func toggle(_ user: AdminUserRecord, _ active: Bool) async { do { let _: EmptyResponse = try await session.send("admin-users/\(user.id)/status", method: "PATCH", body: ["is_active": active], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}

private struct UserAccessForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss
    let item: AdminUserRecord?; let onSave: () async -> Void
    @State private var username = ""; @State private var password = ""; @State private var role: String; @State private var permissions: [String: String]; @State private var saving = false; @State private var error: String?
    private let modules = ["dashboard": "运营工作台", "links": "链接广场", "task_bookkeeping": "任务记账", "dingtalk_profits": "钉钉利润", "shop_records": "店铺账号", "peer_shops": "同行店铺", "licenses": "执照档案", "account_usage": "账号使用", "mobile_devices": "手机设备", "warehouse": "仓储发货"]
    init(item: AdminUserRecord?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _username = State(initialValue: item?.username ?? ""); _role = State(initialValue: item?.role ?? "editor"); _permissions = State(initialValue: item?.permissions ?? [:]) }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; Section("账号") { TextField("用户名", text: $username).disabled(item != nil); if item == nil { SecureField("至少 8 位密码", text: $password) }; Picker("角色", selection: $role) { Text("超级管理员").tag("superadmin"); Text("编辑员").tag("editor"); Text("只读账号").tag("viewer") }.onChange(of: role) { value in applyDefaults(value) } }; if role != "superadmin" { Section("模块权限") { ForEach(modules.keys.sorted(), id: \.self) { key in Picker(modules[key] ?? key, selection: Binding(get: { permissions[key] ?? (role == "viewer" ? "read" : "write") }, set: { permissions[key] = $0 })) { Text("无权限").tag("none"); Text("只读").tag("read"); Text("可编辑").tag("write") } } } } }.navigationTitle(item == nil ? "创建账号" : "编辑权限").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || username.isEmpty || (item == nil && password.count < 8)) } } } }
    private func applyDefaults(_ value: String) { guard value != "superadmin" else { return }; permissions = Dictionary(uniqueKeysWithValues: modules.keys.map { ($0, value == "viewer" ? "read" : "write") }) }
    private func save() async { saving = true; defer { saving = false }; do { if let item { let _: AdminUserRecord = try await session.send("admin-users/\(item.id)", method: "PATCH", body: ["role": role, "permissions": permissions]) } else { let _: AdminUserRecord = try await session.send("admin-users", method: "POST", body: ["username": username, "password": password, "role": role, "permissions": permissions.isEmpty ? Dictionary(uniqueKeysWithValues: modules.keys.map { ($0, role == "viewer" ? "read" : "write") }) : permissions]) }; await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeLicensesView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var licenses: [LicenseRecord] = []; @State private var query = ""; @State private var error: String?
    @State private var showingCreate = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(licenses.filter { query.isEmpty || "\($0.licenseKey) \($0.planName)".localizedCaseInsensitiveContains(query) }) { item in NavigationLink { LicenseDetail(item: item) { await load() } } label: { VStack(alignment: .leading, spacing: 5) { HStack { Text(item.planName).fontWeight(.medium); Spacer(); StatusBadge(text: licenseStatus(item.status), done: item.status == "active") }; Text(item.licenseKey).font(.caption.monospaced()).foregroundStyle(.secondary); Text("\(item.devices.count) / \(item.maxDevices) 台设备").font(.caption2).foregroundStyle(.secondary) } }.swipeActions { Button(item.status == "disabled" ? "启用" : "停用") { Task { await toggle(item) } }.tint(item.status == "disabled" ? .green : .orange) } } }.navigationTitle("授权码").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { showingCreate = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showingCreate) { LicenseCreateForm { await load() } } }
    private func load() async { do { licenses = try await session.get("license-admin/licenses") } catch { self.error = session.message(for: error) } }
    private func toggle(_ item: LicenseRecord) async { let key = item.licenseKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.licenseKey; do { let _: EmptyResponse = try await session.send("license-admin/licenses/\(key)/status", method: "POST", body: ["status": item.status == "disabled" ? "active" : "disabled"], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}

private struct LicenseCreateForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss
    let onSave: () async -> Void; @State private var plan = "标准版"; @State private var count = 5; @State private var days = 30; @State private var devices = 1; @State private var note = ""; @State private var saving = false; @State private var error: String?
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("套餐名称", text: $plan); Stepper("生成数量：\(count)", value: $count, in: 1...100); Stepper("有效天数：\(days)", value: $days, in: 1...3650); Stepper("最大设备：\(devices)", value: $devices, in: 1...100); TextField("备注", text: $note) }.navigationTitle("批量生成授权码").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("生成") { Task { await save() } }.disabled(saving || plan.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; do { let _: [LicenseRecord] = try await session.send("license-admin/licenses", method: "POST", body: ["plan_name": plan, "count": count, "duration_days": days, "max_devices": devices, "note": note, "feature_flags": ["pro": true]]); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativePeerShopsView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [PeerShopRecord] = []; @State private var query = ""; @State private var error: String?; @State private var editing: PeerShopRecord?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.shopName) \($0.shopURL ?? "") \($0.remark ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { PeerShopDetail(item: row) } label: { VStack(alignment: .leading, spacing: 5) { Text(row.shopName).fontWeight(.medium); Text(row.shopURL ?? row.remark ?? "-").font(.caption).foregroundStyle(.secondary) } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("同行店铺").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { PeerShopForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("peer-shops") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: PeerShopRecord) async { do { try await session.delete("peer-shops/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct PeerShopDetail: View { let item: PeerShopRecord; var body: some View { List { LabeledContent("店铺", value: item.shopName); LabeledContent("链接", value: item.shopURL ?? "-"); Section("备注") { Text(item.remark ?? "无") } }.navigationTitle("同行店铺详情") } }
private struct PeerShopForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: PeerShopRecord?; let onSave: () async -> Void; @State private var name: String; @State private var url: String; @State private var remark: String; @State private var saving = false; @State private var error: String?; @State private var importing = false
    init(item: PeerShopRecord?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.shopName ?? ""); _url = State(initialValue: item?.shopURL ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("店铺名称", text: $name); TextField("店铺链接", text: $url); TextField("备注", text: $remark, axis: .vertical).lineLimit(4...8); if item != nil { Button("选择店铺图片") { importing = true } } }.navigationTitle(item == nil ? "新增同行店铺" : "编辑同行店铺").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || name.isEmpty) } }.fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in Task { await uploadImage(result) } } } }
    private func save() async { saving = true; defer { saving = false }; let shopURL: Any = url.isEmpty ? NSNull() : url; let savedRemark: Any = remark.isEmpty ? NSNull() : remark; let extra: [String: Any] = [:]; let body: [String: Any] = ["shop_name": name, "shop_url": shopURL, "remark": savedRemark, "extra_fields": extra]; do { let _: PeerShopRecord = try await session.send(item.map { "peer-shops/\($0.id)" } ?? "peer-shops", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
    private func uploadImage(_ result: Result<URL, Error>) async { guard let item else { return }; do { let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw NativeAPIError.invalidResponse }; defer { url.stopAccessingSecurityScopedResource() }; let data = try Data(contentsOf: url); let _: PeerShopRecord = try await session.upload(path: "peer-shops/\(item.id)/image", field: "image", filename: url.lastPathComponent, data: data, mime: "image/jpeg"); await onSave() } catch { self.error = session.message(for: error) } }
}

private struct NativeLicenseRecordsView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [LicenseRecordItem] = []; @State private var query = ""; @State private var error: String?; @State private var editing: LicenseRecordItem?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.subjectName) \($0.creditCode) \($0.legalRepresentative ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { LicenseRecordDetail(item: row) } label: { VStack(alignment: .leading, spacing: 5) { Text(row.subjectName).fontWeight(.medium); Text(row.creditCode).font(.caption).foregroundStyle(.secondary); Text(row.expiryDate ?? "未填写到期日").font(.caption2).foregroundStyle(.secondary) } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("执照档案").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { LicenseRecordForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("license-records") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: LicenseRecordItem) async { do { try await session.delete("license-records/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct LicenseRecordDetail: View { let item: LicenseRecordItem; var body: some View { List { LabeledContent("主体名称", value: item.subjectName); LabeledContent("统一信用代码", value: item.creditCode); LabeledContent("法定代表人", value: item.legalRepresentative ?? "-"); LabeledContent("签发日期", value: item.issueDate ?? "-"); LabeledContent("到期日期", value: item.expiryDate ?? "-"); Section("备注") { Text(item.remark ?? "无") } }.navigationTitle("执照详情") } }
private struct LicenseRecordForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: LicenseRecordItem?; let onSave: () async -> Void; @State private var subject: String; @State private var code: String; @State private var legal: String; @State private var issue: String; @State private var expiry: String; @State private var remark: String; @State private var saving = false; @State private var error: String?; @State private var importing = false
    init(item: LicenseRecordItem?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _subject = State(initialValue: item?.subjectName ?? ""); _code = State(initialValue: item?.creditCode ?? ""); _legal = State(initialValue: item?.legalRepresentative ?? ""); _issue = State(initialValue: item?.issueDate ?? ""); _expiry = State(initialValue: item?.expiryDate ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("主体名称", text: $subject); TextField("统一信用代码", text: $code); TextField("法定代表人", text: $legal); TextField("签发日期", text: $issue); TextField("到期日期", text: $expiry); TextField("备注", text: $remark, axis: .vertical).lineLimit(4...8); if item != nil { Button("选择执照图片") { importing = true } } }.navigationTitle(item == nil ? "新增执照" : "编辑执照").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || subject.isEmpty || code.isEmpty) } }.fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in Task { await uploadImage(result) } } } }
    private func save() async { saving = true; defer { saving = false }; let savedLegal: Any = legal.isEmpty ? NSNull() : legal; let savedIssue: Any = issue.isEmpty ? NSNull() : issue; let savedExpiry: Any = expiry.isEmpty ? NSNull() : expiry; let savedRemark: Any = remark.isEmpty ? NSNull() : remark; let extra: [String: Any] = [:]; let body: [String: Any] = ["subject_name": subject, "credit_code": code, "legal_representative": savedLegal, "issue_date": savedIssue, "expiry_date": savedExpiry, "remark": savedRemark, "extra_fields": extra]; do { let _: LicenseRecordItem = try await session.send(item.map { "license-records/\($0.id)" } ?? "license-records", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
    private func uploadImage(_ result: Result<URL, Error>) async { guard let item else { return }; do { let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw NativeAPIError.invalidResponse }; defer { url.stopAccessingSecurityScopedResource() }; let data = try Data(contentsOf: url); let _: LicenseRecordItem = try await session.upload(path: "license-records/\(item.id)/image", field: "image", filename: url.lastPathComponent, data: data, mime: "image/jpeg"); await onSave() } catch { self.error = session.message(for: error) } }
}

private struct NativeDevicesView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [MobileDevice] = []; @State private var query = ""; @State private var error: String?; @State private var editing: MobileDevice?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.deviceName) \($0.primaryCard ?? "") \($0.secondaryCard ?? "")".localizedCaseInsensitiveContains(query) }) { row in VStack(alignment: .leading, spacing: 5) { Text(row.deviceName).fontWeight(.medium); Text([row.primaryCard, row.secondaryCard].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("手机设备").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { DeviceForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("mobile-devices") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: MobileDevice) async { do { try await session.delete("mobile-devices/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct DeviceForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: MobileDevice?; let onSave: () async -> Void; @State private var name: String; @State private var primary: String; @State private var secondary: String; @State private var remark: String; @State private var saving = false; @State private var error: String?
    init(item: MobileDevice?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.deviceName ?? ""); _primary = State(initialValue: item?.primaryCard ?? ""); _secondary = State(initialValue: item?.secondaryCard ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("设备名称", text: $name); TextField("主卡", text: $primary); TextField("副卡", text: $secondary); TextField("备注", text: $remark) }.navigationTitle(item == nil ? "新增设备" : "编辑设备").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || name.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; let body: [String: Any] = ["device_name": name, "primary_card": primary, "secondary_card": secondary, "remark": remark, "extra_fields": [String: Any]()]; do { let _: MobileDevice = try await session.send(item.map { "mobile-devices/\($0.id)" } ?? "mobile-devices", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeAccountUsageView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [AccountUsage] = []; @State private var query = ""; @State private var error: String?; @State private var editing: AccountUsage?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.accountName) \($0.phoneNumber ?? "") \($0.deviceName ?? "")".localizedCaseInsensitiveContains(query) }) { row in VStack(alignment: .leading, spacing: 5) { HStack { Text(row.accountName).fontWeight(.medium); Spacer(); StatusBadge(text: row.isBanned ? "已封禁" : "正常", done: !row.isBanned) }; Text([row.phoneNumber, row.deviceName].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }.swipeActions { Button(row.isBanned ? "恢复" : "封禁") { Task { await setBanned(row, !row.isBanned) } }.tint(row.isBanned ? .green : .orange); Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("账号使用").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { AccountUsageForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("account-usage-records") } catch { self.error = session.message(for: error) } }
    private func setBanned(_ row: AccountUsage, _ banned: Bool) async { do { let _: EmptyResponse = try await session.send("account-usage-records/batch-status", method: "PATCH", body: ["record_ids": [row.id], "is_banned": banned], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}
private struct AccountUsageForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: AccountUsage?; let onSave: () async -> Void; @State private var account: String; @State private var password = ""; @State private var phone: String; @State private var device: String; @State private var notes: String; @State private var reason: String; @State private var saving = false; @State private var error: String?
    init(item: AccountUsage?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _account = State(initialValue: item?.accountName ?? ""); _phone = State(initialValue: item?.phoneNumber ?? ""); _device = State(initialValue: item?.deviceName ?? ""); _notes = State(initialValue: item?.usageNotes ?? ""); _reason = State(initialValue: item?.bannedReason ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("账号名称", text: $account); SecureField(item == nil ? "密码" : "留空保留原密码", text: $password); TextField("手机号", text: $phone).keyboardType(.phonePad); TextField("手机设备", text: $device); TextField("使用说明", text: $notes, axis: .vertical).lineLimit(3...6); TextField("封禁原因", text: $reason) }.navigationTitle(item == nil ? "新增账号记录" : "编辑账号记录").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || (item == nil && account.isEmpty)) } } } }
    private func save() async { saving = true; defer { saving = false }; var body: [String: Any] = ["account_name": account, "phone_number": phone, "device_name": device, "usage_notes": notes, "banned_reason": reason, "is_banned": item?.isBanned ?? false, "extra_fields": [String: Any]()]; if !password.isEmpty { body["password"] = password }; do { let _: AccountUsage = try await session.send(item.map { "account-usage-records/\($0.id)" } ?? "account-usage-records", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct LicenseDetail: View {
    @EnvironmentObject private var session: NativeSession; let item: LicenseRecord; let onChange: () async -> Void; @State private var error: String?
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; Section("授权") { LabeledContent("授权码", value: item.licenseKey); LabeledContent("套餐", value: item.planName); LabeledContent("状态", value: licenseStatus(item.status)); LabeledContent("到期", value: item.expiresAt ?? "-") }; Section("绑定设备") { ForEach(item.devices) { device in HStack { VStack(alignment: .leading) { Text(device.deviceName ?? device.deviceID); Text("\(device.platform ?? "未知平台") · \(device.appVersion ?? "未知版本")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("解绑", role: .destructive) { Task { await unbind(device) } } } } } }.navigationTitle("授权详情").navigationBarTitleDisplayMode(.inline) }
    private func unbind(_ device: LicenseDevice) async { let key = item.licenseKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.licenseKey; do { let _: EmptyResponse = try await session.send("license-admin/licenses/\(key)/unbind", method: "POST", body: ["device_id": device.deviceID], allowEmpty: true); await onChange() } catch { self.error = session.message(for: error) } }
}

private struct NativeModelsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var models: [AIModel] = []
    @State private var loading = false
    @State private var error: String?
    @State private var connections: [AIConnection] = []
    @State private var segment = 0
    @State private var editingConnection: AIConnection?
    @State private var showingConnection = false
    @State private var notice: String?
    @State private var editingModel: AIModel?
    @State private var showingModel = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("类型", selection: $segment) { Text("模型").tag(0); Text("连接").tag(1) }.pickerStyle(.segmented).padding()
            List {
            if let error { Text(error).foregroundStyle(.red) }
            if let notice { Text(notice).foregroundStyle(.green) }
            if segment == 0 { ForEach(models) { model in
                HStack(spacing: 12) {
                    Image(systemName: model.modelType == "audio" ? "waveform" : model.modelType == "image" ? "photo" : "cpu")
                        .frame(width: 34, height: 34).background(Color.blue.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) { Text(model.name).fontWeight(.medium); Text(model.baseModel).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(model.modelType ?? "chat").font(.caption).foregroundStyle(.secondary)
                    Circle().fill(model.enabled == 0 ? Color.gray : Color.green).frame(width: 8, height: 8)
                }.padding(.vertical, 3).contentShape(Rectangle()).onTapGesture { editingModel = model; showingModel = true }
                    .swipeActions { Button("删除", role: .destructive) { Task { await deleteModel(model) } }; Button(model.enabled == 0 ? "启用" : "停用") { Task { await toggleModel(model) } }.tint(model.enabled == 0 ? .green : .orange) }
            } } else { ForEach(connections) { connection in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(connection.name).fontWeight(.semibold); Spacer(); Circle().fill(connection.enabled == 0 ? Color.gray : Color.green).frame(width: 8, height: 8) }
                    Text(connection.baseURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(connection.providerType ?? "openai") · \(connection.hasKey == true ? "Key 已配置" : "未配置 Key")").font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 3).contentShape(Rectangle()).onTapGesture { editingConnection = connection; showingConnection = true }
                    .swipeActions { Button(connection.enabled == 0 ? "启用" : "停用") { Task { await toggleConnection(connection) } }.tint(connection.enabled == 0 ? .green : .orange); Button("同步") { Task { await sync(connection) } }.tint(.blue) }
            } }
            }
        }
        .overlay { if loading && models.isEmpty { ProgressView() } }
        .navigationTitle("AI 模型").refreshable { await load() }.task { await load() }
        .toolbar { Menu { Button("新增模型") { editingModel = nil; showingModel = true }; Button("新增连接") { editingConnection = nil; showingConnection = true }; Button("同步全部模型") { Task { await syncAll() } } } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingConnection) { ConnectionForm(item: editingConnection) { await load() } }
        .sheet(isPresented: $showingModel) { ModelForm(item: editingModel, connections: connections) { await load() } }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            async let modelRequest: AIModelsResponse = session.get("ai-api/models")
            async let connectionRequest: AIConnectionsResponse = session.get("ai-api/connections")
            let result = try await (modelRequest, connectionRequest); models = result.0.models; connections = result.1.connections
        }
        catch { self.error = session.message(for: error) }
    }

    private func toggleConnection(_ item: AIConnection) async { do { let _: EmptyResponse = try await session.send("ai-api/connections/toggle", method: "POST", body: ["id": item.id, "enabled": item.enabled == 0], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func sync(_ item: AIConnection) async { do { let result: AISyncResponse = try await session.send("ai-api/connections/sync", method: "POST", body: ["id": item.id]); notice = "同步完成，共 \(result.total ?? 0) 个模型"; await load() } catch { self.error = session.message(for: error) } }
    private func toggleModel(_ item: AIModel) async {
        let body: [String: Any] = ["id": item.id, "name": item.name, "base_model": item.baseModel, "model_type": item.modelType ?? "chat", "enabled": item.enabled == 0, "temperature": item.temperature ?? 0.7, "top_p": item.topP ?? 1, "max_tokens": item.maxTokens ?? 2048]
        do { let _: EmptyResponse = try await session.send("ai-api/models/update", method: "POST", body: body, allowEmpty: true); await load() } catch { self.error = session.message(for: error) }
    }
    private func deleteModel(_ item: AIModel) async { do { let _: EmptyResponse = try await session.send("ai-api/models/delete", method: "POST", body: ["id": item.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func syncAll() async { do { let result: AISyncResponse = try await session.send("ai-api/models/sync", method: "POST", body: [:]); notice = "同步完成，共 \(result.total ?? 0) 个模型"; await load() } catch { self.error = session.message(for: error) } }
}

private struct NativeKnowledgeView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var collections: [KnowledgeCollection] = []
    @State private var files: [KnowledgeFile] = []
    @State private var query = ""
    @State private var newName = ""
    @State private var loading = false
    @State private var error: String?
    @State private var importing = false
    @State private var selectedFile: KnowledgeFile?
    @State private var detail: KnowledgeFileDetail?
    @State private var deletingFile: KnowledgeFile?

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
                    Button { selectedFile = file; Task { await preview(file) } } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(file.name).foregroundStyle(.primary); Text(file.status ?? "已导入").font(.caption).foregroundStyle(.secondary) }
                    }.swipeActions {
                        Button("删除", role: .destructive) { deletingFile = file }
                        Button("重解析") { Task { await reprocess(file) } }.tint(.blue)
                    }
                }
            }
        }
        .overlay { if loading && collections.isEmpty && files.isEmpty { ProgressView() } }
        .navigationTitle("知识库").searchable(text: $query, prompt: "搜索文件")
        .refreshable { await load() }.task { await load() }
        .toolbar { Button { importing = true } label: { Image(systemName: "doc.badge.plus") } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText, .json, .commaSeparatedText, .image, .data]) { result in Task { await importFile(result) } }
        .sheet(item: $selectedFile) { file in NavigationStack { List { if let detail { Section("内容") { Text(detail.file.content ?? "无可读取内容").textSelection(.enabled) }; Section("分块") { ForEach(detail.chunks) { chunk in VStack(alignment: .leading) { Text("第 \(chunk.chunkIndex + 1) 块").font(.caption).foregroundStyle(.secondary); Text(chunk.content).textSelection(.enabled) } } } } else { ProgressView() } }.navigationTitle(file.name).toolbar { Button("关闭") { selectedFile = nil; detail = nil } } } }
        .confirmationDialog("确定删除这个知识文件吗？", isPresented: Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let file = deletingFile { Task { await remove(file) } } }; Button("取消", role: .cancel) { deletingFile = nil } }
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

    private func importFile(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw NativeAPIError.invalidResponse }; defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url); guard data.count <= 15_000_000 else { throw NativeAPIError.server(400, "单个文件不能超过 15MB") }
            let response: ImportFileResponse = try await session.send("ai-api/documents/import-file", method: "POST", body: ["title": url.deletingPathExtension().lastPathComponent, "filename": url.lastPathComponent, "data": data.base64EncodedString()])
            if let collection = collections.first { let _: EmptyResponse = try await session.send("ai-api/files/assign", method: "POST", body: ["file_id": response.file.id, "knowledge_id": collection.id], allowEmpty: true) }
            await load()
        } catch { self.error = session.message(for: error) }
    }
    private func preview(_ file: KnowledgeFile) async { do { detail = try await session.get("ai-api/files/detail?id=\(file.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file.id)") } catch { self.error = session.message(for: error) } }
    private func reprocess(_ file: KnowledgeFile) async { do { let _: EmptyResponse = try await session.send("ai-api/files/reprocess", method: "POST", body: ["id": file.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func remove(_ file: KnowledgeFile) async { do { let _: EmptyResponse = try await session.send("ai-api/files/delete", method: "POST", body: ["id": file.id], allowEmpty: true); deletingFile = nil; await load() } catch { self.error = session.message(for: error) } }
}

private struct ConnectionForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: AIConnection?; let onSave: () async -> Void
    @State private var name: String; @State private var baseURL: String; @State private var apiKey = ""; @State private var provider: String; @State private var purpose: String
    @State private var saving = false; @State private var testing = false; @State private var message: String?
    init(item: AIConnection?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.name ?? "OpenAI"); _baseURL = State(initialValue: item?.baseURL ?? "https://api.openai.com/v1"); _provider = State(initialValue: item?.providerType ?? "openai"); _purpose = State(initialValue: item?.purpose ?? "general") }
    var body: some View { NavigationStack { Form {
        if let message { Text(message).foregroundStyle(.secondary) }
        Section("连接") { TextField("名称", text: $name); TextField("接口地址", text: $baseURL).textInputAutocapitalization(.never).keyboardType(.URL); SecureField(item?.hasKey == true ? "留空保留已有 Key" : "API Key", text: $apiKey).textInputAutocapitalization(.never) }
        Section("类型") { Picker("协议", selection: $provider) { Text("OpenAI 兼容").tag("openai"); Text("Ollama").tag("ollama"); Text("Pipeline").tag("pipeline") }; Picker("用途", selection: $purpose) { Text("通用").tag("general"); Text("对话").tag("chat"); Text("图片").tag("image"); Text("音频").tag("audio") } }
        if item != nil { Button(testing ? "测试中..." : "测试连接") { Task { await test() } }.disabled(testing) }
    }.navigationTitle(item == nil ? "新增连接" : "编辑连接").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving || name.isEmpty || baseURL.isEmpty || (item == nil && apiKey.isEmpty && provider != "ollama")) } } } }
    private func save() async { saving = true; defer { saving = false }; var body: [String: Any] = ["id": item?.id ?? "", "name": name, "base_url": baseURL, "provider_type": provider, "provider_id": provider, "purpose": purpose, "enabled": true]; if !apiKey.isEmpty { body["api_key"] = apiKey }; do { let _: EmptyResponse = try await session.send("ai-api/connections/save", method: "POST", body: body, allowEmpty: true); await onSave(); dismiss() } catch { message = session.message(for: error) } }
    private func test() async { guard let item else { return }; testing = true; defer { testing = false }; do { let result: ConnectionTestResponse = try await session.send("ai-api/connections/test", method: "POST", body: ["id": item.id]); message = result.message ?? "连接成功" } catch { message = session.message(for: error) } }
}

private struct ModelForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: AIModel?; let connections: [AIConnection]; let onSave: () async -> Void
    @State private var name: String; @State private var baseModel: String; @State private var type: String; @State private var connectionID: String
    @State private var description: String; @State private var systemPrompt: String; @State private var temperature: Double; @State private var topP: Double; @State private var maxTokens: Int
    @State private var enabled: Bool; @State private var saving = false; @State private var error: String?
    init(item: AIModel?, connections: [AIConnection], onSave: @escaping () async -> Void) {
        self.item = item; self.connections = connections; self.onSave = onSave
        _name = State(initialValue: item?.name ?? ""); _baseModel = State(initialValue: item?.baseModel ?? ""); _type = State(initialValue: item?.modelType ?? "chat")
        _connectionID = State(initialValue: item?.connectionID ?? connections.first?.id ?? ""); _description = State(initialValue: item?.description ?? ""); _systemPrompt = State(initialValue: item?.systemPrompt ?? "")
        _temperature = State(initialValue: item?.temperature ?? 0.7); _topP = State(initialValue: item?.topP ?? 1); _maxTokens = State(initialValue: item?.maxTokens ?? 2048); _enabled = State(initialValue: item?.enabled != 0)
    }
    var body: some View { NavigationStack { Form {
        if let error { Text(error).foregroundStyle(.red) }
        Section("模型") { TextField("显示名称", text: $name); TextField("基础模型，例如 gpt-4.1", text: $baseModel).textInputAutocapitalization(.never); Picker("模型类型", selection: $type) { Text("对话").tag("chat"); Text("图片").tag("image"); Text("音频").tag("audio"); Text("嵌入").tag("embedding") }; Picker("供应商连接", selection: $connectionID) { Text("未绑定").tag(""); ForEach(connections) { Text($0.name).tag($0.id) } }; Toggle("启用", isOn: $enabled) }
        Section("说明") { TextField("模型用途", text: $description, axis: .vertical).lineLimit(2...5); TextField("系统提示词", text: $systemPrompt, axis: .vertical).lineLimit(4...10) }
        if type == "chat" { Section("生成参数") { LabeledContent("Temperature", value: String(format: "%.1f", temperature)); Slider(value: $temperature, in: 0...2, step: 0.1); LabeledContent("Top P", value: String(format: "%.1f", topP)); Slider(value: $topP, in: 0...1, step: 0.1); Stepper("最大 Token：\(maxTokens)", value: $maxTokens, in: 128...128000, step: 128) } }
    }.navigationTitle(item == nil ? "新增模型" : "编辑模型").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving || name.isEmpty || baseModel.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; let body: [String: Any] = ["id": item?.id ?? "", "name": name, "base_model": baseModel, "model_type": type, "connection_id": connectionID, "description": description, "system_prompt": systemPrompt, "temperature": temperature, "top_p": topP, "max_tokens": maxTokens, "enabled": enabled, "capabilities": ["knowledge"]]; do { let _: EmptyResponse = try await session.send(item == nil ? "ai-api/models" : "ai-api/models/update", method: "POST", body: body, allowEmpty: true); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeCapabilitiesView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var kind: CapabilityKind = .prompts
    @State private var items: [CapabilityItem] = []
    @State private var query = ""; @State private var loading = false; @State private var error: String?
    @State private var editing: CapabilityItem?; @State private var showingEditor = false; @State private var deleting: CapabilityItem?
    private var filtered: [CapabilityItem] { query.isEmpty ? items : items.filter { "\($0.displayName) \($0.description ?? "") \($0.content ?? "")".localizedCaseInsensitiveContains(query) } }
    var body: some View { VStack(spacing: 0) {
        Picker("能力", selection: $kind) { ForEach(CapabilityKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding()
        List { if let error { Text(error).foregroundStyle(.red) }; ForEach(filtered) { item in
            VStack(alignment: .leading, spacing: 5) { HStack { Text(item.displayName).fontWeight(.medium); Spacer(); if kind == .tools { Circle().fill(item.enabled == 0 ? Color.gray : Color.green).frame(width: 8, height: 8) } }; Text(kind == .prompts ? "/\(item.command ?? "")" : item.description ?? item.content ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                .contentShape(Rectangle()).onTapGesture { editing = item; showingEditor = true }.swipeActions { if !item.id.hasPrefix("builtin-") { Button("删除", role: .destructive) { deleting = item } } }
        } }
    }.navigationTitle("AI 能力").searchable(text: $query).overlay { if loading && items.isEmpty { ProgressView() } }.task(id: kind) { await load() }.refreshable { await load() }
        .toolbar { Button { editing = nil; showingEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingEditor) { CapabilityForm(kind: kind, item: editing) { await load() } }
        .confirmationDialog("确定删除这项能力吗？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let item = deleting { Task { await remove(item) } } }; Button("取消", role: .cancel) { deleting = nil } }
    }
    private func load() async { loading = true; defer { loading = false }; do { let response: CapabilityResponse = try await session.get("ai-api/\(kind.path)\(kind == .tools ? "?all=1" : "")"); items = response.items(for: kind) } catch { self.error = session.message(for: error) } }
    private func remove(_ item: CapabilityItem) async { do { let _: EmptyResponse = try await session.send("ai-api/\(kind.path)/delete", method: "POST", body: ["id": item.id], allowEmpty: true); deleting = nil; await load() } catch { self.error = session.message(for: error) } }
}

private struct CapabilityForm: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let kind: CapabilityKind; let item: CapabilityItem?; let onSave: () async -> Void
    @State private var title: String; @State private var command: String; @State private var name: String; @State private var description: String; @State private var content: String; @State private var toolKind: String; @State private var enabled: Bool
    @State private var saving = false; @State private var error: String?
    init(kind: CapabilityKind, item: CapabilityItem?, onSave: @escaping () async -> Void) { self.kind = kind; self.item = item; self.onSave = onSave; _title = State(initialValue: item?.title ?? ""); _command = State(initialValue: item?.command ?? ""); _name = State(initialValue: item?.name ?? ""); _description = State(initialValue: item?.description ?? ""); _content = State(initialValue: item?.content ?? ""); _toolKind = State(initialValue: item?.kind ?? "custom"); _enabled = State(initialValue: (item?.enabled ?? 1) != 0) }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }
        if kind == .prompts { Section("Prompt") { TextField("标题", text: $title); TextField("斜杠命令", text: $command).textInputAutocapitalization(.never); TextField("Prompt 内容", text: $content, axis: .vertical).lineLimit(8...16) } }
        else if kind == .notes { Section("笔记") { TextField("标题", text: $title); TextField("笔记内容", text: $content, axis: .vertical).lineLimit(8...16) } }
        else { Section(kind == .skills ? "Skill" : "Tool") { TextField("名称", text: $name); TextField("说明", text: $description); if kind == .skills { TextField("技能指令", text: $content, axis: .vertical).lineLimit(8...16) } else { Picker("类型", selection: $toolKind) { Text("自定义").tag("custom"); Text("HTTP").tag("http"); Text("函数").tag("function") }; Toggle("启用", isOn: $enabled) } } }
    }.navigationTitle(item == nil ? "新增 \(kind.title)" : "编辑 \(kind.title)").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中..." : "保存") { Task { await save() } }.disabled(saving) } } } }
    private func save() async { saving = true; defer { saving = false }; var body: [String: Any] = ["id": item?.id ?? ""]; if kind == .prompts { body.merge(["title": title, "command": command, "content": content]) { _, new in new } } else if kind == .notes { body.merge(["title": title, "content": content]) { _, new in new } } else if kind == .skills { body.merge(["name": name, "description": description, "content": content]) { _, new in new } } else { let config: [String: Any] = [:]; body.merge(["name": name, "description": description, "kind": toolKind, "enabled": enabled, "config": config]) { _, new in new } }; do { let path = "ai-api/\(kind.path)\(item == nil ? "" : "/update")"; let _: EmptyResponse = try await session.send(path, method: "POST", body: body, allowEmpty: true); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeOperationsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var section: OperationsSection = .usage
    @State private var usage: [UsageRecord] = []; @State private var summary: UsageSummary?
    @State private var memories: [AIMemory] = []; @State private var workflows: [AIWorkflow] = []; @State private var jobs: [AIJob] = []
    @State private var loading = false; @State private var error: String?
    @State private var editingMemory: AIMemory?; @State private var showingMemory = false
    @State private var editingWorkflow: AIWorkflow?; @State private var showingWorkflow = false
    @State private var runWorkflow: AIWorkflow?; @State private var runInput = ""

    var body: some View { VStack(spacing: 0) {
        Picker("运营", selection: $section) { ForEach(OperationsSection.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding()
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if section == .usage {
                if let summary { Section { HStack { Metric(title: "调用", value: "\(summary.calls)"); Metric(title: "输入 Token", value: "\(summary.inputTokens)"); Metric(title: "输出 Token", value: "\(summary.outputTokens)") }; LabeledContent("累计费用", value: String(format: "¥ %.4f", summary.cost)) } }
                ForEach(usage) { item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.operation).fontWeight(.medium); Spacer(); Text("\(item.inputTokens + item.outputTokens) Token").font(.caption) }; Text("\(item.modelID.flatMap { $0.isEmpty ? nil : $0 } ?? "默认模型") · \(item.latencyMS) ms").font(.caption).foregroundStyle(.secondary) } }
            } else if section == .memory {
                ForEach(memories) { item in VStack(alignment: .leading, spacing: 6) { Text(item.content); HStack { Text(item.sourceChatID.isEmpty ? "手动添加" : "来自会话").font(.caption).foregroundStyle(.secondary); Spacer(); Toggle("", isOn: Binding(get: { item.enabled != 0 }, set: { enabled in Task { await toggleMemory(item, enabled) } })).labelsHidden() } }.contentShape(Rectangle()).onTapGesture { editingMemory = item; showingMemory = true }.swipeActions { Button("删除", role: .destructive) { Task { await deleteMemory(item) } } } }
            } else if section == .workflow {
                ForEach(workflows) { item in VStack(alignment: .leading, spacing: 6) { HStack { Text(item.name).fontWeight(.medium); Spacer(); StatusBadge(text: item.enabled != 0 ? "启用" : "停用", done: item.enabled != 0) }; Text(item.description).font(.caption).foregroundStyle(.secondary) }.contentShape(Rectangle()).onTapGesture { editingWorkflow = item; showingWorkflow = true }.swipeActions { Button("运行") { runWorkflow = item }.tint(.green); Button("删除", role: .destructive) { Task { await deleteWorkflow(item) } } } }
            } else {
                ForEach(jobs) { item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.kind).fontWeight(.medium); Spacer(); Text(jobStatus(item.status)).foregroundStyle(jobColor(item.status)) }; Text(item.resultText).font(.caption).foregroundStyle(.secondary).lineLimit(3) }.swipeActions { if ["queued", "running"].contains(item.status) { Button("取消") { Task { await jobAction(item, "cancel") } }.tint(.orange) } else { Button("重试") { Task { await jobAction(item, "retry") } }.tint(.blue); Button("删除", role: .destructive) { Task { await jobAction(item, "delete") } } } }
            }
        }
    }.navigationTitle("AI 运营").overlay { if loading && usage.isEmpty && memories.isEmpty && workflows.isEmpty && jobs.isEmpty { ProgressView() } }.task(id: section) { await load() }.refreshable { await load() }
        .toolbar { if section == .memory { Button { editingMemory = nil; showingMemory = true } label: { Image(systemName: "plus") } } else if section == .workflow { Button { editingWorkflow = nil; showingWorkflow = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingMemory) { MemoryForm(item: editingMemory) { await load() } }
        .sheet(isPresented: $showingWorkflow) { WorkflowForm(item: editingWorkflow) { await load() } }
        .alert("运行工作流", isPresented: Binding(get: { runWorkflow != nil }, set: { if !$0 { runWorkflow = nil } })) { TextField("输入内容", text: $runInput); Button("运行") { if let workflow = runWorkflow { Task { await run(workflow) } } }; Button("取消", role: .cancel) { runWorkflow = nil } } message: { Text("输入工作流处理内容") }
    }
    }
    private func load() async { loading = true; defer { loading = false }; do { switch section { case .usage: let result: UsageResponse = try await session.get("ai-api/usage"); usage = result.usage; summary = result.summary; case .memory: let result: MemoriesResponse = try await session.get("ai-api/memories"); memories = result.memories; case .workflow: let result: WorkflowsResponse = try await session.get("ai-api/workflows"); workflows = result.workflows; case .jobs: let result: JobsResponse = try await session.get("ai-api/jobs"); jobs = result.jobs } } catch { self.error = session.message(for: error) } }
    private func toggleMemory(_ item: AIMemory, _ enabled: Bool) async { do { let _: EmptyResponse = try await session.send("ai-api/memories", method: "POST", body: ["id": item.id, "content": item.content, "source_chat_id": item.sourceChatID, "enabled": enabled], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func deleteMemory(_ item: AIMemory) async { do { let _: EmptyResponse = try await session.send("ai-api/memories/delete", method: "POST", body: ["id": item.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func deleteWorkflow(_ item: AIWorkflow) async { do { let _: EmptyResponse = try await session.send("ai-api/workflows/delete", method: "POST", body: ["id": item.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func run(_ item: AIWorkflow) async { do { let _: JobActionResponse = try await session.send("ai-api/workflows/run", method: "POST", body: ["id": item.id, "input": runInput]); runWorkflow = nil; runInput = ""; section = .jobs; await load() } catch { self.error = session.message(for: error) } }
    private func jobAction(_ item: AIJob, _ action: String) async { do { let _: EmptyResponse = try await session.send("ai-api/jobs/\(action)", method: "POST", body: ["id": item.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}

private struct MemoryForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss
    let item: AIMemory?; let onSave: () async -> Void; @State private var content: String; @State private var enabled: Bool; @State private var saving = false; @State private var error: String?
    init(item: AIMemory?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _content = State(initialValue: item?.content ?? ""); _enabled = State(initialValue: (item?.enabled ?? 1) != 0) }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("记忆内容", text: $content, axis: .vertical).lineLimit(8...16); Toggle("启用", isOn: $enabled) }.navigationTitle(item == nil ? "新增记忆" : "编辑记忆").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || content.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; do { let _: EmptyResponse = try await session.send("ai-api/memories", method: "POST", body: ["id": item?.id ?? "", "content": content, "source_chat_id": item?.sourceChatID ?? "", "enabled": enabled], allowEmpty: true); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct WorkflowForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss
    let item: AIWorkflow?; let onSave: () async -> Void; @State private var name: String; @State private var description: String; @State private var prompt: String; @State private var enabled: Bool; @State private var saving = false; @State private var error: String?
    init(item: AIWorkflow?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.name ?? ""); _description = State(initialValue: item?.description ?? ""); _prompt = State(initialValue: item?.firstPrompt ?? "请根据以下输入完成任务：{{input}}"); _enabled = State(initialValue: (item?.enabled ?? 1) != 0) }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; Section("工作流") { TextField("名称", text: $name); TextField("说明", text: $description); Toggle("启用", isOn: $enabled) }; Section("Prompt 步骤") { TextField("支持 {{input}}", text: $prompt, axis: .vertical).lineLimit(8...16) } }.navigationTitle(item == nil ? "新建工作流" : "编辑工作流").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || name.isEmpty || prompt.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; let steps: [[String: Any]] = [["type": "prompt", "content": prompt]]; do { let _: EmptyResponse = try await session.send("ai-api/workflows", method: "POST", body: ["id": item?.id ?? "", "name": name, "description": description, "steps": steps, "enabled": enabled], allowEmpty: true); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
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

private enum WarehouseTab: String, CaseIterable, Identifiable { case stocks = "库存", outbound = "出库", inbound = "入库", products = "商品", warehouses = "仓库", movements = "流水"; var id: String { rawValue } }
private enum WarehouseSheet: Identifiable { case warehouse, product, inbound, outbound; var id: String { String(describing: self) } }

private struct NativeWarehouseView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var tab: WarehouseTab = .stocks; @State private var summary: WarehouseSummary?; @State private var warehouses: [WarehouseRecord] = []; @State private var products: [WarehouseProduct] = []; @State private var stocks: [WarehouseStock] = []; @State private var inbound: [WarehouseInbound] = []; @State private var outbound: [WarehouseOutbound] = []; @State private var movements: [WarehouseMovement] = []
    @State private var query = ""; @State private var loading = false; @State private var error: String?; @State private var sheet: WarehouseSheet?
    var body: some View {
        List {
            if let summary { Section { ScrollView(.horizontal, showsIndicators: false) { HStack { WarehouseMetric("总库存", "\(summary.totalQuantity)"); WarehouseMetric("库存成本", money(summary.totalCost)); WarehouseMetric("低库存", "\(summary.lowStockCount)"); WarehouseMetric("待出库", "\(summary.pendingOutboundCount)") }.padding(.vertical, 4) } } }
            Section { Picker("分类", selection: $tab) { ForEach(WarehouseTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu) }
            if let error { Text(error).foregroundStyle(.red) }
            switch tab {
            case .stocks: ForEach(stocks.filter { matches("\($0.sku) \($0.productName) \($0.warehouseName)") }) { row in HStack { VStack(alignment: .leading) { Text(row.productName).fontWeight(.medium); Text("\(row.sku) · \(row.warehouseName)").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text("\(row.availableQuantity) \(row.unit)").foregroundStyle(row.isLowStock ? .red : .primary); if row.lockedQuantity > 0 { Text("锁定 \(row.lockedQuantity)").font(.caption2).foregroundStyle(.orange) } } } }
            case .products: ForEach(products.filter { matches("\($0.sku) \($0.name) \($0.barcode ?? "")") }) { row in WarehouseTextRow(title: row.name, detail: "\(row.sku) · \(row.specification ?? row.unit) · \(money(row.costPrice))", status: row.isActive ? "启用" : "停用") }
            case .warehouses: ForEach(warehouses.filter { matches("\($0.code) \($0.name) \($0.address ?? "")") }) { row in WarehouseTextRow(title: row.name, detail: "\(row.code) · \(row.address ?? "未填写地址")", status: row.isActive ? "启用" : "停用") }
            case .inbound: ForEach(inbound.filter { matches("\($0.orderNo) \($0.warehouseName) \(lineSummary($0.items))") }) { row in WarehouseTextRow(title: row.orderNo, detail: "\(row.warehouseName) · \(lineSummary(row.items))", status: row.status == "completed" ? "已入库" : "已撤销").swipeActions { if row.status == "completed" { Button("撤销", role: .destructive) { Task { await cancel(row) } } } } }
            case .outbound: ForEach(outbound.filter { matches("\($0.orderNo) \($0.warehouseName) \($0.trackingNo ?? "")") }) { row in NavigationLink { WarehouseOutboundDetail(row: row) } label: { WarehouseTextRow(title: row.orderNo, detail: "\(row.warehouseName) · \(lineSummary(row.items))", status: outboundStatus(row.status)) }.swipeActions { if let next = nextStatus(row.status) { Button("推进") { Task { await setStatus(row, next) } }.tint(.blue) }; if !["shipped","cancelled"].contains(row.status) { Button("取消", role: .destructive) { Task { await setStatus(row, "cancelled") } } } } }
            case .movements: ForEach(movements.filter { matches("\($0.sku) \($0.productName) \($0.warehouseName) \($0.referenceNo)") }) { row in HStack { VStack(alignment: .leading) { Text(row.productName); Text("\(row.warehouseName) · \(row.referenceNo)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(row.quantityChange > 0 ? "+\(row.quantityChange)" : "\(row.quantityChange)").foregroundStyle(row.quantityChange > 0 ? .green : .red) } }
            }
        }.navigationTitle("仓储管理").searchable(text: $query, prompt: "搜索商品、单号或仓库").overlay { if loading && stocks.isEmpty { ProgressView() } }.task { await load() }.refreshable { await load() }
        .toolbar { if [.warehouses,.products,.inbound,.outbound].contains(tab) { Button { sheet = tab == .warehouses ? .warehouse : tab == .products ? .product : tab == .inbound ? .inbound : .outbound } label: { Image(systemName: "plus") } } }
        .sheet(item: $sheet) { value in switch value { case .warehouse: WarehouseBasicEditor(kind: .warehouse) { await load() }; case .product: WarehouseBasicEditor(kind: .product) { await load() }; case .inbound: WarehouseOrderEditor(outbound: false, warehouses: warehouses, products: products) { await load() }; case .outbound: WarehouseOrderEditor(outbound: true, warehouses: warehouses, products: products) { await load() } } }
    }
    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedCaseInsensitiveContains(query) }
    private func load() async { loading = true; defer { loading = false }; do { async let a: WarehouseSummary = session.get("warehouse/summary"); async let b: [WarehouseRecord] = session.get("warehouse/warehouses"); async let c: [WarehouseProduct] = session.get("warehouse/products"); async let d: [WarehouseStock] = session.get("warehouse/stocks"); async let e: [WarehouseInbound] = session.get("warehouse/inbound-orders"); async let f: [WarehouseOutbound] = session.get("warehouse/outbound-orders"); async let g: [WarehouseMovement] = session.get("warehouse/movements"); (summary,warehouses,products,stocks,inbound,outbound,movements) = try await (a,b,c,d,e,f,g) } catch { self.error = session.message(for: error) } }
    private func cancel(_ row: WarehouseInbound) async { do { let _: WarehouseInbound = try await session.send("warehouse/inbound-orders/\(row.id)", method: "DELETE"); await load() } catch { self.error = session.message(for: error) } }
    private func setStatus(_ row: WarehouseOutbound, _ status: String) async { do { let _: WarehouseOutbound = try await session.send("warehouse/outbound-orders/\(row.id)/status", method: "PATCH", body: ["status":status,"carrier":row.carrier ?? "","tracking_no":row.trackingNo ?? ""]); await load() } catch { self.error = session.message(for: error) } }
}
private struct WarehouseMetric: View { let title:String,value:String; init(_ title:String,_ value:String){self.title=title;self.value=value}; var body:some View{VStack(alignment:.leading){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.headline)}.padding(12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:8))} }
private struct WarehouseTextRow: View { let title:String,detail:String,status:String; var body:some View{VStack(alignment:.leading,spacing:5){HStack{Text(title).fontWeight(.medium);Spacer();Text(status).foregroundStyle(.secondary)};Text(detail).font(.caption).foregroundStyle(.secondary)}} }
private struct WarehouseOutboundDetail: View { let row: WarehouseOutbound; var body: some View { List { Section("订单") { LabeledContent("出库单号", value: row.orderNo); LabeledContent("仓库", value: row.warehouseName); LabeledContent("状态", value: outboundStatus(row.status)); if let external = row.externalOrderNo, !external.isEmpty { LabeledContent("平台订单", value: external) } }; Section("收货信息") { LabeledContent("收件人", value: row.recipientName ?? "-"); LabeledContent("联系电话", value: row.recipientPhone ?? "-"); LabeledContent("地址", value: row.recipientAddress ?? "-"); LabeledContent("快递", value: row.carrier ?? "-"); LabeledContent("物流单号", value: row.trackingNo ?? "-") }; Section("商品") { ForEach(row.items, id: \.productID) { item in LabeledContent("\(item.sku) · \(item.productName)", value: "× \(item.quantity) \(item.unit)") } } }.navigationTitle("出库详情").navigationBarTitleDisplayMode(.inline) } }

private struct WarehouseBasicEditor: View {
    enum Kind { case warehouse, product }; @EnvironmentObject private var session:NativeSession; @Environment(\.dismiss) private var dismiss; let kind:Kind; let onSave:() async->Void
    @State private var code=""; @State private var name=""; @State private var extra=""; @State private var unit="件"; @State private var price="0"; @State private var warning=0; @State private var error:String?
    var body:some View{NavigationStack{Form{if let error{Text(error).foregroundStyle(.red)};TextField(kind == .warehouse ? "仓库编码":"SKU",text:$code).textInputAutocapitalization(.characters);TextField(kind == .warehouse ? "仓库名称":"商品名称",text:$name);TextField(kind == .warehouse ? "地址":"条码",text:$extra);if kind == .product{TextField("单位",text:$unit);TextField("成本价",text:$price).keyboardType(.decimalPad);Stepper("预警库存：\(warning)",value:$warning,in:0...999999)}}.navigationTitle(kind == .warehouse ? "新增仓库":"新增商品").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("保存"){Task{await save()}}.disabled(code.isEmpty || name.isEmpty)}}}}
    private func save()async{do{if kind == .warehouse{let _:WarehouseRecord=try await session.send("warehouse/warehouses",method:"POST",body:["code":code,"name":name,"address":extra,"contact_name":"","contact_phone":"","is_active":true,"remark":""])}else{let _:WarehouseProduct=try await session.send("warehouse/products",method:"POST",body:["sku":code,"name":name,"barcode":extra,"specification":"","unit":unit,"cost_price":Double(price) ?? 0,"warning_quantity":warning,"is_active":true,"remark":""])};await onSave();dismiss()}catch{self.error=session.message(for:error)}}
}
private struct WarehouseOrderEditor: View {
    @EnvironmentObject private var session:NativeSession; @Environment(\.dismiss) private var dismiss; let outbound:Bool; let warehouses:[WarehouseRecord]; let products:[WarehouseProduct]; let onSave:() async->Void
    @State private var warehouseID=0;@State private var productID=0;@State private var quantity=1;@State private var source="purchase";@State private var recipient="";@State private var phone="";@State private var address="";@State private var carrier="";@State private var trackingNo="";@State private var remark="";@State private var error:String?
    var body:some View{NavigationStack{Form{if let error{Text(error).foregroundStyle(.red)};Picker("仓库",selection:$warehouseID){Text("请选择").tag(0);ForEach(warehouses.filter(\.isActive)){Text($0.name).tag($0.id)}};Picker("商品",selection:$productID){Text("请选择").tag(0);ForEach(products.filter(\.isActive)){Text("\($0.sku) · \($0.name)").tag($0.id)}};Stepper("数量：\(quantity)",value:$quantity,in:1...999999);if outbound{TextField("收件人",text:$recipient);TextField("联系电话",text:$phone).keyboardType(.phonePad);TextField("收货地址",text:$address);TextField("快递公司（可选）",text:$carrier);TextField("物流单号（可选）",text:$trackingNo)}else{Picker("入库类型",selection:$source){Text("采购入库").tag("purchase");Text("退货入库").tag("return");Text("其他入库").tag("other")}};TextField("备注",text:$remark,axis:.vertical)}.navigationTitle(outbound ? "新建出库单":"商品入库").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("提交"){Task{await save()}}.disabled(warehouseID == 0 || productID == 0)}}}}
    private func save()async{var body:[String:Any]=["warehouse_id":warehouseID,"items":[["product_id":productID,"quantity":quantity]],"remark":remark];do{if outbound{body.merge(["external_order_no":"","delivery_method":"shipping","recipient_name":recipient,"recipient_phone":phone,"recipient_address":address,"carrier":carrier,"tracking_no":trackingNo]){_,new in new};let _:WarehouseOutbound=try await session.send("warehouse/outbound-orders",method:"POST",body:body)}else{body["source_type"]=source;body["supplier"]="";let _:WarehouseInbound=try await session.send("warehouse/inbound-orders",method:"POST",body:body)};await onSave();dismiss()}catch{self.error=session.message(for:error)}}
}

private extension View {
    func nativeField() -> some View { padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct AIChatMessage: Codable, Identifiable {
    let id: String; let role: String; var content: String
    init(id: String = UUID().uuidString, role: String, content: String) { self.id = id; self.role = role; self.content = content }
}
private struct AIChat: Decodable, Identifiable {
    let id: String; var title: String; var messages: [AIChatMessage]; var modelID: String?; var favorite: Bool; var archived: Bool; var folder: String; let createdAt: TimeInterval; var updatedAt: TimeInterval
    enum CodingKeys: String, CodingKey { case id, title, messages, favorite, archived, folder; case modelID = "model_id"; case createdAt = "created_at"; case updatedAt = "updated_at" }
    init(id: String, title: String, messages: [AIChatMessage], modelID: String?, favorite: Bool, archived: Bool, folder: String, createdAt: TimeInterval, updatedAt: TimeInterval) { self.id = id; self.title = title; self.messages = messages; self.modelID = modelID; self.favorite = favorite; self.archived = archived; self.folder = folder; self.createdAt = createdAt; self.updatedAt = updatedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); title = try values.decode(String.self, forKey: .title)
        messages = (try? values.decode([AIChatMessage].self, forKey: .messages)) ?? []
        modelID = try? values.decode(String.self, forKey: .modelID)
        favorite = (try? values.decode(Bool.self, forKey: .favorite)) ?? (((try? values.decode(Int.self, forKey: .favorite)) ?? 0) != 0)
        archived = (try? values.decode(Bool.self, forKey: .archived)) ?? (((try? values.decode(Int.self, forKey: .archived)) ?? 0) != 0)
        folder = (try? values.decode(String.self, forKey: .folder)) ?? ""
        createdAt = TimeInterval((try? values.decode(Int.self, forKey: .createdAt)) ?? 0); updatedAt = TimeInterval((try? values.decode(Int.self, forKey: .updatedAt)) ?? 0)
    }
}
private struct AIChatsResponse: Decodable { let chats: [AIChat] }

private struct AIModel: Codable, Identifiable {
    let id: String; let name: String; let baseModel: String; let modelType: String?; let enabled: Int; let hidden: Int?
    let temperature: Double?; let topP: Double?; let maxTokens: Int?
    let description: String?; let systemPrompt: String?; let connectionID: String?
    enum CodingKeys: String, CodingKey { case id, name, enabled, hidden, temperature, description; case baseModel = "base_model"; case modelType = "model_type"; case topP = "top_p"; case maxTokens = "max_tokens"; case systemPrompt = "system_prompt"; case connectionID = "connection_id" }
}
private struct AIModelsResponse: Codable { let models: [AIModel] }
private struct AIConnection: Codable, Identifiable {
    let id: String; let name: String; let baseURL: String; let providerType: String?; let purpose: String?; let enabled: Int; let hasKey: Bool?
    enum CodingKeys: String, CodingKey { case id, name, purpose, enabled; case baseURL = "base_url"; case providerType = "provider_type"; case hasKey = "has_key" }
}
private struct AIConnectionsResponse: Codable { let connections: [AIConnection] }
private struct AISyncResponse: Codable { let total: Int? }
private struct ConnectionTestResponse: Codable { let message: String? }
private struct TranscriptionResponse: Codable { let text: String }
private struct KnowledgeCollection: Codable, Identifiable { let id: String; let name: String; let description: String? }
private struct KnowledgeFile: Codable, Identifiable {
    let id: String; let name: String; let knowledgeID: String?; let status: String?; let content: String?
    enum CodingKeys: String, CodingKey { case id, name, status, content; case knowledgeID = "knowledge_id" }
}
private struct KnowledgeResponse: Codable { let knowledge: [KnowledgeCollection] }
private struct KnowledgeFilesResponse: Codable { let files: [KnowledgeFile] }
private struct KnowledgeChunk: Codable, Identifiable { let id: String; let chunkIndex: Int; let content: String; enum CodingKeys: String, CodingKey { case id, content; case chunkIndex = "chunk_index" } }
private struct KnowledgeFileDetail: Codable { let file: KnowledgeFile; let chunks: [KnowledgeChunk] }
private struct ImportFileResponse: Codable { let file: KnowledgeFile }
private enum CapabilityKind: String, CaseIterable, Identifiable { case prompts, skills, tools, notes; var id: String { rawValue }; var path: String { rawValue }; var title: String { switch self { case .prompts: return "Prompts"; case .skills: return "Skills"; case .tools: return "Tools"; case .notes: return "Notes" } } }
private struct CapabilityItem: Codable, Identifiable {
    let id: String; let title: String?; let command: String?; let name: String?; let description: String?; let content: String?; let kind: String?; let enabled: Int?
    var displayName: String { title ?? name ?? "未命名" }
}
private struct CapabilityResponse: Codable {
    let prompts: [CapabilityItem]?; let skills: [CapabilityItem]?; let tools: [CapabilityItem]?; let notes: [CapabilityItem]?
    func items(for kind: CapabilityKind) -> [CapabilityItem] { switch kind { case .prompts: return prompts ?? []; case .skills: return skills ?? []; case .tools: return tools ?? []; case .notes: return notes ?? [] } }
}
private enum OperationsSection: String, CaseIterable, Identifiable { case usage, memory, workflow, jobs; var id: String { rawValue }; var title: String { switch self { case .usage: return "用量"; case .memory: return "记忆"; case .workflow: return "工作流"; case .jobs: return "任务" } } }
private struct UsageRecord: Codable, Identifiable {
    let id: Int; let operation: String; let modelID: String?; let inputTokens: Int; let outputTokens: Int; let latencyMS: Int
    enum CodingKeys: String, CodingKey { case id, operation; case modelID = "model_id"; case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case latencyMS = "latency_ms" }
}
private struct UsageSummary: Codable { let calls: Int; let inputTokens: Int; let outputTokens: Int; let cost: Double; enum CodingKeys: String, CodingKey { case calls, cost; case inputTokens = "input_tokens"; case outputTokens = "output_tokens" } }
private struct UsageResponse: Codable { let usage: [UsageRecord]; let summary: UsageSummary }
private struct AIMemory: Codable, Identifiable { let id: String; let content: String; let sourceChatID: String; let enabled: Int; enum CodingKeys: String, CodingKey { case id, content, enabled; case sourceChatID = "source_chat_id" } }
private struct MemoriesResponse: Codable { let memories: [AIMemory] }
private struct AIWorkflow: Codable, Identifiable {
    let id: String; let name: String; let description: String; let steps: String; let enabled: Int
    var firstPrompt: String { guard let data = steps.data(using: .utf8), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return "" }; return rows.first?["content"] as? String ?? "" }
}
private struct WorkflowsResponse: Codable { let workflows: [AIWorkflow] }
private struct AIJob: Codable, Identifiable {
    let id: String; let kind: String; let status: String; let output: String?; let error: String?
    var resultText: String { if let error, !error.isEmpty { return error }; guard let output, !output.isEmpty else { return "暂无结果" }; if let data = output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let result = object["result"] { return String(describing: result) }; return output }
}
private struct JobsResponse: Codable { let jobs: [AIJob] }
private struct JobActionResponse: Codable { let jobID: String?; let status: String?; enum CodingKeys: String, CodingKey { case status; case jobID = "job_id" } }
private struct ShopField: Codable, Identifiable { let id: Int; let fieldName: String; let label: String; let fieldType: String; let required: Bool; let sortOrder: Int; let isVisible: Bool; enum CodingKeys: String, CodingKey { case id, label, required; case fieldName = "field_name"; case fieldType = "field_type"; case sortOrder = "sort_order"; case isVisible = "is_visible" } }
private struct ShopRecord: Codable, Identifiable { let id: Int; let values: [String: JSONValue] }
private enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws { let value = try decoder.singleValueContainer(); if value.decodeNil() { self = .null } else if let item = try? value.decode(String.self) { self = .string(item) } else if let item = try? value.decode(Bool.self) { self = .bool(item) } else if let item = try? value.decode(Double.self) { self = .number(item) } else { self = .null } }
    func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); switch self { case .string(let item): try value.encode(item); case .number(let item): try value.encode(item); case .bool(let item): try value.encode(item); case .null: try value.encodeNil() } }
    var display: String { switch self { case .string(let item): return item; case .number(let item): return item.rounded() == item ? String(Int(item)) : String(item); case .bool(let item): return item ? "是" : "否"; case .null: return "-" } }
}
private struct TaskOwner: Codable, Identifiable { let id: Int; let name: String }
private struct AdminUserRecord: Codable, Identifiable { let id: Int; let username: String; let displayName: String?; let role: String; let isActive: Bool; let permissions: [String: String]?; enum CodingKeys: String, CodingKey { case id, username, role, permissions; case displayName = "display_name"; case isActive = "is_active" } }
private struct LicenseDevice: Codable, Identifiable { var id: String { deviceID }; let deviceID: String; let deviceName: String?; let platform: String?; let appVersion: String?; enum CodingKeys: String, CodingKey { case platform; case deviceID = "device_id"; case deviceName = "device_name"; case appVersion = "app_version" } }
private struct LicenseRecord: Codable, Identifiable { var id: String { licenseKey }; let licenseKey: String; let planName: String; let status: String; let maxDevices: Int; let expiresAt: String?; let devices: [LicenseDevice]; enum CodingKeys: String, CodingKey { case status, devices; case licenseKey = "license_key"; case planName = "plan_name"; case maxDevices = "max_devices"; case expiresAt = "expires_at" } }
private struct PeerShopRecord: Codable, Identifiable { let id: Int; let shopName: String; let shopURL: String?; let remark: String?; enum CodingKeys: String, CodingKey { case id, remark; case shopName = "shop_name"; case shopURL = "shop_url" } }
private struct LicenseRecordItem: Codable, Identifiable { let id: Int; let subjectName: String; let creditCode: String; let legalRepresentative: String?; let issueDate: String?; let expiryDate: String?; let remark: String?; enum CodingKeys: String, CodingKey { case id, remark; case subjectName = "subject_name"; case creditCode = "credit_code"; case legalRepresentative = "legal_representative"; case issueDate = "issue_date"; case expiryDate = "expiry_date" } }
private struct MobileDevice: Codable, Identifiable { let id: Int; let deviceName: String; let primaryCard: String?; let secondaryCard: String?; let remark: String?; enum CodingKeys: String, CodingKey { case id, remark; case deviceName = "device_name"; case primaryCard = "primary_card"; case secondaryCard = "secondary_card" } }
private struct AccountUsage: Codable, Identifiable { let id: Int; let accountName: String; let phoneNumber: String?; let deviceName: String?; let usageNotes: String?; let isBanned: Bool; let bannedReason: String?; enum CodingKeys: String, CodingKey { case id; case accountName = "account_name"; case phoneNumber = "phone_number"; case deviceName = "device_name"; case usageNotes = "usage_notes"; case isBanned = "is_banned"; case bannedReason = "banned_reason" } }
private struct WarehouseSummary: Codable { let warehouseCount:Int;let productCount:Int;let totalQuantity:Int;let totalCost:Double;let lowStockCount:Int;let pendingOutboundCount:Int;let todayInboundQuantity:Int;let todayOutboundQuantity:Int; enum CodingKeys:String,CodingKey{case warehouseCount="warehouse_count",productCount="product_count",totalQuantity="total_quantity",totalCost="total_cost",lowStockCount="low_stock_count",pendingOutboundCount="pending_outbound_count",todayInboundQuantity="today_inbound_quantity",todayOutboundQuantity="today_outbound_quantity"} }
private struct WarehouseRecord: Codable, Identifiable { let id:Int;let code:String;let name:String;let address:String?;let contactName:String?;let contactPhone:String?;let isActive:Bool;let remark:String?; enum CodingKeys:String,CodingKey{case id,code,name,address,remark;case contactName="contact_name",contactPhone="contact_phone",isActive="is_active"} }
private struct WarehouseProduct: Codable, Identifiable { let id:Int;let sku:String;let name:String;let barcode:String?;let specification:String?;let unit:String;let costPrice:Double;let warningQuantity:Int;let isActive:Bool;let remark:String?; enum CodingKeys:String,CodingKey{case id,sku,name,barcode,specification,unit,remark;case costPrice="cost_price",warningQuantity="warning_quantity",isActive="is_active"} }
private struct WarehouseStock: Codable, Identifiable { var id:String{"\(warehouseID)-\(productID)"};let warehouseID:Int;let warehouseName:String;let productID:Int;let sku:String;let productName:String;let unit:String;let quantity:Int;let lockedQuantity:Int;let availableQuantity:Int;let isLowStock:Bool; enum CodingKeys:String,CodingKey{case sku,unit,quantity;case warehouseID="warehouse_id",warehouseName="warehouse_name",productID="product_id",productName="product_name",lockedQuantity="locked_quantity",availableQuantity="available_quantity",isLowStock="is_low_stock"} }
private struct WarehouseLine: Codable { let productID:Int;let sku:String;let productName:String;let unit:String;let quantity:Int; enum CodingKeys:String,CodingKey{case sku,unit,quantity;case productID="product_id",productName="product_name"} }
private struct WarehouseInbound: Codable, Identifiable { let id:Int;let orderNo:String;let warehouseName:String;let status:String;let items:[WarehouseLine]; enum CodingKeys:String,CodingKey{case id,status,items;case orderNo="order_no",warehouseName="warehouse_name"} }
private struct WarehouseOutbound: Codable, Identifiable { let id:Int;let orderNo:String;let warehouseName:String;let externalOrderNo:String?;let status:String;let carrier:String?;let trackingNo:String?;let recipientName:String?;let recipientPhone:String?;let recipientAddress:String?;let items:[WarehouseLine]; enum CodingKeys:String,CodingKey{case id,status,carrier,items;case orderNo="order_no",warehouseName="warehouse_name",externalOrderNo="external_order_no",trackingNo="tracking_no",recipientName="recipient_name",recipientPhone="recipient_phone",recipientAddress="recipient_address"} }
private struct WarehouseMovement: Codable, Identifiable { let id:Int;let warehouseName:String;let sku:String;let productName:String;let quantityChange:Int;let quantityAfter:Int;let referenceNo:String; enum CodingKeys:String,CodingKey{case id,sku;case warehouseName="warehouse_name",productName="product_name",quantityChange="quantity_change",quantityAfter="quantity_after",referenceNo="reference_no"} }

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
private struct MultipartFile { let field: String; let filename: String; let data: Data; let mime: String }

@MainActor private final class NativeSession: ObservableObject {
    @Published var loggedIn = false
    @Published var loading = false
    @Published var error: String?
    @Published var captchaImageData: String?
    @Published var needsTOTP = false
    @Published var username = "管理员"
    private var captchaID: String?
    private let origin = URL(string: "https://xiaoxu666.asia")!
    private let decoder: JSONDecoder = { let value = JSONDecoder(); value.keyDecodingStrategy = .useDefaultKeys; return value }()

    func restoreSession() async {
        guard !loggedIn else { return }
        do {
            let user: CurrentUserSession = try await get("auth/me")
            username = user.username
            loggedIn = true
        } catch {
            loggedIn = false
        }
    }

    func login(username: String, password: String, totpCode: String = "", captchaCode: String = "") async {
        loading = true; error = nil; defer { loading = false }
        do {
            let cleanTOTP = totpCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCaptcha = captchaCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedTOTP: Any = cleanTOTP.isEmpty ? NSNull() : cleanTOTP
            let savedCaptchaID: Any = captchaID ?? NSNull()
            let savedCaptchaCode: Any = cleanCaptcha.isEmpty ? NSNull() : cleanCaptcha
            let body: [String: Any] = ["username": username, "password": password, "totp_code": savedTOTP, "captcha_id": savedCaptchaID, "captcha_code": savedCaptchaCode]
            guard let url = URL(string: "auth/login", relativeTo: origin) else { throw NativeAPIError.invalidResponse }
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NativeAPIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String ?? "登录失败"
                if http.value(forHTTPHeaderField: "X-TOTP-Required") == "true" { needsTOTP = true }
                if http.value(forHTTPHeaderField: "X-Captcha-Required") == "true" { await loadCaptcha() }
                throw NativeAPIError.server(http.statusCode, detail)
            }
            self.username = username; captchaID = nil; captchaImageData = nil; loggedIn = true
        } catch { self.error = message(for: error) }
    }

    func loadCaptcha() async {
        do {
            let response: LoginCaptcha = try await get("auth/captcha")
            captchaID = response.captchaID
            captchaImageData = response.imageData
        } catch { self.error = message(for: error) }
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

    func upload<T: Decodable>(path: String, field: String, filename: String, data: Data, mime: String) async throws -> T {
        try await uploadMany(path: path, files: [MultipartFile(field: field, filename: filename, data: data, mime: mime)])
    }

    func uploadMany<T: Decodable>(path: String, files: [MultipartFile]) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw NativeAPIError.invalidResponse }
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            let safeFilename = file.filename.replacingOccurrences(of: "\"", with: "")
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(safeFilename)\"\r\n".utf8))
            body.append(Data("Content-Type: \(file.mime)\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NativeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { let detail = ((try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any])?["detail"] as? String ?? "上传失败"; throw NativeAPIError.server(http.statusCode, detail) }
        return try decoder.decode(T.self, from: responseData)
    }

    func chat(_ question: String, modelID: String = "") async -> String? {
        do {
            var body: [String: Any] = ["question": question]
            if !modelID.isEmpty { body["model_id"] = modelID }
            let response: ChatResponse = try await send("ai-api/chat", method: "POST", body: body)
            return response.content ?? response.answer ?? response.response
        } catch { return message(for: error) }
    }

    func streamChat(_ question: String, modelID: String, onChunk: @escaping @MainActor (String) -> Void) async throws {
        guard let url = URL(string: "ai-api/chat/stream", relativeTo: origin) else { throw NativeAPIError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["question": question]
        if !modelID.isEmpty { body["model_id"] = modelID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NativeAPIError.invalidResponse }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let content = object["content"] as? String else { continue }
            onChunk(content)
        }
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

private func lineSummary(_ items: [WarehouseLine]) -> String { items.map { "\($0.sku) × \($0.quantity)" }.joined(separator: "；") }
private func outboundStatus(_ value: String) -> String { switch value { case "pending": return "待拣货"; case "picking": return "拣货中"; case "checked": return "已复核"; case "packed": return "已打包"; case "shipped": return "已发货"; case "cancelled": return "已取消"; default: return value } }
private func nextStatus(_ value: String) -> String? { switch value { case "pending": return "picking"; case "picking": return "checked"; case "checked": return "packed"; case "packed": return "shipped"; default: return nil } }
private struct EmptyResponse: Codable {}
private struct ChatResponse: Codable { let content: String?; let answer: String?; let response: String? }
private struct LoginCaptcha: Decodable { let captchaID: String; let imageData: String; enum CodingKeys: String, CodingKey { case captchaID = "captcha_id"; case imageData = "image_data" } }
private struct CurrentUserSession: Decodable { let username: String }
private struct CaptchaWebView: UIViewRepresentable {
    let data: String
    func makeUIView(context: Context) -> WKWebView { let view = WKWebView(); view.isOpaque = false; view.backgroundColor = .clear; return view }
    func updateUIView(_ view: WKWebView, context: Context) { view.loadHTMLString("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;background:transparent;overflow:hidden\">\(data.hasPrefix("data:") ? "<img src='\(data)' style='width:132px;height:44px'>" : "")</body>", baseURL: nil) }
}

private struct HomeShortcut: View { let title: String; let icon: String; let color: Color; init(_ title: String, _ icon: String, _ color: Color) { self.title = title; self.icon = icon; self.color = color }; var body: some View { VStack(spacing: 6) { Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 48, height: 42).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)); Text(title).font(.caption2).fontWeight(.semibold).lineLimit(1) } } }
private struct HomeMetric: View { let title: String; let value: String; init(_ title: String, _ value: String) { self.title = title; self.value = value }; var body: some View { VStack(spacing: 5) { Text(value).font(.system(size: 16, weight: .semibold)); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 14).background(.background) } }
private struct HomeTodo: View { let color: Color; let title: String; let detail: String; let value: String; var body: some View { HStack(spacing: 12) { Circle().fill(color).frame(width: 7, height: 7); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline).fontWeight(.semibold); Text(detail).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text(value).font(.title3).fontWeight(.bold) }.padding(.horizontal, 14).padding(.vertical, 13) } }
private func money(_ value: Double) -> String { String(format: "¥ %.2f", value) }
private func shortDate(_ value: String?) -> String { guard let value else { return "-" }; return String(value.replacingOccurrences(of: "T", with: " ").prefix(16)) }
private func shortTimestamp(_ value: TimeInterval) -> String { let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"; return formatter.string(from: Date(timeIntervalSince1970: value)) }
private func jobStatus(_ value: String) -> String { switch value { case "queued": return "排队中"; case "running": return "运行中"; case "completed": return "已完成"; case "failed": return "失败"; case "cancelled": return "已取消"; default: return value } }
private func jobColor(_ value: String) -> Color { switch value { case "completed": return .green; case "failed": return .red; case "queued", "running": return .blue; default: return .secondary } }
private func roleLabel(_ value: String) -> String { switch value { case "superadmin": return "超级管理员"; case "editor": return "编辑员"; default: return "只读账号" } }
private func licenseStatus(_ value: String) -> String { switch value { case "active": return "生效中"; case "disabled": return "已停用"; case "expired": return "已过期"; default: return "未激活" } }
