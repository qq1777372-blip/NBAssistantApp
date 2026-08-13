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
        Group { session.loggedIn ? AnyView(NativeTabView().environmentObject(session)) : AnyView(NativeLoginView().environmentObject(session)) }
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
                Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 54)).foregroundStyle(.blue)
                Text("内部管理 App").font(.title.bold())
                Text("原生 iOS 工作台").foregroundStyle(.secondary)
                VStack(spacing: 14) {
                    TextField("账号", text: $account).textContentType(.username).padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    SecureField("密码", text: $password).textContentType(.password).padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    Button(session.loading ? "登录中…" : "登录") { Task { await session.login(username: account, password: password) } }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(session.loading || account.isEmpty || password.isEmpty)
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 22)).shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                Spacer()
            }.padding(22).background(Color(.systemGroupedBackground)).navigationBarHidden(true)
        }
    }
}

private struct NativeTabView: View {
    var body: some View {
        TabView {
            NativeHomeView().tabItem { Label("首页", systemImage: "house") }
            Text("任务").tabItem { Label("任务", systemImage: "checklist") }
            Text("记账").tabItem { Label("记账", systemImage: "wallet.pass") }
            Text("链接").tabItem { Label("链接", systemImage: "link") }
            NativeMineView().tabItem { Label("我的", systemImage: "person") }
        }
    }
}

private struct NativeHomeView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var message = ""
    @State private var messages = ["你好！请告诉我需要处理什么问题。"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView { LazyVStack(alignment: .leading, spacing: 16) { ForEach(messages, id: \.self) { text in Text(text).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)) } }.padding() }
                HStack(spacing: 10) { TextField("给 AI 发消息…", text: $message, axis: .vertical).lineLimit(1...4).padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18)); Button { let value = message.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; messages.append(value); message = ""; Task { if let answer = await session.chat(value) { messages.append(answer) } } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) } }.padding()
            }.navigationTitle("AI 工作台").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NativeMineView: View {
    @EnvironmentObject private var session: NativeSession
    var body: some View { NavigationStack { List { Section("账户") { Label(session.username, systemImage: "person.circle"); Button("退出登录", role: .destructive) { Task { await session.logout() } } } }.navigationTitle("我的") } }
}

@MainActor private final class NativeSession: ObservableObject {
    @Published var loggedIn = false
    @Published var loading = false
    @Published var error: String?
    @Published var username = "管理员"
    private let origin = URL(string: "https://xiaoxu666.asia")!

    func login(username: String, password: String) async {
        loading = true; error = nil; defer { loading = false }
        do {
            var request = URLRequest(url: origin.appendingPathComponent("auth/login")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password, "totp_code": NSNull(), "captcha_id": NSNull(), "captcha_code": NSNull()])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.userAuthenticationRequired) }
            self.username = username; loggedIn = true
        } catch { self.error = "登录失败，请检查账号、密码和网络" }
    }

    func chat(_ question: String) async -> String? {
        do {
            var request = URLRequest(url: origin.appendingPathComponent("ai-api/chat")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["question": question])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "请求失败，请稍后重试。" }
            return (object["content"] ?? object["answer"] ?? object["response"]) as? String
        } catch { return "无法连接 AI 服务，请检查网络。" }
    }

    func logout() async {
        var request = URLRequest(url: origin.appendingPathComponent("auth/logout")); request.httpMethod = "POST"; _ = try? await URLSession.shared.data(for: request); loggedIn = false
    }
}
