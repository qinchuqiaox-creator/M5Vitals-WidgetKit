import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 数据

struct RawMetrics: Decodable {
    struct Temp: Decodable {
        let cpu_temp_avg: Double?
        let gpu_temp_avg: Double?
    }
    struct Mem: Decodable {
        let ram_usage: Double?
        let ram_total: Double?
    }

    // 新字段（macmon ≥ 0.9 的官方字段）
    let cpu_scaled_ratio: Double?
    let gpu_scaled_ratio: Double?

    // v0.7 兼容别名（上游标为 deprecated，未来可能删除）—— 只做兜底
    let cpu_usage_pct: Double?
    let gpu_usage: [Double]?

    let sys_power: Double?
    let temp: Temp?
    let memory: Mem?

    /// CPU 负载 0…1：优先新字段，退回旧别名
    var cpuLoad: Double { cpu_scaled_ratio ?? cpu_usage_pct ?? 0 }

    /// GPU 负载 0…1：优先新字段，退回旧别名（gpu_usage = [频率, 负载]）
    var gpuLoad: Double {
        if let v = gpu_scaled_ratio { return v }
        if let arr = gpu_usage, arr.count > 1 { return arr[1] }
        return 0
    }
}

struct VitalsEntry: TimelineEntry {
    var date: Date
    var cpuTemp: Double
    var gpuTemp: Double
    var cpuPct: Double
    var gpuPct: Double
    var ramUsed: Double
    var ramTotal: Double
    var watts: Double
    /// false = 拿不到 macmon 数据（没启动 / 超时 / 返回不可解析）
    var online: Bool
}

extension VitalsEntry {
    static let sample = VitalsEntry(date: Date(), cpuTemp: 28.4, gpuTemp: 28.2,
                                    cpuPct: 2, gpuPct: 4, ramUsed: 16.1, ramTotal: 256,
                                    watts: 2.0, online: true)

    /// 明确表达「没有数据」，而不是伪装成 0% / 0W 的待机状态
    static func offline() -> VitalsEntry {
        VitalsEntry(date: Date(), cpuTemp: .nan, gpuTemp: .nan, cpuPct: .nan, gpuPct: .nan,
                    ramUsed: .nan, ramTotal: .nan, watts: .nan, online: false)
    }

    /// 读 macmon 在本机暴露的 JSON。超时 2 秒：宁可快速失败，也不卡住扩展
    static func load() async -> VitalsEntry {
        guard let url = URL(string: "http://127.0.0.1:41414/json") else { return .offline() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONDecoder().decode(RawMetrics.self, from: data) else {
            return .offline()
        }

        return VitalsEntry(
            date: Date(),
            cpuTemp: root.temp?.cpu_temp_avg ?? .nan,
            gpuTemp: root.temp?.gpu_temp_avg ?? .nan,
            cpuPct: root.cpuLoad * 100,
            gpuPct: root.gpuLoad * 100,
            ramUsed: (root.memory?.ram_usage ?? .nan) / 1_073_741_824,
            ramTotal: (root.memory?.ram_total ?? .nan) / 1_073_741_824,
            watts: root.sys_power ?? .nan,
            online: true
        )
    }
}

// MARK: - 刷新间隔（用户可在「编辑小组件」里改）

enum RefreshRate: Int, AppEnum {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Refresh rate")
    static var caseDisplayRepresentations: [RefreshRate: DisplayRepresentation] = [
        .oneMinute: "1 min",
        .fiveMinutes: "5 min",
        .fifteenMinutes: "15 min",
        .thirtyMinutes: "30 min"
    ]
}

struct VitalsConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "M5Vitals"
    static var description = IntentDescription("How often the widget asks for fresh sensor data.")

    @Parameter(title: "Refresh every", default: .fiveMinutes)
    var rate: RefreshRate
}

// MARK: - Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VitalsEntry { .sample }

    func snapshot(for configuration: VitalsConfigIntent, in context: Context) async -> VitalsEntry {
        await VitalsEntry.load()
    }

    func timeline(for configuration: VitalsConfigIntent, in context: Context) async -> Timeline<VitalsEntry> {
        let entry = await VitalsEntry.load()
        // 只是「请求」这个间隔；最终节奏仍由系统预算（budgeted）决定
        let next = Date().addingTimeInterval(TimeInterval(configuration.rate.rawValue * 60))
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - 外观

private func tempColor(_ t: Double) -> Color {
    if t.isNaN { return .secondary }
    if t >= 90 { return Color(red: 1.00, green: 0.36, blue: 0.36) }
    if t >= 80 { return Color(red: 1.00, green: 0.62, blue: 0.27) }
    if t >= 68 { return Color(red: 1.00, green: 0.82, blue: 0.40) }
    return Color(red: 0.29, green: 0.87, blue: 0.50)
}

/// 一行：小标签 + 百分比 / 大温度 / 细进度条
struct VitalsRow: View {
    var label: String
    var pct: Double
    var temp: Double
    var tempSize: CGFloat
    var barHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(pct.isNaN ? "--" : "\(Int(pct.rounded()))%")
                    .font(.system(size: 8.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(temp.isNaN ? "--" : String(format: "%.1f", temp))
                    .font(.system(size: tempSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tempColor(temp))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("°")
                    .font(.system(size: tempSize * 0.42, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tempColor(temp).opacity(0.85))
                        .frame(width: max(2, geo.size.width * (pct.isNaN ? 0 : min(100, max(0, pct))) / 100))
                }
            }
            .frame(height: barHeight)
        }
    }
}

struct VitalsWidgetView: View {
    var entry: VitalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(.thinMaterial, for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            VitalsRow(label: "CPU", pct: entry.cpuPct, temp: entry.cpuTemp, tempSize: 34, barHeight: 3)
            VitalsRow(label: "GPU", pct: entry.gpuPct, temp: entry.gpuTemp, tempSize: 34, barHeight: 3)
            footer
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                VitalsRow(label: "CPU", pct: entry.cpuPct, temp: entry.cpuTemp, tempSize: 40, barHeight: 3.5)
                VitalsRow(label: "GPU", pct: entry.gpuPct, temp: entry.gpuTemp, tempSize: 40, barHeight: 3.5)
            }
            footer
        }
    }

    /// 在线：RAM / 功耗；离线：明确说没数据，绝不显示成 0 W 的「待机」
    private var footer: some View {
        HStack(spacing: 0) {
            if entry.online {
                Text(String(format: "RAM %.1f/%.0f GB", entry.ramUsed, entry.ramTotal))
                Spacer(minLength: 4)
                Text(entry.watts.isNaN ? "-- W" : String(format: "%.1f W", entry.watts))
            } else {
                Text("macmon offline")
                Spacer(minLength: 4)
                Text("no data").opacity(0.6)
            }
        }
        .font(.system(size: 8.5))
        .monospacedDigit()
        .foregroundStyle(entry.online ? AnyShapeStyle(.secondary)
                                      : AnyShapeStyle(Color.orange.opacity(0.85)))
    }
}

struct M5VitalsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "M5VitalsWidget", intent: VitalsConfigIntent.self, provider: Provider()) { entry in
            VitalsWidgetView(entry: entry)
        }
        .configurationDisplayName("M5Vitals")
        .description("CPU / GPU temperature, memory and package power.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct M5VitalsWidgetBundle: WidgetBundle {
    var body: some Widget {
        M5VitalsWidget()
    }
}
