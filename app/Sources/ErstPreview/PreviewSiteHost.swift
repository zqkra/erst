import Foundation

/// The site a preview URL stands for, with the same rule as `erst_core::url_host`.
enum PreviewSiteHost {
    /// The host, lowercased and without a leading `www.`.
    static func host(_ url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
