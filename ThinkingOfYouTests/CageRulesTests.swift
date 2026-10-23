import XCTest
@testable import ThinkingOfYou

final class CageRulesTests: XCTestCase {

    private let rules = CageRules()
    private let mine = CageRules(ownUsername: "@Me.Myself")

    private func ig(_ path: String) -> URL {
        URL(string: "https://www.instagram.com" + path)!
    }

    // MARK: Route rules (locked)

    func testFeedsAreBlocked() {
        XCTAssertEqual(rules.blockedRoute(forPath: "/"), .feed)
        XCTAssertEqual(rules.blockedRoute(forPath: ""), .feed)
        XCTAssertEqual(rules.blockedRoute(forPath: "/?variant=following"), .feed)
        XCTAssertEqual(rules.blockedRoute(forPath: "/reels/"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/reels"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/reels/C9xYz12AbCd/"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/reel/"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/reel"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/explore/"), .explore)
        XCTAssertEqual(rules.blockedRoute(forPath: "/explore/tags/cats/"), .explore)
        XCTAssertEqual(rules.blockedRoute(forPath: "/explore/search/"), .explore)
    }

    func testProfileTabsAreBlocked() {
        XCTAssertEqual(rules.blockedRoute(forPath: "/some.friend/reels/"), .profileTab)
        XCTAssertEqual(rules.blockedRoute(forPath: "/some_friend/tagged/"), .profileTab)
        XCTAssertEqual(rules.blockedRoute(forPath: "/somefriend/saved/all-posts/"), .profileTab)
        XCTAssertEqual(rules.blockedRoute(forPath: "/SomeFriend/Reels"), .profileTab)
    }

    func testAllowedPaths() {
        let allowed = [
            "/direct/inbox/",
            "/direct/t/1234567890/",
            "/direct/new/",
            "/p/CxYz123AbCd/",
            "/reel/CxYz123AbCd/",
            "/reel/CxYz123AbCd/?igsh=abc",
            "/stories/some.friend/3141592653/",
            "/stories/highlights/1789/",
            "/some.friend/",
            "/some.friend/p/CxYz123AbCd/",
            "/accounts/activity/",
            "/accounts/edit/",
            "/notes/",
        ]
        for path in allowed {
            XCTAssertNil(rules.blockedRoute(forPath: path), path)
            XCTAssertNil(rules.block(forPath: path, currentPath: "/direct/inbox/"), path)
        }
    }

    // MARK: Own profile

    func testOwnProfileIsBlockedCaseInsensitively() {
        XCTAssertEqual(mine.ownUsername, "me.myself")
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/"), .ownProfile)
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself"), .ownProfile)
        XCTAssertEqual(mine.blockedRoute(forPath: "/ME.MYSELF/"), .ownProfile)
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/p/CxYz123AbCd/"), .ownProfile)
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/reel/CxYz123AbCd/"), .ownProfile)
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/followers/"), .ownProfile)
        // Own profile tabs report as profile tabs (blocked either way).
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/reels/"), .profileTab)
    }

    func testOwnProfileRuleDoesNotCatchOtherPaths() {
        XCTAssertNil(mine.blockedRoute(forPath: "/me.myselfie/"))
        XCTAssertNil(mine.blockedRoute(forPath: "/stories/me.myself/123/"))
        XCTAssertNil(mine.blockedRoute(forPath: "/direct/inbox/"))
        XCTAssertNil(mine.blockedRoute(forPath: "/p/me.myself/"))
    }

    func testWithoutAUsernameProfilesAreAllowed() {
        XCTAssertNil(rules.ownUsername)
        XCTAssertNil(rules.blockedRoute(forPath: "/me.myself/"))
    }

    func testOwnProfileBlocksFullNavigationsAndBouncesToInbox() {
        let decision = mine.decide(url: ig("/me.myself/"), currentURL: ig("/direct/inbox/"), isMainFrame: true, unlocked: false)
        XCTAssertEqual(decision, .block(.ownProfile))
        XCTAssertTrue(CageRules.Block.ownProfile.bouncesToInbox)
        XCTAssertEqual(mine.decide(url: ig("/me.myself/"), currentURL: nil, isMainFrame: true, unlocked: true), .allow)
    }

    // MARK: Next reel

    func testNextReelIsBlockedFromASingleReel() {
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/reel/AAAAAAAAAAA/", toPath: "/reel/BBBBBBBBBBB/"))
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/reel/AAAAAAAAAAA", toPath: "/reels/BBBBBBBBBBB/"))
        XCTAssertFalse(rules.blocksNextReel(fromPath: "/reel/AAAAAAAAAAA/", toPath: "/reel/AAAAAAAAAAA/?igsh=1"))
        XCTAssertFalse(rules.blocksNextReel(fromPath: "/direct/t/123/", toPath: "/reel/BBBBBBBBBBB/"))
        XCTAssertFalse(rules.blocksNextReel(fromPath: nil, toPath: "/reel/BBBBBBBBBBB/"))
        XCTAssertFalse(rules.blocksNextReel(fromPath: "/reel/AAAAAAAAAAA/", toPath: "/direct/inbox/"))
        XCTAssertEqual(rules.block(forPath: "/reel/BBBBBBBBBBB/", currentPath: "/reel/AAAAAAAAAAA/"), .nextReel)
        XCTAssertFalse(CageRules.Block.nextReel.bouncesToInbox)
    }

    func testUserScopedReelsAreSingleReels() {
        XCTAssertEqual(CageRules.reelCode(inPath: "/ada/reel/CxYz123AbCd/"), "CxYz123AbCd")
        XCTAssertEqual(CageRules.reelCode(inPath: "/Ada.L/reel/CxYz123AbCd/?igsh=1"), "CxYz123AbCd")
        XCTAssertEqual(CageRules.anyReelCode(inPath: "/ada/reel/CxYz123AbCd/"), "CxYz123AbCd")
        XCTAssertNil(CageRules.reelCode(inPath: "/p/reel/CxYz123AbCd/"))        // reserved first segment
        XCTAssertNil(CageRules.reelCode(inPath: "/explore/reel/CxYz123AbCd/"))
        XCTAssertNil(CageRules.reelCode(inPath: "/ada/reel/"))

        // The next-reel lock covers the user-scoped form.
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/ada/reel/AAAAAAAAAAA/", toPath: "/ada/reel/BBBBBBBBBBB/"))
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/ada/reel/AAAAAAAAAAA/", toPath: "/reel/BBBBBBBBBBB/"))
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/reel/AAAAAAAAAAA/", toPath: "/ada/reel/BBBBBBBBBBB/"))
        XCTAssertFalse(rules.blocksNextReel(fromPath: "/ada/reel/AAAAAAAAAAA/", toPath: "/ada/reel/AAAAAAAAAAA/"))
        XCTAssertEqual(rules.decide(url: ig("/ada/reel/BBBBBBBBBBB/"), currentURL: ig("/ada/reel/AAAAAAAAAAA/"),
                                    isMainFrame: true, unlocked: false), .block(.nextReel))

        // A single user-scoped reel is allowed; the bare doorway is Reels.
        XCTAssertNil(rules.blockedRoute(forPath: "/ada/reel/AAAAAAAAAAA/"))
        XCTAssertEqual(rules.blockedRoute(forPath: "/ada/reel/"), .reels)
        XCTAssertEqual(rules.blockedRoute(forPath: "/ada/reel"), .reels)
        XCTAssertNil(rules.blockedRoute(forPath: "/p/reel/"))
        // Own user-scoped reels stay blocked as your own profile.
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/reel/"), .reels)
        XCTAssertEqual(mine.blockedRoute(forPath: "/me.myself/reel/AAAAAAAAAAA/"), .ownProfile)
    }

    func testSameReelInAnotherFormNeverLoops() {
        XCTAssertTrue(CageRules.isSameReel("/reel/AAAAAAAAAAA/", "/reels/AAAAAAAAAAA/"))
        XCTAssertFalse(CageRules.isSameReel("/reel/AAAAAAAAAAA/", "/reels/BBBBBBBBBBB/"))
        XCTAssertFalse(CageRules.isSameReel(nil, "/reels/AAAAAAAAAAA/"))
        // Rewriting /reel/A/ to /reels/A/ is allowed, not redirected back.
        XCTAssertEqual(rules.decide(url: ig("/reels/AAAAAAAAAAA/"), currentURL: ig("/reel/AAAAAAAAAAA/"),
                                    isMainFrame: true, unlocked: false), .allow)
        // ...and the other direction too.
        XCTAssertEqual(rules.decide(url: ig("/reel/AAAAAAAAAAA/"), currentURL: ig("/reels/AAAAAAAAAAA/"),
                                    isMainFrame: true, unlocked: false), .allow)
        // But moving on from a /reels/ page to another code is still the next reel.
        XCTAssertTrue(rules.blocksNextReel(fromPath: "/reels/AAAAAAAAAAA/", toPath: "/reel/BBBBBBBBBBB/"))
    }

    func testReelCodes() {
        XCTAssertEqual(CageRules.reelCode(inPath: "/reel/CxYz123AbCd/"), "CxYz123AbCd")
        XCTAssertNil(CageRules.reelCode(inPath: "/reels/CxYz123AbCd/"))
        XCTAssertEqual(CageRules.anyReelCode(inPath: "/reels/CxYz123AbCd/"), "CxYz123AbCd")
        XCTAssertNil(CageRules.anyReelCode(inPath: "/reels/audio/"))
        XCTAssertEqual(CageRules.singleReelRedirect(forPath: "/reels/CxYz123AbCd/"), "/reel/CxYz123AbCd/")
        XCTAssertNil(CageRules.singleReelRedirect(forPath: "/reels/"))
        XCTAssertNil(CageRules.singleReelRedirect(forPath: "/reels/audio/123/"))
    }

    // MARK: Navigation policy

    func testUnlockedAllowsEverythingOnInstagram() {
        for path in ["/", "/reels/", "/explore/", "/x/reels/"] {
            XCTAssertEqual(rules.decide(url: ig(path), currentURL: nil, isMainFrame: true, unlocked: true), .allow, path)
        }
    }

    func testLockedNavigationDecisions() {
        XCTAssertEqual(rules.decide(url: ig("/"), currentURL: ig("/direct/inbox/"), isMainFrame: true, unlocked: false), .block(.feed))
        XCTAssertEqual(rules.decide(url: URL(string: "https://instagram.com")!, currentURL: nil, isMainFrame: true, unlocked: false), .block(.feed))
        XCTAssertEqual(rules.decide(url: ig("/explore/"), currentURL: nil, isMainFrame: true, unlocked: false), .block(.explore))
        XCTAssertEqual(rules.decide(url: ig("/direct/inbox/"), currentURL: nil, isMainFrame: true, unlocked: false), .allow)
        XCTAssertEqual(rules.decide(url: ig("/p/CxYz123AbCd/"), currentURL: ig("/direct/t/1/"), isMainFrame: true, unlocked: false), .allow)
        XCTAssertEqual(rules.decide(url: ig("/reel/CxYz123AbCd/"), currentURL: ig("/direct/t/1/"), isMainFrame: true, unlocked: false), .allow)
        XCTAssertEqual(rules.decide(url: ig("/reels/CxYz123AbCd/"), currentURL: ig("/direct/t/1/"), isMainFrame: true, unlocked: false),
                       .redirect(ig("/reel/CxYz123AbCd/")))
        XCTAssertEqual(rules.decide(url: ig("/reel/BBBBBBBBBBB/"), currentURL: ig("/reel/AAAAAAAAAAA/"), isMainFrame: true, unlocked: false),
                       .block(.nextReel))
        // Sub-frames are never caged.
        XCTAssertEqual(rules.decide(url: ig("/"), currentURL: nil, isMainFrame: false, unlocked: false), .allow)
    }

    func testExternalAndSpecialLinks() {
        let external = URL(string: "https://example.com/article")!
        XCTAssertEqual(rules.decide(url: external, currentURL: ig("/direct/t/1/"), isMainFrame: true, unlocked: false), .openExternally(external))
        XCTAssertEqual(rules.decide(url: external, currentURL: nil, isMainFrame: false, unlocked: false), .allow)

        let shim = URL(string: "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Farticle&e=AT0")!
        XCTAssertEqual(rules.decide(url: shim, currentURL: nil, isMainFrame: true, unlocked: false), .openExternally(external))

        XCTAssertEqual(rules.decide(url: URL(string: "instagram://user?username=x")!, currentURL: nil, isMainFrame: true, unlocked: false), .cancel)
        XCTAssertEqual(rules.decide(url: URL(string: "itms-apps://apps.apple.com/app/id389801252")!, currentURL: nil, isMainFrame: true, unlocked: true), .cancel)
        let mail = URL(string: "mailto:hi@example.com")!
        XCTAssertEqual(rules.decide(url: mail, currentURL: nil, isMainFrame: true, unlocked: false), .openExternally(mail))
        XCTAssertEqual(rules.decide(url: URL(string: "about:blank")!, currentURL: nil, isMainFrame: true, unlocked: false), .allow)

        let fbLogin = URL(string: "https://m.facebook.com/login.php?next=x")!
        XCTAssertEqual(rules.decide(url: fbLogin, currentURL: nil, isMainFrame: true, unlocked: false), .allow)
        let fbOAuth = URL(string: "https://www.facebook.com/v19.0/dialog/oauth?client_id=1")!
        XCTAssertEqual(rules.decide(url: fbOAuth, currentURL: nil, isMainFrame: true, unlocked: false), .allow)
        let fbFeed = URL(string: "https://www.facebook.com/watch/")!
        XCTAssertEqual(rules.decide(url: fbFeed, currentURL: nil, isMainFrame: true, unlocked: false), .openExternally(fbFeed))
    }

    func testHosts() {
        XCTAssertTrue(CageRules.isInstagramHost("www.instagram.com"))
        XCTAssertTrue(CageRules.isInstagramHost("instagram.com"))
        XCTAssertTrue(CageRules.isInstagramHost("accountscenter.instagram.com"))
        XCTAssertFalse(CageRules.isInstagramHost("notinstagram.com"))
        XCTAssertFalse(CageRules.isInstagramHost("instagram.com.evil.example"))
        XCTAssertFalse(CageRules.isInstagramHost(nil))
    }

    // MARK: Usernames

    func testUsernameSanitizing() {
        XCTAssertEqual(CageRules.sanitizeUsername("@Bob_1"), "bob_1")
        XCTAssertEqual(CageRules.sanitizeUsername("  ada.l  "), "ada.l")
        XCTAssertEqual(CageRules.sanitizeUsername("grace/"), "grace")
        XCTAssertNil(CageRules.sanitizeUsername("bad name"))
        XCTAssertNil(CageRules.sanitizeUsername(""))
        XCTAssertNil(CageRules.sanitizeUsername(nil))
        XCTAssertNil(CageRules.sanitizeUsername("direct"))
        XCTAssertNil(CageRules.sanitizeUsername("explore"))
        XCTAssertNil(CageRules.sanitizeUsername(String(repeating: "a", count: 31)))
        XCTAssertNil(CageRules.sanitizeUsername("émile"))
    }

    // MARK: Cage.js parity

    func testCageScriptIsBundledAndSharesTheRules() throws {
        let url = try XCTUnwrap(Bundle(for: InstagramWebCoordinator.self).url(forResource: "Cage", withExtension: "js"),
                                "Cage.js must be a bundle resource of the app")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("window.__toySetState"))
        XCTAssertTrue(source.contains("messageHandlers.toy"))
        XCTAssertTrue(source.contains("'/direct/inbox/'"))
        for block in CageRules.Block.allCases {
            XCTAssertTrue(source.contains("'\(block.reason)'"), "Cage.js should use the reason \"\(block.reason)\"")
        }
        for reserved in ["direct", "stories", "accounts", "explore"] {
            XCTAssertTrue(source.contains("'\(reserved)'"))
        }
    }
}
