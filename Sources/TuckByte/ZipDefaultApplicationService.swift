import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

final class ZipDefaultApplicationService {
    private static let previousApplicationURLKey =
        "zipBrowser.previousDefaultApplicationURL"
    private static let archiveUtilityURL = URL(
        fileURLWithPath:
            "/System/Library/CoreServices/Applications/Archive Utility.app",
        isDirectory: true
    )

    private let workspace: NSWorkspace
    private let userDefaults: UserDefaults

    init(
        workspace: NSWorkspace = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.workspace = workspace
        self.userDefaults = userDefaults
    }

    var canChangeDefaultApplication: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    var isTuckByteDefaultApplication: Bool {
        guard let tuckByteBundleIdentifier = Bundle.main.bundleIdentifier,
              let currentURL = currentDefaultApplicationURL,
              let currentBundleIdentifier = bundleIdentifier(at: currentURL) else {
            return false
        }
        return currentBundleIdentifier == tuckByteBundleIdentifier
    }

    var currentDefaultApplicationName: String {
        currentDefaultApplicationURL?
            .deletingPathExtension()
            .lastPathComponent ?? "系統預設程式"
    }

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        guard canChangeDefaultApplication else {
            completion(ZipDefaultApplicationError.appBundleRequired)
            return
        }

        if enabled {
            rememberCurrentApplication()
            setDefaultApplication(Bundle.main.bundleURL, completion: completion)
            return
        }

        setDefaultApplication(restorationApplicationURL) { [weak self] error in
            if error == nil {
                self?.userDefaults.removeObject(
                    forKey: Self.previousApplicationURLKey
                )
            }
            completion(error)
        }
    }

    private var currentDefaultApplicationURL: URL? {
        if #available(macOS 12.0, *) {
            return workspace.urlForApplication(toOpen: .zip)
        }

        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            UTType.zip.identifier as CFString,
            .all
        )?.takeRetainedValue() else {
            return nil
        }
        return workspace.urlForApplication(
            withBundleIdentifier: handler as String
        )
    }

    private var restorationApplicationURL: URL {
        if let storedPath = userDefaults.string(
            forKey: Self.previousApplicationURLKey
        ) {
            let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: storedURL.path),
               bundleIdentifier(at: storedURL) != Bundle.main.bundleIdentifier {
                return storedURL
            }
        }
        return Self.archiveUtilityURL
    }

    private func rememberCurrentApplication() {
        guard let tuckByteBundleIdentifier = Bundle.main.bundleIdentifier,
              let currentURL = currentDefaultApplicationURL,
              bundleIdentifier(at: currentURL) != tuckByteBundleIdentifier else {
            return
        }
        userDefaults.set(
            currentURL.path,
            forKey: Self.previousApplicationURLKey
        )
    }

    private func setDefaultApplication(
        _ applicationURL: URL,
        completion: @escaping (Error?) -> Void
    ) {
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            completion(
                ZipDefaultApplicationError.applicationNotFound(applicationURL)
            )
            return
        }

        if #available(macOS 12.0, *) {
            workspace.setDefaultApplication(
                at: applicationURL,
                toOpen: .zip,
                completion: completion
            )
            return
        }

        guard let bundleIdentifier = bundleIdentifier(at: applicationURL) else {
            completion(
                ZipDefaultApplicationError.missingBundleIdentifier(
                    applicationURL
                )
            )
            return
        }
        let status = LSSetDefaultRoleHandlerForContentType(
            UTType.zip.identifier as CFString,
            .all,
            bundleIdentifier as CFString
        )
        guard status == noErr else {
            completion(ZipDefaultApplicationError.launchServices(status))
            return
        }
        completion(nil)
    }

    private func bundleIdentifier(at applicationURL: URL) -> String? {
        Bundle(url: applicationURL)?.bundleIdentifier
    }
}

private enum ZipDefaultApplicationError: LocalizedError {
    case appBundleRequired
    case applicationNotFound(URL)
    case missingBundleIdentifier(URL)
    case launchServices(OSStatus)

    var errorDescription: String? {
        switch self {
        case .appBundleRequired:
            return "請先將 TuckByte.app 放進「應用程式」後再設定。"
        case .applicationNotFound(let url):
            return "找不到要設為 ZIP 預設程式的 App：\(url.path)"
        case .missingBundleIdentifier(let url):
            return "無法辨識 App 的 bundle identifier：\(url.path)"
        case .launchServices(let status):
            return "無法更新 ZIP 預設程式（狀態碼 \(status)）。"
        }
    }
}
