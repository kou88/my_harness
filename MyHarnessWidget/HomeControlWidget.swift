import AppIntents
import SwiftUI
import WidgetKit

// Optional parameters mean the user has not configured this widget yet.
enum HomeClimateMode: String, AppEnum {
    case resume, auto, cool, dry, fan, heat
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "運転モード")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .resume: "前回設定", .auto: "自動", .cool: "冷房", .dry: "除湿", .fan: "送風", .heat: "暖房"
    ]
    var label: String {
        switch self { case .resume: return "前回設定"; case .auto: return "自動"; case .cool: return "冷房"; case .dry: return "除湿"; case .fan: return "送風"; case .heat: return "暖房" }
    }
}
enum HomeClimateFan: String, AppEnum {
    case auto, low, medium, high
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "風量")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.auto: "自動", .low: "弱", .medium: "中", .high: "強"]
}
struct HomeControlConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "エアコンの運転設定"
    static var description = IntentDescription("前回設定、またはモード・温度・風量を指定します。設定の変更だけでは送信しません。")
    @Parameter(title: "運転モード") var mode: HomeClimateMode?
    @Parameter(title: "温度（16〜30℃）", inclusiveRange: (16, 30)) var temperature: Int?
    @Parameter(title: "風量") var fan: HomeClimateFan?
    var startLabel: String {
        guard let mode else { return "運転設定が必要" }
        if mode == .resume { return "前回設定で運転" }
        guard let temperature, fan != nil, (16...30).contains(temperature) else { return "温度・風量を設定" }
        return "\(mode.label) \(temperature)℃"
    }
    var isConfigured: Bool {
        guard let mode else { return false }
        if mode == .resume { return true }
        guard let temperature, fan != nil else { return false }
        return (16...30).contains(temperature)
    }
}
enum HomeWidgetAction: String, AppEnum {
    case lightOn, lightOff, acOn, acOff
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "家電操作")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.lightOn: "ライトをつける", .lightOff: "ライトを消す", .acOn: "エアコンを運転", .acOff: "エアコンを停止"]
    var device: HomeAppliance { self == .lightOn || self == .lightOff ? .light : .airConditioner }
}
struct HomeControlIntent: AppIntent {
    static var title: LocalizedStringResource = "家電を操作"
    static var openAppWhenRun = false
    @Parameter(title: "操作") var action: HomeWidgetAction
    @Parameter(title: "運転モード") var mode: HomeClimateMode?
    @Parameter(title: "温度") var temperature: Int?
    @Parameter(title: "風量") var fan: HomeClimateFan?
    init() {}
    init(_ action: HomeWidgetAction, configuration: HomeControlConfiguration) {
        self.action = action
        mode = configuration.mode
        temperature = configuration.temperature
        fan = configuration.fan
    }
    func perform() async throws -> some IntentResult {
        let command: HomeControlCommand
        switch action {
        case .lightOn: command = .power(.light, true)
        case .lightOff: command = .power(.light, false)
        case .acOff: command = .power(.airConditioner, false)
        case .acOn:
            guard let mode else { throw HomeControlError.message("ウィジェットを長押しして運転設定を選んでください。") }
            if mode == .resume { command = .power(.airConditioner, true) }
            else {
                guard let temperature, (16...30).contains(temperature), let fan else {
                    throw HomeControlError.message("温度と風量を選んでください。")
                }
                command = .climate(temperature: temperature, mode: mode.rawValue, fan: fan.rawValue)
            }
        }
        try await HomeWidgetExecutor.shared.send(command, device: action.device)
        return .result()
    }
}
private struct HomeFeedback: Codable {
    enum Phase: String, Codable { case sending, sent, failed }
    let phase: Phase
    let message: String
    let date: Date
    var label: String {
        if phase == .sending && Date().timeIntervalSince(date) > 20 { return "結果不明・家電を確認" }
        return message
    }
}
private enum HomeFeedbackStore {
    static func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: "group.com.kou888.myharness") else {
            throw HomeControlError.message("ウィジェットの共有領域を開けません。")
        }
        return defaults
    }
    static func save(_ feedback: HomeFeedback, device: HomeAppliance) throws {
        try defaults().set(JSONEncoder().encode(feedback), forKey: "home-control.\(device.rawValue)")
        WidgetCenter.shared.reloadTimelines(ofKind: "HomeControlWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LightControlWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "AirConditionerControlWidget")
    }
    static func read(device: HomeAppliance) -> HomeFeedback? {
        do {
            guard let data = try defaults().data(forKey: "home-control.\(device.rawValue)") else { return nil }
            return try JSONDecoder().decode(HomeFeedback.self, from: data)
        } catch { return HomeFeedback(phase: .failed, message: "送信履歴を読み取れません", date: Date()) }
    }
}
private actor HomeWidgetExecutor {
    static let shared = HomeWidgetExecutor()
    private var sending = Set<String>()
    func send(_ command: HomeControlCommand, device: HomeAppliance) async throws {
        guard !sending.contains(device.rawValue) else { throw HomeControlError.message("送信中です。少しお待ちください。") }
        sending.insert(device.rawValue)
        defer { sending.remove(device.rawValue) }
        do {
            try HomeFeedbackStore.save(HomeFeedback(phase: .sending, message: "送信中…", date: Date()), device: device)
            let client = HomeControlClient(config: try ActionInboxConfig.load())
            _ = try await client.send(command)
            try HomeFeedbackStore.save(HomeFeedback(phase: .sent, message: "信号を送信しました", date: Date()), device: device)
        } catch {
            try HomeFeedbackStore.save(HomeFeedback(phase: .failed, message: error.localizedDescription, date: Date()), device: device)
            throw error
        }
    }
}
private struct HomeEntry: TimelineEntry {
    let date: Date
    let configuration: HomeControlConfiguration
    let light: HomeFeedback?
    let airConditioner: HomeFeedback?
}
private struct HomeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HomeEntry { entry(configuration: HomeControlConfiguration()) }
    func snapshot(for configuration: HomeControlConfiguration, in context: Context) async -> HomeEntry { entry(configuration: configuration) }
    func timeline(for configuration: HomeControlConfiguration, in context: Context) async -> Timeline<HomeEntry> {
        let value = entry(configuration: configuration)
        let sending = [value.light, value.airConditioner].compactMap { $0 }.contains { $0.phase == .sending && Date().timeIntervalSince($0.date) < 20 }
        return Timeline(entries: [value], policy: sending ? .after(Date().addingTimeInterval(21)) : .never)
    }
    private func entry(configuration: HomeControlConfiguration) -> HomeEntry {
        HomeEntry(date: Date(), configuration: configuration, light: HomeFeedbackStore.read(device: .light), airConditioner: HomeFeedbackStore.read(device: .airConditioner))
    }
}
private struct ApplianceControls: View {
    let device: HomeAppliance
    let configuration: HomeControlConfiguration
    let feedback: HomeFeedback?
    private var isSending: Bool {
        guard let feedback else { return false }
        return feedback.phase == .sending && Date().timeIntervalSince(feedback.date) < 20
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(device == .light ? "ライト" : "エアコン", systemImage: device == .light ? "lightbulb.fill" : "air.conditioner.horizontal.fill")
                .font(.headline)
            Text(device == .light ? "照明の電源" : configuration.startLabel)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 8) {
                Button(intent: HomeControlIntent(device == .light ? .lightOn : .acOn, configuration: configuration)) {
                    Text(device == .light ? "つける" : "運転").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent).tint(device == .light ? .orange : .blue)
                .disabled(device == .airConditioner && !configuration.isConfigured)
                Button(intent: HomeControlIntent(device == .light ? .lightOff : .acOff, configuration: configuration)) {
                    Text(device == .light ? "消す" : "停止").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered).tint(.secondary)
            }
            .disabled(isSending)
            if let feedback {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedback.label).lineLimit(2).foregroundStyle(feedback.phase == .failed ? .red : .secondary)
                    if feedback.phase == .sent { Text(feedback.date, style: .time).foregroundStyle(.secondary) }
                }.font(.caption2)
            } else if device == .airConditioner && !configuration.isConfigured {
                Text("長押し → ウィジェットを編集").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("赤外線リモコン").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
struct HomeControlWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HomeControlWidget", intent: HomeControlConfiguration.self, provider: HomeProvider()) { entry in
            HStack(alignment: .top, spacing: 14) {
                ApplianceControls(device: .light, configuration: entry.configuration, feedback: entry.light)
                Divider()
                ApplianceControls(device: .airConditioner, configuration: entry.configuration, feedback: entry.airConditioner)
            }
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "myharness://home-control"))
        }
        .configurationDisplayName("家電リモコン")
        .description("ライトとエアコンをアプリを開かず操作します。エアコンの運転設定はウィジェットを編集して選べます。")
        .supportedFamilies([.systemMedium])
    }
}
private struct LightProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry { makeEntry() }
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) { completion(makeEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let entry = makeEntry()
        let sending = entry.light.map { $0.phase == .sending && Date().timeIntervalSince($0.date) < 20 } == true
        completion(Timeline(entries: [entry], policy: sending ? .after(Date().addingTimeInterval(21)) : .never))
    }
    private func makeEntry() -> HomeEntry {
        HomeEntry(date: Date(), configuration: HomeControlConfiguration(), light: HomeFeedbackStore.read(device: .light), airConditioner: nil)
    }
}
struct LightControlWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightControlWidget", provider: LightProvider()) { entry in
            ApplianceControls(device: .light, configuration: entry.configuration, feedback: entry.light)
                .containerBackground(.background, for: .widget).widgetURL(URL(string: "myharness://home-control"))
        }
        .configurationDisplayName("ライト")
        .description("ワンタップでライトをつける・消す。")
        .supportedFamilies([.systemSmall])
    }
}
struct AirConditionerControlWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AirConditionerControlWidget", intent: HomeControlConfiguration.self, provider: HomeProvider()) { entry in
            ApplianceControls(device: .airConditioner, configuration: entry.configuration, feedback: entry.airConditioner)
                .containerBackground(.background, for: .widget).widgetURL(URL(string: "myharness://home-control"))
        }
        .configurationDisplayName("エアコン")
        .description("運転・停止。長押しして運転モード・温度・風量を選べます。")
        .supportedFamilies([.systemSmall])
    }
}
#Preview(as: .systemMedium) { HomeControlWidget() } timeline: {
    HomeEntry(date: Date(), configuration: HomeControlConfiguration(), light: nil, airConditioner: nil)
}
