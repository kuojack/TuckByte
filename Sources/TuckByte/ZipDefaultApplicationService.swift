import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

final class ZipDefaultApplicationService {
    private static let previousZipApplicationURLKey =
        "zipBrowser.previousDefaultApplicationURL"
    private static let previousSevenZipApplicationURLKey =
        "sevenZipBrowser.previousDefaultApplicationURL"
    private static let sevenZipType = UTType(
        importedAs: "org.7-zip.7-zip-archive"
    )
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
        guard let tuckByteBundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        return archiveTypes.allSatisfy { archiveType in
            guard let currentURL = currentDefaultApplicationURL(
                for: archiveType.contentType
            ) else {
                return false
            }
            return bundleIdentifier(at: currentURL) == tuckByteBundleIdentifier
        }
    }

    var currentDefaultApplicationName: String {
        let names = archiveTypes.compactMap { archiveType in
            currentDefaultApplicationURL(for: archiveType.contentType)?
                .deletingPathExtension()
                .lastPathComponent
        }
        let uniqueNames = Array(Set(names)).sorted()
        return uniqueNames.isEmpty
            ? "系統預設程式"
            : uniqueNames.joined(separator: "、")
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
            rememberCurrentApplications()
            let requests = archiveTypes.map {
                (Bundle.main.bundleURL, $0.contentType)
            }
            setDefaultApplications(requests, completion: completion)
            return
        }

        let requests = archiveTypes.map {
            (restorationApplicationURL(forKey: $0.previousApplicationKey), $0.contentType)
        }
        setDefaultApplications(requests) { [weak self] error in
            if error == nil {
                self?.userDefaults.removeObject(
                    forKey: Self.previousZipApplicationURLKey
                )
                self?.userDefaults.removeObject(
                    forKey: Self.previousSevenZipApplicationURLKey
                )
            }
            completion(error)
        }
    }

    private var archiveTypes: [(
        contentType: UTType,
        previousApplicationKey: String
    )] {
        [
            (.zip, Self.previousZipApplicationURLKey),
            (Self.sevenZipType, Self.previousSevenZipApplicationURLKey)
        ]
    }

    private func currentDefaultApplicationURL(
        for contentType: UTType
    ) -> URL? {
        if #available(macOS 12.0, *) {
            return workspace.urlForApplication(toOpen: contentType)
        }

        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            contentType.identifier as CFString,
            .all
        )?.takeRetainedValue() else {
            return nil
        }
        return workspace.urlForApplication(
            withBundleIdentifier: handler as String
        )
    }

    private func restorationApplicationURL(forKey key: String) -> URL {
        if let storedPath = userDefaults.string(
            forKey: key
        ) {
            let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: storedURL.path),
               bundleIdentifier(at: storedURL) != Bundle.main.bundleIdentifier {
                return storedURL
            }
        }
        return Self.archiveUtilityURL
    }

    private func rememberCurrentApplications() {
        guard let tuckByteBundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }
        for archiveType in archiveTypes {
            guard let currentURL = currentDefaultApplicationURL(
                for: archiveType.contentType
            ), bundleIdentifier(at: currentURL) != tuckByteBundleIdentifier else {
                continue
            }
            userDefaults.set(
                currentURL.path,
                forKey: archiveType.previousApplicationKey
            )
        }
    }

    private func setDefaultApplications(
        _ requests: [(applicationURL: URL, contentType: UTType)],
        completion: @escaping (Error?) -> Void
    ) {
        guard let request = requests.first else {
            completion(nil)
            return
        }
        setDefaultApplication(
            request.applicationURL,
            for: request.contentType
        ) { error in
            guard error == nil else {
                completion(error)
                return
            }
            self.setDefaultApplications(
                Array(requests.dropFirst()),
                completion: completion
            )
        }
    }

    private func setDefaultApplication(
        _ applicationURL: URL,
        for contentType: UTType,
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
                toOpen: contentType,
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
            contentType.identifier as CFString,
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
            return "找不到要設為壓縮檔預設程式的 App：\(url.path)"
        case .missingBundleIdentifier(let url):
            return "無法辨識 App 的 bundle identifier：\(url.path)"
        case .launchServices(let status):
            return "無法更新壓縮檔預設程式（狀態碼 \(status)）。"
        }
    }
}
