import AppKit
import FinderSync
import SwiftUI
import UserNotifications

final class FinderIntegrationSettingsModel: ObservableObject {
    @Published var isExtensionEnabled = false
    @Published var notificationStatus = "尚未確認"
    @Published var isZipBrowsingEnabled = false
    @Published var isUpdatingZipBrowsing = false
    @Published var zipBrowsingStatus = "尚未確認"

    private let notificationService = FinderNotificationService()
    private let zipDefaultApplicationService =
        ZipDefaultApplicationService()

    var canChangeZipBrowsing: Bool {
        zipDefaultApplicationService.canChangeDefaultApplication
    }

    func refresh() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        refreshZipBrowsingStatus()
        notificationService.authorizationStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.notificationStatus = Self.description(for: status)
            }
        }
    }

    func setZipBrowsingEnabled(_ enabled: Bool) {
        isUpdatingZipBrowsing = true
        zipBrowsingStatus = "正在更新 ZIP 預設開啟方式..."
        zipDefaultApplicationService.setEnabled(enabled) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingZipBrowsing = false
                if let error = error {
                    self.zipBrowsingStatus =
                        (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
                self.refreshZipBrowsingStatus(
                    preservingError: error != nil
                )
            }
        }
    }

    private func refreshZipBrowsingStatus(
        preservingError: Bool = false
    ) {
        isZipBrowsingEnabled =
            zipDefaultApplicationService.isTuckByteDefaultApplication
        guard !preservingError else { return }

        if isZipBrowsingEnabled {
            zipBrowsingStatus = "雙擊 ZIP 時會使用 TuckByte 瀏覽內容。"
        } else if zipDefaultApplicationService.canChangeDefaultApplication {
            zipBrowsingStatus =
                "目前由 \(zipDefaultApplicationService.currentDefaultApplicationName) 開啟 ZIP。"
        } else {
            zipBrowsingStatus =
                "請使用打包後的 TuckByte.app 設定此功能。"
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
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "雙擊 ZIP 時先用 TuckByte 瀏覽",
                    isOn: Binding(
                        get: { model.isZipBrowsingEnabled },
                        set: model.setZipBrowsingEnabled
                    )
                )
                .disabled(
                    model.isUpdatingZipBrowsing
                    || !model.canChangeZipBrowsing
                )
                Text(model.zipBrowsingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Label("Finder 右鍵選單", systemImage: "folder.badge.gearshape")
                Spacer()
                Text(model.isExtensionEnabled ? "已啟用" : "未啟用")
                    .foregroundColor(model.isExtensionEnabled ? .green : .secondary)
                Button("開啟設定", action: model.openExtensionSettings)
            }

            HStack {
                Label("背景作業通知", systemImage: "bell")
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

            Text("啟用 TuckByte Finder Extension 後，右鍵選單可開啟介面、原地壓縮或解壓縮至此。")
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
