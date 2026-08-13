import SwiftUI

struct NativeSycmView: View {
    @EnvironmentObject private var session: NativeSession
    @State private var period = "today"; @State private var selectedShop = ""; @State private var shops: [SycmShop] = []
    @State private var devices: [SycmDevice] = []; @State private var syncing = false; @State private var error: String?
    private let periods = [("today", "今日"), ("yesterday", "昨日"), ("recent7", "近7天"), ("recent30", "近30天")]
    private var scoped: [SycmShop] { selectedShop.isEmpty ? shops : shops.filter { $0.shopID == selectedShop } }
    private func sum(_ key: String) -> Double? { let values = scoped.compactMap { $0.value(key) }; return values.isEmpty ? nil : values.reduce(0, +) }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section { Picker("店铺范围", selection: $selectedShop) { Text("全部店铺（\(shops.count)）").tag(""); ForEach(shops) { Text($0.shopName).tag($0.shopID) } }; Picker("数据周期", selection: $period) { ForEach(Array(periods.enumerated()), id: \.offset) { _, item in Text(item.1).tag(item.0) } }.pickerStyle(.segmented).onChange(of: period) { _ in Task { await load() } } }
            Section("经营概览") { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { SycmMetric("访客数", sum("uv")); SycmMetric("浏览量", sum("pv")); SycmMetric("加购人数", sum("cartByrCnt")); SycmMetric("支付买家", sum("payByrCnt")); SycmMetric("支付金额", sum("payAmt"), money: true); SycmMetric("支付转化率", conversion, percent: true) }.padding(.vertical, 6) }
            Section("店铺排行") { ForEach(scoped.sorted { ($0.value("payAmt") ?? 0) > ($1.value("payAmt") ?? 0) }) { shop in HStack { VStack(alignment: .leading) { Text(shop.shopName).fontWeight(.medium); Text("访客 \(format(shop.value("uv"))) · 买家 \(format(shop.value("payByrCnt")))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(shop.value("payAmt").map { String(format: "¥%.2f", $0) } ?? "--") } } }
            Section("采集设备") { if devices.isEmpty { Text("暂无采集设备").foregroundStyle(.secondary) }; ForEach(devices) { device in HStack { VStack(alignment: .leading) { Text(device.deviceName); Text(device.sessionDetail.isEmpty ? "店铺 \(device.shopCount) 家" : device.sessionDetail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Label(device.online ? "在线" : "离线", systemImage: device.online ? "checkmark.circle.fill" : "xmark.circle").font(.caption).foregroundStyle(device.online ? .green : .secondary) } } }
            Button(syncing ? "同步中…" : "同步数据") { Task { await sync() } }.disabled(syncing)
        }.navigationTitle("生意参谋").task { await load() }.refreshable { await load() }
    }
    private var conversion: Double? { guard let uv = sum("uv"), uv > 0, let buyers = sum("payByrCnt") else { return nil }; return buyers / uv }
    private func format(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "--" }
    private func load() async { do { async let shopRequest: [SycmShop] = session.get("api/sycm/latest?period=\(period)"); async let deviceRequest: [SycmDevice] = session.get("api/sycm/collector-devices"); (shops, devices) = try await (shopRequest, deviceRequest); error = nil } catch { self.error = session.message(for: error) } }
    private func sync() async { syncing = true; defer { syncing = false }; do { let latest: [SycmDevice] = try await session.get("api/sycm/collector-devices"); devices = latest; guard latest.contains(where: { $0.online }) else { throw NativeAPIError.server(409, "没有已连接的采集设备，请先启动采集端") }; if let blocked = latest.first(where: { $0.online && $0.sessionState == "blocked" }) { throw NativeAPIError.server(409, blocked.sessionDetail.isEmpty ? "采集端拿不到千牛会话" : blocked.sessionDetail) }; let _: SycmSyncRequest = try await session.send("api/sycm/sync-requests", method: "POST"); try? await Task.sleep(nanoseconds: 2_000_000_000); await load() } catch { self.error = session.message(for: error) } }
}

private struct SycmMetric: View { let title: String; let value: Double?; let money: Bool; let percent: Bool; init(_ title: String, _ value: Double?, money: Bool = false, percent: Bool = false) { self.title = title; self.value = value; self.money = money; self.percent = percent }; var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(display).font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8)) }; private var display: String { guard let value else { return "--" }; if money { return String(format: "¥%.2f", value) }; if percent { return String(format: "%.2f%%", value * 100) }; return String(format: "%.0f", value) } }
struct SycmMetricValue: Decodable { let value: Double? }
struct SycmShop: Decodable, Identifiable { let id: Int; let shopID: String; let shopName: String; let overview: [String: SycmMetricValue]; let uv: Double?; let pv: Double?; let cartByrCnt: Double?; let payByrCnt: Double?; let payAmt: Double?; enum CodingKeys: String, CodingKey { case id, overview, uv, pv, cartByrCnt, payByrCnt, payAmt; case shopID = "shopId"; case shopName = "shopName" }; func value(_ key: String) -> Double? { if let value = overview[key]?.value { return value }; switch key { case "uv": return uv; case "pv": return pv; case "cartByrCnt": return cartByrCnt; case "payByrCnt": return payByrCnt; case "payAmt": return payAmt; default: return nil } } }
struct SycmDevice: Decodable, Identifiable { let deviceID: String; let deviceName: String; let online: Bool; let shopCount: Int; let sessionState: String; let sessionDetail: String; var id: String { deviceID }; enum CodingKeys: String, CodingKey { case online; case deviceID = "deviceId"; case deviceName = "deviceName"; case shopCount = "shopCount"; case sessionState = "sessionState"; case sessionDetail = "sessionDetail" } }
struct SycmSyncRequest: Decodable { let id: Int; let status: String }
