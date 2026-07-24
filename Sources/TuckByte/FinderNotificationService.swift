import Foundation
import UserNotifications
import TuckByteCore

final class FinderNotificationService {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    func deliverExtractionSuccess(
        results: [ArchiveExtractionResult],
        completion: @escaping (Bool) -> Void
    ) {
        authorizationStatus { [weak self] status in
            guard let self = self else {
                completion(false)
                return
            }

            switch status {
            case .authorized, .provisional:
                self.scheduleExtractionSuccess(results: results, completion: completion)
            case .notDetermined, .denied, .ephemeral:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    func deliverCompressionSuccess(
        result: ArchiveCompressionResult,
        completion: @escaping (Bool) -> Void
    ) {
        guard result.succeeded, let destinationURL = result.destinationURL else {
            completion(false)
            return
        }

        authorizationStatus { [weak self] status in
            guard let self = self else {
                completion(false)
                return
            }

            switch status {
            case .authorized, .provisional:
                self.scheduleCompressionSuccess(
                    destinationURL: destinationURL,
                    completion: completion
                )
            case .notDetermined, .denied, .ephemeral:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    private func scheduleExtractionSuccess(
        results: [ArchiveExtractionResult],
        completion: @escaping (Bool) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = "TuckByte 解壓完成"

        if results.count == 1, let result = results.first, let destinationURL = result.destinationURL {
            content.body = "\(result.archiveURL.lastPathComponent) 已解壓到 \(destinationURL.path)"
        } else {
            content.body = "已完成 \(results.count) 個 ZIP 的解壓。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "finder-extract-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { error in
            completion(error == nil)
        }
    }

    private func scheduleCompressionSuccess(
        destinationURL: URL,
        completion: @escaping (Bool) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = "TuckByte 壓縮完成"
        content.body = "\(destinationURL.lastPathComponent) 已建立於 \(destinationURL.path)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "finder-compress-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { error in
            completion(error == nil)
        }
    }
}
