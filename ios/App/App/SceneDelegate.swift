import UIKit
import Capacitor
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import WebKit
import ImageIO
import PhotosUI

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
    @AppStorage("native-dark-mode") private var darkMode = false

    var body: some View {
        Group {
            if session.restoring {
                NativeLaunchView()
            } else if session.loggedIn { NativeTabView().environmentObject(session) }
            else { NativeLoginView().environmentObject(session) }
        }
        .tint(Color(red: 0.08, green: 0.49, blue: 0.96))
        .preferredColorScheme(darkMode ? .dark : .light)
        .animation(.easeOut(duration: 0.25), value: session.restoring)
        .task { await session.restoreSession() }
    }
}

private struct NativeLoginView: View {
    @EnvironmentObject private var session: NativeSession
#if DEBUG
    @State private var account = "demo"
    @State private var password = "Demo@123456"
#else
    @State private var account = ""
    @State private var password = ""
#endif
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
        TabView(selection: $selected) {
            NativeHomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            NativeTaskView()
                .tabItem { Label("任务", systemImage: "checklist") }
                .tag(1)
            NativeQuickLedgerView()
                .tabItem { Label("记账", systemImage: "wallet.pass") }
                .tag(2)
            NativeLinksView()
                .tabItem { Label("链接", systemImage: "link") }
                .tag(3)
            NativeMineView(isActive: selected == 4)
                .tabItem { Label("我的", systemImage: "person") }
                .tag(4)
        }
    }
}

private struct NativeLaunchView: View {
    @State private var animated = false
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(Color.blue).frame(width: 84, height: 84).scaleEffect(animated ? 1 : 0.88).shadow(color: .blue.opacity(0.25), radius: animated ? 20 : 8, y: 8)
                    Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white).rotationEffect(.degrees(animated ? 0 : -8))
                }
                VStack(spacing: 6) { Text("NBAssistant").font(.title2.bold()); Text("内部管理工作台").font(.subheadline).foregroundStyle(.secondary) }
                ProgressView().controlSize(.regular).padding(.top, 4)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { animated = true } }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在启动 NBAssistant")
    }
}

private enum NativeDestination: String, Identifiable, Hashable {
    case tasks, shops, warehouse, links, workbench, profits, expenses, owners
    case peers, licenses, accountUsage, devices, users, licenseKeys
    case aiWorkspace, aiModels, aiKnowledge, aiCapabilities, aiOperations
    case sycm, server, alerts, search, systemSettings, appSettings, profile

    var id: String { rawValue }

    @ViewBuilder var view: some View {
        Group { switch self {
        case .tasks: NativeTaskView(embedded: true)
        case .shops: NativeShopsView()
        case .warehouse: NativeWarehouseView()
        case .links: NativeLinksView(embedded: true)
        case .expenses: NativeQuickLedgerView(embedded: true)
        case .owners: NativeOwnersView()
        case .peers: NativePeerShopsView()
        case .licenses: NativeLicenseRecordsView()
        case .accountUsage: NativeAccountUsageView()
        case .devices: NativeDevicesView()
        case .users: NativeUsersView()
        case .licenseKeys: NativeLicensesView()
        case .aiModels: NativeModelsView()
        case .aiKnowledge: NativeKnowledgeView()
        case .aiCapabilities: NativeCapabilitiesView()
        case .aiOperations: NativeOperationsView()
        case .aiWorkspace: NativeAIWorkspaceView()
        case .workbench: NativeWorkbenchView()
        case .profits: NativeProfitView()
        case .sycm: NativeSycmView()
        case .server: NativeServerView()
        case .alerts: NativeAlertsView()
        case .search: NativeSearchView()
        case .systemSettings: NativeSystemSettingsView()
        case .appSettings: NativeAppSettingsView()
        case .profile: NativeProfileView()
        } }
        .listStyle(.plain)
        .scrollContentBackground(.visible)
    }

    var title: String {
        switch self {
        case .aiWorkspace: "AI 工作台"
        case .workbench: "全部功能"
        case .profits: "钉钉利润"
        default: "功能"
        }
    }
}

private struct NativeNavigationContainer<Content: View>: View {
    let embedded: Bool
    private let content: () -> Content

    init(embedded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.embedded = embedded
        self.content = content
    }

    @ViewBuilder var body: some View {
        if embedded { content() }
        else { NavigationStack { content() } }
    }
}

private struct NativeWorkbenchView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var query = ""
    private let groups: [(String, [(String, String, Color, NativeDestination)])] = [
        ("任务记账", [("任务记录", "doc.text", .indigo, .tasks), ("负责人管理", "person.badge.plus", .cyan, .owners), ("钉钉利润", "chart.bar", .orange, .profits), ("公司记账", "creditcard", .blue, .expenses)]),
        ("店铺管理", [("生意参谋", "chart.bar", .teal, .sycm), ("店铺账号", "storefront", .mint, .shops), ("同行店铺", "building.2", .green, .peers), ("执照档案", "doc.badge.gearshape", .pink, .licenses), ("账号使用", "person.text.rectangle", .teal, .accountUsage), ("手机设备", "iphone", .cyan, .devices)]),
        ("仓储管理", [("仓储管理", "shippingbox", .orange, .warehouse)]),
        ("AI 工具", [("AI 工作台", "sparkles", .blue, .aiWorkspace), ("模型管理", "cpu", .purple, .aiModels), ("知识库", "books.vertical", .brown, .aiKnowledge), ("AI 能力", "wand.and.stars", .indigo, .aiCapabilities), ("AI 运营", "chart.bar.xaxis", .green, .aiOperations)]),
        ("系统管理", [("服务器运行", "server.rack", .green, .server), ("通知中心", "bell", .red, .alerts), ("账号与权限", "person.badge.key", .gray, .users), ("卡密管理", "key", .purple, .licenseKeys), ("系统设置", "gearshape", .gray, .systemSettings), ("链接广场", "link", .blue, .links)])
    ]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(Array(filteredGroups.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 13) {
                        Text(entry.0).font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 20) {
                            ForEach(Array(entry.1.enumerated()), id: \.offset) { _, item in
                                NavigationLink { item.3.view } label: { HomeShortcutLabel(item.0, item.1, item.2) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground)).navigationTitle("全部功能")
        .searchable(text: $query, prompt: "搜索功能")
    }
    private var filteredGroups: [(String, [(String, String, Color, NativeDestination)])] {
        groups.compactMap { group, items in let visible = items.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) || group.localizedCaseInsensitiveContains(query) }; return visible.isEmpty ? nil : (group, visible) }
    }
}

private struct NativeProfitView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var summary: ProfitListSummary?
    @State private var months: [ProfitMonth] = []
    @State private var rows: [ProfitRecord] = []
    @State private var query = ""
    @State private var period = "month"
    @State private var error: String?
    private var filtered: [ProfitRecord] {
        rows
            .filter { query.isEmpty || "\($0.storeName) \($0.reporterName) \($0.reportDate)".localizedCaseInsensitiveContains(query) }
            .sorted {
                if $0.reportDate == $1.reportDate { return $0.sourceRecordID > $1.sourceRecordID }
                return $0.reportDate > $1.reportDate
            }
    }
    private var buckets: [(String, Double)] {
        let grouped = Dictionary(grouping: rows) { item -> String in
            switch period { case "day": String(item.reportDate.prefix(10)); case "year": String(item.reportDate.prefix(4)); default: String(item.reportDate.prefix(7)) }
        }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.profit }) }.sorted { $0.0 < $1.0 }
    }
    private var maximum: Double { max(buckets.map { abs($0.1) }.max() ?? 1, 1) }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section { HStack { Metric(title: "累计利润", value: money(summary?.totalProfit ?? 0)); Metric(title: "店铺数", value: "\(summary?.uniqueStoreCount ?? 0) 家"); Metric(title: "报表人数", value: "\(summary?.uniqueReporterCount ?? 0) 人") } }
            Section { Picker("统计周期", selection: $period) { Text("日").tag("day"); Text("月").tag("month"); Text("年").tag("year") }.pickerStyle(.segmented) }
            Section(period == "day" ? "日利润趋势" : period == "year" ? "年度利润趋势" : "月度利润趋势") { ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .bottom, spacing: 18) { ForEach(buckets, id: \.0) { item in VStack { Text(money(item.1)).font(.caption2).foregroundStyle(item.1 < 0 ? .red : .secondary); RoundedRectangle(cornerRadius: 5).fill(item.1 < 0 ? Color.red : Color.blue).frame(width: 28, height: max(CGFloat(abs(item.1) / maximum) * 115, 5)); Text(period == "day" ? String(item.0.suffix(5)) : period == "month" ? String(item.0.suffix(2)) + "月" : item.0).font(.caption) } } }.frame(height: 165, alignment: .bottom).padding(.vertical, 8) } }
            Section("利润明细") { ForEach(filtered) { item in HStack { VStack(alignment: .leading, spacing: 4) { Text(item.storeName).fontWeight(.medium); Text("\(item.reportDate) · \(item.reporterName)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(money(item.profit)).foregroundStyle(item.profit < 0 ? .red : .green) } } }
        }.listStyle(.plain).navigationTitle("钉钉利润").searchable(text: $query, prompt: "搜索店铺、上报人或日期").task { await load() }.refreshable { await load() }
    }
    private func load() async { do { async let a: ProfitListSummary = session.get("dingtalk-profits/summary"); async let b: [ProfitMonth] = session.get("dingtalk-profits/monthly-summary"); async let c: [ProfitRecord] = session.get("dingtalk-profits"); (summary, months, rows) = try await (a, b, c) } catch { self.error = session.message(for: error) } }
}

private struct NativeAIWorkspaceView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var question = ""; @State private var chats: [AIChat] = []; @State private var activeChatID = ""
    @State private var models: [AIModel] = []; @State private var selectedModel = ""
    @State private var sending = false; @State private var error: String?; @State private var streamTask: Task<Void, Never>?
    @State private var showingHistory = false; @State private var renaming: AIChat?; @State private var renameText = ""
    @StateObject private var recorder = NativeAudioRecorder(); @State private var audioModel = ""
    @State private var knowledge: [KnowledgeCollection] = []; @State private var skills: [CapabilityItem] = []; @State private var tools: [CapabilityItem] = []
    @State private var selectedKnowledge = ""; @State private var selectedSkills: Set<String> = []; @State private var selectedTools: Set<String> = []
    @State private var webSearch = false; @State private var imageMode = false; @State private var imageSize = "1024x1024"; @State private var showingTools = false
    @State private var scrollRequest = 0
    @FocusState private var composerFocused: Bool
    private var activeIndex: Int? { chats.firstIndex { $0.id == activeChatID } }
    private var activeChat: AIChat? { activeIndex.map { chats[$0] } }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if activeChat?.messages.isEmpty != false { VStack(spacing: 10) { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.blue); Text("开始新对话").font(.headline); Text("输入问题或使用语音开始").font(.subheadline).foregroundStyle(.secondary) }.padding(.top, 80) }
                        ForEach(activeChat?.messages ?? []) { item in HStack { if item.role == "user" { Spacer(minLength: 48) }; VStack(alignment: .leading, spacing: 8) { if let imageURL = generatedImageURL(item.content) { CachedRemoteImage(url: imageURL, contentMode: .fit, maxPixelSize: 1600, placeholder: ProgressView()).frame(maxWidth: .infinity).frame(height: 280) } else { Text(item.content.isEmpty ? "…" : item.content).textSelection(.enabled) }; if item.role == "assistant" && !item.content.isEmpty { HStack { Button { UIPasteboard.general.string = item.content } label: { Image(systemName: "doc.on.doc") }; Button { regenerate(item.id) } label: { Image(systemName: "arrow.clockwise") } }.font(.caption) } }.padding(13).foregroundStyle(item.role == "user" ? .white : .primary).background(item.role == "user" ? Color.blue : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15)); if item.role != "user" { Spacer(minLength: 48) } }.id(item.id) }
                        Color.clear.frame(height: 1).id("ai-chat-bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: activeChatID) { _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: activeChat?.messages.count ?? 0) { _ in scrollToBottom(proxy) }
                .onChange(of: activeChat?.messages.last?.content.count ?? 0) { _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: scrollRequest) { _ in scrollToBottom(proxy, animated: false) }
            }
            if let error { HStack(spacing: 6) { Image(systemName: "exclamationmark.circle"); Text(error).lineLimit(2); Spacer(); Button { Task { await loadWorkspace() } } label: { Image(systemName: "arrow.clockwise") }; Button { self.error = nil } label: { Image(systemName: "xmark") } }.font(.caption).foregroundStyle(.orange).padding(.horizontal, 14).padding(.top, 6) }
            composer
        }.navigationTitle("AI 工作台").navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in requestKeyboardScroll() }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Menu { ForEach(models.filter { $0.modelType != "audio" }) { model in Button(model.name) { selectedModel = model.id; updateActiveModel() } } } label: { Label(models.first(where: { $0.id == selectedModel })?.name ?? "选择模型", systemImage: "cpu") } }; ToolbarItemGroup(placement: .topBarTrailing) { if let chat = activeChat { ShareLink(item: exportText(chat)) { Image(systemName: "square.and.arrow.up") } }; Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }; Button { createChat() } label: { Image(systemName: "square.and.pencil") } } }
        .sheet(isPresented: $showingHistory) { historySheet }
        .sheet(isPresented: $showingTools) { toolsSheet }
        .alert("重命名会话", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) { TextField("会话名称", text: $renameText); Button("保存") { applyRename() }; Button("取消", role: .cancel) { renaming = nil } }
        .task { await loadWorkspace() }.onDisappear { streamTask?.cancel(); Task { await saveActiveChat() } }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            TextField(recorder.recording ? "正在录音…" : imageMode ? "描述要生成的图片…" : "给 AI 发消息…", text: $question, axis: .vertical)
                .lineLimit(1...5)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { if !sending { send() } }
                .onChange(of: composerFocused) { focused in if focused { requestKeyboardScroll() } }
            HStack(spacing: 12) {
                Button { showingTools = true } label: { Image(systemName: activeTools ? "plus.circle.fill" : "plus.circle").font(.title2) }
                Spacer(minLength: 4)
                if sending {
                    Button { stop() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(.primary, in: Circle()) }
                } else if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { Task { await toggleRecording() } } label: { Image(systemName: recorder.recording ? "stop.fill" : "mic.fill").foregroundStyle(recorder.recording ? .red : .primary).frame(width: 32, height: 32).background(Color(.tertiarySystemFill), in: Circle()) }
                } else {
                    Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(.blue, in: Circle()) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color(.separator).opacity(0.45), lineWidth: 0.5) }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
    private var activeTools: Bool { webSearch || imageMode || !selectedKnowledge.isEmpty || !selectedSkills.isEmpty || !selectedTools.isEmpty }
    private var historySheet: some View { NavigationStack { List { ForEach(chats.sorted { $0.updatedAt > $1.updatedAt }) { chat in Button { activeChatID = chat.id; selectedModel = chat.modelID ?? selectedModel; showingHistory = false } label: { HStack { Image(systemName: chat.favorite ? "star.fill" : chat.archived ? "archivebox" : "bubble.left").foregroundStyle(chat.favorite ? .yellow : .secondary); VStack(alignment: .leading) { Text(chat.title).foregroundStyle(.primary); Text(shortTimestamp(chat.updatedAt)).font(.caption).foregroundStyle(.secondary) } } }.swipeActions { Button("删除", role: .destructive) { Task { await delete(chat) } }; Button(chat.archived ? "恢复" : "归档") { update(chat, archived: !chat.archived) }.tint(.orange); Button(chat.favorite ? "取消收藏" : "收藏") { update(chat, favorite: !chat.favorite) }.tint(.yellow); Button("重命名") { renaming = chat; renameText = chat.title }.tint(.blue) } } }.navigationTitle("历史会话").toolbar { Button("完成") { showingHistory = false } } } }
    private var toolsSheet: some View { NavigationStack { Form { Toggle("联网搜索", isOn: $webSearch); Toggle("生成图片", isOn: $imageMode); if imageMode { Picker("图片尺寸", selection: $imageSize) { Text("方图").tag("1024x1024"); Text("横图").tag("1536x1024"); Text("竖图").tag("1024x1536") } }; Picker("知识集合", selection: $selectedKnowledge) { Text("不使用知识库").tag(""); ForEach(knowledge) { Text($0.name).tag($0.id) } }; if !skills.isEmpty { Section("Skills") { ForEach(skills) { item in Toggle(item.displayName, isOn: setBinding($selectedSkills, item.id)) } } }; if !tools.isEmpty { Section("Tools") { ForEach(tools) { item in Toggle(item.displayName, isOn: setBinding($selectedTools, item.id)) } } } }.navigationTitle("对话能力").toolbar { Button("完成") { showingTools = false } } } }
    private func loadWorkspace() async {
        error = nil
        restoreLocalChats()
        await loadModels()
        await loadCapabilities()
        await loadChats()
        scrollRequest += 1
    }
    private func loadModels() async { do { let result: AIModelsResponse = try await session.get("ai-api/models"); models = result.models.filter { $0.enabled != 0 && $0.hidden != 1 }; if selectedModel.isEmpty { selectedModel = models.first(where: { $0.modelType != "audio" })?.id ?? "" }; audioModel = models.first(where: { $0.modelType == "audio" })?.id ?? "" } catch { if models.isEmpty { self.error = "AI 模型暂时无法加载，请稍后重试。" } } }
    private func loadCapabilities() async {
        if let result: KnowledgeResponse = try? await session.get("ai-api/knowledge") { knowledge = result.knowledge }
        if let result: CapabilityResponse = try? await session.get("ai-api/skills") { skills = result.skills ?? [] }
        if let result: CapabilityResponse = try? await session.get("ai-api/tools") { tools = result.tools ?? [] }
    }
    private func loadChats() async { do { let result: AIChatsResponse = try await session.get("ai-api/chats?user_id=\(session.currentUser?.id ?? 0)"); if !result.chats.isEmpty { chats = result.chats; activeChatID = chats.first(where: { !$0.archived })?.id ?? chats[0].id; selectedModel = activeChat?.modelID ?? selectedModel; persistChatsLocally() } } catch { } ; if chats.isEmpty { createChat() } }
    private func send() { let value = question.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; if activeIndex == nil { createChat() }; guard let index = activeIndex else { return }; question = ""; error = nil; chats[index].messages.append(AIChatMessage(role: "user", content: value)); let answerID = UUID().uuidString; chats[index].messages.append(AIChatMessage(id: answerID, role: "assistant", content: "")); if chats[index].messages.count == 2 { chats[index].title = String(value.prefix(24)) }; chats[index].modelID = selectedModel; chats[index].updatedAt = Date().timeIntervalSince1970; sending = true; streamTask = Task { do { if imageMode { let response: ImageGenerationResponse = try await session.send("ai-api/images/generations", method: "POST", body: ["prompt":value,"model_id":selectedModel,"size":imageSize]); if let chatIndex = chats.firstIndex(where: { $0.id == activeChatID }), let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == answerID }) { chats[chatIndex].messages[messageIndex].content = "image:\(response.url)" } } else { var documents: [SearchDocument] = []; if !selectedKnowledge.isEmpty { let result: SearchDocumentsResponse = try await session.send("ai-api/search", method: "POST", body: ["query":value,"limit":5,"knowledge_id":selectedKnowledge]); documents += result.documents }; if webSearch { let result: SearchDocumentsResponse = try await session.send("ai-api/web-search", method: "POST", body: ["query":value,"limit":5]); documents += result.documents }; try await session.streamChat(value, modelID: selectedModel, documents: documents, skillIDs: Array(selectedSkills), toolIDs: Array(selectedTools)) { chunk in guard let chatIndex = chats.firstIndex(where: { $0.id == activeChatID }), let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == answerID }) else { return }; chats[chatIndex].messages[messageIndex].content += chunk } } } catch is CancellationError { } catch { self.error = session.message(for: error) }; sending = false; await saveActiveChat() } }
    private func stop() { streamTask?.cancel(); streamTask = nil; sending = false; Task { await saveActiveChat() } }
    private func createChat() { let now = Date().timeIntervalSince1970; let chat = AIChat(id: "chat-\(UUID().uuidString)", title: "新对话", messages: [], modelID: selectedModel, favorite: false, archived: false, folder: "", createdAt: now, updatedAt: now); chats.insert(chat, at: 0); activeChatID = chat.id; persistChatsLocally(); scrollRequest += 1 }
    private func updateActiveModel() { guard let index = activeIndex else { return }; chats[index].modelID = selectedModel; Task { await saveActiveChat() } }
    private func saveActiveChat() async { persistChatsLocally(); guard let chat = activeChat else { return }; let messages = chat.messages.map { ["id": $0.id, "role": $0.role, "content": $0.content] }; let _: EmptyResponse? = try? await session.send("ai-api/chats/save", method: "POST", body: ["id": chat.id, "user_id": session.currentUser?.id ?? 0, "title": chat.title, "messages": messages, "model_id": chat.modelID ?? "", "favorite": chat.favorite, "archived": chat.archived, "folder": chat.folder, "created_at": Int(chat.createdAt)], allowEmpty: true) }
    private func update(_ chat: AIChat, favorite: Bool? = nil, archived: Bool? = nil) { guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }; if let favorite { chats[index].favorite = favorite }; if let archived { chats[index].archived = archived }; activeChatID = chat.id; Task { await saveActiveChat() } }
    private func applyRename() { guard let chat = renaming, let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }; chats[index].title = renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? chat.title : renameText; activeChatID = chat.id; renaming = nil; Task { await saveActiveChat() } }
    private func delete(_ chat: AIChat) async { let _: EmptyResponse? = try? await session.send("ai-api/chats/delete", method: "POST", body: ["id": chat.id, "user_id": session.currentUser?.id ?? 0], allowEmpty: true); chats.removeAll { $0.id == chat.id }; if activeChatID == chat.id { activeChatID = chats.first?.id ?? ""; if chats.isEmpty { createChat() } }; persistChatsLocally() }
    private func regenerate(_ messageID: String) { guard let index = activeIndex, let answerIndex = chats[index].messages.firstIndex(where: { $0.id == messageID }), answerIndex > 0 else { return }; let value = chats[index].messages[..<answerIndex].last(where: { $0.role == "user" })?.content ?? ""; chats[index].messages.removeSubrange((answerIndex - 1)...answerIndex); question = value; send() }
    private func exportText(_ chat: AIChat) -> String { chat.messages.map { "\($0.role == "user" ? "我" : "AI")：\($0.content)" }.joined(separator: "\n\n") }
    private func generatedImageURL(_ content: String) -> URL? { guard content.hasPrefix("image:") else { return nil }; return URL(string: String(content.dropFirst(6))) }
    private var localChatsKey: String { "native-ai-chats-\(session.currentUser?.id ?? 0)" }
    private func restoreLocalChats() { guard chats.isEmpty, let data = UserDefaults.standard.data(forKey: localChatsKey), let saved = try? JSONDecoder().decode([AIChat].self, from: data), !saved.isEmpty else { return }; chats = saved; activeChatID = saved.first(where: { !$0.archived })?.id ?? saved[0].id; selectedModel = activeChat?.modelID ?? selectedModel }
    private func persistChatsLocally() { if let data = try? JSONEncoder().encode(Array(chats.prefix(60))) { UserDefaults.standard.set(data, forKey: localChatsKey) } }
    private func requestKeyboardScroll() { scrollRequest += 1; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollRequest += 1 } }
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) { DispatchQueue.main.async { if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("ai-chat-bottom", anchor: .bottom) } } else { proxy.scrollTo("ai-chat-bottom", anchor: .bottom) } } }
    private func setBinding(_ selection: Binding<Set<String>>, _ id: String) -> Binding<Bool> { Binding(get: { selection.wrappedValue.contains(id) }, set: { enabled in if enabled { selection.wrappedValue.insert(id) } else { selection.wrappedValue.remove(id) } }) }
    private func toggleRecording() async { if recorder.recording { guard let data = recorder.stop() else { return }; recorder.transcribing = true; defer { recorder.transcribing = false }; do { let result: TranscriptionResponse = try await session.send("ai-api/audio/transcriptions", method: "POST", body: ["filename": "recording.m4a", "data": data.base64EncodedString(), "model_id": audioModel]); question = [question, result.text].filter { !$0.isEmpty }.joined(separator: " ") } catch { self.error = session.message(for: error) } } else { do { try await recorder.start() } catch { self.error = "无法使用麦克风，请在系统设置中允许权限。" } } }
}

private struct NativeHomeView: View {
    @EnvironmentObject private var session: NativeSession
    @AppStorage("native-dark-mode") private var darkMode = false
    @State private var path: [NativeDestination] = []
    @State private var dashboard = HomeDashboard()
    @State private var dashboardLoading = false
    @State private var dashboardError: String?
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
    @State private var homeModuleKeys = defaultHomeModuleKeys
    @State private var showingHomeModules = false

    private var activeIndex: Int? { chats.firstIndex { $0.id == activeChatID } }
    private var activeChat: AIChat? { activeIndex.map { chats[$0] } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("常用功能").font(.headline); Spacer(); if session.currentUser?.role == "superadmin" { Button("排序") { showingHomeModules = true }.font(.subheadline) } }.padding(.horizontal, 16)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                        ForEach(homeModuleKeys.compactMap { key in homeModuleCatalog.first { $0.id == key } }) { item in HomeShortcut(item.title, item.icon, item.color) { path.append(item.destination) } }
                        HomeShortcut("全部", "circle.grid.2x2.fill", .gray) { path.append(.workbench) }
                    }.padding(.horizontal, 16)
                    HStack { Text("经营数据").font(.headline); Spacer(); Text("实时同步").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 16)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        HomeDashboardMetric("公司消费", dashboard.expenseTotal.map(money) ?? "--", "creditcard", .blue)
                        HomeDashboardMetric("累计利润", dashboard.profitTotal.map(money) ?? "--", "chart.line.uptrend.xyaxis", .green)
                        HomeDashboardMetric("本月钉钉利润", dashboard.monthlyProfit.map(money) ?? "--", "calendar", .orange)
                        HomeDashboardMetric("库存数量", dashboard.stockQuantity.map(String.init) ?? "--", "cube.box", .teal)
                        HomeDashboardMetric("库存成本", dashboard.stockCost.map(money) ?? "--", "banknote", .indigo)
                        HomeDashboardMetric("库存预警", dashboard.lowStock.map(String.init) ?? "--", "exclamationmark.triangle", .orange)
                    }.padding(.horizontal, 16)
                    HStack { Text("待办提醒").font(.headline); Spacer(); Text("查看全部").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 16)
                    VStack(spacing: 0) { HomeTodo(color: .orange, title: "待签收任务", detail: "需要及时处理任务状态", value: dashboard.pendingSigned.map(String.init) ?? "--"); Divider(); HomeTodo(color: .red, title: "待结算任务", detail: "等待结算的任务", value: dashboard.pendingSettlement.map(String.init) ?? "--"); Divider(); HomeTodo(color: .blue, title: "库存预警", detail: "可用库存已达到预警值", value: dashboard.lowStock.map(String.init) ?? "--") }.background(.background, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                    if let dashboardError { Text(dashboardError).font(.caption).foregroundStyle(.red).padding(.horizontal, 16) }
                }.padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { darkMode.toggle() }
                    } label: {
                        Image(systemName: darkMode ? "sun.max.fill" : "moon.fill")
                    }
                    .accessibilityLabel(darkMode ? "切换浅色模式" : "切换深色模式")
                    Button { path.append(.alerts) } label: { Image(systemName: "bell.badge.fill") }
                    Button { path.append(.search) } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .task { await loadDashboard() }
            .task { await loadHomeModules() }
            .sheet(isPresented: $showingHomeModules) { HomeModuleManager(keys: $homeModuleKeys) }
            .refreshable { await loadDashboard() }
            .navigationDestination(for: NativeDestination.self) { destination in destination.view }
        }
    }

    private func loadDashboard() async {
        guard !dashboardLoading else { return }
        dashboardLoading = true; dashboardError = nil
        defer { dashboardLoading = false }
        async let warehouse: WarehouseSummary? = try? session.get("warehouse/summary")
        async let tasks: TaskSummary? = try? session.get("task-bookkeeping/summary")
        async let expenses: ExpenseSummary? = try? session.get("company-expenses/summary")
        async let profits: ProfitSummary? = try? session.get("dingtalk-profits/summary")
        async let monthlyProfits: [ProfitMonth]? = try? session.get("dingtalk-profits/monthly-summary")
        let results: [HomeDashboard.Partial] = await [.warehouse(warehouse), .tasks(tasks), .expenses(expenses), .profits(profits), .monthlyProfits(monthlyProfits)]
        var successes = 0
        for result in results { if dashboard.apply(result) { successes += 1 } }
        if successes == 0 { dashboardError = "经营数据加载失败，请下拉重试" }
    }
    private func loadHomeModules() async { if let response: HomeModulesSettingResponse = try? await session.get("ui-settings/home-modules"), let value = response.value, !value.isEmpty { homeModuleKeys = value.filter { key in homeModuleCatalog.contains { $0.id == key } } } }

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
    let embedded: Bool
    init(embedded: Bool = false) { self.embedded = embedded }
    @EnvironmentObject private var session: NativeSession
    @State private var records: [TaskRecord] = []
    @State private var summary: TaskSummary?
    @State private var query = ""
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var editing: TaskRecord?
    @State private var showingForm = false
    @State private var selectedIDs: Set<Int> = []
    @State private var editMode: EditMode = .inactive
    @State private var exporting = false

    var body: some View {
        NativeNavigationContainer(embedded: embedded) {
            List(selection: $selectedIDs) {
                if let summary {
                    Section {
                        HStack {
                            Metric(title: "任务", value: "\(summary.totalRecords)")
                            Metric(title: "待签收", value: "\(summary.pendingSignedCount)")
                            Metric(title: "待结算", value: "\(summary.pendingSettlementCount)")
                        }
                        HStack {
                            Metric(title: "本金合计", value: money(summary.principalTotal))
                            Metric(title: "佣金合计", value: money(summary.commissionTotal))
                            Metric(title: "礼品合计", value: money(summary.giftTotal))
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section("任务记录") {
                    ForEach(records) { item in
                        NavigationLink {
                            TaskDetail(item: item) { await load() }
                        } label: { VStack(alignment: .leading, spacing: 8) {
                            Text(item.shopName).font(.headline)
                            Text("\(item.orderNo) · \(item.ownerName)").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Metric(title: "本金", value: money(item.principalAmount))
                                Metric(title: "佣金", value: money(item.commissionAmount))
                                Metric(title: "礼品", value: money(item.giftAmount))
                            }
                            HStack {
                                StatusBadge(text: item.signedStatus == "completed" ? "已签收" : "待签收", done: item.signedStatus == "completed")
                                StatusBadge(text: item.settlementStatus == "completed" ? "已结算" : "待结算", done: item.settlementStatus == "completed")
                                Spacer(); Text(shortDate(item.taskTime)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4) }
                        .swipeActions(edge: .leading) { Button("编辑") { editing = item; showingForm = true }.tint(.blue) }
                        .tag(item.id)
                    }
                     if hasMore {
                        HStack { Spacer(); if loadingMore { ProgressView() } else { Text("加载更多") }; Spacer() }
                             .onAppear { Task { await loadMore() } }
                     }
                 }
             }
             .listStyle(.plain)
             .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索订单、店铺或负责人")
            .refreshable { await load(reset: true) }
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup { EditButton(); if !selectedIDs.isEmpty { Menu { Button("标记已签收") { Task { await batchStatus("signed_status") } }; Button("标记已结算") { Task { await batchStatus("settlement_status") } }; Button("导出所选") { exporting = true }; Button("删除所选", role: .destructive) { Task { await batchDelete() } } } label: { Image(systemName: "ellipsis.circle") } }; Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingForm) { TaskForm(item: editing) { await load() } }
            .environment(\.editMode, $editMode)
            .fileExporter(isPresented: $exporting, document: TaskCSVDocument(records: records.filter { selectedIDs.contains($0.id) }), contentType: .commaSeparatedText, defaultFilename: "任务记录") { _ in }
            .task { if records.isEmpty { await load(reset: true) } }
            .task(id: query) { if !records.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000); guard !Task.isCancelled else { return }; await load(reset: true) } }
        }
    }

    private func load(reset: Bool = false) async {
        loading = true; error = nil; defer { loading = false }
        do {
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let path = "task-bookkeeping/records?offset=0&limit=30\(keyword.isEmpty ? "" : "&q=\(keyword)")"
            async let fetchedRecords: [TaskRecord] = session.get(path)
            async let fetchedSummary: TaskSummary = session.get("task-bookkeeping/summary")
            records = try await fetchedRecords; summary = try await fetchedSummary
            hasMore = records.count == 30
        } catch { self.error = session.message(for: error) }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let path = "task-bookkeeping/records?offset=\(records.count)&limit=30\(keyword.isEmpty ? "" : "&q=\(keyword)")"
            let more: [TaskRecord] = try await session.get(path)
            let ids = Set(records.map(\.id)); records.append(contentsOf: more.filter { !ids.contains($0.id) }); hasMore = more.count == 30
        } catch { self.error = session.message(for: error) }
    }
    private func batchStatus(_ field: String) async { do { let _: EmptyResponse = try await session.send("task-bookkeeping/records/batch-status", method: "PATCH", body: ["record_ids": Array(selectedIDs), "field": field, "value": "completed"], allowEmpty: true); selectedIDs.removeAll(); editMode = .inactive; await load(reset: true) } catch { self.error = session.message(for: error) } }
    private func batchDelete() async { do { let _: EmptyResponse = try await session.send("task-bookkeeping/records/batch-delete", method: "POST", body: ["record_ids": Array(selectedIDs)], allowEmpty: true); selectedIDs.removeAll(); editMode = .inactive; await load(reset: true) } catch { self.error = session.message(for: error) } }
}

private struct TaskCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let records: [TaskRecord]
    init(records: [TaskRecord]) { self.records = records }
    init(configuration: ReadConfiguration) throws { records = [] }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { let header = "订单号,店铺,负责人,本金,佣金,礼品,数量,签收,结算,时间\n"; let rows = records.map { "\($0.orderNo),\($0.shopName),\($0.ownerName),\($0.principalAmount),\($0.commissionAmount),\($0.giftAmount),\($0.orderCount),\($0.signedStatus),\($0.settlementStatus),\($0.taskTime ?? "")" }.joined(separator: "\n"); return FileWrapper(regularFileWithContents: Data((header + rows).utf8)) }
}

private let defaultExpenseCategories = ["办公用品", "快递物流", "餐饮招待", "差旅交通", "软件服务", "广告推广", "采购货款", "其他消费"]
private let expenseCategoriesKey = "native-expense-categories"

private func loadExpenseCategories() -> [String] {
    guard let values = UserDefaults.standard.stringArray(forKey: expenseCategoriesKey), !values.isEmpty else { return defaultExpenseCategories }
    return values
}

private func saveExpenseCategories(_ values: [String]) {
    UserDefaults.standard.set(values, forKey: expenseCategoriesKey)
}

private struct ExpenseCategoryManager: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    @Binding var categories: [String]
    @Binding var selection: String
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("新增分类") {
                    HStack {
                        TextField("分类名称", text: $name)
                        Button("添加") { add() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Section("消费分类") {
                    ForEach(categories, id: \.self) { value in
                        HStack { Image(systemName: value == selection ? "checkmark.circle.fill" : "circle").foregroundStyle(value == selection ? .blue : .secondary); Text(value); Spacer() }
                            .contentShape(Rectangle()).onTapGesture { selection = value }
                    }
                    .onDelete(perform: remove)
                }
            }
            .navigationTitle("分类管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func add() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !categories.contains(value) else { return }
        categories.append(value); selection = value; name = ""; persist()
    }

    private func remove(at offsets: IndexSet) {
        guard categories.count > offsets.count else { return }
        let removedSelection = offsets.contains { categories[$0] == selection }
        categories.remove(atOffsets: offsets)
        if removedSelection { selection = categories[0] }
        persist()
    }

    private func persist() {
        saveExpenseCategories(categories)
        Task { saving = true; defer { saving = false }; do { let response: ExpenseCategoriesResponse = try await session.send("expense-categories", method: "PUT", body: ["categories": categories]); categories = response.categories; saveExpenseCategories(categories) } catch { self.error = session.message(for: error) } }
    }
}

private struct NativeQuickLedgerView: View {
    let embedded: Bool
    init(embedded: Bool = false) { self.embedded = embedded; _categories = State(initialValue: loadExpenseCategories()) }
    @EnvironmentObject private var session: NativeSession
    @State private var amount = ""
    @State private var category = "办公用品"
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @State private var categories: [String]
    @State private var showingCategories = false
    var body: some View {
        NativeNavigationContainer(embedded: embedded) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) { Text("公司消费").font(.caption).opacity(0.85); Text(amount.isEmpty ? "¥ 0.00" : "¥ \(amount)").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit(); Text("使用下方数字键输入金额").font(.caption2).opacity(0.72) }.padding(20).frame(maxWidth: .infinity, minHeight: 132, alignment: .leading).background(Color.blue, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                        Text("消费分类").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { ForEach(categories, id: \.self) { value in Button { category = value } label: { VStack(spacing: 7) { NativeAppIconTile(symbol: categoryIcon(value), color: categoryColor(value), size: 42, iconSize: 19, selected: category == value); Text(value).font(.caption2).foregroundStyle(.primary).lineLimit(1) }.frame(width: 68) }.buttonStyle(.plain) } }.padding(.vertical, 2) }
                        TextField("写一句消费说明（可选）", text: $note).textFieldStyle(.roundedBorder)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        Spacer(minLength: 16)
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) { GridRow { ledgerKey("1"); ledgerKey("2"); ledgerKey("3"); ledgerKey("⌫", symbol: "delete.left") }; GridRow { ledgerKey("4"); ledgerKey("5"); ledgerKey("6"); ledgerKey("C") }; GridRow { ledgerKey("7"); ledgerKey("8"); ledgerKey("9"); ledgerKey("00") }; GridRow { ledgerKey("."); ledgerKey("0", columns: 2); Button { Task { await save() } } label: { Image(systemName: saving ? "hourglass" : "checkmark").font(.title2.bold()).frame(maxWidth: .infinity).frame(height: 54) }.buttonStyle(.plain).foregroundStyle(.white).background(Color.blue, in: RoundedRectangle(cornerRadius: 10)).disabled(saving || (Double(amount) ?? 0) <= 0) } }
                    }
                    .padding()
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup { NavigationLink { NativeLedgerView() } label: { Label("流水", systemImage: "list.bullet.rectangle") }; Button { showingCategories = true } label: { Label("分类管理", systemImage: "square.grid.2x2") } } }
            .sheet(isPresented: $showingCategories) { ExpenseCategoryManager(categories: $categories, selection: $category) }
            .task { await syncCategories() }
        }
    }
    private func ledgerKey(_ key: String, symbol: String? = nil, columns: Int = 1) -> some View { Button { pressKey(key) } label: { Group { if let symbol { Image(systemName: symbol) } else { Text(key) } }.font(.title2.weight(.medium)).frame(maxWidth: .infinity).frame(height: 54) }.buttonStyle(.plain).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10)).gridCellColumns(columns) }
    private func categoryIcon(_ value: String) -> String { switch value { case "办公用品": "paperclip"; case "快递物流": "shippingbox"; case "餐饮招待": "fork.knife"; case "差旅交通": "car"; case "软件服务": "laptopcomputer"; case "广告推广": "megaphone"; case "采购货款": "cart"; default: "ellipsis.circle" } }
    private func categoryColor(_ value: String) -> Color { switch value { case "办公用品": .blue; case "快递物流": .orange; case "餐饮招待": .red; case "差旅交通": .teal; case "软件服务": .indigo; case "广告推广": .pink; case "采购货款": .green; default: .gray } }
    private func syncCategories() async { if let response: ExpenseCategoriesResponse = try? await session.get("expense-categories") { categories = response.categories; saveExpenseCategories(categories); if !categories.contains(category), let first = categories.first { category = first } } }
    private func save() async { saving = true; defer { saving = false }; let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let body: [String: Any] = ["expense_date": f.string(from: Date()), "amount": Double(amount) ?? 0, "category": category, "payment_type": "company", "payment_account": "公司卡", "expense_scope": "公共费用", "description": note.isEmpty ? category : note]; do { let _: CompanyExpense = try await session.send("company-expenses", method: "POST", body: body); amount = ""; note = "" } catch let requestError { error = session.message(for: requestError) } }
    private func pressKey(_ key: String) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil); switch key { case "C": amount = ""; case "⌫": if !amount.isEmpty { amount.removeLast() }; case ".": if !amount.contains(".") { amount = amount.isEmpty ? "0." : amount + "." }; default: amount = amount == "0" ? key : amount + key } }
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
    private var groupedByDay: [(String, [CompanyExpense])] { Dictionary(grouping: filtered, by: { $0.expenseDate }).map { ($0.key, $0.value.sorted { $0.id > $1.id }) }.sorted { $0.0 > $1.0 } }

    var body: some View {
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
                ForEach(groupedByDay, id: \.0) { day, items in
                    Section(dayLabel(day)) {
                    ForEach(items) { item in
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
            .listStyle(.plain)
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索分类、账户或说明")
            .refreshable { await load() }.navigationTitle("公司记账")
            .task { if records.isEmpty { await load() } }
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

private func dayLabel(_ value: String) -> String {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
    if value == formatter.string(from: Date()) { return "今天  \(value)" }
    if let date = formatter.date(from: value), let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()), formatter.string(from: yesterday) == formatter.string(from: date) { return "昨天  \(value)" }
    return value
}

private struct LinkComposerRoute: Identifiable {
    let id = UUID()
    let item: SavedLink?
    let article: Bool
}

private struct NativeLinksView: View {
    let embedded: Bool
    init(embedded: Bool = false) { self.embedded = embedded }
    @EnvironmentObject private var session: NativeSession
    @State private var records: [SavedLink] = []
    @State private var query = ""
    @State private var loading = false
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var deleting: SavedLink?
    @State private var pushing: SavedLink?
    @State private var scheduling: SavedLink?
    @State private var viewing: SavedLink?
    @State private var composer: LinkComposerRoute?
    @State private var tab = "latest"
    private let pageSize = 24

    private var filtered: [SavedLink] {
        let scoped = records.filter { tab == "latest" || (tab == "with-images" && savedLinkIsArticle($0) && !$0.images.isEmpty) || (tab == "mine" && $0.authorUsername == session.username) }
        let rows = query.isEmpty ? scoped : scoped.filter { "\($0.title) \($0.url ?? "") \($0.category ?? "") \($0.description ?? "") \($0.authorUsername)".localizedCaseInsensitiveContains(query) }
        return rows.sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
    }

    private var linkFilterSection: some View {
        Picker("筛选", selection: $tab) {
            Text("最新").tag("latest")
            Text("带图").tag("with-images")
            Text("我发布的").tag("mine")
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
    }

    var body: some View {
        NativeNavigationContainer(embedded: embedded) {
            List {
                linkFilterSection
                if let error { LinkLoadErrorView(message: error) { Task { await load() } } }
                if !loading && error == nil && filtered.isEmpty { LinkEmptyView(searching: !query.isEmpty) }
                ForEach(filtered) { item in
                    SavedLinkFeedRow(item: item) {
                        viewing = item
                    } onEdit: {
                        composer = LinkComposerRoute(item: item, article: savedLinkIsArticle(item))
                    } onTogglePin: {
                        Task { await togglePin(item) }
                    } onDelete: {
                        deleting = item
                    } onPushNow: {
                        pushing = item
                    } onSchedule: {
                        scheduling = item
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                }
                if hasMore && query.isEmpty {
                    Button { Task { await loadMore() } } label: { HStack { Spacer(); if loadingMore { ProgressView() } else { Text("加载更多") }; Spacer() } }.disabled(loadingMore)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.visible)
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索标题、用户或正文")
            .refreshable { await load() }
            .navigationTitle("链接广场")
            .navigationBarTitleDisplayMode(.inline)
            .task { if records.isEmpty { await load() } }
            .navigationDestination(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
                if let viewing { SavedLinkDetail(item: viewing) }
            }
            .toolbar {
                Menu {
                    Button("发布帖子", systemImage: "bubble.left.and.bubble.right") { composer = LinkComposerRoute(item: nil, article: false) }
                    Button("发布文章", systemImage: "doc.text") { composer = LinkComposerRoute(item: nil, article: true) }
                } label: { Image(systemName: "square.and.pencil") }
            }
            .sheet(item: $composer) { route in LinkForm(item: route.item, article: route.article) { await load() } }
            .sheet(item: $scheduling) { item in SavedLinkPushSheet(item: item) { updated in update(updated) } }
            .confirmationDialog("确定删除这条内容吗？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let item = deleting { Task { await remove(item) } } }
                Button("取消", role: .cancel) { deleting = nil }
            }
            .confirmationDialog("立即推送到钉钉群？", isPresented: Binding(get: { pushing != nil }, set: { if !$0 { pushing = nil } }), titleVisibility: .visible) {
                Button("立即推送") { if let item = pushing { Task { await pushNow(item) } } }
                Button("取消", role: .cancel) { pushing = nil }
            } message: { Text(pushing.map { "将“\($0.title)”发送到已配置的钉钉群。" } ?? "") }
        }
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { records = try await session.get("saved-links?offset=0&limit=\(pageSize)"); hasMore = records.count == pageSize; prefetchImages(in: records) }
        catch { self.error = session.message(for: error) }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }; loadingMore = true; defer { loadingMore = false }
        do {
            let more: [SavedLink] = try await session.get("saved-links?offset=\(records.count)&limit=\(pageSize)")
            let ids = Set(records.map(\.id)); records.append(contentsOf: more.filter { !ids.contains($0.id) }); hasMore = more.count == pageSize
            prefetchImages(in: more)
        } catch { self.error = session.message(for: error) }
    }

    private func togglePin(_ item: SavedLink) async {
        do {
            let updated: SavedLink = try await session.send("saved-links/\(item.id)/pin", method: item.isPinned ? "DELETE" : "POST")
            update(updated)
        } catch { self.error = session.message(for: error) }
    }

    private func pushNow(_ item: SavedLink) async {
        do {
            let updated: SavedLink = try await session.send("saved-links/\(item.id)/push", method: "POST", body: ["scheduled_at": NSNull()])
            update(updated); pushing = nil
        } catch { self.error = session.message(for: error); pushing = nil }
    }

    private func update(_ item: SavedLink) { if let index = records.firstIndex(where: { $0.id == item.id }) { records[index] = item } }

    private func remove(_ item: SavedLink) async {
        do { try await session.delete("saved-links/\(item.id)"); records.removeAll { $0.id == item.id }; deleting = nil }
        catch { self.error = session.message(for: error); deleting = nil }
    }
    private func prefetchImages(in rows: [SavedLink]) {
        var requests: [(URL, CGFloat)] = []
        for item in rows.prefix(4) {
            if let value = item.authorAvatarURL, let avatar = nativeThumbnailURL(value, maxPixelSize: 144) { requests.append((avatar, 144)) }
            requests.append(contentsOf: item.images.prefix(1).compactMap { nativeThumbnailURL($0.url, maxPixelSize: 520).map { ($0, 520) } })
        }
        Task(priority: .utility) { await NativeImagePipeline.shared.prefetch(requests) }
    }
}

private struct TaskDetail: View {
    @EnvironmentObject private var session: NativeSession
    @State var item: TaskRecord
    let onChange: () async -> Void
    @State private var error: String?
    @State private var updating = false
    @State private var copiedField: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section("任务信息") {
                ForEach(taskFields.prefix(5)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) }
            }
            Section("金额") {
                ForEach(taskFields.dropFirst(5).prefix(3)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) }
            }
            Section("状态") {
                Toggle("已签收", isOn: Binding(get: { item.signedStatus == "completed" }, set: { value in Task { await update("signed_status", value) } })).disabled(updating)
                Toggle("已结算", isOn: Binding(get: { item.settlementStatus == "completed" }, set: { value in Task { await update("settlement_status", value) } })).disabled(updating)
            }
            if let note = item.note, !note.isEmpty { Section("备注") { NativeCopyRow(label: "备注", value: note, copiedField: $copiedField) } }
        }.navigationTitle(item.shopName).navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: taskFields, copiedField: $copiedField) }
    }
    private var taskFields: [NativeCopyField] { [NativeCopyField(label: "订单号", value: item.orderNo), NativeCopyField(label: "店铺", value: item.shopName), NativeCopyField(label: "负责人", value: item.ownerName), NativeCopyField(label: "任务时间", value: shortDate(item.taskTime)), NativeCopyField(label: "刷单数量", value: "\(item.orderCount)"), NativeCopyField(label: "本金", value: money(item.principalAmount)), NativeCopyField(label: "佣金", value: money(item.commissionAmount)), NativeCopyField(label: "礼品", value: money(item.giftAmount)), NativeCopyField(label: "备注", value: item.note ?? "-")] }

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
    private var categories: [String] { let saved = loadExpenseCategories(); return saved.contains(category) ? saved : [category] + saved }

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
    let item: SavedLink?; let article: Bool; let onSave: () async -> Void
    @State private var title: String; @State private var category: String; @State private var url: String
    @State private var description: String; @State private var pinned: Bool; @State private var saving = false; @State private var error: String?
    @State private var photoItems: [PhotosPickerItem] = []; @State private var images: [URL] = []
    @State private var previewing = false
    @State private var editCommand: ArticleEditCommand?
    @State private var pendingInlineImages: [PendingInlineImage] = []
    @State private var draftNotice: String?
    @State private var showingLinkPrompt = false
    @State private var linkURL = "https://"

    init(item: SavedLink?, article: Bool = false, onSave: @escaping () async -> Void) {
        self.item = item; self.article = article; self.onSave = onSave; _title = State(initialValue: item?.title ?? ""); _category = State(initialValue: item?.category ?? "")
        _url = State(initialValue: item?.url ?? ""); _description = State(initialValue: item?.description ?? ""); _pinned = State(initialValue: item?.isPinned ?? false)
    }

    var body: some View {
        NavigationStack {
            Group { if article { articleEditorBody } else { postEditorBody } }
            .navigationTitle(item == nil ? (article ? "发布文章" : "发布帖子") : (article ? "编辑文章" : "编辑帖子")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; if article { ToolbarItem(placement: .principal) { Picker("模式", selection: $previewing) { Text("写作").tag(false); Text("预览").tag(true) }.pickerStyle(.segmented).frame(width: 150) } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "发布中..." : "保存") { Task { await save() } }.disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty) } }
            .onChange(of: photoItems) { items in Task { await receivePhotos(items) } }
            .task { restoreDraft() }
            .onChange(of: title) { _ in saveDraft() }
            .onChange(of: category) { _ in saveDraft() }
            .onChange(of: description) { _ in saveDraft() }
            .alert("插入链接", isPresented: $showingLinkPrompt) {
                TextField("https://example.com", text: $linkURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) { }
                Button("插入") {
                    if let value = normalizedLinkURL { editCommand = ArticleEditCommand(.link(value)) }
                }
                .disabled(normalizedLinkURL == nil)
            } message: {
                Text("输入完整网页地址，链接文字会使用当前选中的内容。")
            }
        }
    }

    private var postEditorBody: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            if let draftNotice { Text(draftNotice).font(.caption).foregroundStyle(.secondary) }
            Section("帖子") {
                TextField("标题", text: $title)
                TextField("分类", text: $category)
                Toggle("置顶", isOn: $pinned)
            }
            Section("正文") {
                TextField("输入纯文字正文", text: $description, axis: .vertical).lineLimit(8...16)
            }
        }
    }

    private var articleEditorBody: some View {
        VStack(spacing: 0) {
            if let error { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8) }
            if previewing {
                articlePreviewBody
            } else {
                if let draftNotice { Text(draftNotice).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8) }
                VStack(spacing: 0) {
                    TextField("输入标题", text: $title, axis: .vertical).font(.title2.weight(.semibold)).lineLimit(1...3).padding(.horizontal, 20).padding(.vertical, 14)
                    Divider().padding(.horizontal, 20)
                    HStack(spacing: 8) { Image(systemName: "tag").foregroundStyle(.secondary); TextField("添加分类", text: $category) }.padding(.horizontal, 20).padding(.vertical, 11)
                    Divider()
                }
                NativeArticleTextEditor(text: $description, command: $editCommand).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 20)
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { if !previewing { articleToolbar } }
    }

    private var articleToolbar: some View {
            HStack(spacing: 2) {
                Menu {
                    Button { editCommand = ArticleEditCommand(.heading1) } label: { Label("一级标题", systemImage: "textformat.size.larger") }
                    Button { editCommand = ArticleEditCommand(.heading2) } label: { Label("二级标题", systemImage: "textformat.size.smaller") }
                    Button { editCommand = ArticleEditCommand(.body) } label: { Label("正文", systemImage: "textformat") }
                    Button { editCommand = ArticleEditCommand(.quote) } label: { Label("引用", systemImage: "text.quote") }
                } label: { ArticleToolIcon("textformat", "文字") }.frame(maxWidth: .infinity)

                Menu {
                    Button { editCommand = ArticleEditCommand(.list) } label: { Label("项目列表", systemImage: "list.bullet") }
                    Button { editCommand = ArticleEditCommand(.numberedList) } label: { Label("数字列表", systemImage: "list.number") }
                    Button { editCommand = ArticleEditCommand(.checklist) } label: { Label("待办列表", systemImage: "checklist") }
                } label: { ArticleToolIcon("list.bullet", "列表") }.frame(maxWidth: .infinity)

                Menu {
                    Button { editCommand = ArticleEditCommand(.bold) } label: { Label("粗体", systemImage: "bold") }
                    Button { editCommand = ArticleEditCommand(.italic) } label: { Label("斜体", systemImage: "italic") }
                    Button { editCommand = ArticleEditCommand(.strikethrough) } label: { Label("删除线", systemImage: "strikethrough") }
                    Button { linkURL = "https://"; showingLinkPrompt = true } label: { Label("链接", systemImage: "link") }
                    Button { editCommand = ArticleEditCommand(.center) } label: { Label("居中", systemImage: "text.aligncenter") }
                } label: { ArticleToolIcon("paintbrush", "样式") }.frame(maxWidth: .infinity)

                Menu {
                    ForEach(["😀", "👍", "✅", "📌", "💡", "🎉"], id: \.self) { value in
                        Button(value) { editCommand = ArticleEditCommand(.emoji(value)) }
                    }
                } label: { ArticleToolIcon("face.smiling", "表情") }.frame(maxWidth: .infinity)

                PhotosPicker(selection: $photoItems, maxSelectionCount: max(9 - images.count, 1), matching: .images) { ArticleToolIcon("photo", "图片") }.frame(maxWidth: .infinity).buttonStyle(.plain).disabled(images.count >= 9)
                Button { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } label: { ArticleToolIcon("keyboard.chevron.compact.down", "收起") }.frame(maxWidth: .infinity).buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
    }

    private var articlePreviewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名文章" : title)
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(category, systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                SavedLinkArticleContent(source: description, pendingImages: pendingInlineImages)
            }
            .padding(20)
        }
    }

    private var normalizedLinkURL: String? {
        let value = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return value
    }

    private var firstArticleURL: String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let value = match.url,
              let scheme = value.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return value.absoluteString
    }

    @MainActor private func receivePhotos(_ items: [PhotosPickerItem]) async {
        let remaining = max(9 - images.count, 0)
        guard remaining > 0, !items.isEmpty else { photoItems = []; return }
        var selected: [URL] = []
        for item in items.prefix(remaining) {
            guard let sourceData = try? await item.loadTransferable(type: Data.self), let data = preparedArticlePhoto(sourceData) else { continue }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("article-photo-\(UUID().uuidString).jpg")
            do { try data.write(to: url, options: .atomic); selected.append(url) } catch { self.error = "读取照片失败，请重新选择。" }
        }
        photoItems = []
        guard !selected.isEmpty else { return }
        images.append(contentsOf: selected)
        guard article else { return }
        let placeholders = selected.map { PendingInlineImage(token: "native-image://\(UUID().uuidString)", url: $0) }
        pendingInlineImages.append(contentsOf: placeholders)
        editCommand = ArticleEditCommand(.images(placeholders))
    }
    private func preparedArticlePhoto(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximum: CGFloat = 2400
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maximum ? maximum / longest : 1
        let size = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.jpegData(compressionQuality: 0.84)
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        let normalizedCategory = article && !category.lowercased().hasPrefix("tutorial:") ? "tutorial:\(category.isEmpty ? "未分类" : category)" : category
        let savedCategory: Any = normalizedCategory.isEmpty ? NSNull() : normalizedCategory
        var initialDescription = description
        for pending in pendingInlineImages {
            let token = NSRegularExpression.escapedPattern(for: pending.token)
            initialDescription = initialDescription.replacingOccurrences(of: "!\\[[^\\]]*\\]\\(\(token)\\)", with: "", options: .regularExpression)
        }
        let savedDescription: Any = initialDescription.isEmpty ? NSNull() : initialDescription
        let savedURLValue = article ? firstArticleURL : url.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedURL: Any = savedURLValue?.isEmpty == false ? savedURLValue! : NSNull()
        var body: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "category": savedCategory, "description": savedDescription, "url": savedURL, "is_pinned": pinned, "sort_order": 0]
        do {
            var saved: SavedLink = try await session.send(item.map { "saved-links/\($0.id)" } ?? "saved-links", method: item == nil ? "POST" : "PUT", body: body)
            if !images.isEmpty {
                var files: [MultipartFile] = []
                for image in images {
                    let hasSecurityScope = image.startAccessingSecurityScopedResource()
                    defer { if hasSecurityScope { image.stopAccessingSecurityScopedResource() } }
                    let mime = UTType(filenameExtension: image.pathExtension)?.preferredMIMEType ?? "image/jpeg"
                    files.append(MultipartFile(field: "images", filename: image.lastPathComponent, data: try Data(contentsOf: image), mime: mime))
                }
                if !files.isEmpty { saved = try await session.uploadMany(path: "saved-links/\(saved.id)/images/append", files: files) }
            }
            if article && !pendingInlineImages.isEmpty {
                var finalDescription = description
                let uploaded = Array(saved.images.suffix(pendingInlineImages.count))
                guard uploaded.count == pendingInlineImages.count else { throw NativeImageError.invalidResponse }
                for (pending, remote) in zip(pendingInlineImages, uploaded) {
                    finalDescription = finalDescription.replacingOccurrences(of: "(\(pending.token))", with: "(\(remote.url))")
                }
                if finalDescription != description {
                    body["description"] = finalDescription
                    let _: SavedLink = try await session.send("saved-links/\(saved.id)", method: "PUT", body: body)
                    description = finalDescription
                }
            }
            UserDefaults.standard.removeObject(forKey: draftKey)
            await onSave(); dismiss()
        } catch { self.error = session.message(for: error) }
    }

    private var draftKey: String { "native-link-draft-\(article ? "article" : "post")" }
    private func saveDraft() {
        guard item == nil, !title.isEmpty || !description.isEmpty else { return }
        let draft = LinkDraft(title: title, category: category, description: description, updatedAt: Date())
        if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: draftKey) }
    }
    private func restoreDraft() {
        guard item == nil, title.isEmpty, description.isEmpty, let data = UserDefaults.standard.data(forKey: draftKey), let draft = try? JSONDecoder().decode(LinkDraft.self, from: data) else { return }
        title = draft.title; category = draft.category; description = draft.description
        draftNotice = "已恢复 \(shortTimestamp(draft.updatedAt.timeIntervalSince1970)) 的草稿"
    }
}

private struct LinkDraft: Codable { let title: String; let category: String; let description: String; let updatedAt: Date }

private struct NativeMineView: View {
    @EnvironmentObject private var session: NativeSession
    let isActive: Bool
    @State private var path: [NativeDestination] = []
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { path.append(.profile) } label: {
                        HStack(spacing: 14) {
                            NativeRemoteImage(url: session.currentUser?.avatarURL, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 7) { Text(session.currentUser?.displayName ?? session.username).font(.title3.bold()).foregroundStyle(.primary); Text(roleLabel(session.currentUser?.role ?? "viewer")).font(.caption2.weight(.medium)).foregroundStyle(.blue).padding(.horizontal, 7).padding(.vertical, 3).background(Color.blue.opacity(0.1), in: Capsule()) }
                                Text("账号 \(session.username)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 0) {
                        MineAccountMetric(value: "\(authorizedModuleCount)", title: "授权模块")
                        Divider().frame(height: 30)
                        MineAccountMetric(value: session.currentUser?.role == "superadmin" ? "超级" : "普通", title: "账号身份")
                        Divider().frame(height: 30)
                        MineAccountMetric(value: "在线", title: "登录状态")
                    }
                    .padding(.vertical, 2)
                }

                Section("账户与访问") {
                    MineEntry("账号与权限", subtitle: "成员、角色与模块权限", "person.badge.key", .blue) { path.append(.users) }
                    MineEntry("卡密管理", subtitle: "授权码与绑定设备", "key", .purple) { path.append(.licenseKeys) }
                }

                Section("系统") {
                    MineEntry("服务器运行", subtitle: "服务状态与资源监控", "server.rack", .green) { path.append(.server) }
                    MineEntry("通知中心", subtitle: "业务提醒与系统消息", "bell", .red) { path.append(.alerts) }
                    MineEntry("系统设置", subtitle: "安全、会话与应用配置", "gearshape", .gray) { path.append(.systemSettings) }
                }

                Section {
                    Button(role: .destructive) { Task { await session.logout() } } label: {
                        Text("退出登录").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NativeDestination.self) { destination in destination.view }
            .onChange(of: isActive) { active in if !active { path.removeAll() } }
        }
    }

    private var authorizedModuleCount: Int { session.currentUser?.permissions.values.filter { $0 != "none" }.count ?? 0 }
}

private struct LinkLoadErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View { VStack(spacing: 10) { Label("加载失败", systemImage: "wifi.exclamationmark").font(.headline); Text(message).font(.caption).foregroundStyle(.secondary); Button("重新加载", action: retry) }.frame(maxWidth: .infinity).padding(.vertical, 20) }
}

private struct ArticleToolIcon: View { let symbol: String; let title: String; init(_ symbol: String, _ title: String) { self.symbol = symbol; self.title = title }; var body: some View { VStack(spacing: 5) { Image(systemName: symbol).font(.headline); Text(title).font(.caption2) }.frame(minWidth: 48, minHeight: 46).contentShape(Rectangle()) } }

private struct PendingInlineImage {
    let token: String
    let url: URL
}

private struct ArticleEditCommand: Identifiable {
    enum Kind { case heading1, heading2, body, bold, italic, strikethrough, quote, list, numberedList, checklist, link(String), center, emoji(String), images([PendingInlineImage]) }
    let id = UUID()
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

private struct NativeArticleTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var command: ArticleEditCommand?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.accessibilityLabel = "文章正文"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        guard let command, context.coordinator.lastCommand != command.id else { return }
        context.coordinator.lastCommand = command.id
        context.coordinator.apply(command.kind, to: view)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeArticleTextEditor
        var lastCommand: UUID?
        init(_ parent: NativeArticleTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func apply(_ kind: ArticleEditCommand.Kind, to view: UITextView) {
            let source = view.text ?? ""
            let range = view.selectedRange
            let ns = source as NSString
            let selected = range.length > 0 ? ns.substring(with: range) : ""
            let replacement: String
            switch kind {
            case .bold: replacement = "**\(selected.isEmpty ? "粗体文字" : selected)**"
            case .italic: replacement = "*\(selected.isEmpty ? "斜体文字" : selected)*"
            case .strikethrough: replacement = "~~\(selected.isEmpty ? "删除线文字" : selected)~~"
            case .link(let url): replacement = "[\(selected.isEmpty ? "链接文字" : selected)](\(url))"
            case .heading1: replacement = isolatedBlock("# \(selected.isEmpty ? "一级标题" : selected)", in: ns, replacing: range)
            case .heading2: replacement = isolatedBlock("## \(selected.isEmpty ? "二级标题" : selected)", in: ns, replacing: range)
            case .body: replacement = (selected.isEmpty ? "正文" : selected).replacingOccurrences(of: #"(?m)^(#{1,6}\s+|>\s+|[-*]\s+|\d+\.\s+|- \[[ xX]\]\s+)"#, with: "", options: .regularExpression)
            case .quote: replacement = isolatedBlock("> \(selected.isEmpty ? "引用内容" : selected.replacingOccurrences(of: "\n", with: "\n> "))", in: ns, replacing: range)
            case .list: replacement = isolatedBlock("- \(selected.isEmpty ? "列表项目" : selected.replacingOccurrences(of: "\n", with: "\n- "))", in: ns, replacing: range)
            case .numberedList:
                let value = (selected.isEmpty ? ["列表项目"] : selected.components(separatedBy: "\n")).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                replacement = isolatedBlock(value, in: ns, replacing: range)
            case .checklist: replacement = isolatedBlock("- [ ] \(selected.isEmpty ? "待办事项" : selected.replacingOccurrences(of: "\n", with: "\n- [ ] "))", in: ns, replacing: range)
            case .center: replacement = isolatedBlock("::: align-center\n\(selected.isEmpty ? "居中内容" : selected)\n:::", in: ns, replacing: range)
            case .emoji(let value): replacement = value
            case .images(let images): replacement = images.map { image in
                let alt = image.url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "]", with: "")
                return "\n![\(alt.isEmpty ? "图片" : alt)](\(image.token))\n"
            }.joined(separator: "\n")
            }
            view.text = ns.replacingCharacters(in: range, with: replacement)
            view.selectedRange = NSRange(location: range.location + (replacement as NSString).length, length: 0)
            parent.text = view.text
            view.becomeFirstResponder()
        }

        private func isolatedBlock(_ value: String, in source: NSString, replacing range: NSRange) -> String {
            let needsLeadingBreak = range.location > 0 && source.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n"
            let end = range.location + range.length
            let needsTrailingBreak = end < source.length && source.substring(with: NSRange(location: end, length: 1)) != "\n"
            return (needsLeadingBreak ? "\n" : "") + value + (needsTrailingBreak ? "\n" : "")
        }
    }
}

private struct SavedLinkFeedRow: View {
    let item: SavedLink
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onPushNow: () -> Void
    let onSchedule: () -> Void
    private var isArticle: Bool { savedLinkIsArticle(item) }
    private var category: String? { item.category?.replacingOccurrences(of: "tutorial:", with: "", options: [.caseInsensitive, .anchored]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    private var bodyText: String { isArticle ? savedLinkPlainText(item.description) : (item.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pushLabel: String? { item.pushStatus == "idle" ? nil : item.pushStatus == "scheduled" ? "已定时" : item.pushStatus == "sending" ? "推送中" : item.pushStatus == "sent" ? "已推送" : "推送失败" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Button(action: onOpen) {
                    HStack(spacing: 9) {
                        SavedLinkAvatar(item: item)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.authorUsername).font(.subheadline.bold())
                            Text(shortDate(item.createdAt)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.isPinned { Label("置顶", systemImage: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button("编辑") { onEdit() }
                    Button(item.isPinned ? "取消置顶" : "置顶") { onTogglePin() }
                    Button("立即推送到钉钉", systemImage: "paperplane") { onPushNow() }
                    Button("定时推送", systemImage: "calendar.badge.clock") { onSchedule() }
                    Button("删除", role: .destructive) { onDelete() }
                } label: { Image(systemName: "ellipsis").font(.headline).frame(width: 28, height: 28).contentShape(Rectangle()) }
                .buttonStyle(.plain)
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: isArticle ? "doc.text" : "bubble.left").foregroundStyle(.blue)
                        Text(item.title).font(.headline).lineLimit(2)
                        if let category { Text(category).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        if let pushLabel { Text(pushLabel).font(.caption2).foregroundStyle(item.pushStatus == "failed" ? .red : .blue) }
                    }
                    if !bodyText.isEmpty {
                        Text(bodyText).lineLimit(4).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
                        if bodyText.count > 120 { Text("全文").font(.subheadline).foregroundStyle(.blue) }
                    }
                    if isArticle && !item.images.isEmpty { SavedLinkImageGrid(images: item.images) }
                    if let url = item.url, !url.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "safari").foregroundStyle(.blue)
                            Text(linkHost(url) ?? "打开原链接").font(.subheadline).foregroundStyle(.blue).lineLimit(1)
                            Spacer()
                        }
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct SavedLinkImageGrid: View {
    let images: [SavedLinkImage]
    var body: some View {
        let urls = images.compactMap { nativeThumbnailURL($0.url, maxPixelSize: 720) }
        if urls.isEmpty {
            EmptyView()
        } else if urls.count == 1 {
            SavedLinkFeedImage(url: urls[0], maxPixelSize: 1400)
                .frame(height: 180)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { index, url in
                    ZStack {
                        SavedLinkFeedImage(url: url, maxPixelSize: 600)
                        if index == 2 && urls.count > 3 {
                            Color.black.opacity(0.38)
                            Text("+\(urls.count - 3)").font(.headline).foregroundStyle(.white)
                        }
                    }
                    .frame(height: 118)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

private struct SavedLinkFeedImage: View {
    let url: URL
    let maxPixelSize: CGFloat

    var body: some View {
        GeometryReader { proxy in
            CachedRemoteImage(url: url, contentMode: .fill, maxPixelSize: maxPixelSize, placeholder: ProgressView())
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

private struct SavedLinkAvatar: View {
    let item: SavedLink
    var body: some View {
        Group {
            if let value = item.authorAvatarURL, let avatar = nativeThumbnailURL(value, maxPixelSize: 144) {
                CachedRemoteImage(url: avatar, contentMode: .fill, placeholder: initials)
            } else { initials }
        }.frame(width: 30, height: 30).clipShape(Circle())
    }
    private var initials: some View { Text(String(item.authorUsername.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.blue) }
}

private func linkHost(_ value: String) -> String? {
    guard let url = URL(string: value), let host = url.host else { return nil }
    return host.replacingOccurrences(of: "www.", with: "", options: [.caseInsensitive, .anchored])
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct LinkEmptyView: View {
    let searching: Bool
    var body: some View { VStack(spacing: 10) { Image(systemName: searching ? "magnifyingglass" : "link").font(.title2).foregroundStyle(.secondary); Text(searching ? "没有搜索结果" : "暂无内容").font(.headline); Text(searching ? "请尝试其他关键词" : "发布第一条帖子或文章").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 28) }
}
private struct NativeEmptyState: View {
    let icon: String; let title: String; let message: String
    var body: some View { VStack(spacing: 8) { Image(systemName: icon).font(.title2).foregroundStyle(.secondary); Text(title).font(.headline); Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 30).listRowSeparator(.hidden) }
}

private struct MineEntry: View {
    let title: String; let subtitle: String; let icon: String; let color: Color; let action: () -> Void
    init(_ title: String, subtitle: String, _ icon: String, _ color: Color, action: @escaping () -> Void) { self.title = title; self.subtitle = subtitle; self.icon = icon; self.color = color; self.action = action }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NativeAppIconTile(symbol: icon, color: color, size: 34, iconSize: 16)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.body).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
private struct MineAccountMetric: View { let value: String; let title: String; var body: some View { VStack(spacing: 3) { Text(value).font(.subheadline.weight(.semibold)); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) } }

private struct NativeShopsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var fields: [ShopField] = []; @State private var records: [ShopRecord] = []; @State private var query = ""; @State private var loading = false; @State private var error: String?
    @State private var editing: ShopRecord?; @State private var showingForm = false
    private var visibleFields: [ShopField] { fields.filter(\.isVisible).sorted { $0.sortOrder < $1.sortOrder } }
    private var filtered: [ShopRecord] { query.isEmpty ? records : records.filter { $0.values.values.map(\.display).joined(separator: " ").localizedCaseInsensitiveContains(query) } }
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(filtered) { record in NavigationLink { ShopDetail(record: record, fields: visibleFields) } label: { VStack(alignment: .leading, spacing: 5) { Text(title(record)).fontWeight(.medium); Text(visibleFields.prefix(3).compactMap { field in record.values[field.fieldName].map { "\(field.label)：\($0.display)" } }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(record) } }; Button("编辑") { editing = record; showingForm = true }.tint(.blue) } } }.navigationTitle("店铺档案").searchable(text: $query).overlay { if loading && records.isEmpty { ProgressView() } }.task { await load() }.refreshable { await load() }.toolbar { ToolbarItemGroup { NavigationLink { ShopFieldsView() } label: { Image(systemName: "slider.horizontal.3") }; Button { editing = nil; showingForm = true } label: { Image(systemName: "plus") } } }.sheet(isPresented: $showingForm) { ShopForm(item: editing, fields: visibleFields) { await load() } } }
    private func title(_ record: ShopRecord) -> String { for key in ["shop_name", "store_name", "name"] { if let value = record.values[key], !value.display.isEmpty { return value.display } }; return visibleFields.compactMap { record.values[$0.fieldName]?.display }.first ?? "店铺 #\(record.id)" }
    private func load() async { loading = true; defer { loading = false }; do { async let fieldRequest: [ShopField] = session.get("custom-fields"); async let recordRequest: [ShopRecord] = session.get("shop-records"); let result = try await (fieldRequest, recordRequest); fields = result.0; records = result.1 } catch { self.error = session.message(for: error) } }
    private func remove(_ record: ShopRecord) async { do { try await session.delete("shop-records/\(record.id)"); records.removeAll { $0.id == record.id } } catch { self.error = session.message(for: error) } }
}

private struct ShopDetail: View { let record: ShopRecord; let fields: [ShopField]; @State private var copiedField: String?; private var copyFields:[NativeCopyField]{fields.map{NativeCopyField(label:$0.label,value:record.values[$0.fieldName]?.display ?? "-")}}; var body: some View { List { ForEach(copyFields) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } }.navigationTitle("店铺详情").navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: copyFields, copiedField: $copiedField) } } }

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
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if owners.isEmpty && error == nil { NativeEmptyState(icon: "person.2", title: "暂无负责人", message: "点击右上角添加负责人") }
            ForEach(owners.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { owner in
                HStack(spacing: 14) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 38, height: 38)
                        .background(Color.blue.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(owner.name).font(.body.weight(.medium))
                        Text("任务负责人").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions { Button("删除", role: .destructive) { Task { await remove(owner) } } }
            }
        }
        .listStyle(.plain)
        .navigationTitle("负责人")
        .searchable(text: $query)
        .task { await load() }
        .refreshable { await load() }
        .toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        .alert("新增负责人", isPresented: $showingAdd) {
            TextField("负责人名称", text: $newName)
            Button("保存") { Task { await add() } }
            Button("取消", role: .cancel) {}
        }
    }
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
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.shopName) \($0.shopURL ?? "") \($0.remark ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { PeerShopDetail(item: row) } label: { HStack(spacing: 10) { NativeRemoteImage(url: row.imageURL, size: 48); VStack(alignment: .leading, spacing: 5) { Text(row.shopName).fontWeight(.medium); Text(row.shopURL ?? row.remark ?? "-").font(.caption).foregroundStyle(.secondary) } } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("同行店铺").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { PeerShopForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("peer-shops") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: PeerShopRecord) async { do { try await session.delete("peer-shops/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct PeerShopDetail: View { let item: PeerShopRecord; @State private var copiedField:String?; private var fields:[NativeCopyField]{[NativeCopyField(label:"店铺",value:item.shopName),NativeCopyField(label:"链接",value:item.shopURL ?? "-"),NativeCopyField(label:"备注",value:item.remark ?? "无")]}; var body: some View { List { NativeRemoteImage(url: item.imageURL, size: 180); Section("资料") { ForEach(fields) { field in NativeCopyRow(label:field.label,value:field.value,copiedField:$copiedField) } } }.navigationTitle("同行店铺详情").toolbar { NativeCopyAllButton(fields:fields,copiedField:$copiedField) } } }
private struct PeerShopForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: PeerShopRecord?; let onSave: () async -> Void; @State private var name: String; @State private var url: String; @State private var remark: String; @State private var saving = false; @State private var error: String?; @State private var photoItem: PhotosPickerItem?
    init(item: PeerShopRecord?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.shopName ?? ""); _url = State(initialValue: item?.shopURL ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("店铺名称", text: $name); TextField("店铺链接", text: $url); TextField("备注", text: $remark, axis: .vertical).lineLimit(4...8); if item != nil { PhotosPicker(selection: $photoItem, matching: .images) { Label("从照片中选择店铺图片", systemImage: "photo.on.rectangle") } } }.navigationTitle(item == nil ? "新增同行店铺" : "编辑同行店铺").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || name.isEmpty) } }.onChange(of: photoItem) { value in if let value { Task { await uploadImage(value) } } } } }
    private func save() async { saving = true; defer { saving = false }; let shopURL: Any = url.isEmpty ? NSNull() : url; let savedRemark: Any = remark.isEmpty ? NSNull() : remark; let extra: [String: Any] = [:]; let body: [String: Any] = ["shop_name": name, "shop_url": shopURL, "remark": savedRemark, "extra_fields": extra]; do { let _: PeerShopRecord = try await session.send(item.map { "peer-shops/\($0.id)" } ?? "peer-shops", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
    private func uploadImage(_ photo: PhotosPickerItem) async { guard let item else { return }; do { guard let raw = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = image.jpegData(compressionQuality: 0.86) else { throw NativeAPIError.invalidResponse }; let _: PeerShopRecord = try await session.upload(path: "peer-shops/\(item.id)/image", field: "image", filename: "peer-shop.jpg", data: data, mime: "image/jpeg"); await onSave() } catch { self.error = session.message(for: error) } }
}

private struct NativeLicenseRecordsView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [LicenseRecordItem] = []; @State private var query = ""; @State private var error: String?; @State private var editing: LicenseRecordItem?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.subjectName) \($0.creditCode) \($0.legalRepresentative ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { LicenseRecordDetail(item: row, records: rows) } label: { HStack(spacing: 10) { NativeRemoteImage(url: row.imageURL, size: 48); VStack(alignment: .leading, spacing: 5) { Text(row.subjectName).fontWeight(.medium); Text(row.creditCode).font(.caption).foregroundStyle(.secondary); Text(row.expiryDate ?? "未填写到期日").font(.caption2).foregroundStyle(.secondary) } } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("执照档案").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { LicenseRecordForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("license-records") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: LicenseRecordItem) async { do { try await session.delete("license-records/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct LicenseRecordDetail: View {
    let item: LicenseRecordItem
    let records: [LicenseRecordItem]
    @State private var showingViewer = false
    @State private var selectedImageID = 0
    @State private var copiedField: String?
    private var imageRecords: [LicenseRecordItem] { records.filter { $0.imageURL?.isEmpty == false } }
    var body: some View {
        List {
            if item.imageURL != nil {
                Button { selectedImageID = item.id; showingViewer = true } label: {
                    VStack(spacing: 8) {
                        NativeRemoteImage(url: item.imageURL, size: 220)
                        Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
            Section("执照信息") {
                NativeCopyRow(label: "主体名称", value: item.subjectName, copiedField: $copiedField)
                NativeCopyRow(label: "统一社会信用代码", value: item.creditCode, copiedField: $copiedField)
                NativeCopyRow(label: "法定代表人", value: item.legalRepresentative ?? "-", copiedField: $copiedField)
                NativeCopyRow(label: "签发日期", value: item.issueDate ?? "-", copiedField: $copiedField)
                NativeCopyRow(label: "到期日期", value: item.expiryDate ?? "-", copiedField: $copiedField)
            }
            Section("备注") { Text(item.remark ?? "无").textSelection(.enabled) }
        }
        .navigationTitle("执照详情")
        .toolbar { Menu { Button("复制全部信息", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText; copiedField = "全部信息" }; if item.imageURL != nil { Button("查看大图", systemImage: "photo") { selectedImageID = item.id; showingViewer = true } } } label: { Image(systemName: copiedField == "全部信息" ? "checkmark.circle" : "ellipsis.circle") } }
        .fullScreenCover(isPresented: $showingViewer) { LicenseImageViewer(records: imageRecords, selection: $selectedImageID) }
    }
    private var copyText: String { ["主体名称：\(item.subjectName)", "统一社会信用代码：\(item.creditCode)", "法定代表人：\(item.legalRepresentative ?? "-")", "签发日期：\(item.issueDate ?? "-")", "到期日期：\(item.expiryDate ?? "-")", "备注：\(item.remark ?? "无")"].joined(separator: "\n") }
}

private struct NativeCopyRow: View {
    let label: String
    let value: String
    @Binding var copiedField: String?
    var body: some View { Button { UIPasteboard.general.string = value; copiedField = label } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).foregroundStyle(.primary).textSelection(.enabled) }; Spacer(); Image(systemName: copiedField == label ? "checkmark.circle.fill" : "doc.on.doc").foregroundStyle(copiedField == label ? .green : .secondary) } }.buttonStyle(.plain) }
}

private struct NativeCopyField: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

private struct NativeCopyAllButton: View {
    let fields: [NativeCopyField]
    @Binding var copiedField: String?
    var body: some View { Button { UIPasteboard.general.string = fields.map { "\($0.label)：\($0.value)" }.joined(separator: "\n"); copiedField = "全部信息" } label: { Label("复制全部信息", systemImage: copiedField == "全部信息" ? "checkmark.circle.fill" : "doc.on.doc") } }
}

private struct LicenseImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let records: [LicenseRecordItem]
    @Binding var selection: Int
    var body: some View { NavigationStack { ZStack { Color.black.ignoresSafeArea(); TabView(selection: $selection) { ForEach(records) { record in ZoomableLicenseImage(url: record.imageURL).tag(record.id).overlay(alignment: .bottom) { Text(record.subjectName).font(.caption).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.55), in: Capsule()).padding(.bottom, 24) } } }.tabViewStyle(.page(indexDisplayMode: records.count > 1 ? .automatic : .never)) }.navigationTitle("执照图片").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar).toolbarBackground(.black, for: .navigationBar).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() }.foregroundStyle(.white) } } } }
}

private struct ZoomableLicenseImage: View {
    let url: String?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero
    var body: some View { GeometryReader { proxy in ZStack { if let url, let imageURL = nativeImageURL(url) { CachedRemoteImage(url: imageURL, contentMode: .fit, maxPixelSize: 2600, placeholder: ProgressView().tint(.white)) } else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) } }.frame(width: proxy.size.width, height: proxy.size.height).scaleEffect(min(max(scale * gestureScale, 1), 5)).offset(x: offset.width + gestureOffset.width, y: offset.height + gestureOffset.height).contentShape(Rectangle()).simultaneousGesture(MagnificationGesture().updating($gestureScale) { value, state, _ in state = value }.onEnded { value in scale = min(max(scale * value, 1), 5); if scale == 1 { offset = .zero } }).simultaneousGesture(DragGesture().updating($gestureOffset) { value, state, _ in if scale > 1 { state = value.translation } }.onEnded { value in if scale > 1 { offset.width += value.translation.width; offset.height += value.translation.height } }).onTapGesture(count: 2) { withAnimation(.easeInOut(duration: 0.2)) { if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 } } } } }
}
private struct LicenseRecordForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: LicenseRecordItem?; let onSave: () async -> Void; @State private var subject: String; @State private var code: String; @State private var legal: String; @State private var issue: String; @State private var expiry: String; @State private var remark: String; @State private var saving = false; @State private var error: String?; @State private var photoItem: PhotosPickerItem?
    init(item: LicenseRecordItem?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _subject = State(initialValue: item?.subjectName ?? ""); _code = State(initialValue: item?.creditCode ?? ""); _legal = State(initialValue: item?.legalRepresentative ?? ""); _issue = State(initialValue: item?.issueDate ?? ""); _expiry = State(initialValue: item?.expiryDate ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("主体名称", text: $subject); TextField("统一信用代码", text: $code); TextField("法定代表人", text: $legal); TextField("签发日期", text: $issue); TextField("到期日期", text: $expiry); TextField("备注", text: $remark, axis: .vertical).lineLimit(4...8); if item != nil { PhotosPicker(selection: $photoItem, matching: .images) { Label("从照片中选择执照图片", systemImage: "photo.on.rectangle") } } }.navigationTitle(item == nil ? "新增执照" : "编辑执照").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || subject.isEmpty || code.isEmpty) } }.onChange(of: photoItem) { value in if let value { Task { await uploadImage(value) } } } } }
    private func save() async { saving = true; defer { saving = false }; let savedLegal: Any = legal.isEmpty ? NSNull() : legal; let savedIssue: Any = issue.isEmpty ? NSNull() : issue; let savedExpiry: Any = expiry.isEmpty ? NSNull() : expiry; let savedRemark: Any = remark.isEmpty ? NSNull() : remark; let extra: [String: Any] = [:]; let body: [String: Any] = ["subject_name": subject, "credit_code": code, "legal_representative": savedLegal, "issue_date": savedIssue, "expiry_date": savedExpiry, "remark": savedRemark, "extra_fields": extra]; do { let _: LicenseRecordItem = try await session.send(item.map { "license-records/\($0.id)" } ?? "license-records", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
    private func uploadImage(_ photo: PhotosPickerItem) async { guard let item else { return }; do { guard let raw = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = image.jpegData(compressionQuality: 0.9) else { throw NativeAPIError.invalidResponse }; let _: LicenseRecordItem = try await session.upload(path: "license-records/\(item.id)/image", field: "image", filename: "license.jpg", data: data, mime: "image/jpeg"); await onSave() } catch { self.error = session.message(for: error) } }
}

private struct NativeDevicesView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [MobileDevice] = []; @State private var query = ""; @State private var error: String?; @State private var editing: MobileDevice?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.deviceName) \($0.primaryCard ?? "") \($0.secondaryCard ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { DeviceDetail(item: row) } label: { VStack(alignment: .leading, spacing: 5) { Text(row.deviceName).fontWeight(.medium); Text([row.primaryCard, row.secondaryCard].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }.swipeActions { Button("删除", role: .destructive) { Task { await remove(row) } }; Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("手机设备").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { DeviceForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("mobile-devices") } catch { self.error = session.message(for: error) } }
    private func remove(_ row: MobileDevice) async { do { try await session.delete("mobile-devices/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct DeviceDetail: View {
    let item: MobileDevice; @State private var copiedField: String?
    private var fields: [NativeCopyField] { [.init(label: "设备名称", value: item.deviceName), .init(label: "主卡", value: item.primaryCard ?? "-"), .init(label: "副卡", value: item.secondaryCard ?? "-"), .init(label: "备注", value: item.remark ?? "无")] }
    var body: some View { List { Section("设备资料") { ForEach(fields) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } } }.navigationTitle("设备详情").navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: fields, copiedField: $copiedField) } }
}
private struct DeviceForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: MobileDevice?; let onSave: () async -> Void; @State private var name: String; @State private var primary: String; @State private var secondary: String; @State private var remark: String; @State private var saving = false; @State private var error: String?
    init(item: MobileDevice?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _name = State(initialValue: item?.deviceName ?? ""); _primary = State(initialValue: item?.primaryCard ?? ""); _secondary = State(initialValue: item?.secondaryCard ?? ""); _remark = State(initialValue: item?.remark ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("设备名称", text: $name); TextField("主卡", text: $primary); TextField("副卡", text: $secondary); TextField("备注", text: $remark) }.navigationTitle(item == nil ? "新增设备" : "编辑设备").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || name.isEmpty) } } } }
    private func save() async { saving = true; defer { saving = false }; let body: [String: Any] = ["device_name": name, "primary_card": primary, "secondary_card": secondary, "remark": remark, "extra_fields": [String: Any]()]; do { let _: MobileDevice = try await session.send(item.map { "mobile-devices/\($0.id)" } ?? "mobile-devices", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct NativeAccountUsageView: View {
    @EnvironmentObject private var session: NativeSession; @State private var rows: [AccountUsage] = []; @State private var query = ""; @State private var error: String?; @State private var editing: AccountUsage?; @State private var showing = false
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(rows.filter { query.isEmpty || "\($0.accountName) \($0.phoneNumber ?? "") \($0.deviceName ?? "")".localizedCaseInsensitiveContains(query) }) { row in NavigationLink { AccountUsageDetail(item: row) } label: { VStack(alignment: .leading, spacing: 5) { HStack { Text(row.accountName).fontWeight(.medium); Spacer(); StatusBadge(text: row.isBanned ? "已封禁" : "正常", done: !row.isBanned) }; Text([row.phoneNumber, row.deviceName].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }.swipeActions { Button(row.isBanned ? "恢复" : "封禁") { Task { await setBanned(row, !row.isBanned) } }.tint(row.isBanned ? .green : .orange); Button("编辑") { editing = row; showing = true }.tint(.blue) } } }.navigationTitle("账号使用").searchable(text: $query).task { await load() }.refreshable { await load() }.toolbar { Button { editing = nil; showing = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showing) { AccountUsageForm(item: editing) { await load() } } }
    private func load() async { do { rows = try await session.get("account-usage-records") } catch { self.error = session.message(for: error) } }
    private func setBanned(_ row: AccountUsage, _ banned: Bool) async { do { let _: EmptyResponse = try await session.send("account-usage-records/batch-status", method: "PATCH", body: ["record_ids": [row.id], "is_banned": banned], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}
private struct AccountUsageDetail: View {
    let item: AccountUsage; @State private var copiedField: String?
    private var fields: [NativeCopyField] { [.init(label: "账号名称", value: item.accountName), .init(label: "手机号", value: item.phoneNumber ?? "-"), .init(label: "手机设备", value: item.deviceName ?? "-"), .init(label: "状态", value: item.isBanned ? "已封禁" : "正常"), .init(label: "使用说明", value: item.usageNotes ?? "无"), .init(label: "封禁原因", value: item.bannedReason ?? "无")] }
    var body: some View { List { Section("账号资料") { ForEach(fields) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } } }.navigationTitle("账号详情").navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: fields, copiedField: $copiedField) } }
}
private struct AccountUsageForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let item: AccountUsage?; let onSave: () async -> Void; @State private var account: String; @State private var password = ""; @State private var phone: String; @State private var device: String; @State private var notes: String; @State private var reason: String; @State private var saving = false; @State private var error: String?
    init(item: AccountUsage?, onSave: @escaping () async -> Void) { self.item = item; self.onSave = onSave; _account = State(initialValue: item?.accountName ?? ""); _phone = State(initialValue: item?.phoneNumber ?? ""); _device = State(initialValue: item?.deviceName ?? ""); _notes = State(initialValue: item?.usageNotes ?? ""); _reason = State(initialValue: item?.bannedReason ?? "") }
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("账号名称", text: $account); SecureField(item == nil ? "密码" : "留空保留原密码", text: $password); TextField("手机号", text: $phone).keyboardType(.phonePad); TextField("手机设备", text: $device); TextField("使用说明", text: $notes, axis: .vertical).lineLimit(3...6); TextField("封禁原因", text: $reason) }.navigationTitle(item == nil ? "新增账号记录" : "编辑账号记录").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving || (item == nil && account.isEmpty)) } } } }
    private func save() async { saving = true; defer { saving = false }; var body: [String: Any] = ["account_name": account, "phone_number": phone, "device_name": device, "usage_notes": notes, "banned_reason": reason, "is_banned": item?.isBanned ?? false, "extra_fields": [String: Any]()]; if !password.isEmpty { body["password"] = password }; do { let _: AccountUsage = try await session.send(item.map { "account-usage-records/\($0.id)" } ?? "account-usage-records", method: item == nil ? "POST" : "PUT", body: body); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}

private struct LicenseDetail: View {
    @EnvironmentObject private var session: NativeSession; let item: LicenseRecord; let onChange: () async -> Void; @State private var error: String?; @State private var copiedField: String?
    private var fields: [NativeCopyField] { var result = [NativeCopyField(label: "授权码", value: item.licenseKey), .init(label: "套餐", value: item.planName), .init(label: "状态", value: licenseStatus(item.status)), .init(label: "到期", value: item.expiresAt ?? "-"), .init(label: "设备上限", value: "\(item.maxDevices)")]; for (index, device) in item.devices.enumerated() { result.append(.init(label: "绑定设备\(index + 1)", value: "\(device.deviceName ?? device.deviceID) | \(device.deviceID) | \(device.platform ?? "未知平台") | \(device.appVersion ?? "未知版本")")) }; return result }
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; Section("授权") { ForEach(fields.prefix(5)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } }; Section("绑定设备") { ForEach(Array(item.devices.enumerated()), id: \.element.id) { index, device in HStack { Button { UIPasteboard.general.string = fields[index + 5].value; copiedField = "绑定设备\(index + 1)" } label: { VStack(alignment: .leading) { Text(device.deviceName ?? device.deviceID); Text("\(device.platform ?? "未知平台") · \(device.appVersion ?? "未知版本")").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain); Spacer(); Button("解绑", role: .destructive) { Task { await unbind(device) } } } } } }.navigationTitle("授权详情").navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: fields, copiedField: $copiedField) } }
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
    @State private var selectedCollectionID = ""; @State private var renamingCollection: KnowledgeCollection?; @State private var collectionName = ""

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section("知识集合") {
                HStack { TextField("集合名称", text: $newName); Button("创建") { Task { await create() } }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
                Picker("当前集合", selection: $selectedCollectionID) { Text("全部文件").tag(""); ForEach(collections) { Text($0.name).tag($0.id) } }
            }
            Section("集合") {
                ForEach(collections) { item in Button { selectedCollectionID = item.id } label: { HStack { Label(item.name, systemImage: selectedCollectionID == item.id ? "folder.fill" : "folder"); Spacer(); Text("\(files.filter { $0.knowledgeID == item.id }.count) 个文件").font(.caption).foregroundStyle(.secondary) } }.contextMenu { Button("重命名") { renamingCollection = item; collectionName = item.name } } }
            }
            Section("文件") {
                ForEach(files.filter { (selectedCollectionID.isEmpty || $0.knowledgeID == selectedCollectionID) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { file in
                    Button { selectedFile = file; Task { await preview(file) } } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(file.name).foregroundStyle(.primary); Text(file.status ?? "已导入").font(.caption).foregroundStyle(.secondary) }
                    }.contextMenu { Menu("移动到") { ForEach(collections.filter { $0.id != file.knowledgeID }) { collection in Button(collection.name) { Task { await assign(file, to: collection.id) } } } } }.swipeActions {
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
        .alert("重命名集合", isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } })) { TextField("集合名称", text: $collectionName); Button("保存") { Task { await renameCollection() } }; Button("取消", role: .cancel) { renamingCollection = nil } }
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
            let target = selectedCollectionID.isEmpty ? collections.first?.id : selectedCollectionID
            if let target { let _: EmptyResponse = try await session.send("ai-api/files/assign", method: "POST", body: ["file_id": response.file.id, "knowledge_id": target], allowEmpty: true) }
            await load()
        } catch { self.error = session.message(for: error) }
    }
    private func preview(_ file: KnowledgeFile) async { do { detail = try await session.get("ai-api/files/detail?id=\(file.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file.id)") } catch { self.error = session.message(for: error) } }
    private func reprocess(_ file: KnowledgeFile) async { do { let _: EmptyResponse = try await session.send("ai-api/files/reprocess", method: "POST", body: ["id": file.id], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func assign(_ file: KnowledgeFile, to knowledgeID: String) async { do { let _: EmptyResponse = try await session.send("ai-api/files/assign", method: "POST", body: ["file_id": file.id, "knowledge_id": knowledgeID], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
    private func renameCollection() async { guard let item = renamingCollection else { return }; do { let _: EmptyResponse = try await session.send("ai-api/knowledge", method: "POST", body: ["id": item.id, "name": collectionName], allowEmpty: true); renamingCollection = nil; await load() } catch { self.error = session.message(for: error) } }
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
    @State private var shares: [AIShare] = []; @State private var query = ""
    @AppStorage("ai-monthly-budget") private var monthlyBudget = 0.0
    @State private var loading = false; @State private var error: String?
    @State private var editingMemory: AIMemory?; @State private var showingMemory = false
    @State private var editingWorkflow: AIWorkflow?; @State private var showingWorkflow = false
    @State private var runWorkflow: AIWorkflow?; @State private var runInput = ""

    var body: some View { VStack(spacing: 0) {
        Picker("运营", selection: $section) { ForEach(OperationsSection.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding()
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if section == .usage {
                if let summary { Section { HStack { Metric(title: "调用", value: "\(summary.calls)"); Metric(title: "输入 Token", value: "\(summary.inputTokens)"); Metric(title: "输出 Token", value: "\(summary.outputTokens)") }; LabeledContent("累计费用", value: String(format: "¥ %.4f", summary.cost)); HStack { Text("月度预算"); Spacer(); TextField("0", value: $monthlyBudget, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }; if monthlyBudget > 0 { ProgressView(value: min(summary.cost / monthlyBudget, 1)); Text(String(format: "已使用 %.1f%%", summary.cost / monthlyBudget * 100)).font(.caption).foregroundStyle(.secondary) } } }
                ForEach(usage.filter { query.isEmpty || "\($0.operation) \($0.modelID ?? "")".localizedCaseInsensitiveContains(query) }) { item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.operation).fontWeight(.medium); Spacer(); Text("\(item.inputTokens + item.outputTokens) Token").font(.caption) }; Text("\(item.modelID.flatMap { $0.isEmpty ? nil : $0 } ?? "默认模型") · \(item.latencyMS) ms").font(.caption).foregroundStyle(.secondary) } }
            } else if section == .memory {
                ForEach(memories) { item in VStack(alignment: .leading, spacing: 6) { Text(item.content); HStack { Text(item.sourceChatID?.isEmpty == false ? "来自会话" : "手动添加").font(.caption).foregroundStyle(.secondary); Spacer(); Toggle("", isOn: Binding(get: { item.enabled != 0 }, set: { enabled in Task { await toggleMemory(item, enabled) } })).labelsHidden() } }.contentShape(Rectangle()).onTapGesture { editingMemory = item; showingMemory = true }.swipeActions { Button("删除", role: .destructive) { Task { await deleteMemory(item) } } } }
            } else if section == .workflow {
                ForEach(workflows) { item in VStack(alignment: .leading, spacing: 6) { HStack { Text(item.name).fontWeight(.medium); Spacer(); StatusBadge(text: item.enabled != 0 ? "启用" : "停用", done: item.enabled != 0) }; Text(item.description).font(.caption).foregroundStyle(.secondary) }.contentShape(Rectangle()).onTapGesture { editingWorkflow = item; showingWorkflow = true }.swipeActions { Button("运行") { runWorkflow = item }.tint(.green); Button("删除", role: .destructive) { Task { await deleteWorkflow(item) } } } }
            } else if section == .jobs {
                ForEach(jobs) { item in
                    NavigationLink {
                        List {
                            LabeledContent("类型", value: item.kind)
                            LabeledContent("状态", value: jobStatus(item.status))
                            Section("结果") {
                                Text(item.resultText).textSelection(.enabled)
                            }
                        }
                        .navigationTitle("任务详情")
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.kind).fontWeight(.medium)
                                Spacer()
                                Text(jobStatus(item.status)).foregroundStyle(jobColor(item.status))
                            }
                            Text(item.resultText).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .swipeActions {
                        if ["queued", "running"].contains(item.status) {
                            Button("取消") { Task { await jobAction(item, "cancel") } }.tint(.orange)
                        } else {
                            Button("重试") { Task { await jobAction(item, "retry") } }.tint(.blue)
                            Button("删除", role: .destructive) { Task { await jobAction(item, "delete") } }
                        }
                    }
                }
            } else {
                ForEach(shares) { item in ShareLink(item: URL(string: "https://xiaoxu666.asia/ai/shared/\(item.id)")!) { VStack(alignment: .leading, spacing: 5) { Text(item.title).foregroundStyle(.primary).fontWeight(.medium); Text(shortDate(item.createdAt)).font(.caption).foregroundStyle(.secondary) } } }
            }
        }
    }.navigationTitle("AI 运营").searchable(text: $query, prompt: "搜索用量记录").overlay { if loading && usage.isEmpty && memories.isEmpty && workflows.isEmpty && jobs.isEmpty && shares.isEmpty { ProgressView() } }.task(id: section) { await load() }.refreshable { await load() }
        .toolbar { if section == .memory { Button { editingMemory = nil; showingMemory = true } label: { Image(systemName: "plus") } } else if section == .workflow { Button { editingWorkflow = nil; showingWorkflow = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingMemory) { MemoryForm(item: editingMemory) { await load() } }
        .sheet(isPresented: $showingWorkflow) { WorkflowForm(item: editingWorkflow) { await load() } }
        .alert("运行工作流", isPresented: Binding(get: { runWorkflow != nil }, set: { if !$0 { runWorkflow = nil } })) { TextField("输入内容", text: $runInput); Button("运行") { if let workflow = runWorkflow { Task { await run(workflow) } } }; Button("取消", role: .cancel) { runWorkflow = nil } } message: { Text("输入工作流处理内容") }
    }
    private func load() async { loading = true; error = nil; defer { loading = false }; do { switch section { case .usage: let result: UsageResponse = try await session.get("ai-api/usage"); usage = result.usage; summary = result.summary; case .memory: let result: MemoriesResponse = try await session.get("ai-api/memories"); memories = result.memories; case .workflow: let result: WorkflowsResponse = try await session.get("ai-api/workflows"); workflows = result.workflows; case .jobs: let result: JobsResponse = try await session.get("ai-api/jobs"); jobs = result.jobs; case .shares: let result: SharesResponse = try await session.get("ai-api/shares"); shares = result.shares } } catch { self.error = session.message(for: error) } }
    private func toggleMemory(_ item: AIMemory, _ enabled: Bool) async { do { let _: EmptyResponse = try await session.send("ai-api/memories", method: "POST", body: ["id": item.id, "content": item.content, "source_chat_id": item.sourceChatID ?? "", "enabled": enabled], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
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
    let item: CompanyExpense; @State private var copiedField: String?
    private var fields: [NativeCopyField] { [.init(label: "流水号", value: item.expenseNo), .init(label: "金额", value: money(item.amount)), .init(label: "分类", value: item.category), .init(label: "付款账户", value: item.paymentAccount), .init(label: "消费日期", value: item.expenseDate), .init(label: "提交人", value: item.submitterName), .init(label: "消费范围", value: item.expenseScope), .init(label: "说明", value: item.description.isEmpty ? "无" : item.description)] }
    var body: some View { List { Section("流水资料") { ForEach(fields) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } } }.navigationTitle(item.expenseNo).navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: fields, copiedField: $copiedField) } }
}

struct Metric: View {
    let title: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72) }.frame(maxWidth: .infinity, alignment: .leading) }
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
    @State private var editingWarehouse: WarehouseRecord?; @State private var editingProduct: WarehouseProduct?
    var body: some View {
        List {
            if let summary { Section { ScrollView(.horizontal, showsIndicators: false) { HStack { WarehouseMetric("总库存", "\(summary.totalQuantity)"); WarehouseMetric("库存成本", money(summary.totalCost)); WarehouseMetric("低库存", "\(summary.lowStockCount)"); WarehouseMetric("待出库", "\(summary.pendingOutboundCount)") }.padding(.vertical, 4) } } }
            Section { Picker("分类", selection: $tab) { ForEach(WarehouseTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu) }
            if let error { Text(error).foregroundStyle(.red) }
            switch tab {
            case .stocks: ForEach(stocks.filter { matches("\($0.sku) \($0.productName) \($0.warehouseName)") }) { row in HStack(spacing: 11) { NativeRemoteImage(url: row.imageURL, size: 48); VStack(alignment: .leading) { Text(row.productName).fontWeight(.medium); Text("\(row.sku) · \(row.warehouseName)").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text("\(row.availableQuantity) \(row.unit)").foregroundStyle(row.isLowStock ? .red : .primary); if row.lockedQuantity > 0 { Text("锁定 \(row.lockedQuantity)").font(.caption2).foregroundStyle(.orange) } } } }
            case .products: ForEach(products.filter { matches("\($0.sku) \($0.name) \($0.barcode ?? "")") }) { row in HStack(spacing: 11) { NativeRemoteImage(url: row.imageURL, size: 48); WarehouseTextRow(title: row.name, detail: "\(row.sku) · \(row.specification ?? row.unit) · \(money(row.costPrice))", status: row.isActive ? "启用" : "停用") }.swipeActions { Button("删除", role: .destructive) { Task { await deleteProduct(row) } }; Button("编辑") { editingProduct = row; sheet = .product }.tint(.blue) } }
            case .warehouses: ForEach(warehouses.filter { matches("\($0.code) \($0.name) \($0.address ?? "")") }) { row in WarehouseTextRow(title: row.name, detail: "\(row.code) · \(row.address ?? "未填写地址")", status: row.isActive ? "启用" : "停用").swipeActions { Button("删除", role: .destructive) { Task { await deleteWarehouse(row) } }; Button("编辑") { editingWarehouse = row; sheet = .warehouse }.tint(.blue) } }
            case .inbound: ForEach(inbound.filter { matches("\($0.orderNo) \($0.warehouseName) \(lineSummary($0.items))") }) { row in WarehouseTextRow(title: row.orderNo, detail: "\(row.warehouseName) · \(lineSummary(row.items))", status: row.status == "completed" ? "已入库" : "已撤销").swipeActions { if row.status == "completed" { Button("撤销", role: .destructive) { Task { await cancel(row) } } } } }
            case .outbound: ForEach(outbound.filter { matches("\($0.orderNo) \($0.warehouseName) \($0.trackingNo ?? "")") }) { row in NavigationLink { WarehouseOutboundDetail(row: row) } label: { WarehouseTextRow(title: row.orderNo, detail: "\(row.warehouseName) · \(lineSummary(row.items))", status: outboundStatus(row.status)) }.swipeActions { if let next = nextStatus(row.status) { Button("推进") { Task { await setStatus(row, next) } }.tint(.blue) }; if !["shipped","cancelled"].contains(row.status) { Button("取消", role: .destructive) { Task { await setStatus(row, "cancelled") } } } } }
            case .movements: ForEach(movements.filter { matches("\($0.sku) \($0.productName) \($0.warehouseName) \($0.referenceNo)") }) { row in HStack { VStack(alignment: .leading) { Text(row.productName); Text("\(row.warehouseName) · \(row.referenceNo)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(row.quantityChange > 0 ? "+\(row.quantityChange)" : "\(row.quantityChange)").foregroundStyle(row.quantityChange > 0 ? .green : .red) } }
            }
        }.navigationTitle("仓储管理").searchable(text: $query, prompt: "搜索商品、单号或仓库").overlay { if loading && stocks.isEmpty { ProgressView() } }.task { await load() }.refreshable { await load() }
        .toolbar { if [.warehouses,.products,.inbound,.outbound].contains(tab) { Button { editingWarehouse = nil; editingProduct = nil; sheet = tab == .warehouses ? .warehouse : tab == .products ? .product : tab == .inbound ? .inbound : .outbound } label: { Image(systemName: "plus") } } }
        .sheet(item: $sheet) { value in switch value { case .warehouse: WarehouseBasicEditor(kind: .warehouse, warehouse: editingWarehouse, product: nil) { await load() }; case .product: WarehouseBasicEditor(kind: .product, warehouse: nil, product: editingProduct) { await load() }; case .inbound: WarehouseOrderEditor(outbound: false, warehouses: warehouses, products: products) { await load() }; case .outbound: WarehouseOrderEditor(outbound: true, warehouses: warehouses, products: products) { await load() } } }
    }
    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedCaseInsensitiveContains(query) }
    private func load() async { loading = true; defer { loading = false }; do { async let a: WarehouseSummary = session.get("warehouse/summary"); async let b: [WarehouseRecord] = session.get("warehouse/warehouses"); async let c: [WarehouseProduct] = session.get("warehouse/products"); async let d: [WarehouseStock] = session.get("warehouse/stocks"); async let e: [WarehouseInbound] = session.get("warehouse/inbound-orders"); async let f: [WarehouseOutbound] = session.get("warehouse/outbound-orders"); async let g: [WarehouseMovement] = session.get("warehouse/movements"); (summary,warehouses,products,stocks,inbound,outbound,movements) = try await (a,b,c,d,e,f,g); prefetchProductImages() } catch { self.error = session.message(for: error) } }
    private func prefetchProductImages() { let requests = products.prefix(12).compactMap { product -> (URL, CGFloat)? in guard let value = product.imageURL, let url = nativeThumbnailURL(value, maxPixelSize: 144) else { return nil }; return (url, 144) }; Task(priority: .utility) { await NativeImagePipeline.shared.prefetch(requests) } }
    private func cancel(_ row: WarehouseInbound) async { do { let _: WarehouseInbound = try await session.send("warehouse/inbound-orders/\(row.id)", method: "DELETE"); await load() } catch { self.error = session.message(for: error) } }
    private func setStatus(_ row: WarehouseOutbound, _ status: String) async { do { let _: WarehouseOutbound = try await session.send("warehouse/outbound-orders/\(row.id)/status", method: "PATCH", body: ["status":status,"carrier":row.carrier ?? "","tracking_no":row.trackingNo ?? ""]); await load() } catch { self.error = session.message(for: error) } }
    private func deleteWarehouse(_ row: WarehouseRecord) async { do { try await session.delete("warehouse/warehouses/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
    private func deleteProduct(_ row: WarehouseProduct) async { do { try await session.delete("warehouse/products/\(row.id)"); await load() } catch { self.error = session.message(for: error) } }
}
private struct WarehouseMetric: View { let title:String,value:String; init(_ title:String,_ value:String){self.title=title;self.value=value}; var body:some View{VStack(alignment:.leading){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.headline)}.padding(12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:8))} }
private struct WarehouseTextRow: View { let title:String,detail:String,status:String; var body:some View{VStack(alignment:.leading,spacing:5){HStack{Text(title).fontWeight(.medium);Spacer();Text(status).foregroundStyle(.secondary)};Text(detail).font(.caption).foregroundStyle(.secondary)}} }
private struct WarehouseOutboundDetail: View {
    let row: WarehouseOutbound; @State private var copiedField: String?
    private var fields: [NativeCopyField] { var result = [NativeCopyField(label: "出库单号", value: row.orderNo), .init(label: "仓库", value: row.warehouseName), .init(label: "状态", value: outboundStatus(row.status))]; if let external = row.externalOrderNo, !external.isEmpty { result.append(.init(label: "平台订单", value: external)) }; result.append(contentsOf: [.init(label: "收件人", value: row.recipientName ?? "-"), .init(label: "联系电话", value: row.recipientPhone ?? "-"), .init(label: "地址", value: row.recipientAddress ?? "-"), .init(label: "快递", value: row.carrier ?? "-"), .init(label: "物流单号", value: row.trackingNo ?? "-")]); for (index, item) in row.items.enumerated() { result.append(.init(label: "商品\(index + 1)", value: "\(item.sku) · \(item.productName) × \(item.quantity) \(item.unit)")) }; return result }
    private var orderCount: Int { 3 + ((row.externalOrderNo?.isEmpty == false) ? 1 : 0) }
    var body: some View { List { Section("订单") { ForEach(fields.prefix(orderCount)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } }; Section("收货信息") { ForEach(fields.dropFirst(orderCount).prefix(5)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } }; Section("商品") { ForEach(fields.dropFirst(orderCount + 5)) { field in NativeCopyRow(label: field.label, value: field.value, copiedField: $copiedField) } } }.navigationTitle("出库详情").navigationBarTitleDisplayMode(.inline).toolbar { NativeCopyAllButton(fields: fields, copiedField: $copiedField) } }
}

private struct WarehouseBasicEditor: View {
    enum Kind { case warehouse, product }; @EnvironmentObject private var session:NativeSession; @Environment(\.dismiss) private var dismiss; let kind:Kind; let warehouse: WarehouseRecord?; let product: WarehouseProduct?; let onSave:() async->Void
    @State private var code:String; @State private var name:String; @State private var extra:String; @State private var unit:String; @State private var price:String; @State private var warning:Int; @State private var enabled:Bool; @State private var error:String?
    init(kind:Kind,warehouse:WarehouseRecord?,product:WarehouseProduct?,onSave:@escaping()async->Void){self.kind=kind;self.warehouse=warehouse;self.product=product;self.onSave=onSave;_code=State(initialValue:warehouse?.code ?? product?.sku ?? "");_name=State(initialValue:warehouse?.name ?? product?.name ?? "");_extra=State(initialValue:warehouse?.address ?? product?.barcode ?? "");_unit=State(initialValue:product?.unit ?? "件");_price=State(initialValue:product.map{String($0.costPrice)} ?? "0");_warning=State(initialValue:product?.warningQuantity ?? 0);_enabled=State(initialValue:warehouse?.isActive ?? product?.isActive ?? true)}
    var body:some View{NavigationStack{Form{if let error{Text(error).foregroundStyle(.red)};TextField(kind == .warehouse ? "仓库编码":"SKU",text:$code).textInputAutocapitalization(.characters);TextField(kind == .warehouse ? "仓库名称":"商品名称",text:$name);TextField(kind == .warehouse ? "地址":"条码",text:$extra);if kind == .product{TextField("单位",text:$unit);TextField("成本价",text:$price).keyboardType(.decimalPad);Stepper("预警库存：\(warning)",value:$warning,in:0...999999)};Toggle("启用",isOn:$enabled)}.navigationTitle((warehouse != nil || product != nil) ? "编辑资料" : (kind == .warehouse ? "新增仓库":"新增商品")).toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("保存"){Task{await save()}}.disabled(code.isEmpty || name.isEmpty)}}}}
    private func save()async{do{if kind == .warehouse{let path=warehouse.map{"warehouse/warehouses/\($0.id)"} ?? "warehouse/warehouses";let _:WarehouseRecord=try await session.send(path,method:warehouse == nil ? "POST":"PUT",body:["code":code,"name":name,"address":extra,"contact_name":warehouse?.contactName ?? "","contact_phone":warehouse?.contactPhone ?? "","is_active":enabled,"remark":warehouse?.remark ?? ""])}else{let path=product.map{"warehouse/products/\($0.id)"} ?? "warehouse/products";let _:WarehouseProduct=try await session.send(path,method:product == nil ? "POST":"PUT",body:["sku":code,"name":name,"barcode":extra,"specification":product?.specification ?? "","unit":unit,"cost_price":Double(price) ?? 0,"warning_quantity":warning,"is_active":enabled,"remark":product?.remark ?? ""])};await onSave();dismiss()}catch{self.error=session.message(for:error)}}
}
private struct WarehouseOrderEditor: View {
    @EnvironmentObject private var session:NativeSession; @Environment(\.dismiss) private var dismiss; let outbound:Bool; let warehouses:[WarehouseRecord]; let products:[WarehouseProduct]; let onSave:() async->Void
    @State private var warehouseID=0;@State private var lines:[WarehouseDraftLine]=[WarehouseDraftLine()];@State private var source="purchase";@State private var recipient="";@State private var phone="";@State private var address="";@State private var carrier="";@State private var trackingNo="";@State private var remark="";@State private var error:String?
    var body:some View{NavigationStack{Form{if let error{Text(error).foregroundStyle(.red)};Picker("仓库",selection:$warehouseID){Text("请选择").tag(0);ForEach(warehouses.filter(\.isActive)){Text($0.name).tag($0.id)}};Section("商品明细"){ForEach($lines){$line in VStack{Picker("商品",selection:$line.productID){Text("请选择").tag(0);ForEach(products.filter(\.isActive)){Text("\($0.sku) · \($0.name)").tag($0.id)}};Stepper("数量：\(line.quantity)",value:$line.quantity,in:1...999999)}.swipeActions{if lines.count>1{Button("删除",role:.destructive){lines.removeAll{$0.id==line.id}}}}};Button{lines.append(WarehouseDraftLine())}label:{Label("添加商品",systemImage:"plus")}};if outbound{Section("收货信息"){TextField("收件人",text:$recipient);TextField("联系电话",text:$phone).keyboardType(.phonePad);TextField("收货地址",text:$address);TextField("快递公司（可选）",text:$carrier);TextField("物流单号（可选）",text:$trackingNo)}}else{Picker("入库类型",selection:$source){Text("采购入库").tag("purchase");Text("退货入库").tag("return");Text("其他入库").tag("other")}};TextField("备注",text:$remark,axis:.vertical)}.navigationTitle(outbound ? "新建出库单":"商品入库").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("提交"){Task{await save()}}.disabled(warehouseID == 0 || lines.contains{$0.productID==0})}}}}
    private func save()async{var body:[String:Any]=["warehouse_id":warehouseID,"items":lines.map{["product_id":$0.productID,"quantity":$0.quantity]},"remark":remark];do{if outbound{body.merge(["external_order_no":"","delivery_method":"shipping","recipient_name":recipient,"recipient_phone":phone,"recipient_address":address,"carrier":carrier,"tracking_no":trackingNo]){_,new in new};let _:WarehouseOutbound=try await session.send("warehouse/outbound-orders",method:"POST",body:body)}else{body["source_type"]=source;body["supplier"]="";let _:WarehouseInbound=try await session.send("warehouse/inbound-orders",method:"POST",body:body)};await onSave();dismiss()}catch{self.error=session.message(for:error)}}
}
private struct WarehouseDraftLine: Identifiable { let id=UUID(); var productID=0; var quantity=1 }

private extension View {
    func nativeField() -> some View { padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct AIChatMessage: Codable, Identifiable {
    let id: String; let role: String; var content: String
    init(id: String = UUID().uuidString, role: String, content: String) { self.id = id; self.role = role; self.content = content }
}
private struct AIChat: Codable, Identifiable {
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

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(title, forKey: .title); try values.encode(messages, forKey: .messages)
        try values.encodeIfPresent(modelID, forKey: .modelID); try values.encode(favorite, forKey: .favorite); try values.encode(archived, forKey: .archived); try values.encode(folder, forKey: .folder)
        try values.encode(Int(createdAt), forKey: .createdAt); try values.encode(Int(updatedAt), forKey: .updatedAt)
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
private enum OperationsSection: String, CaseIterable, Identifiable { case usage, memory, workflow, jobs, shares; var id: String { rawValue }; var title: String { switch self { case .usage: return "用量"; case .memory: return "记忆"; case .workflow: return "工作流"; case .jobs: return "任务"; case .shares: return "分享" } } }
private struct UsageRecord: Codable, Identifiable {
    let id: String; let operation: String; let modelID: String?; let inputTokens: Int; let outputTokens: Int; let latencyMS: Int
    enum CodingKeys: String, CodingKey { case id, operation; case modelID = "model_id"; case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case latencyMS = "latency_ms" }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString; operation = try c.decodeIfPresent(String.self, forKey: .operation) ?? "AI 调用"; modelID = try c.decodeIfPresent(String.self, forKey: .modelID); inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0; outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0; latencyMS = try c.decodeIfPresent(Int.self, forKey: .latencyMS) ?? 0 }
}

private struct ShopFieldsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var fields: [ShopField] = []; @State private var showingNew = false; @State private var error: String?
    var body: some View { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(Array(fields.enumerated()), id: \.offset) { index, field in VStack(alignment: .leading, spacing: 8) { HStack { VStack(alignment: .leading) { Text(field.label).fontWeight(.medium); Text("\(field.fieldName) · \(fieldTypeLabel(field.fieldType))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("显示", isOn: Binding(get: { field.isVisible }, set: { update(field, ["is_visible": $0]) })).labelsHidden() }; Toggle("必填", isOn: Binding(get: { field.required }, set: { update(field, ["required": $0]) })); HStack { Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0); Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == fields.count - 1); Spacer(); if field.isBuiltin != true { Button("删除", role: .destructive) { Task { await remove(field) } } } } }.padding(.vertical, 4) } }.navigationTitle("店铺字段").task { await load() }.refreshable { await load() }.toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showingNew) { ShopFieldForm { await load() } } }
    private func load() async { do { fields = try await session.get("custom-fields"); fields.sort { $0.sortOrder < $1.sortOrder } } catch { self.error = session.message(for: error) } }
    private func update(_ field: ShopField, _ body: [String: Any]) { Task { do { let _: ShopField = try await session.send("custom-fields/\(field.id)", method: "PATCH", body: body); await load() } catch { self.error = session.message(for: error) } } }
    private func move(_ index: Int, _ offset: Int) { let target = index + offset; guard fields.indices.contains(target) else { return }; fields.swapAt(index, target); let ids = fields.map(\.id); Task { do { let _: EmptyResponse = try await session.send("custom-fields/reorder", method: "POST", body: ["field_ids": ids], allowEmpty: true) } catch { self.error = session.message(for: error); await load() } } }
    private func remove(_ field: ShopField) async { do { try await session.delete("custom-fields/\(field.id)"); await load() } catch { self.error = session.message(for: error) } }
    private func fieldTypeLabel(_ value: String) -> String { ["text":"文本","number":"数字","date":"日期"][value] ?? value }
}

private struct ShopFieldForm: View {
    @EnvironmentObject private var session: NativeSession; @Environment(\.dismiss) private var dismiss; let onSave: () async -> Void
    @State private var label = ""; @State private var name = ""; @State private var type = "text"; @State private var error: String?
    var body: some View { NavigationStack { Form { if let error { Text(error).foregroundStyle(.red) }; TextField("字段名称", text: $label); TextField("英文标识", text: $name).textInputAutocapitalization(.never); Picker("类型", selection: $type) { Text("文本").tag("text"); Text("数字").tag("number"); Text("日期").tag("date") } }.navigationTitle("新增字段").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("新增") { Task { await save() } }.disabled(label.isEmpty || name.isEmpty) } } } }
    private func save() async { do { let _: ShopField = try await session.send("custom-fields", method: "POST", body: ["label":label,"field_name":name,"field_type":type,"required":false]); await onSave(); dismiss() } catch { self.error = session.message(for: error) } }
}
private struct UsageSummary: Codable { let calls: Int; let inputTokens: Int; let outputTokens: Int; let cost: Double; enum CodingKeys: String, CodingKey { case calls, cost; case inputTokens = "input_tokens"; case outputTokens = "output_tokens" }; init(calls: Int, inputTokens: Int, outputTokens: Int, cost: Double) { self.calls = calls; self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cost = cost }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0; inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0; outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0; cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0 } }
private struct UsageResponse: Codable { let usage: [UsageRecord]; let summary: UsageSummary; enum CodingKeys: CodingKey { case usage, summary }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); usage = try c.decodeIfPresent([UsageRecord].self, forKey: .usage) ?? []; summary = try c.decodeIfPresent(UsageSummary.self, forKey: .summary) ?? UsageSummary(calls: 0, inputTokens: 0, outputTokens: 0, cost: 0) } }
private struct AIMemory: Codable, Identifiable { let id: String; let content: String; let sourceChatID: String?; let enabled: Int; enum CodingKeys: String, CodingKey { case id, content, enabled; case sourceChatID = "source_chat_id" }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString; content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""; sourceChatID = try c.decodeIfPresent(String.self, forKey: .sourceChatID); enabled = (try? c.decode(Int.self, forKey: .enabled)) ?? ((try? c.decode(Bool.self, forKey: .enabled)) == true ? 1 : 0) } }
private struct MemoriesResponse: Codable { let memories: [AIMemory]; enum CodingKeys: CodingKey { case memories }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); memories = try c.decodeIfPresent([AIMemory].self, forKey: .memories) ?? [] } }
private struct AIWorkflow: Codable, Identifiable {
    let id: String; let name: String; let description: String; let steps: String; let enabled: Int
    var firstPrompt: String { guard let data = steps.data(using: .utf8), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return "" }; return rows.first?["content"] as? String ?? "" }
    enum CodingKeys: CodingKey { case id, name, description, steps, enabled }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString; name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名工作流"; description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""; if let value = try? c.decode(String.self, forKey: .steps) { steps = value } else if let value = try? c.decode([[String: JSONValue]].self, forKey: .steps), let data = try? JSONEncoder().encode(value) { steps = String(data: data, encoding: .utf8) ?? "[]" } else { steps = "[]" }; enabled = (try? c.decode(Int.self, forKey: .enabled)) ?? ((try? c.decode(Bool.self, forKey: .enabled)) == true ? 1 : 0) }
}
private struct WorkflowsResponse: Codable { let workflows: [AIWorkflow]; enum CodingKeys: CodingKey { case workflows }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); workflows = try c.decodeIfPresent([AIWorkflow].self, forKey: .workflows) ?? [] } }
private struct AIJob: Codable, Identifiable {
    let id: String; let kind: String; let status: String; let output: String?; let error: String?
    var resultText: String { if let error, !error.isEmpty { return error }; guard let output, !output.isEmpty else { return "暂无结果" }; if let data = output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let result = object["result"] { return String(describing: result) }; return output }
    enum CodingKeys: CodingKey { case id, kind, status, output, error }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString; kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "AI 任务"; status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"; output = try c.decodeIfPresent(String.self, forKey: .output); error = try c.decodeIfPresent(String.self, forKey: .error) }
}
private struct JobsResponse: Codable { let jobs: [AIJob]; enum CodingKeys: CodingKey { case jobs }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); jobs = try c.decodeIfPresent([AIJob].self, forKey: .jobs) ?? [] } }
private struct AIShare: Decodable, Identifiable { let id: String; let title: String; let createdAt: String?; enum CodingKeys: String, CodingKey { case id, title; case createdAt = "created_at" }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString; title = try c.decodeIfPresent(String.self, forKey: .title) ?? "共享会话"; createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) } }
private struct SharesResponse: Decodable { let shares: [AIShare]; enum CodingKeys: CodingKey { case shares }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); shares = try c.decodeIfPresent([AIShare].self, forKey: .shares) ?? [] } }
private struct JobActionResponse: Codable { let jobID: String?; let status: String?; enum CodingKeys: String, CodingKey { case status; case jobID = "job_id" } }
private struct ShopField: Codable, Identifiable { let id: Int; let fieldName: String; let label: String; let fieldType: String; let required: Bool; let sortOrder: Int; let isVisible: Bool; let isBuiltin: Bool?; enum CodingKeys: String, CodingKey { case id, label, required; case fieldName = "field_name"; case fieldType = "field_type"; case sortOrder = "sort_order"; case isVisible = "is_visible"; case isBuiltin = "is_builtin" } }
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
private struct PeerShopRecord: Codable, Identifiable { let id: Int; let shopName: String; let shopURL: String?; let remark: String?; let imageURL: String?; enum CodingKeys: String, CodingKey { case id, remark; case shopName = "shop_name"; case shopURL = "shop_url"; case imageURL = "image_url" } }
private struct LicenseRecordItem: Codable, Identifiable { let id: Int; let subjectName: String; let creditCode: String; let legalRepresentative: String?; let issueDate: String?; let expiryDate: String?; let remark: String?; let imageURL: String?; enum CodingKeys: String, CodingKey { case id, remark; case subjectName = "subject_name"; case creditCode = "credit_code"; case legalRepresentative = "legal_representative"; case issueDate = "issue_date"; case expiryDate = "expiry_date"; case imageURL = "image_url" } }
private struct MobileDevice: Codable, Identifiable { let id: Int; let deviceName: String; let primaryCard: String?; let secondaryCard: String?; let remark: String?; enum CodingKeys: String, CodingKey { case id, remark; case deviceName = "device_name"; case primaryCard = "primary_card"; case secondaryCard = "secondary_card" } }
private struct AccountUsage: Codable, Identifiable { let id: Int; let accountName: String; let phoneNumber: String?; let deviceName: String?; let usageNotes: String?; let isBanned: Bool; let bannedReason: String?; enum CodingKeys: String, CodingKey { case id; case accountName = "account_name"; case phoneNumber = "phone_number"; case deviceName = "device_name"; case usageNotes = "usage_notes"; case isBanned = "is_banned"; case bannedReason = "banned_reason" } }
private struct WarehouseSummary: Codable { let warehouseCount:Int;let productCount:Int;let totalQuantity:Int;let totalCost:Double;let lowStockCount:Int;let pendingOutboundCount:Int;let todayInboundQuantity:Int;let todayOutboundQuantity:Int; enum CodingKeys:String,CodingKey{case warehouseCount="warehouse_count",productCount="product_count",totalQuantity="total_quantity",totalCost="total_cost",lowStockCount="low_stock_count",pendingOutboundCount="pending_outbound_count",todayInboundQuantity="today_inbound_quantity",todayOutboundQuantity="today_outbound_quantity"} }
private struct WarehouseRecord: Codable, Identifiable { let id:Int;let code:String;let name:String;let address:String?;let contactName:String?;let contactPhone:String?;let isActive:Bool;let remark:String?; enum CodingKeys:String,CodingKey{case id,code,name,address,remark;case contactName="contact_name",contactPhone="contact_phone",isActive="is_active"} }
private struct WarehouseProduct: Codable, Identifiable { let id:Int;let sku:String;let name:String;let barcode:String?;let specification:String?;let unit:String;let costPrice:Double;let warningQuantity:Int;let isActive:Bool;let remark:String?;let imageURL:String?; enum CodingKeys:String,CodingKey{case id,sku,name,barcode,specification,unit,remark;case costPrice="cost_price",warningQuantity="warning_quantity",isActive="is_active",imageURL="image_url"} }
private struct WarehouseStock: Codable, Identifiable { var id:String{"\(warehouseID)-\(productID)"};let warehouseID:Int;let warehouseName:String;let productID:Int;let sku:String;let productName:String;let unit:String;let quantity:Int;let lockedQuantity:Int;let availableQuantity:Int;let isLowStock:Bool;let imageURL:String?; enum CodingKeys:String,CodingKey{case sku,unit,quantity;case warehouseID="warehouse_id",warehouseName="warehouse_name",productID="product_id",productName="product_name",lockedQuantity="locked_quantity",availableQuantity="available_quantity",isLowStock="is_low_stock",imageURL="image_url"} }
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
    let totalRecords: Int; let principalTotal: Double; let commissionTotal: Double; let giftTotal: Double
    let pendingSignedCount: Int; let pendingSettlementCount: Int
    enum CodingKeys: String, CodingKey { case totalRecords = "total_records"; case principalTotal = "principal_total"; case commissionTotal = "commission_total"; case giftTotal = "gift_total"; case pendingSignedCount = "pending_signed_count"; case pendingSettlementCount = "pending_settlement_count" }
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
private func savedLinkIsArticle(_ item: SavedLink) -> Bool {
    item.category?.lowercased().hasPrefix("tutorial:") == true
}
private func savedLinkPlainText(_ value: String?) -> String {
    guard var text = value, !text.isEmpty else { return "" }
    text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
    text = text.replacingOccurrences(of: #":::\s*align-center\s*"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"(?m)^\s*:::\s*$"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(?:#{1,6}\s+|>\s+|[-*]\s+\[[ xX]\]\s+|[-*]\s+|\d+\.\s+)"#, with: "", options: .regularExpression)
    for marker in ["**", "~~", "`", "*"] { text = text.replacingOccurrences(of: marker, with: "") }
    text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
private struct ExpenseCategoriesResponse: Codable { let categories: [String]; let isDefault: Bool?; let usage: [String: Int]?; enum CodingKeys: String, CodingKey { case categories, usage; case isDefault = "is_default" } }
private func savedLinkMarkdown(_ value: String?) -> AttributedString {
    let source = value ?? ""
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
}

private enum SavedLinkArticleBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case quote(String)
    case bullet(String)
    case numbered(number: String, text: String)
    case checklist(checked: Bool, text: String)
    case centered(String)
}

private func savedLinkArticleBlocks(_ source: String) -> [SavedLinkArticleBlock] {
    var blocks: [SavedLinkArticleBlock] = []
    var paragraph: [String] = []
    var centered: [String] = []
    var isCentering = false

    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph.removeAll()
    }

    func flushCenter() {
        guard !centered.isEmpty else { return }
        blocks.append(.centered(centered.joined(separator: "\n")))
        centered.removeAll()
    }

    for line in source.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if isCentering {
            if trimmed == ":::" {
                flushCenter()
                isCentering = false
            } else {
                centered.append(line)
            }
            continue
        }
        if trimmed == "::: align-center" {
            flushParagraph()
            isCentering = true
        } else if trimmed.isEmpty {
            flushParagraph()
        } else if trimmed.hasPrefix("## ") {
            flushParagraph()
            blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
        } else if trimmed.hasPrefix("# ") {
            flushParagraph()
            blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
        } else if trimmed.hasPrefix("> ") {
            flushParagraph()
            blocks.append(.quote(String(trimmed.dropFirst(2))))
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.lowercased().hasPrefix("- [x] ") {
            flushParagraph()
            blocks.append(.checklist(checked: trimmed.lowercased().hasPrefix("- [x] "), text: String(trimmed.dropFirst(6))))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            flushParagraph()
            blocks.append(.bullet(String(trimmed.dropFirst(2))))
        } else if let marker = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            flushParagraph()
            let prefix = String(trimmed[..<marker.upperBound])
            let number = prefix.split(separator: ".").first.map(String.init) ?? ""
            blocks.append(.numbered(number: number, text: String(trimmed[marker.upperBound...])))
        } else {
            paragraph.append(line)
        }
    }
    flushParagraph()
    if isCentering { flushCenter() }
    return blocks
}

private struct SavedLinkArticleBlockView: View {
    let block: SavedLinkArticleBlock

    @ViewBuilder var body: some View {
        switch block {
        case .paragraph(let text):
            Text(savedLinkMarkdown(text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(savedLinkMarkdown(text))
                .font(level == 1 ? .title2.bold() : .title3.bold())
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.45)).frame(width: 3)
                Text(savedLinkMarkdown(text)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•").fontWeight(.bold)
                Text(savedLinkMarkdown(text)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(number).").fontWeight(.semibold).monospacedDigit()
                Text(savedLinkMarkdown(text)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .checklist(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? .green : .secondary)
                Text(savedLinkMarkdown(text)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .centered(let text):
            Text(savedLinkMarkdown(text))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct SavedLinkArticleContent: View {
    let source: String?
    var pendingImages: [PendingInlineImage] = []
    var onImageTap: ((String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(savedLinkContentSegments(source).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let value):
                    ForEach(Array(savedLinkArticleBlocks(value).enumerated()), id: \.offset) { _, block in
                        SavedLinkArticleBlockView(block: block)
                    }
                case .image(let url, _):
                    if let pending = pendingImages.first(where: { url.contains($0.token) }), let image = UIImage(contentsOfFile: pending.url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if onImageTap != nil {
                        Button { onImageTap?(url) } label: { SavedLinkDetailImage(url: url) }
                            .buttonStyle(.plain)
                    } else {
                        SavedLinkDetailImage(url: url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SavedLinkDetail: View {
    let item: SavedLink
    @State private var previewURL: URL?
    private var isArticle: Bool { savedLinkIsArticle(item) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) { SavedLinkAvatar(item: item).frame(width: 38, height: 38); VStack(alignment: .leading, spacing: 3) { Text(item.authorUsername).fontWeight(.semibold); Text(shortDate(item.createdAt)).font(.caption).foregroundStyle(.secondary) }; Spacer() }
                Text(item.title).font(.title.bold())
                if let category = item.category, !category.isEmpty { Label(category.replacingOccurrences(of: "tutorial:", with: "", options: [.caseInsensitive, .anchored]), systemImage: "tag").font(.caption).foregroundStyle(.secondary) }
                if item.pushStatus != "idle" { SavedLinkPushStatusView(item: item) }
                if isArticle {
                    SavedLinkArticleContent(source: item.description, onImageTap: { previewURL = nativeImageURL($0) })
                } else if let value = item.description, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(value).lineLimit(nil).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                let segments = isArticle ? savedLinkContentSegments(item.description) : []
                let inlineURLs = Set(segments.compactMap { segment -> String? in if case .image(let url, _) = segment { return nativeImageURL(url)?.absoluteString }; return nil })
                if isArticle {
                    ForEach(Array(item.images.filter { image in guard let value = nativeImageURL(image.url)?.absoluteString else { return true }; return !inlineURLs.contains(value) }.enumerated()), id: \.offset) { _, image in Button { previewURL = nativeImageURL(image.url) } label: { SavedLinkDetailImage(url: image.url) }.buttonStyle(.plain) }
                }
                if let value = item.url, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) { Link(destination: url) { Label("打开原链接", systemImage: "safari").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).padding(.top, 8) }
            }.padding(20)
        }.background(Color(.systemBackground)).navigationTitle(isArticle ? "文章" : "帖子").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) { NavigationStack { ZStack { Color.black.ignoresSafeArea(); if let previewURL { CachedRemoteImage(url: previewURL, contentMode: .fit, placeholder: ProgressView().tint(.white)) } }.toolbar { Button("关闭") { previewURL = nil } } } }
    }
}

private struct SavedLinkPushStatusView: View {
    let item: SavedLink
    private var title: String { item.pushStatus == "scheduled" ? "已安排钉钉定时推送" : item.pushStatus == "sending" ? "钉钉推送中" : item.pushStatus == "sent" ? "已推送到钉钉群" : "钉钉推送失败" }
    var body: some View { VStack(alignment: .leading, spacing: 5) { Label(title, systemImage: item.pushStatus == "failed" ? "exclamationmark.triangle" : "paperplane.fill").foregroundStyle(item.pushStatus == "failed" ? .red : .blue); if let scheduled = item.pushScheduledAt { Text("计划时间：\(shortDate(scheduled))").font(.caption).foregroundStyle(.secondary) }; if let sent = item.pushSentAt { Text("发送时间：\(shortDate(sent))").font(.caption).foregroundStyle(.secondary) }; if let pushError = item.pushError, !pushError.isEmpty { Text(pushError).font(.caption).foregroundStyle(.red).textSelection(.enabled) } }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10)) }
}

private struct SavedLinkPushSheet: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    let item: SavedLink
    let onSave: (SavedLink) -> Void
    @State private var scheduledAt = Date().addingTimeInterval(600)
    @State private var saving = false
    @State private var error: String?
    var body: some View { NavigationStack { Form { Section(savedLinkIsArticle(item) ? "文章" : "帖子") { Text(item.title).fontWeight(.medium) }; Section("推送时间") { DatePicker("发送时间", selection: $scheduledAt, in: Date().addingTimeInterval(60)..., displayedComponents: [.date, .hourAndMinute]) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("定时推送").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("安排") { Task { await schedule() } }.disabled(saving) } } } }
    private func schedule() async { saving = true; defer { saving = false }; let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withTimeZone]; do { let updated: SavedLink = try await session.send("saved-links/\(item.id)/push", method: "POST", body: ["scheduled_at": formatter.string(from: scheduledAt)]); onSave(updated); dismiss() } catch { self.error = session.message(for: error) } }
}

private enum SavedLinkContentSegment {
    case text(String)
    case image(url: String, alt: String)
}

private func savedLinkContentSegments(_ value: String?) -> [SavedLinkContentSegment] {
    guard let source = value, !source.isEmpty else { return [] }
    let pattern = #"!\[([^\]]*)\]\(([^\)]+)\)|\[([^\]]+)\]\(((?:/?saved-links/)[^\)]+)\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.text(source)] }
    let ns = source as NSString
    let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return [.text(source)] }
    var result: [SavedLinkContentSegment] = []
    var cursor = 0
    for match in matches {
        if match.range.location > cursor { result.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
        let altRange = match.range(at: match.range(at: 1).location == NSNotFound ? 3 : 1)
        let urlRange = match.range(at: match.range(at: 2).location == NSNotFound ? 4 : 2)
        result.append(.image(url: ns.substring(with: urlRange), alt: altRange.location == NSNotFound ? "图片" : ns.substring(with: altRange)))
        cursor = match.range.location + match.range.length
    }
    if cursor < ns.length { result.append(.text(ns.substring(from: cursor))) }
    return result
}
private struct SavedLinkDetailImage: View {
    let url: String
    var body: some View {
        Group {
            if let imageURL = nativeImageURL(url) {
                CachedRemoteImage(url: imageURL, contentMode: .fit, placeholder: ProgressView().frame(maxWidth: .infinity, minHeight: 120))
            } else {
                Image(systemName: "photo").frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
private struct SavedLink: Codable, Identifiable {
    let id: Int; let title: String; let url: String?; let category: String?; let description: String?
    let isPinned: Bool; let authorUsername: String; let authorAvatarURL: String?; let images: [SavedLinkImage]; let createdAt: String; let updatedAt: String
    let pushStatus: String; let pushScheduledAt: String?; let pushSentAt: String?; let pushError: String?
    enum CodingKeys: String, CodingKey { case id, title, url, category, description, images; case isPinned = "is_pinned"; case authorUsername = "author_username"; case authorAvatarURL = "author_avatar_url"; case createdAt = "created_at"; case updatedAt = "updated_at"; case pushStatus = "push_status"; case pushScheduledAt = "push_scheduled_at"; case pushSentAt = "push_sent_at"; case pushError = "push_error" }
}

enum NativeAPIError: Error { case invalidResponse; case microphoneDenied; case server(Int, String) }
struct MultipartFile { let field: String; let filename: String; let data: Data; let mime: String }

@MainActor final class NativeSession: ObservableObject {
    @Published var loggedIn = false
    @Published var restoring = true
    @Published var loading = false
    @Published var error: String?
    @Published var captchaImageData: String?
    @Published var needsTOTP = false
    @Published var username = "管理员"
    @Published var currentUser: CurrentUserSession?
    private var captchaID: String?
    private let origin: URL = {
#if DEBUG
        return URL(string: "http://127.0.0.1:4174")!
#else
        return URL(string: "https://xiaoxu666.asia")!
#endif
    }()
    private let decoder: JSONDecoder = { let value = JSONDecoder(); value.keyDecodingStrategy = .useDefaultKeys; return value }()

    func restoreSession() async {
        guard !loggedIn else { restoring = false; return }
        defer { restoring = false }
        do {
            let user: CurrentUserSession = try await get("auth/me")
            currentUser = user
            username = user.username
            loggedIn = true
        } catch {
            loggedIn = false
        }
    }

    func apply(_ user: CurrentUserSession) {
        currentUser = user
        username = user.username
        loggedIn = true
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
            let user = try decoder.decode(CurrentUserSession.self, from: data)
            currentUser = user; self.username = user.username; captchaID = nil; captchaImageData = nil; needsTOTP = false; loggedIn = true
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
        applyWorkspaceHeaders(to: &request, path: path)
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NativeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { currentUser = nil; loggedIn = false }
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["error"] as? String ?? payload?["detail"] as? String ?? "请求失败"
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
        applyWorkspaceHeaders(to: &request, path: path)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NativeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { if http.statusCode == 401 { currentUser = nil; loggedIn = false }; let payload = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]; let detail = payload?["error"] as? String ?? payload?["detail"] as? String ?? "上传失败"; throw NativeAPIError.server(http.statusCode, detail) }
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

    func streamChat(_ question: String, modelID: String, documents: [SearchDocument] = [], skillIDs: [String] = [], toolIDs: [String] = [], onChunk: @escaping @MainActor (String) -> Void) async throws {
        guard let url = URL(string: "ai-api/chat/stream", relativeTo: origin) else { throw NativeAPIError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyWorkspaceHeaders(to: &request, path: "ai-api/chat/stream")
        var body: [String: Any] = ["question": question, "documents": documents.map(\.body), "skill_ids": skillIDs, "tool_ids": toolIDs]
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
        currentUser = nil; loggedIn = false
    }

    func message(for error: Error) -> String {
        if case let NativeAPIError.server(_, detail) = error { return detail }
        if let network = error as? URLError { return network.code == .notConnectedToInternet ? "当前网络不可用，请联网后重试。" : "网络请求失败，请稍后重试。" }
        return "数据加载失败，请检查网络后重试。"
    }

    private func applyWorkspaceHeaders(to request: inout URLRequest, path: String) {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard normalized.hasPrefix("ai-api/") else { return }
        request.setValue(currentUser.map { String($0.id) } ?? "local", forHTTPHeaderField: "X-Workspace-User")
        request.setValue(currentUser?.role ?? "user", forHTTPHeaderField: "X-Workspace-Role")
    }
}

private func lineSummary(_ items: [WarehouseLine]) -> String { items.map { "\($0.sku) × \($0.quantity)" }.joined(separator: "；") }
private func outboundStatus(_ value: String) -> String { switch value { case "pending": return "待拣货"; case "picking": return "拣货中"; case "checked": return "已复核"; case "packed": return "已打包"; case "shipped": return "已发货"; case "cancelled": return "已取消"; default: return value } }
private func nextStatus(_ value: String) -> String? { switch value { case "pending": return "picking"; case "picking": return "checked"; case "checked": return "packed"; case "packed": return "shipped"; default: return nil } }
struct EmptyResponse: Codable {}
private struct ChatResponse: Codable { let content: String?; let answer: String?; let response: String? }
private struct ImageGenerationResponse: Decodable { let url: String }
struct SearchDocument: Decodable { let title: String?; let content: String?; let url: String?; var body: [String: Any] { ["title":title ?? "","content":content ?? "","url":url ?? ""] } }
private struct SearchDocumentsResponse: Decodable { let documents: [SearchDocument]; enum CodingKeys: CodingKey { case documents }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); documents = try c.decodeIfPresent([SearchDocument].self, forKey: .documents) ?? [] } }
private struct LoginCaptcha: Decodable { let captchaID: String; let imageData: String; enum CodingKeys: String, CodingKey { case captchaID = "captcha_id"; case imageData = "image_data" } }
struct CurrentUserSession: Decodable {
    let id: Int; let username: String; let displayName: String?; let avatarURL: String?; let role: String; let permissions: [String: String]
    enum CodingKeys: String, CodingKey { case id, username, role, permissions; case displayName = "display_name"; case avatarURL = "avatar_url" }
}
private struct CaptchaWebView: UIViewRepresentable {
    let data: String
    func makeUIView(context: Context) -> WKWebView { let view = WKWebView(); view.isOpaque = false; view.backgroundColor = .clear; return view }
    func updateUIView(_ view: WKWebView, context: Context) { view.loadHTMLString("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;background:transparent;overflow:hidden\">\(data.hasPrefix("data:") ? "<img src='\(data)' style='width:132px;height:44px'>" : "")</body>", baseURL: nil) }
}

private struct ProfitSummary: Decodable { let totalProfit: Double; enum CodingKeys: String, CodingKey { case totalProfit = "total_profit" } }
private struct ProfitListSummary: Decodable { let totalProfit: Double; let uniqueStoreCount: Int; let uniqueReporterCount: Int; enum CodingKeys: String, CodingKey { case totalProfit = "total_profit"; case uniqueStoreCount = "unique_store_count"; case uniqueReporterCount = "unique_reporter_count" } }
private struct ProfitMonth: Decodable, Identifiable { let month: String; let totalProfit: Double; var id: String { month }; enum CodingKeys: String, CodingKey { case month; case totalProfit = "total_profit" } }
private struct ProfitRecord: Decodable, Identifiable { let sourceRecordID: Int; let reportDate: String; let storeName: String; let profit: Double; let reporterName: String; var id: Int { sourceRecordID }; enum CodingKeys: String, CodingKey { case profit; case sourceRecordID = "source_record_id"; case reportDate = "report_date"; case storeName = "store_name"; case reporterName = "reporter_name" } }

private struct HomeDashboard {
    var expenseTotal: Double?; var profitTotal: Double?; var monthlyProfit: Double?
    var pendingSigned: Int?; var pendingSettlement: Int?; var stockQuantity: Int?
    var stockCost: Double?; var lowStock: Int?
    enum Partial { case warehouse(WarehouseSummary?); case tasks(TaskSummary?); case expenses(ExpenseSummary?); case profits(ProfitSummary?); case monthlyProfits([ProfitMonth]?) }
    mutating func apply(_ partial: Partial) -> Bool { switch partial {
        case .warehouse(let value): stockQuantity = value?.totalQuantity; stockCost = value?.totalCost; lowStock = value?.lowStockCount; return value != nil
        case .tasks(let value): pendingSigned = value?.pendingSignedCount; pendingSettlement = value?.pendingSettlementCount; return value != nil
        case .expenses(let value): expenseTotal = value?.monthTotal; return value != nil
        case .profits(let value): profitTotal = value?.totalProfit; return value != nil
        case .monthlyProfits(let value):
            guard let value else { return false }
            let components = Calendar.current.dateComponents([.year, .month], from: Date())
            let currentMonth = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            monthlyProfit = value.first(where: { $0.month == currentMonth })?.totalProfit ?? 0
            return true
    } }
}

private struct HomeModuleItem: Identifiable { let id: String; let title: String; let icon: String; let color: Color; let destination: NativeDestination }
private let homeModuleCatalog = [HomeModuleItem(id: "sycm", title: "生意参谋", icon: "chart.bar.fill", color: .teal, destination: .sycm), HomeModuleItem(id: "company-expenses", title: "公司记账", icon: "creditcard.fill", color: .blue, destination: .expenses), HomeModuleItem(id: "tasks", title: "任务记录", icon: "doc.text.fill", color: .indigo, destination: .tasks), HomeModuleItem(id: "profits", title: "钉钉利润", icon: "chart.line.uptrend.xyaxis", color: .orange, destination: .profits), HomeModuleItem(id: "shops", title: "店铺账号", icon: "storefront.fill", color: .mint, destination: .shops), HomeModuleItem(id: "warehouse", title: "仓储管理", icon: "shippingbox.fill", color: .orange, destination: .warehouse), HomeModuleItem(id: "links", title: "链接广场", icon: "link", color: .blue, destination: .links), HomeModuleItem(id: "ai-workspace", title: "AI 工作台", icon: "sparkles", color: .cyan, destination: .aiWorkspace), HomeModuleItem(id: "owners", title: "负责人", icon: "person.2.fill", color: .green, destination: .owners)]
private let defaultHomeModuleKeys = ["sycm", "company-expenses", "tasks", "profits", "shops", "warehouse", "links", "ai-workspace", "owners"]
private struct HomeModulesSettingResponse: Codable { let key: String; let value: [String]? }
private struct HomeModuleManager: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    @Binding var keys: [String]
    @State private var saving = false
    @State private var error: String?
    private var available: [HomeModuleItem] { homeModuleCatalog.filter { !keys.contains($0.id) } }
    var body: some View { NavigationStack { List { if let error { Text(error).font(.caption).foregroundStyle(.red) }; Section("已显示 · 拖动排序") { ForEach(keys, id: \.self) { key in if let item = homeModuleCatalog.first(where: { $0.id == key }) { Label(item.title, systemImage: item.icon) } }.onMove { keys.move(fromOffsets: $0, toOffset: $1) }.onDelete { offsets in guard keys.count > offsets.count else { return }; keys.remove(atOffsets: offsets) } }; if !available.isEmpty { Section("更多功能") { ForEach(available) { item in Button { keys.append(item.id) } label: { Label(item.title, systemImage: "plus.circle") } } } } }.environment(\.editMode, .constant(.active)).navigationTitle("常用功能排序").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "保存中…" : "保存") { Task { await save() } }.disabled(saving) } } } }
    private func save() async { saving = true; defer { saving = false }; do { let response: HomeModulesSettingResponse = try await session.send("ui-settings/home-modules", method: "PUT", body: ["value": keys]); if let value = response.value { keys = value }; dismiss() } catch { self.error = session.message(for: error) } }
}
private struct NativeAppIconTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    let iconSize: CGFloat
    var selected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.34), .clear, .black.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(.white.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: color.opacity(0.3), radius: size * 0.11, y: size * 0.07)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Color.blue, in: Circle())
                    .overlay { Circle().stroke(.white, lineWidth: 2) }
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}
private struct HomeShortcutLabel: View { let title: String; let icon: String; let color: Color; init(_ title: String, _ icon: String, _ color: Color) { self.title = title; self.icon = icon; self.color = color }; var body: some View { VStack(spacing: 6) { NativeAppIconTile(symbol: icon, color: color, size: 36, iconSize: 18); Text(title).font(.caption2).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center).foregroundStyle(.primary) }.frame(maxWidth: .infinity).frame(height: 64) } }
private struct HomeShortcut: View { let title: String; let icon: String; let color: Color; let action: () -> Void; init(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) { self.title = title; self.icon = icon; self.color = color; self.action = action }; var body: some View { Button(action: action) { HomeShortcutLabel(title, icon, color) }.buttonStyle(.plain) } }
private struct HomeMetric: View { let title: String; let value: String; init(_ title: String, _ value: String) { self.title = title; self.value = value }; var body: some View { VStack(spacing: 5) { Text(value).font(.system(size: 16, weight: .semibold)); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 14).background(.background) } }
private struct HomeDashboardMetric: View { let title: String; let value: String; let icon: String; let color: Color; init(_ title: String, _ value: String, _ icon: String, _ color: Color) { self.title = title; self.value = value; self.icon = icon; self.color = color }; var body: some View { VStack(alignment: .leading, spacing: 12) { NativeAppIconTile(symbol: icon, color: color, size: 30, iconSize: 14); Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10)) } }
private struct HomeTodo: View { let color: Color; let title: String; let detail: String; let value: String; var body: some View { HStack(spacing: 12) { Circle().fill(color).frame(width: 7, height: 7); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline).fontWeight(.semibold); Text(detail).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text(value).font(.title3).fontWeight(.bold) }.padding(.horizontal, 14).padding(.vertical, 13) } }
private func money(_ value: Double) -> String { String(format: "¥ %.2f", value) }
func shortDate(_ value: String?) -> String { guard let value else { return "-" }; return String(value.replacingOccurrences(of: "T", with: " ").prefix(16)) }
private func nativeImageURL(_ value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let base: URL
#if DEBUG
    base = URL(string: "http://127.0.0.1:4174/")!
#else
    base = URL(string: "https://xiaoxu666.asia/")!
#endif
    return URL(string: trimmed, relativeTo: base)?.absoluteURL
}
private func nativeThumbnailURL(_ value: String, maxPixelSize: CGFloat = 720) -> URL? {
    guard let url = nativeImageURL(value), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nativeImageURL(value) }
    let requested = max(Int(maxPixelSize.rounded(.up)), 1)
    let width = [96, 320, 720, 1280].first(where: { $0 >= requested }) ?? 1280
    var items = (components.queryItems ?? []).filter { !["thumb", "width", "format", "quality"].contains($0.name) }
    items.append(URLQueryItem(name: "thumb", value: "1"))
    items.append(URLQueryItem(name: "width", value: String(width)))
    items.append(URLQueryItem(name: "format", value: "webp"))
    items.append(URLQueryItem(name: "quality", value: "76"))
    components.queryItems = items
    return components.url ?? url
}
private struct NativeRemoteImage: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        Group {
            if let url, let imageURL = nativeThumbnailURL(url, maxPixelSize: size * 3) {
                CachedRemoteImage(url: imageURL, contentMode: .fill, maxPixelSize: size * 3, placeholder: placeholder)
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: min(size * 0.2, 12)))
    }

    private var placeholder: some View { Image(systemName: "photo").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
}

private enum NativeImageError: Error { case invalidResponse, invalidImage }

private actor NativeImagePipeline {
    static let shared = NativeImagePipeline()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let responseCache: URLCache
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    private init() {
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 64 * 1024 * 1024
        let cache = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 384 * 1024 * 1024)
        responseCache = cache
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        let bucket = max(Int(maxPixelSize.rounded(.up)), 120)
        let key = "\(url.absoluteString)#\(bucket)"
        if let cached = memoryCache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return try await task.value }

        let session = session
        let responseCache = responseCache
        let task = Task.detached(priority: .userInitiated) {
            var lastError: Error = NativeImageError.invalidResponse
            let requestURLs = NativeImagePipeline.requestURLs(for: url)
            for requestURL in requestURLs {
                do {
                    var request = URLRequest(url: requestURL)
                    request.cachePolicy = .returnCacheDataElseLoad
                    request.timeoutInterval = 8
                    request.networkServiceType = .responsiveData
                    request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    let data: Data
                    let response: URLResponse
                    let shouldStore: Bool
                    if let cached = responseCache.cachedResponse(for: request) {
                        data = cached.data; response = cached.response; shouldStore = false
                    } else {
                        (data, response) = try await session.data(for: request)
                        shouldStore = true
                    }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NativeImageError.invalidResponse }
                    if let mime = http.mimeType, !mime.lowercased().hasPrefix("image/") { throw NativeImageError.invalidImage }
                    if shouldStore { responseCache.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowed), for: request) }
                    guard let image = NativeImagePipeline.downsample(data: data, maxPixelSize: bucket) else { throw NativeImageError.invalidImage }
                    return image
                } catch {
                    lastError = error
                    guard !Task.isCancelled else { break }
                }
            }
            throw lastError
        }
        inFlight[key] = task
        do {
            let image = try await task.value
            inFlight[key] = nil
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? bucket * bucket * 4
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private static func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func requestURLs(for url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.queryItems?.contains(where: { $0.name == "thumb" }) == true else { return [url] }
        components.queryItems = components.queryItems?.filter { $0.name != "thumb" }
        guard let original = components.url else { return [url] }
        return original == url ? [url] : [url, original]
    }

    func prefetch(_ requests: [(URL, CGFloat)]) async {
        await withTaskGroup(of: Void.self) { group in
            for (url, size) in requests.prefix(18) {
                group.addTask { _ = try? await self.image(for: url, maxPixelSize: size) }
            }
        }
    }
}

private struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL
    let contentMode: ContentMode
    var maxPixelSize: CGFloat = 1600
    let placeholder: Placeholder
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    @State private var retryID = 0
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
            else {
                placeholder
                if failed {
                    Button { failed = false; retryID += 1 } label: {
                        Image(systemName: "arrow.clockwise.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重新加载图片")
                }
            }
        }
        .task(id: "\(url.absoluteString)#\(retryID)") {
            if loadedURL != url { image = nil; failed = false }
            do {
                image = try await NativeImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
                loadedURL = url
                failed = false
            } catch is CancellationError {
            } catch {
                failed = true
            }
        }
    }
}
private func shortTimestamp(_ value: TimeInterval) -> String { let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"; return formatter.string(from: Date(timeIntervalSince1970: value)) }
private func jobStatus(_ value: String) -> String { switch value { case "queued": return "排队中"; case "running": return "运行中"; case "completed": return "已完成"; case "failed": return "失败"; case "cancelled": return "已取消"; default: return value } }
private func jobColor(_ value: String) -> Color { switch value { case "completed": return .green; case "failed": return .red; case "queued", "running": return .blue; default: return .secondary } }
private func roleLabel(_ value: String) -> String { switch value { case "superadmin": return "超级管理员"; case "editor": return "编辑员"; default: return "只读账号" } }
private func licenseStatus(_ value: String) -> String { switch value { case "active": return "生效中"; case "disabled": return "已停用"; case "expired": return "已过期"; default: return "未激活" } }
