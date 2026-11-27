import SwiftUI
import AppKit

@main
struct ClaudeUsageMonitorApp: App {
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            Themed { ContentView() }
                .environmentObject(model)
                .onAppear { model.panelOpened() }
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
// Layout (TaskOcean-style): warm chrome band on top (wordmark · session hero ·
// account), white body with cards (weekly limits · trend), chrome band footer.
struct ContentView: View {
    @EnvironmentObject var model: UsageViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.divider).frame(height: 1)
            content
            Rectangle().fill(theme.divider).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .background(theme.window)
    }

    // MARK: Header band

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Wordmark()
                if let plan = model.plan, !model.needsLogin {
                    Chip(text: planLabel(plan))
                }
                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView().controlSize(.mini)
                }
                if !model.needsLogin {
                    ChromeIconButton(systemName: "arrow.clockwise", help: "새로고침") {
                        Task { await model.refresh(force: true) }
                    }
                }
            }

            if !model.needsLogin, model.usage != nil {
                sessionHero
            }

            if !model.needsLogin {
                accountRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .background(theme.chrome)
    }

    // The 5-hour session is the headline number — the big, date-like title.
    private var sessionHero: some View {
        let w = model.usage?.fiveHour
        let pct = w?.utilization
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("현재 세션")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                if let r = w?.resetsAt {
                    Text(sessionResetText(r))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(pct.map { "\(Int($0))" } ?? "–")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(pct.map(theme.levelColor) ?? theme.textMuted)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textMuted)
                Spacer(minLength: 0)
                Text("5시간 한도")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
            InkBar(fraction: (pct ?? 0) / 100,
                   color: pct.map(theme.levelColor) ?? theme.ink,
                   height: 6)
        }
        .animation(.snappy, value: pct)
    }

    // Which account the numbers belong to, plus an explicit logout.
    private var accountRow: some View {
        let a = model.account
        let primary = a?.email ?? a?.name ?? "계정 정보 확인 중…"
        var details: [String] = []
        if let n = a?.name, a?.email != nil { details.append(n) }
        if let o = a?.organization, !o.isEmpty { details.append(o) }
        if let src = a?.source {
            details.append(src == .app ? "앱 로그인" : "Claude Code 로그인 공유")
        }
        let avatarColor = a?.source == .claudeCode ? theme.accentBlue : theme.accentTan

        return HStack(spacing: 9) {
            Avatar(text: a?.email ?? a?.name ?? "?", color: a == nil ? theme.textFaint : avatarColor, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(a == nil ? theme.textMuted : theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
            Button {
                model.logout()
            } label: {
                Text("로그아웃")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 4.5)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(a?.source == .claudeCode
                  ? "이 앱에서만 로그아웃합니다 (Claude Code 로그인은 유지)"
                  : "로그아웃")
        }
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let up = model.availableUpdate {
                updateBanner(up)
            }

            if model.needsLogin {
                loginPrompt
            } else if let err = model.errorMessage, model.usage == nil {
                notice(icon: "exclamationmark.circle", tint: theme.danger,
                       title: "불러올 수 없음", message: err)
            } else {
                if let err = model.errorMessage {
                    notice(icon: "arrow.triangle.2.circlepath", tint: theme.warn,
                           title: "최신화를 잠시 못 했어요 — 마지막 데이터 표시 중",
                           message: err.contains("제한") ? err : nil)
                }

                SectionLabel("주간 한도")
                    .padding(.top, 2)

                LimitCard(title: "모든 모델", window: model.usage?.sevenDay)
                if let opus = model.usage?.sevenDayOpus, opus.utilization != nil {
                    LimitCard(title: "Opus", window: opus)
                }

                BurstChartView(snapshots: model.snapshots)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // Subtle, dismissible "update available" banner (TaskOcean's overdue-summary style).
    private func updateBanner(_ up: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.ok)
                Text("새 버전 \(up.version) 사용 가능")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button { model.dismissUpdate() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("이 버전 알림 숨기기")
            }
            HStack(spacing: 6) {
                Text(model.updateCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button { model.copyUpdateCommand() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: model.commandCopied ? "checkmark" : "doc.on.doc")
                        Text(model.commandCopied ? "복사됨" : "복사")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.onInk)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Homebrew 업데이트 명령 복사")
            }
            Button { NSWorkspace.shared.open(up.url) } label: {
                Text("또는 릴리즈에서 DMG 받기 →")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.infoSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorder, lineWidth: 1))
        .animation(.default, value: model.commandCopied)
    }

    private func notice(icon: String, tint: Color, title: String, message: String?) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.infoSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorder, lineWidth: 1))
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Avatar(text: "?", color: theme.textFaint, size: 40)
                .padding(.top, 10)
            VStack(spacing: 4) {
                Text("로그인이 필요해요")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Claude 계정으로 로그인하면\n플랜 사용량을 표시합니다.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textMuted)
            }
            if let err = model.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await model.login() }
            } label: {
                HStack(spacing: 7) {
                    if model.isLoggingIn {
                        ProgressView().controlSize(.small).tint(theme.onInk)
                        Text("브라우저에서 승인 대기 중…")
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Claude로 로그인")
                    }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isLoggingIn)
            .opacity(model.isLoggingIn ? 0.75 : 1)

            if model.signedOut {
                Button {
                    Task { await model.useClaudeCodeLogin() }
                } label: {
                    Text("Claude Code에 로그인된 계정 사용")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.chrome, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isLoggingIn || model.isLoading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: Footer band

    private var statusColor: Color {
        if model.needsLogin { return theme.textFaint }
        if model.isLoading { return theme.warn }
        if model.errorMessage != nil { return model.usage == nil ? theme.danger : theme.warn }
        return model.lastUpdated == nil ? theme.textFaint : theme.ok
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                StatusDot(color: statusColor)
                Text(lastUpdatedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                intervalMenu
                ChromeIconButton(systemName: "power", help: "종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
            HStack(spacing: 8) {
                if model.launchAtLoginSupported {
                    Toggle(isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) })) {
                        Text("로그인 시 자동 실행")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textMuted)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                updateCheckLink
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.chrome)
    }

    private var intervalMenu: some View {
        let options: [(Double, String)] = [(60, "1분"), (300, "5분"), (900, "15분"), (1800, "30분")]
        let current = options.first { $0.0 == model.pollInterval }?.1 ?? "5분"
        return Menu {
            ForEach(options, id: \.0) { opt in
                Button {
                    model.pollInterval = opt.0
                } label: {
                    if opt.0 == model.pollInterval {
                        Label("\(opt.1)마다", systemImage: "checkmark")
                    } else {
                        Text("\(opt.1)마다")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("\(current)마다")
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Chip styling lives outside the Menu: borderless menus drop label backgrounds.
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("자동 새로고침 주기")
    }

    // Subtle on-demand update check. Normally just shows the version; tapping
    // checks GitHub and either raises the banner or briefly confirms up-to-date.
    @ViewBuilder private var updateCheckLink: some View {
        if let v = model.displayVersion {
            Button {
                Task { await model.checkForUpdatesNow() }
            } label: {
                HStack(spacing: 4) {
                    if model.isCheckingForUpdate {
                        ProgressView().controlSize(.mini)
                        Text("확인 중…")
                    } else if model.noUpdateNotice {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.ok)
                        Text("최신 버전이에요")
                    } else {
                        Text("v\(v) · 업데이트 확인")
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(model.isCheckingForUpdate)
            .help("최신 업데이트 확인")
            .animation(.default, value: model.noUpdateNotice)
            .animation(.default, value: model.isCheckingForUpdate)
        }
    }

    private var lastUpdatedText: String {
        if model.needsLogin { return "로그인 대기 중" }
        guard let d = model.lastUpdated else { return "업데이트 대기 중" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 5 { return "방금 업데이트" }
        if secs < 60 { return "\(secs)초 전 업데이트" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)분 전 업데이트" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)시간 전 업데이트" : "\(h)시간 \(m)분 전 업데이트"
    }
}

// MARK: - Weekly limit card
struct LimitCard: View {
    let title: String
    let window: UsageWindow?
    @Environment(\.theme) private var theme

    var body: some View {
        let pct = window?.utilization
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
                if let pct {
                    Text("\(Int(pct))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.levelColor(pct))
                } else {
                    Text("데이터 없음")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            if let pct {
                InkBar(fraction: pct / 100, color: theme.levelColor(pct), height: 5)
            }
            if let r = window?.resetsAt {
                Text(weeklyResetText(r))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .card()
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
