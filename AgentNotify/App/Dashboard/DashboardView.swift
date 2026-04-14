import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    private let cooldownOptions: [TimeInterval] = [15, 30, 60, 120, 300]
    private let detailColumnWidth: CGFloat = 420
    private let statusColumns = [
        GridItem(.flexible(minimum: 0), spacing: 10),
        GridItem(.flexible(minimum: 0), spacing: 10)
    ]

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    dashboardSection(title: "Needs Attention", accent: .orange) {
                        if let emptyText = viewModel.needsAttentionEmptyText {
                            emptyState(text: emptyText)
                        } else {
                            rowList(viewModel.needsAttentionRows)
                        }
                    }

                    dashboardSection(title: "All Monitored", accent: .blue) {
                        if viewModel.allMonitoredRows.isEmpty {
                            emptyState(text: String(localized: "No tabs are being monitored yet."))
                        } else {
                            rowList(viewModel.allMonitoredRows)
                        }
                    }

                    dashboardSection(title: "Settings", accent: .green) {
                        settingsContent
                    }

                    if let error = viewModel.inlineErrorText, !error.isEmpty {
                        errorBanner(error)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 680)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("AgentNotify")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(viewModel.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(.thinMaterial, in: Capsule())
                }

                LazyVGrid(columns: statusColumns, alignment: .leading, spacing: 10) {
                    statusTile(
                        title: "Notifications",
                        value: viewModel.notificationsStatusText,
                        tint: viewModel.isNotificationsGranted ? .green : .red
                    )
                    statusTile(
                        title: "Automation",
                        value: viewModel.automationStatusText,
                        tint: viewModel.isAutomationGranted ? .green : .orange
                    )
                    statusTile(
                        title: "Launch at Login",
                        value: viewModel.launchAtLoginEnabled ? String(localized: "On") : String(localized: "Off"),
                        tint: viewModel.launchAtLoginEnabled ? .green : .gray
                    )
                    statusTile(
                        title: "Alerts",
                        value: viewModel.isMuted ? String(localized: "Muted") : String(localized: "Sound On"),
                        tint: viewModel.isMuted ? .orange : .blue
                    )
                }
            }
            .frame(maxWidth: detailColumnWidth, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Mute Alerts", isOn: Binding(
                get: { viewModel.isMuted },
                set: { viewModel.setMuted($0) }
            ))

            VStack(alignment: .leading, spacing: 8) {
                Text("Alert Cooldown")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 12) {
                    Text("Alert Cooldown")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Picker("Alert Cooldown", selection: Binding(
                        get: { viewModel.alertCooldownSeconds },
                        set: { viewModel.setAlertCooldown($0) }
                    )) {
                        ForEach(cooldownOptions, id: \.self) { seconds in
                            Text(cooldownLabel(for: seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                )
            }

            HStack(spacing: 12) {
                settingStatusCard(title: "Notifications", value: viewModel.notificationsStatusText)
                settingStatusCard(title: "Automation", value: viewModel.automationStatusText)
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { viewModel.launchAtLoginEnabled },
                set: { _ in viewModel.toggleLaunchAtLogin() }
            ))

            Button("Test Moo") {
                viewModel.testMoo()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Quit AgentNotify") {
                viewModel.quit()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowList(_ rows: [DashboardRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                Button {
                    viewModel.select(row)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.headline)
                            if row.isCoolingDown {
                                Text("Cooling down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(row.badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.isWaiting ? .orange : .secondary)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(row.isWaiting ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.10))
                            )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.70))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
    }

    private func dashboardSection<Content: View>(
        title: LocalizedStringKey,
        accent: Color,
        maxWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
    }

    private func statusTile(title: LocalizedStringKey, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func settingStatusCard(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }

    private func cooldownLabel(for seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(localized: "\(Int(seconds))s")
        }

        let minutes = Int(seconds / 60)
        return minutes == 1 ? String(localized: "1 minute") : String(localized: "\(minutes) minutes")
    }
}
