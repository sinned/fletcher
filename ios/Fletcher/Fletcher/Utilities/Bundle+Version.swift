import Foundation

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var fullVersion: String {
        "v\(appVersion) (\(buildNumber))"
    }
}
