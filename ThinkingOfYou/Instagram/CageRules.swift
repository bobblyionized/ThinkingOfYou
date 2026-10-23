//  CageRules.swift
//  ThinkingOfYou/Instagram — the native mirror of the route rules in Cage.js.
//  Pure value type: used by the WKNavigationDelegate as a backstop for full
//  page navigations (Cage.js handles Instagram's client-side routing).
//
//  While LOCKED these bounce to the inbox:
//    /                         the feed
//    /reels/..., bare /reel/   Reels
//    /explore/...              Explore
//    /<user>/reels|tagged|saved/...
//    /<ownUsername>/...        your own profile, posts and videos
//  and on a single /reel/<code>/ page, moving to a different reel code is
//  refused (no scrolling to the next reel).
//  Always allowed: DMs, notes, stories, other profiles, notifications, a
//  single /p/<code>/ and a single /reel/<code>/.

import Foundation

struct CageRules: Equatable, Sendable {
    static let inboxPath = "/direct/inbox/"
    static let inboxURL = URL(string: "https://www.instagram.com/direct/inbox/")!
    static let activityURL = URL(string: "https://www.instagram.com/accounts/activity/")!

    /// Why a path is blocked. `reason` is the phrase shown in toasts and is
    /// identical to the strings Cage.js posts.
    enum Block: String, Equatable, Sendable, CaseIterable {
        case feed
        case reels
        case explore
        case profileTab
        case ownProfile
        case nextReel

        var reason: String {
            switch self {
            case .feed: return "The feed"
            case .reels: return "Reels"
            case .explore: return "Explore"
            case .profileTab: return "That profile tab"
            case .ownProfile: return "Your own profile"
            case .nextReel: return "The next reel"
            }
        }

        /// Next-reel blocks keep you on the current reel; everything else
        /// bounces to the inbox.
        var bouncesToInbox: Bool { self != .nextReel }
    }

    /// What the navigation delegate should do with a request.
    enum NavigationDecision: Equatable, Sendable {
        case allow
        /// Drop it silently (e.g. "open in the Instagram app" deep links).
        case cancel
        /// Refuse it and toast `block.reason`; bounce to the inbox if `block.bouncesToInbox`.
        case block(Block)
        /// Not Instagram: hand it to Safari / the system.
        case openExternally(URL)
        /// Load this Instagram URL instead (`/reels/<code>/` -> `/reel/<code>/`).
        case redirect(URL)
    }

    /// Normalized (lowercase, no "@") username whose profile is blocked.
    var ownUsername: String?

    init(ownUsername: String? = nil) {
        self.ownUsername = CageRules.sanitizeUsername(ownUsername)
    }

    // MARK: Paths

    static let profileTabs: Set<String> = ["reels", "tagged", "saved"]

    /// Path segments, without empty pieces, query or fragment.
    static func segments(of path: String) -> [String] {
        let bare = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let noFragment = bare.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? bare
        return noFragment.split(separator: "/").map(String.init)
    }

    /// The code of a single-reel path, case preserved: `/reel/<code>/` or the
    /// user-scoped form `/<user>/reel/<code>/`.
    static func reelCode(inPath path: String) -> String? {
        let parts = segments(of: path)
        if parts.count >= 2, parts[0].lowercased() == "reel" { return parts[1] }
        if parts.count >= 3, parts[1].lowercased() == "reel", isProfileSegment(parts[0]) { return parts[2] }
        return nil
    }

    /// A first segment that can be a username (not an Instagram route).
    static func isProfileSegment(_ segment: String) -> Bool {
        isUsernameLike(segment) && !reservedTopLevel.contains(segment.lowercased())
    }

    /// True for something shaped like a post/reel shortcode (not "audio" etc.).
    static func isShortcode(_ segment: String) -> Bool {
        segment.count >= 8 && segment.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || scalar == "_" || scalar == "-"
        }
    }

    /// `/reels/<code>/` is the Reels feed positioned on one reel. While locked
    /// it is rewritten to the single-reel page `/reel/<code>/` instead of
    /// bouncing, so a friend's reel shared in that form still opens.
    static func singleReelRedirect(forPath path: String) -> String? {
        let parts = segments(of: path)
        guard parts.count >= 2, parts[0].lowercased() == "reels", isShortcode(parts[1]) else { return nil }
        return "/reel/\(parts[1])/"
    }

    /// The reel code of `/reel/<code>/` or `/reels/<code>/`.
    static func anyReelCode(inPath path: String) -> String? {
        if let code = reelCode(inPath: path) { return code }
        let parts = segments(of: path)
        guard parts.count >= 2, parts[0].lowercased() == "reels", isShortcode(parts[1]) else { return nil }
        return parts[1]
    }

    private static func isUsernameLike(_ segment: String) -> Bool {
        !segment.isEmpty && segment.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_"
        }
    }

    /// The route block for a path while locked, or nil when it's allowed.
    func blockedRoute(forPath path: String) -> Block? {
        let parts = Self.segments(of: path).map { $0.lowercased() }
        guard let first = parts.first else { return .feed }
        if first == "reels" || (first == "reel" && parts.count == 1) { return .reels }
        if first == "explore" { return .explore }
        // Bare `/<user>/reel/` (no code) is a doorway into Reels.
        if parts.count == 2, parts[1] == "reel", Self.isProfileSegment(first) { return .reels }
        if parts.count >= 2, Self.isUsernameLike(first), Self.profileTabs.contains(parts[1]) { return .profileTab }
        if let own = ownUsername, first == own { return .ownProfile }
        return nil
    }

    /// True when moving from one reel to a different one (scrolling to the
    /// next reel) while locked. Either side may be any reel form.
    func blocksNextReel(fromPath current: String?, toPath next: String) -> Bool {
        guard let current,
              let from = Self.anyReelCode(inPath: current),
              let to = Self.anyReelCode(inPath: next) else { return false }
        return from != to
    }

    /// True when both paths show the same reel code (e.g. Instagram rewriting
    /// `/reel/A/` to `/reels/A/`): never blocked or redirected, so it can't loop.
    static func isSameReel(_ current: String?, _ next: String) -> Bool {
        guard let current,
              let from = anyReelCode(inPath: current),
              let to = anyReelCode(inPath: next) else { return false }
        return from == to
    }

    /// Full rule for a locked path, including the next-reel rule. (A
    /// `/reels/<code>/` path reports `.reels` here; `decide` redirects it.)
    func block(forPath path: String, currentPath: String?) -> Block? {
        if blocksNextReel(fromPath: currentPath, toPath: path) { return .nextReel }
        if let route = blockedRoute(forPath: path) { return route }
        return nil
    }

    // MARK: Hosts

    static func isInstagramHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    /// Facebook / Meta hosts used by "Log in with Facebook" and Accounts Center.
    static func isMetaLoginHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        let roots = ["facebook.com", "meta.com", "fbsbx.com"]
        return roots.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isMetaLoginPath(_ path: String) -> Bool {
        let p = path.lowercased()
        // Versioned Graph dialogs: /v19.0/dialog/oauth
        if p.hasPrefix("/v"), let next = p.dropFirst(2).first, next.isNumber { return true }
        let prefixes = ["/login", "/dialog", "/oauth", "/checkpoint", "/recover", "/two_step", "/auth",
                        "/accounts", "/cookie", "/privacy", "/help", "/security", "/x/oauth"]
        return prefixes.contains { p.hasPrefix($0) }
    }

    /// Schemes that would hand off to the real Instagram app or the App Store:
    /// dropped silently.
    static let silentlyDroppedSchemes: Set<String> = ["instagram", "itms-apps", "itms-appss", "itms", "fb", "intent", "barcelona"]
    /// Schemes the web view handles itself.
    static let inWebViewSchemes: Set<String> = ["about", "blob", "data", "javascript"]

    /// The real target of Instagram's link shim (`l.instagram.com/?u=...`).
    static func unwrapLinkShim(_ url: URL) -> URL? {
        guard url.host?.lowercased() == "l.instagram.com",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "u" })?.value,
              let target = URL(string: raw),
              let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return target
    }

    // MARK: Navigation policy

    /// Decides a WKWebView navigation. `currentURL` is the page being left.
    func decide(url: URL, currentURL: URL?, isMainFrame: Bool, unlocked: Bool) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        if Self.inWebViewSchemes.contains(scheme) { return .allow }
        if Self.silentlyDroppedSchemes.contains(scheme) { return .cancel }
        guard scheme == "http" || scheme == "https" else {
            // mailto:, tel:, sms:, maps: ... belong to the system.
            return isMainFrame ? .openExternally(url) : .cancel
        }
        // Sub-frames (captcha, consent, media) are never caged.
        guard isMainFrame else { return .allow }

        if Self.isInstagramHost(url.host) {
            if let target = Self.unwrapLinkShim(url) {
                return Self.isInstagramHost(target.host)
                    ? decide(url: target, currentURL: currentURL, isMainFrame: true, unlocked: unlocked)
                    : .openExternally(target)
            }
            if url.host?.lowercased() == "l.instagram.com" { return .cancel }
            guard !unlocked else { return .allow }
            let path = Self.pathWithSlash(url)
            let currentPath = Self.isInstagramHost(currentURL?.host) ? currentURL?.path : nil
            if blocksNextReel(fromPath: currentPath, toPath: path) { return .block(.nextReel) }
            if Self.isSameReel(currentPath, path) { return .allow }
            if let single = Self.singleReelRedirect(forPath: path),
               let target = URL(string: "https://www.instagram.com" + single) {
                return .redirect(target)
            }
            if let block = blockedRoute(forPath: path) { return .block(block) }
            return .allow
        }

        if Self.isMetaLoginHost(url.host), Self.isMetaLoginPath(url.path) {
            return .allow
        }
        return .openExternally(url)
    }

    /// `URL.path` drops the trailing slash and turns "" into ""; normalize to "/".
    static func pathWithSlash(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    // MARK: Usernames

    /// Lowercased, "@"-stripped username, or nil if it isn't a valid handle
    /// (1-30 of a-z, 0-9, ".", "_").
    static func sanitizeUsername(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if name.hasPrefix("@") { name.removeFirst() }
        if name.hasSuffix("/") { name.removeLast() }
        guard (1...30).contains(name.count) else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._")
        guard name.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard !reservedTopLevel.contains(name) else { return nil }
        return name
    }

    /// First path segments that are Instagram routes, never usernames.
    static let reservedTopLevel: Set<String> = [
        "direct", "p", "reel", "reels", "tv", "stories", "explore", "accounts", "about", "legal",
        "developer", "emails", "challenge", "notes", "web", "api", "graphql", "ajax", "static",
        "create", "session", "privacy", "terms", "help", "your_activity", "nametag", "qr", "sync",
        "invites", "lite", "topics", "locations", "music", "audio", "threads", "oauth", "data", "_n", "_u"
    ]
}
