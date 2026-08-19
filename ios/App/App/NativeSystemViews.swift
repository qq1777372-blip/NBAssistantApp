import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UserNotifications

struct NativeAlertsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var payload = AlertPayload()
    @State private var error: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    var body: some View {
        List {
            Section("系统通知") {
                HStack { Label(notificationLabel, systemImage: notificationStatus == .authorized ? "bell.badge.fill" : "bell.slash"); Spacer(); if notificationStatus != .authorized { Button("开启") { Task { await requestNotifications() } } } }
            }
            Section { HStack { Metric(title: "待处理", value: "\(payload.openCount)"); Metric(title: "紧急提醒", value: "\(payload.criticalCount)") } }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(payload.items) { item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Circle().fill(item.severity == "critical" ? .red : .orange).frame(width: 8, height: 8); Text(item.title).fontWeight(.semibold); Spacer(); Text(item.acknowledged ? "已处理" : "待处理").font(.caption).foregroundStyle(.secondary) }
                    Text(item.description).font(.subheadline).foregroundStyle(.secondary)
                    if let occurred = item.occurredAt { Text(shortDate(occurred)).font(.caption2).foregroundStyle(.tertiary) }
                    Button(item.acknowledged ? "重新打开" : "标记已处理") { Task { await toggle(item) } }.font(.caption)
                }.padding(.vertical, 4).opacity(item.acknowledged ? 0.6 : 1)
            }
        }.navigationTitle("通知中心").task { await refreshNotificationStatus(); await load() }.refreshable { await load() }
    }
    private var notificationLabel: String { switch notificationStatus { case .authorized, .provisional, .ephemeral: "通知已开启"; case .denied: "通知已关闭"; default: "尚未开启通知" } }
    private func refreshNotificationStatus() async { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    private func requestNotifications() async { do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]); UIApplication.shared.registerForRemoteNotifications(); await refreshNotificationStatus() } catch { self.error = "无法开启系统通知" } }
    private func load() async { do { payload = try await session.get("system-alerts"); UIApplication.shared.applicationIconBadgeNumber = payload.openCount } catch { self.error = session.message(for: error) } }
    private func toggle(_ item: SystemAlert) async { do { let _: EmptyResponse = try await session.send("system-alerts/\(item.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.key)", method: "PATCH", body: ["acknowledged": !item.acknowledged], allowEmpty: true); await load() } catch { self.error = session.message(for: error) } }
}

struct NativeSearchView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var query = ""; @State private var result = GlobalSearchResponse(); @State private var loading = false; @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView("正在搜索…") }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(result.all) { item in
                NavigationLink { SearchResultDetail(item: item) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).fontWeight(.medium)
                        Text("\(item.categoryLabel) · \(item.subtitle ?? item.detail ?? "查看详情")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !query.isEmpty && !loading && result.all.isEmpty && error == nil { ContentUnavailableViewCompat(title: "没有找到匹配数据", icon: "magnifyingglass") }
        }.navigationTitle("全局搜索").searchable(text: $query, prompt: "名称、账号、订单号或手机号").task(id: query) { try? await Task.sleep(nanoseconds: 280_000_000); guard !Task.isCancelled else { return }; await search() }
    }
    private func search() async { let value = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { result = GlobalSearchResponse(); return }; loading = true; error = nil; defer { loading = false }; do { result = try await session.get("global-search?q=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)") } catch { self.error = session.message(for: error) } }
}

private struct SearchResultDetail: View {
    let item: SearchItem
    var body: some View {
        List {
            Section("基本信息") {
                LabeledContent("类型", value: item.categoryLabel)
                LabeledContent("标题", value: item.title)
                if let subtitle = item.subtitle, !subtitle.isEmpty { LabeledContent("摘要", value: subtitle) }
            }
            if let detail = item.detail, !detail.isEmpty { Section("详细信息") { Text(detail).textSelection(.enabled) } }
        }
        .navigationTitle("搜索详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeServerView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var status: ServerStatus?; @State private var error: String?
    @State private var endpointQuery = ""
    @State private var endpointResults: [String: ServerEndpointProbe] = [:]
    @State private var probingEndpoint: String?
    private var filteredEndpoints: [ServerAPIEndpoint] {
        let query = endpointQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return serverAPICatalog }
        return serverAPICatalog.filter { "\($0.group) \($0.title) \($0.method) \($0.path)".localizedCaseInsensitiveContains(query) }
    }
    private var endpointGroups: [(String, [ServerAPIEndpoint])] {
        let grouped = Dictionary(grouping: filteredEndpoints, by: \.group)
        return grouped.keys.sorted().compactMap { key in grouped[key].map { (key, $0) } }
    }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let status {
                Section { HStack { Image(systemName: "server.rack").font(.title).foregroundStyle(status.health == "healthy" ? .green : .orange); VStack(alignment: .leading) { Text(status.hostname).fontWeight(.semibold); Text(status.healthLabel).font(.caption).foregroundStyle(.secondary) } } }
                Section("资源使用") { ResourceRow(title: "CPU", value: status.cpuPercent); ResourceRow(title: "内存", value: status.memoryPercent); ResourceRow(title: "磁盘", value: status.diskPercent) }
                Section("系统") { LabeledContent("操作系统", value: status.operatingSystem); LabeledContent("架构", value: status.architecture); LabeledContent("数据库", value: status.databaseConnectionStatus); LabeledContent("数据库数量", value: "\(status.databaseCount)") }
                Section("服务") { ForEach(status.services) { service in HStack { VStack(alignment: .leading) { Text(service.displayName); Text(service.subState).font(.caption).foregroundStyle(.secondary) }; Spacer(); Circle().fill(service.isActive ? .green : .red).frame(width: 8, height: 8) } } }
            }
            Section("接口目录") {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索接口名称、方法或路径", text: $endpointQuery)
                    Text("\(filteredEndpoints.count)").font(.caption).foregroundStyle(.secondary)
                }
                Text("仅 GET 接口提供测试，写入接口只展示目录信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(endpointGroups, id: \.0) { group, endpoints in
                Section(group) {
                    ForEach(endpoints) { endpoint in
                        ServerEndpointRow(endpoint: endpoint, probe: endpointResults[endpoint.id], testing: probingEndpoint == endpoint.id) {
                            Task { await test(endpoint) }
                        }
                    }
                }
            }
        }.navigationTitle("服务器运行").task { await load(false) }.refreshable { await load(true) }
    }
    private func load(_ force: Bool) async { do { status = try await session.get("dashboard/server-status\(force ? "?refresh=true" : "")") } catch { self.error = session.message(for: error) } }
    private func test(_ endpoint: ServerAPIEndpoint) async {
        guard endpoint.method == "GET", probingEndpoint == nil else { return }
        probingEndpoint = endpoint.id; defer { probingEndpoint = nil }
        let path = endpoint.path.replacingOccurrences(of: "{current_user}", with: String(session.currentUser?.id ?? 0))
        do { endpointResults[endpoint.id] = try await session.probe(path) }
        catch { endpointResults[endpoint.id] = ServerEndpointProbe(statusCode: nil, latencyMS: nil, message: session.message(for: error)) }
    }
}

private struct ServerEndpointRow: View {
    let endpoint: ServerAPIEndpoint
    let probe: ServerEndpointProbe?
    let testing: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(endpoint.method)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(endpoint.method == "GET" ? .green : .orange)
                .frame(width: 42)
                .padding(.vertical, 4)
                .background((endpoint.method == "GET" ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(endpoint.title).font(.subheadline.weight(.medium))
                Text(endpoint.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                if let probe, let code = probe.statusCode {
                    Text("HTTP \(code) · \(probe.latencyMS ?? 0) ms").font(.caption2).foregroundStyle(code < 400 ? .green : .red)
                } else if let message = probe?.message {
                    Text(message).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if endpoint.method == "GET" {
                Button(action: action) {
                    Image(systemName: testing ? "hourglass" : "play.circle")
                        .frame(width: 32, height: 32)
                }
                .disabled(testing)
                .accessibilityLabel("测试\(endpoint.title)")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServerAPIEndpoint: Identifiable {
    let group: String
    let title: String
    let method: String
    let path: String
    var id: String { "\(method):\(path)" }
}

struct ServerEndpointProbe {
    let statusCode: Int?
    let latencyMS: Int?
    let message: String?
}

private let serverAPICatalog: [ServerAPIEndpoint] = [
    .init(group: "系统", title: "服务器状态", method: "GET", path: "dashboard/server-status"),
    .init(group: "系统", title: "系统设置", method: "GET", path: "system-settings"),
    .init(group: "系统", title: "系统通知", method: "GET", path: "system-alerts"),
    .init(group: "系统", title: "全局搜索", method: "GET", path: "global-search?q="),
    .init(group: "认证", title: "当前用户", method: "GET", path: "auth/me"),
    .init(group: "认证", title: "登录", method: "POST", path: "auth/login"),
    .init(group: "认证", title: "退出登录", method: "POST", path: "auth/logout"),
    .init(group: "任务记账", title: "任务列表", method: "GET", path: "task-bookkeeping/records"),
    .init(group: "任务记账", title: "任务汇总", method: "GET", path: "task-bookkeeping/summary"),
    .init(group: "任务记账", title: "负责人列表", method: "GET", path: "task-bookkeeping/owners"),
    .init(group: "公司记账", title: "公司消费列表", method: "GET", path: "company-expenses"),
    .init(group: "公司记账", title: "公司消费汇总", method: "GET", path: "company-expenses/summary"),
    .init(group: "公司记账", title: "新增公司消费", method: "POST", path: "company-expenses"),
    .init(group: "钉钉利润", title: "利润记录", method: "GET", path: "dingtalk-profits"),
    .init(group: "钉钉利润", title: "利润汇总", method: "GET", path: "dingtalk-profits/summary"),
    .init(group: "钉钉利润", title: "月度利润", method: "GET", path: "dingtalk-profits/monthly-summary"),
    .init(group: "仓储", title: "仓储汇总", method: "GET", path: "warehouse/summary"),
    .init(group: "仓储", title: "仓库列表", method: "GET", path: "warehouse/warehouses"),
    .init(group: "仓储", title: "商品列表", method: "GET", path: "warehouse/products"),
    .init(group: "仓储", title: "库存列表", method: "GET", path: "warehouse/stocks"),
    .init(group: "仓储", title: "入库单", method: "GET", path: "warehouse/inbound-orders"),
    .init(group: "仓储", title: "出库单", method: "GET", path: "warehouse/outbound-orders"),
    .init(group: "仓储", title: "库存流水", method: "GET", path: "warehouse/movements"),
    .init(group: "链接广场", title: "链接列表", method: "GET", path: "saved-links"),
    .init(group: "链接广场", title: "新增链接", method: "POST", path: "saved-links"),
    .init(group: "AI", title: "模型列表", method: "GET", path: "ai-api/models"),
    .init(group: "AI", title: "模型连接", method: "GET", path: "ai-api/connections"),
    .init(group: "AI", title: "AI 用量", method: "GET", path: "ai-api/usage"),
    .init(group: "AI", title: "AI 会话", method: "GET", path: "ai-api/chats?user_id={current_user}"),
    .init(group: "AI", title: "知识库", method: "GET", path: "ai-api/knowledge"),
    .init(group: "AI", title: "技能列表", method: "GET", path: "ai-api/skills"),
    .init(group: "AI", title: "工具列表", method: "GET", path: "ai-api/tools?all=1"),
    .init(group: "AI", title: "流式对话", method: "POST", path: "ai-api/chat/stream"),
    .init(group: "AI", title: "图片生成", method: "POST", path: "ai-api/images/generations"),
    .init(group: "管理", title: "管理账号", method: "GET", path: "admin-users"),
    .init(group: "管理", title: "卡密列表", method: "GET", path: "license-admin/licenses"),
    .init(group: "管理", title: "手机设备", method: "GET", path: "mobile-devices"),
    .init(group: "管理", title: "同行店铺", method: "GET", path: "peer-shops"),
    .init(group: "管理", title: "执照档案", method: "GET", path: "license-records"),
    .init(group: "管理", title: "账号使用记录", method: "GET", path: "account-usage-records")
]

struct NativeSystemSettingsView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var value = SystemSettings(); @State private var saving = false; @State private var error: String?; @State private var notice: String?
    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }; if let notice { Text(notice).foregroundStyle(.green) }
            Section("系统信息") { TextField("系统名称", text: $value.systemName); TextField("系统副标题", text: $value.systemSubtitle) }
            Section("提醒规则") { Stepper("执照提前提醒：\(value.licenseExpiryDays) 天", value: $value.licenseExpiryDays, in: 1...365); Stepper("任务超期：\(value.staleTaskDays) 天", value: $value.staleTaskDays, in: 1...90); Stepper("利润数据超期：\(value.profitStaleDays) 天", value: $value.profitStaleDays, in: 1...90); Toggle("低库存提醒", isOn: $value.lowStockAlertEnabled); Toggle("待出库提醒", isOn: $value.pendingOutboundAlertEnabled); Toggle("任务提醒", isOn: $value.taskAlertEnabled); Toggle("安全提醒", isOn: $value.securityAlertEnabled); Toggle("数据提醒", isOn: $value.dataAlertEnabled) }
            Section("登录安全") { Stepper("失败阈值：\(value.loginFailureThreshold) 次", value: $value.loginFailureThreshold, in: 1...20); Stepper("会话时长：\(value.sessionDurationHours) 小时", value: $value.sessionDurationHours, in: 1...720) }
            Button(saving ? "保存中…" : "保存设置") { Task { await save() } }.disabled(saving)
        }.navigationTitle("系统设置").task { await load() }
    }
    private func load() async { do { value = try await session.get("system-settings") } catch { self.error = session.message(for: error) } }
    private func save() async { saving = true; error = nil; defer { saving = false }; do { value = try await session.send("system-settings", method: "PUT", body: value.body); notice = "系统设置已保存" } catch { self.error = session.message(for: error) } }
}

struct NativeAppSettingsView: View {
    @EnvironmentObject private var session: NativeSession
    @AppStorage("native-dark-mode") private var dark = false
    @State private var confirmingLogout = false
    @State private var loggingOut = false

    var body: some View {
        Form {
            Section("外观") {
                Toggle("深色模式", isOn: $dark)
            }

            Section("应用") {
                NavigationLink { NativeAboutView() } label: {
                    Label("关于 NBAssistant", systemImage: "info.circle")
                }
            }

            Section {
                Button(role: .destructive) { confirmingLogout = true } label: {
                    HStack {
                        Spacer()
                        Label(loggingOut ? "正在退出…" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                    }
                }
                .disabled(loggingOut)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确定退出登录吗？", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task {
                    loggingOut = true
                    await session.logout()
                    loggingOut = false
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("退出后需要重新输入账号和密码才能进入。")
        }
    }
}

private struct NativeAboutView: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--" }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 72, height: 72)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    Text("NBAssistant").font(.title2.bold())
                    Text("内部管理工作台").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            Section("应用信息") {
                LabeledContent("版本", value: version)
                LabeledContent("构建版本", value: build)
                LabeledContent("界面", value: "SwiftUI 原生")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct NativeProfileView: View {
    @EnvironmentObject private var session: NativeSession
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var avatarImage: UIImage?
    @State private var loadingPhoto = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            Section("个人资料") {
                TextField("显示姓名", text: $displayName)
                LabeledContent("登录账号", value: session.username)
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Label(avatarData == nil ? "从照片图库选择头像" : "重新选择头像", systemImage: "photo.on.rectangle")
                }
                if let avatarImage {
                    HStack(spacing: 12) {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        Label("已选择新头像", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                } else if loadingPhoto {
                    ProgressView("正在读取照片…")
                }
            }
            Button(saving ? "保存中…" : "保存") { Task { await save() } }
                .disabled(saving || loadingPhoto || displayName.count > 50)
        }
        .navigationTitle("编辑个人资料")
        .task { displayName = session.currentUser?.displayName ?? "" }
        .onChange(of: selectedPhoto) { item in Task { await receivePhoto(item) } }
    }

    @MainActor
    private func receivePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadingPhoto = true
        error = nil
        defer { loadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else {
                throw NativeAPIError.invalidResponse
            }
            avatarImage = image
            avatarData = jpeg
        } catch {
            avatarImage = nil
            avatarData = nil
            self.error = "无法读取这张照片，请重新选择"
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            let body: [String: Any] = ["username": session.username, "display_name": displayName.isEmpty ? NSNull() : displayName]
            let user: CurrentUserSession = try await session.send("auth/profile", method: "PATCH", body: body)
            session.apply(user)
            if let avatarData {
                let uploaded: CurrentUserSession = try await session.upload(path: "auth/avatar", field: "image", filename: "avatar.jpg", data: avatarData, mime: "image/jpeg")
                session.apply(uploaded)
            }
            dismiss()
        } catch {
            self.error = session.message(for: error)
        }
    }
}

private struct ResourceRow: View { let title: String; let value: Double?; var body: some View { VStack(alignment: .leading) { HStack { Text(title); Spacer(); Text(value.map { String(format: "%.1f%%", $0) } ?? "--") }; ProgressView(value: min(max(value ?? 0, 0), 100), total: 100).tint((value ?? 0) >= 90 ? .red : (value ?? 0) >= 75 ? .orange : .blue) } } }
struct ContentUnavailableViewCompat: View { let title: String; let icon: String; var body: some View { VStack(spacing: 10) { Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary); Text(title).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 50) } }

struct AlertPayload: Decodable { var openCount = 0; var criticalCount = 0; var items: [SystemAlert] = []; enum CodingKeys: String, CodingKey { case openCount = "open_count"; case criticalCount = "critical_count"; case items } }
struct SystemAlert: Decodable, Identifiable { let key: String; let category: String; let severity: String; let title: String; let description: String; let occurredAt: String?; let acknowledged: Bool; var id: String { key }; enum CodingKeys: String, CodingKey { case key, category, severity, title, description, acknowledged; case occurredAt = "occurred_at" } }
struct SearchItem: Decodable, Identifiable { let id: Int; let category: String; let title: String; let subtitle: String?; let detail: String?; var categoryLabel: String { ["shop_record":"店铺账号","license_record":"执照档案","account_usage_record":"账号使用","task_bookkeeping_record":"任务记录"][category] ?? category } }
struct GlobalSearchResponse: Decodable { var shopRecords: [SearchItem] = []; var licenseRecords: [SearchItem] = []; var accountUsageRecords: [SearchItem] = []; var taskBookkeepingRecords: [SearchItem] = []; var all: [SearchItem] { shopRecords + licenseRecords + accountUsageRecords + taskBookkeepingRecords }; enum CodingKeys: String, CodingKey { case shopRecords = "shop_records"; case licenseRecords = "license_records"; case accountUsageRecords = "account_usage_records"; case taskBookkeepingRecords = "task_bookkeeping_records" } }
struct ServerService: Decodable, Identifiable { let name: String; let displayName: String; let activeState: String; let subState: String; let isActive: Bool; var id: String { name }; enum CodingKeys: String, CodingKey { case name; case displayName = "display_name"; case activeState = "active_state"; case subState = "sub_state"; case isActive = "is_active" } }
struct ServerStatus: Decodable { let health: String; let hostname: String; let operatingSystem: String; let architecture: String; let cpuPercent: Double?; let memoryPercent: Double?; let diskPercent: Double?; let databaseCount: Int; let databaseConnectionStatus: String; let services: [ServerService]; var healthLabel: String { health == "healthy" ? "运行正常" : health == "warning" ? "需要关注" : "存在异常" }; enum CodingKeys: String, CodingKey { case health, hostname, architecture, services; case operatingSystem = "operating_system"; case cpuPercent = "cpu_percent"; case memoryPercent = "memory_percent"; case diskPercent = "disk_percent"; case databaseCount = "database_count"; case databaseConnectionStatus = "database_connection_status" }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); health = try c.decodeIfPresent(String.self, forKey: .health) ?? "unknown"; hostname = try c.decodeIfPresent(String.self, forKey: .hostname) ?? "--"; operatingSystem = try c.decodeIfPresent(String.self, forKey: .operatingSystem) ?? "--"; architecture = try c.decodeIfPresent(String.self, forKey: .architecture) ?? "--"; cpuPercent = try c.decodeIfPresent(Double.self, forKey: .cpuPercent); memoryPercent = try c.decodeIfPresent(Double.self, forKey: .memoryPercent); diskPercent = try c.decodeIfPresent(Double.self, forKey: .diskPercent); databaseCount = try c.decodeIfPresent(Int.self, forKey: .databaseCount) ?? 0; databaseConnectionStatus = try c.decodeIfPresent(String.self, forKey: .databaseConnectionStatus) ?? "未知"; services = try c.decodeIfPresent([ServerService].self, forKey: .services) ?? [] } }
struct SystemSettings: Decodable { var systemName = "内部管理系统"; var systemSubtitle = "任务记账与店铺后台"; var licenseExpiryDays = 30; var staleTaskDays = 3; var loginFailureThreshold = 3; var sessionDurationHours = 168; var lowStockAlertEnabled = true; var pendingOutboundAlertEnabled = true; var taskAlertEnabled = true; var securityAlertEnabled = true; var dataAlertEnabled = true; var profitStaleDays = 3; enum CodingKeys: String, CodingKey { case systemName = "system_name"; case systemSubtitle = "system_subtitle"; case licenseExpiryDays = "license_expiry_days"; case staleTaskDays = "stale_task_days"; case loginFailureThreshold = "login_failure_threshold"; case sessionDurationHours = "session_duration_hours"; case lowStockAlertEnabled = "low_stock_alert_enabled"; case pendingOutboundAlertEnabled = "pending_outbound_alert_enabled"; case taskAlertEnabled = "task_alert_enabled"; case securityAlertEnabled = "security_alert_enabled"; case dataAlertEnabled = "data_alert_enabled"; case profitStaleDays = "profit_stale_days" }; var body: [String: Any] { ["system_name":systemName,"system_subtitle":systemSubtitle,"license_expiry_days":licenseExpiryDays,"stale_task_days":staleTaskDays,"login_failure_threshold":loginFailureThreshold,"session_duration_hours":sessionDurationHours,"low_stock_alert_enabled":lowStockAlertEnabled,"pending_outbound_alert_enabled":pendingOutboundAlertEnabled,"task_alert_enabled":taskAlertEnabled,"security_alert_enabled":securityAlertEnabled,"data_alert_enabled":dataAlertEnabled,"profit_stale_days":profitStaleDays] } }
