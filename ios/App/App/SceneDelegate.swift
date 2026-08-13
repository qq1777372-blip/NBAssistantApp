import UIKit
import Capacitor
import SwiftUI

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
                    TextField("给 AI 发消息...", text: $message, axis: .vertical)
                        .lineLimit(1...4).nativeField()
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                        .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            }
            .navigationTitle("AI 工作台").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func send() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        messages.append(ChatMessage(text: value, sent: true)); message = ""; sending = true
        Task {
            let answer = await session.chat(value) ?? "服务没有返回内容。"
            messages.append(ChatMessage(text: answer, sent: false)); sending = false
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.shopName).font(.headline); Spacer(); Text(money(item.principalAmount)).fontWeight(.semibold) }
                            Text("\(item.orderNo) · \(item.ownerName)").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                StatusBadge(text: item.signedStatus == "completed" ? "已签收" : "待签收", done: item.signedStatus == "completed")
                                StatusBadge(text: item.settlementStatus == "completed" ? "已结算" : "待结算", done: item.settlementStatus == "completed")
                                Spacer(); Text(shortDate(item.taskTime)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索订单、店铺或负责人")
            .refreshable { await load() }
            .navigationTitle("任务")
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
                        .swipeActions { Button("删除", role: .destructive) { deleting = item } }
                    }
                }
            }
            .overlay { if loading && records.isEmpty { ProgressView() } }
            .searchable(text: $query, prompt: "搜索分类、账户或说明")
            .refreshable { await load() }.navigationTitle("公司记账")
            .task { if records.isEmpty { await load() } }
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
                            Menu { Button(item.isPinned ? "取消置顶" : "置顶") { Task { await togglePin(item) } }; Button("删除", role: .destructive) { deleting = item } } label: { Image(systemName: "ellipsis") }
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

private struct NativeMineView: View {
    @EnvironmentObject private var session: NativeSession
    var body: some View {
        NavigationStack {
            List { Section("账户") { Label(session.username, systemImage: "person.circle"); Button("退出登录", role: .destructive) { Task { await session.logout() } } } }
                .navigationTitle("我的")
        }
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

private enum NativeAPIError: Error { case invalidResponse; case server(Int, String) }

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

    func chat(_ question: String) async -> String? {
        do {
            let response: ChatResponse = try await send("ai-api/chat", method: "POST", body: ["question": question])
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
