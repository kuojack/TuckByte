import AppKit
import FinderSync
import SwiftUI
import UserNotifications

final class FinderIntegrationSettingsModel: ObservableObject {
    @Published var isExtensionEnabled = false
    @Published var notificationStatus = "尚未確認"

    private let notificationService = FinderNotificationService()

    func refresh() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        notificationService.authorizationStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.notificationStatus = Self.description(for: status)
            }
        }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func requestNotificationAuthorization() {
        notificationService.requestAuthorization { [weak self] _ in
            self?.refresh()
        }
    }

    private static func description(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional:
            return "已允許"
        case .denied:
            return "已拒絕"
        case .notDetermined:
            return "尚未詢問"
        case .ephemeral:
            return "暫時允許"
        @unknown default:
            return "未知"
        }
    }
}

struct FinderIntegrationSettingsView: View {
    @StateObject private var model = FinderIntegrationSettingsModel()

    var body: some View {
        Form {
            HStack {
                Label("Finder 右鍵選單", systemImage: "folder.badge.gearshape")
                Spacer()
                Text(model.isExtensionEnabled ? "已啟用" : "未啟用")
                    .foregroundColor(model.isExtensionEnabled ? .green : .secondary)
                Button("開啟設定", action: model.openExtensionSettings)
            }

            HStack {
                Label("背景解壓通知", systemImage: "bell")
                Spacer()
                Text(model.notificationStatus)
                    .foregroundColor(.secondary)
                Button("允許通知", action: model.requestNotificationAuthorization)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: model.refresh)
    }
}

struct FinderIntegrationOnboardingView: View {
    @StateObject private var model = FinderIntegrationSettingsModel()
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("啟用 Finder 整合", systemImage: "folder.badge.gearshape")
                .font(.title2.weight(.semibold))

            Text("啟用 ZipForge Finder Extension 後，檔案右鍵選單會出現「加入壓縮檔」與「解壓縮至此」。")
                .foregroundColor(.secondary)

            HStack {
                Button("開啟 Finder Extension 設定", action: model.openExtensionSettings)
                Button("允許完成通知", action: model.requestNotificationAuthorization)
            }

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear(perform: model.refresh)
    }
}
