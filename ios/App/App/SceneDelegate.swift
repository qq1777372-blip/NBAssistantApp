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
    @AppStorage("native_logged_in") private var loggedIn = false
    var body: some View {
        Group { loggedIn ? AnyView(NativeTabView()) : AnyView(NativeLoginView(loggedIn: $loggedIn)) }
            .tint(Color(red: 0.08, green: 0.49, blue: 0.96))
    }
}

private struct NativeLoginView: View {
    @Binding var loggedIn: Bool
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
                    Button("登录") { loggedIn = true }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
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
    @State private var message = ""
    @State private var messages = ["你好！请告诉我需要处理什么问题。"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView { LazyVStack(alignment: .leading, spacing: 16) { ForEach(messages, id: \.self) { text in Text(text).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)) } }.padding() }
                HStack(spacing: 10) { TextField("给 AI 发消息…", text: $message, axis: .vertical).lineLimit(1...4).padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18)); Button { let value = message.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; messages.append(value); message = "" } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) } }.padding()
            }.navigationTitle("AI 工作台").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NativeMineView: View {
    @AppStorage("native_logged_in") private var loggedIn = true
    var body: some View { NavigationStack { List { Section("账户") { Label("管理员", systemImage: "person.circle"); Button("退出登录", role: .destructive) { loggedIn = false } } }.navigationTitle("我的") } }
}
