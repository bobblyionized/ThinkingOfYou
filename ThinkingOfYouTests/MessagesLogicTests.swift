import XCTest
import UserNotifications
@testable import ThinkingOfYou

final class ContactActionsTests: XCTestCase {

    private let ada = Person(id: "ada", givenName: "Ada", familyName: "Lovelace",
                             phones: [ContactHandle(kind: .phone, label: "mobile", value: "+1 (555) 010-1815")],
                             emails: [ContactHandle(kind: .email, label: "home", value: "ada@example.com")])
    private let alan = Person(id: "alan", givenName: "Alan",
                              emails: [ContactHandle(kind: .email, label: "work", value: "alan@example.com")])
    private let nobody = Person(id: "x", organization: "Acme")

    func testPhoneSanitizing() {
        XCTAssertEqual(ContactActions.sanitizedPhone("+1 (555) 010-1815"), "+15550101815")
        XCTAssertEqual(ContactActions.sanitizedPhone("555.0123 ext 4"), "55501234")
        XCTAssertEqual(ContactActions.sanitizedPhone("1+2"), "12")
        XCTAssertEqual(ContactActions.sanitizedPhone("*67 555"), "*67555")
    }

    func testSMSURLs() {
        XCTAssertEqual(ContactActions.smsURL(addresses: ["+15550101815"])?.absoluteString, "sms:+15550101815")
        XCTAssertEqual(ContactActions.smsURL(addresses: ["+15550101815"], body: "Hi there!")?.absoluteString,
                       "sms:+15550101815&body=Hi%20there%21")
        XCTAssertEqual(ContactActions.smsURL(addresses: ["ada@example.com"], body: "")?.absoluteString, "sms:ada@example.com")
        XCTAssertEqual(ContactActions.smsURL(addresses: ["111", "222"], body: "yo")?.absoluteString,
                       "sms:/open?addresses=111,222&body=yo")
        XCTAssertNotNil(ContactActions.smsURL(addresses: ["111"], body: "Thinking of you ❤️"))
    }

    func testActionURLs() {
        XCTAssertEqual(ContactActions.url(for: .call, person: ada)?.absoluteString, "tel:+15550101815")
        XCTAssertEqual(ContactActions.url(for: .faceTime, person: ada)?.absoluteString, "facetime:+15550101815")
        XCTAssertEqual(ContactActions.url(for: .faceTimeAudio, person: ada)?.absoluteString, "facetime-audio:+15550101815")
        XCTAssertEqual(ContactActions.url(for: .openInMessages, person: ada, body: "hey")?.absoluteString, "sms:+15550101815&body=hey")
        // Email-only contacts: FaceTime and Messages work, Call doesn't.
        XCTAssertEqual(ContactActions.url(for: .faceTime, person: alan)?.absoluteString, "facetime:alan@example.com")
        XCTAssertNil(ContactActions.url(for: .call, person: alan))
        XCTAssertNil(ContactActions.url(for: .message, person: nobody))
    }

    func testPersonDerivedValues() {
        XCTAssertEqual(ada.displayName, "Ada Lovelace")
        XCTAssertEqual(ada.initials, "AL")
        XCTAssertEqual(ada.messageAddress, "+15550101815")
        XCTAssertEqual(alan.messageAddress, "alan@example.com")
        XCTAssertEqual(nobody.displayName, "Acme")
        XCTAssertEqual(nobody.initials, "A")
        XCTAssertFalse(nobody.canMessage)
        XCTAssertTrue(ada.matches("love"))
        XCTAssertTrue(ada.matches("ADA"))
        XCTAssertTrue(ada.matches("0101"))
        XCTAssertTrue(ada.matches("example.com"))
        XCTAssertFalse(ada.matches("grace"))
        XCTAssertTrue(ada.matches("  "))
    }
}

final class NudgeSchedulerTests: XCTestCase {

    func testContentCarriesTheRouteInUserInfo() {
        let content = NudgeScheduler.makeContent(name: "Ada", contactID: "abc", address: "+1555",
                                                 body: "Miss you!", repeats: .weekly)
        XCTAssertEqual(content.title, "Text Ada")
        XCTAssertTrue(content.body.contains("Miss you!"))
        let route = NudgeScheduler.route(from: content.userInfo)
        XCTAssertEqual(route, NudgeRoute(contactID: "abc", name: "Ada", address: "+1555", body: "Miss you!"))
        XCTAssertEqual(content.userInfo[NudgeScheduler.Key.repeats] as? String, "weekly")
    }

    func testEmptyBodyGetsAFriendlyLine() {
        let content = NudgeScheduler.makeContent(name: "Ada", contactID: nil, address: nil, body: "  ", repeats: .never)
        XCTAssertFalse(content.body.isEmpty)
        XCTAssertNil(NudgeScheduler.route(from: content.userInfo)?.contactID)
    }

    func testForeignNotificationsAreIgnored() {
        XCTAssertNil(NudgeScheduler.route(from: ["aps": ["alert": "hi"]]))
    }

    func testTriggers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 19, minute: 30))!

        let once = NudgeScheduler.makeTrigger(date: date, repeats: .never, calendar: calendar)
        XCTAssertFalse(once.repeats)
        XCTAssertEqual(once.dateComponents.day, 5)
        XCTAssertEqual(once.dateComponents.hour, 19)

        let daily = NudgeScheduler.makeTrigger(date: date, repeats: .daily, calendar: calendar)
        XCTAssertTrue(daily.repeats)
        XCTAssertNil(daily.dateComponents.day)
        XCTAssertEqual(daily.dateComponents.minute, 30)

        let weekly = NudgeScheduler.makeTrigger(date: date, repeats: .weekly, calendar: calendar)
        XCTAssertTrue(weekly.repeats)
        XCTAssertEqual(weekly.dateComponents.weekday, 5) // Thursday
    }

    func testRequestRoundTrip() {
        let content = NudgeScheduler.makeContent(name: "Grace", contactID: "g", address: nil, body: "hi", repeats: .daily)
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0), repeats: true)
        let request = UNNotificationRequest(identifier: NudgeScheduler.identifierPrefix + "1", content: content, trigger: trigger)
        let nudge = NudgeScheduler.nudge(from: request)
        XCTAssertEqual(nudge?.name, "Grace")
        XCTAssertEqual(nudge?.contactID, "g")
        XCTAssertEqual(nudge?.repeats, .daily)
        XCTAssertNotNil(nudge?.nextFireDate)

        let other = UNNotificationRequest(identifier: "something-else", content: content, trigger: trigger)
        XCTAssertNil(NudgeScheduler.nudge(from: other))
    }

    func testSuggestedDateIsAFutureWholeHour() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let suggested = NudgesViewModel.suggestedDate(after: now, calendar: calendar)
        XCTAssertGreaterThan(suggested.timeIntervalSince(now), 30 * 60)
        XCTAssertEqual(calendar.component(.minute, from: suggested), 0)
    }
}

@MainActor
final class StoresTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "StoresTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }

    func testModeIsPersistedAndRestored() {
        let defaults = freshDefaults()
        let shell = ModeShellViewModel(defaults: defaults)
        XCTAssertEqual(shell.mode, ModeShellViewModel.defaultMode)

        var changes: [AppMode] = []
        shell.onModeChange = { changes.append($0) }
        shell.switchMode()
        XCTAssertEqual(shell.mode, ModeShellViewModel.defaultMode.other)
        XCTAssertEqual(defaults.string(forKey: "lastMode"), shell.mode.rawValue)

        shell.select(.messages)
        shell.mode = .instagram
        XCTAssertEqual(ModeShellViewModel(defaults: defaults).mode, .instagram)
        XCTAssertEqual(changes.last, .instagram)
    }

    func testSnippetsSeedEditAndPersist() {
        let defaults = freshDefaults()
        let store = SnippetsStore(defaults: defaults)
        XCTAssertEqual(store.snippets.map(\.text), SnippetsStore.defaultTexts)

        XCTAssertNil(store.add("   "))
        let added = store.add("  See you soon  ")
        XCTAssertEqual(added?.text, "See you soon")
        store.update(store.snippets[0].id, text: "Hi!")
        store.move(fromOffsets: IndexSet(integer: store.snippets.count - 1), toOffset: 0)
        store.delete(atOffsets: IndexSet(integer: 1))

        let reloaded = SnippetsStore(defaults: defaults)
        XCTAssertEqual(reloaded.snippets, store.snippets)
        XCTAssertEqual(reloaded.snippets.first?.text, "See you soon")
        XCTAssertFalse(reloaded.snippets.contains { $0.text == "Hi!" })

        // Deleting everything stays deleted (no re-seeding).
        for snippet in reloaded.snippets { reloaded.delete(snippet.id) }
        XCTAssertTrue(SnippetsStore(defaults: defaults).snippets.isEmpty)
        reloaded.resetToDefaults()
        XCTAssertEqual(SnippetsStore(defaults: defaults).snippets.count, SnippetsStore.defaultTexts.count)
    }

    func testPinsPersistInOrder() {
        let defaults = freshDefaults()
        let people = PeopleViewModel(defaults: defaults, preloaded: Person.samples)
        let ada = Person.samples[0], grace = Person.samples[1], mum = Person.samples[2]
        people.togglePin(mum)
        people.togglePin(ada)
        people.pin(grace)
        XCTAssertEqual(people.pinnedPeople.map(\.id), [mum.id, ada.id, grace.id])
        people.movePinned(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(people.pinnedPeople.map(\.id), [grace.id, mum.id, ada.id])
        people.unpin(atOffsets: IndexSet(integer: 1))
        XCTAssertEqual(PeopleViewModel(defaults: defaults, preloaded: Person.samples).pinnedIDs, [grace.id, ada.id])

        people.searchText = "grace"
        XCTAssertEqual(people.filteredPeople.map(\.id), [grace.id])
        XCTAssertTrue(people.otherPeople.isEmpty)
    }

    func testManualUsernameOverridesDetected() {
        let defaults = freshDefaults()
        let instagram = InstagramViewModel(defaults: defaults)
        instagram.didDetectUsername("Detected.Me")
        XCTAssertEqual(instagram.ownUsername, "detected.me")
        XCTAssertFalse(instagram.setManualUsername("not valid!"))
        XCTAssertTrue(instagram.setManualUsername("@Typed_Me"))
        XCTAssertEqual(instagram.ownUsername, "typed_me")
        XCTAssertEqual(instagram.cageRules.blockedRoute(forPath: "/typed_me/"), .ownProfile)
        let relaunched = InstagramViewModel(defaults: defaults)
        XCTAssertEqual(relaunched.ownUsername, "typed_me")
        relaunched.clearManualUsername()
        XCTAssertEqual(relaunched.ownUsername, "detected.me")
    }

    func testMessagesFallsBackToURLsWhenComposerIsUnavailable() {
        var opened: [URL] = []
        let people = PeopleViewModel(defaults: freshDefaults(), preloaded: Person.samples)
        let messages = MessagesViewModel(people: people, openURL: { opened.append($0) })
        let ada = Person.samples[0]
        messages.call(ada)
        messages.faceTime(ada)
        XCTAssertEqual(opened.map(\.scheme), ["tel", "facetime"])
        messages.call(Person.samples[3]) // email only
        XCTAssertNotNil(messages.alertMessage)
        messages.message(ada, body: "hi")
        if messages.canSendText {
            XCTAssertEqual(messages.composer?.recipients, ["+15550101815"])
            XCTAssertEqual(messages.composer?.body, "hi")
            messages.composerFinished(.cancelled)
            XCTAssertNil(messages.composer)
        } else {
            XCTAssertEqual(opened.last?.absoluteString, "sms:+15550101815&body=hi")
        }
    }
}
