import SwiftUI
import AppKit

@main
struct ClaudeUsageMonitorApp: App {
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
                .onAppear { model.start() }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar status item label (live session %)
struct MenuBarLabel: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        if let pct = model.usage?.fiveHour?.utilization {
            Text("\(Int(pct))%")
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        }
    }
}

// MARK: - Dropdown content
struct ContentView: View {
    @EnvironmentObject var model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let up = model.availableUpdate {
                updateBanner(up)
            }

            if model.needsLogin {
                loginPrompt
            } else if let err = model.errorMessage, model.usage == nil {
                errorBox(err)
            } else {
                if model.errorMessage != nil { offlineNote }

                UsageBar(title: "현재 세션",
                         caption: model.usage?.fiveHour?.resetsAt.map(sessionResetText),
                         window: model.usage?.fiveHour)

                UsageBar(title: "주간 한도 · 모든 모델",
                         caption: model.usage?.sevenDay?.resetsAt.map(weeklyResetText),
                         window: model.usage?.sevenDay)

                if let opus = model.usage?.sevenDayOpus, opus.utilization != nil {
                    UsageBar(title: "주간 한도 · Opus",
                             caption: opus.resetsAt.map(weeklyResetText),
                             window: opus)
                }

                Divider()
                BurstChartView(snapshots: model.snapshots)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude 사용량")
                    .font(.system(size: 14, weight: .bold))
                if let plan = model.plan {
                    Text("플랜 한도 · \(planLabel(plan))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    // Subtle, dismissible "update available" banner — shown only when a newer
    // release exists. No modal, no system notification; opens Releases on tap.
    private func updateBanner(_ up: UpdateInfo) -> some View {
        let clay = Color(red: 0.851, green: 0.459, blue: 0.337)
        return HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(clay)
            VStack(alignment: .leading, spacing: 1) {
                Text("새 버전 \(up.version) 사용 가능")
                    .font(.system(size: 12, weight: .semibold))
                Text("클릭하면 다운로드 페이지가 열립니다")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("업데이트") { NSWorkspace.shared.open(up.url) }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(clay)
            Button {
                model.dismissUpdate()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("이 버전 알림 숨기기")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(clay.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loginPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Claude 계정으로 로그인하면\n플랜 사용량을 표시합니다.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let err = model.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await model.login() }
            } label: {
                HStack(spacing: 6) {
                    if model.isLoggingIn {
                        ProgressView().controlSize(.small)
                        Text("브라우저에서 승인 대기 중…")
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Claude로 로그인")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.851, green: 0.459, blue: 0.337))
            .disabled(model.isLoggingIn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // Shown above the (stale) data when a refresh failed for a transient reason
    // like no network — so frozen numbers never masquerade as current.
    private var offlineNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.system(size: 10))
            Text("연결 문제로 최신화 실패 — 마지막 데이터 표시 중")
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBox(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("불러올 수 없음", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lastUpdatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { model.pollInterval },
                    set: { model.pollInterval = $0 })) {
                    Text("30초").tag(30.0)
                    Text("60초").tag(60.0)
                    Text("120초").tag(120.0)
                    Text("300초").tag(300.0)
                }
                .labelsHidden()
                .font(.system(size: 10))
                .frame(width: 92)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("새로고침")

            if !model.needsLogin {
                Button {
                    model.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("로그아웃")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("종료")
        }
    }

    private var lastUpdatedText: String {
        guard let d = model.lastUpdated else { return "업데이트 대기 중" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 5 { return "마지막 업데이트: 방금" }
        if secs < 60 { return "마지막 업데이트: \(secs)초 전" }
        return "마지막 업데이트: \(secs / 60)분 전"
    }
}

// MARK: - Usage progress bar (mirrors the /usage panel)
struct UsageBar: View {
    let title: String
    let caption: String?
    let window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let u = window?.utilization {
                    Text("\(Int(u))% 사용됨")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let u = window?.utilization {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(barColor(u))
                            .frame(width: max(6, geo.size.width * min(max(u / 100, 0), 1)))
                    }
                }
                .frame(height: 8)
            } else {
                Text("데이터 없음").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func barColor(_ u: Double) -> Color {
        switch u {
        case ..<70: return .blue
        case ..<90: return .orange
        default:    return .red
        }
    }
}

// MARK: - Formatting helpers
func sessionResetText(_ date: Date) -> String {
    let secs = max(0, Int(date.timeIntervalSinceNow))
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h > 0 { return "\(h)시간 \(m)분 후 재설정" }
    return "\(m)분 후 재설정"
}

func weeklyResetText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "(EEE) a h:mm'에 재설정'"
    return f.string(from: date)
}

func planLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case let s where s.contains("max"): return "Max"
    case let s where s.contains("pro"): return "Pro"
    case let s where s.contains("team"): return "Team"
    default: return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
