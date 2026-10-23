# Thinking Of You: UI ↔ Core contract

This file is for the UI agent. **Core** owns `project.yml`, the workflow,
`scripts/`, `ThinkingOfYou/App/`, `Budget/`, `Instagram/` (including
`Cage.js`, `InstagramWebContainer.swift`, `InstagramWebCoordinator.swift`),
`Messages/` (including `MessageComposer.swift`), every `*ViewModel.swift`,
the Info.plist, the asset catalog and `ThinkingOfYouTests/`.
**UI** owns `ThinkingOfYou/UI/` and every `*View.swift`. The phase-1 views in
`UI/` are compiling stubs. Replace them completely.

Signatures here are exact. If one is wrong or something is missing, ask Core
and log it under **Contract changes** at the bottom. Don't put logic in views.

---

## 0. Ground rules

- **iOS 17, Swift 5 mode, SwiftUI + Observation.** Every model is
  `@Observable @MainActor final class`. Read them directly in `body`; for
  bindings use `@Bindable var x = x` inside `body` (or `@Bindable` stored
  properties).
- **Environment.** `AppEnvironment` is injected at the root with
  `.environment(env)`. Read it with
  `@Environment(AppEnvironment.self) private var env`.
- **`RootView()` must keep a parameterless init.** `ThinkingOfYouApp`
  creates it. Every other view's init is yours to design. The stubs pass
  models explicitly: `InstagramView(model:budget:)`,
  `MessagesView(people:messages:snippets:nudges:sheet:)`,
  `PersonRowView(person:isPinned:messages:snippets:nudgeText:)`, `SnippetsView(store:onPick:)`,
  `NudgesView(model:)`, `BudgetPillView(budget:isPresentingSheet:)` and `SettingsView(model:)`.
  Reading `env` instead is also fine.
- **Previews:** `.environment(AppEnvironment.preview())` gives in-memory
  defaults and four sample people (`Person.samples`), and never touches
  Contacts. Use `AppEnvironment.preview(mode: .instagram)` to start in
  Instagram mode. Note that the Instagram web view really loads in previews.
- **Model inits have no UI side effects.** Call the `onAppear()` methods
  from `.task` or `.onAppear` where noted.
- **No onboarding surveys, quizzes or questionnaires anywhere.** A permission
  explainer row with a button is fine.
- **Haptics, animation, colors and layout are UI concerns.** `AccentColor` is
  a rose, `#F2668B` (light) and `#FF809E` (dark). The app icon is a cream
  heart on a coral to rose gradient.
- SF Symbol names that models expose (`systemImage`) are suggestions. Feel
  free to use others.

---

## 1. AppEnvironment (`App/AppEnvironment.swift`)

```swift
@Observable @MainActor final class AppEnvironment {
    let shell: ModeShellViewModel
    let budget: BudgetViewModel
    let instagram: InstagramViewModel
    let people: PeopleViewModel
    let snippets: SnippetsStore
    let nudges: NudgesViewModel
    let messages: MessagesViewModel
    let settings: SettingsViewModel

    init(defaults: UserDefaults = .standard, previewPeople: [Person]? = nil)
    func launch() async                         // called by the App, not by UI
    func scenePhaseChanged(_ phase: ScenePhase) // called by the App, not by UI
    func handleNudge(_ route: NudgeRoute)       // notification tap → Messages mode + composer
    static func preview(mode: AppMode = .messages) -> AppEnvironment
}
```

Core wires these: the mode change starts and stops the budget timer, a
lock/unlock pushes state to the cage, a re-lock sends the web view to the
inbox, and the scene phase gates the timer. **The UI never wires models
together.**

---

## 2. Modes (`App/ModeShellViewModel.swift`)

```swift
enum AppMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case instagram, messages
    var id: String
    var title: String        // "Instagram" / "Messages"
    var systemImage: String  // "camera.circle.fill" / "message.fill"
    var other: AppMode
}

@Observable @MainActor final class ModeShellViewModel {
    static let defaultsKey = "lastMode"
    static let defaultMode: AppMode            // .instagram (first launch)
    var mode: AppMode { get set }              // settable: $shell.mode works; persists
    func switchMode()                          // flip
    func select(_ newMode: AppMode)
}
```

Use a swipe (`TabView(selection: $shell.mode).tabViewStyle(.page(indexDisplayMode: .never))`)
or a pill/segmented switch. The mode survives relaunch.
**Note on swipe:** in Instagram mode, horizontal swipes belong to the web
view (DM swipe-to-reply, story taps, back gesture). If you use a paging
`TabView`, make sure it doesn't steal them, for example with a pill or
edge-only switch.

---

## 3. Scroll budget (`Budget/BudgetViewModel.swift`)

```swift
@Observable @MainActor final class BudgetViewModel {
    // state
    private(set) var dailyRemaining: TimeInterval   // seconds of today's 600
    private(set) var vault: TimeInterval            // banked seconds
    private(set) var isUnlocked: Bool               // a session is running → feeds & reel scrolling open
    private(set) var isTicking: Bool                // timer actually spending (unlocked && foreground && Instagram mode)
    private(set) var unusedDaysEarned: Int          // lifetime unused days that paid the vault
    private(set) var earnedNotice: String?          // "+20 min banked for days you skipped scrolling" (one-shot; also set on a cold launch)
    let dailyAllowance: TimeInterval                // 600

    // derived
    var totalRemaining: TimeInterval
    var canStart: Bool          // !isUnlocked && totalRemaining > 0
    var isOutOfTime: Bool
    var dailyFraction: Double   // 0...1 of today's allowance left (for a ring/bar)
    var dailyRemainingText: String   // "9:59"
    var vaultText: String            // "20:00" / "1:20:00"
    var totalRemainingText: String
    var vaultShortText: String       // "20 min", "1 h 20 min"
    var statusText: String           // one line for the pill, e.g. "Locked · 10:00 today + 20 min vault"

    // actions
    @discardableResult func start() -> Bool   // false if no time left
    func stop()                               // end session now (re-locks; web view goes to inbox)
    func dismissEarnedNotice()
    func refresh()                            // Core calls this; UI doesn't need to
    nonisolated static func earnedNoticeText(_ earned: TimeInterval) -> String
}
```

Rules (for copy): 10 minutes a day, reset at local midnight. Every completed
day with zero scrolling banks 10 minutes in the vault, including days the app
wasn't opened. Daily time is spent first, then the vault. At zero the
session ends and Instagram re-locks. The numbers update every second while
ticking, so just read them (no `TimelineView` needed).

---

## 4. Instagram (`Instagram/`)

### `InstagramWebContainer` (representable, Core-owned)

```swift
struct InstagramWebContainer: UIViewRepresentable {
    init(model: InstagramViewModel)
}
```

Put it wherever the web content goes. The WKWebView is owned by the model, so
it survives the container being removed (mode switches). It fills its frame.
Decide the safe area yourself (`.ignoresSafeArea(edges: .bottom)` usually
looks right). The first appearance creates the web view and loads
`https://www.instagram.com/direct/inbox/`.

### `InstagramViewModel`

```swift
@Observable @MainActor final class InstagramViewModel {
    // state
    private(set) var isLoading: Bool
    private(set) var progress: Double          // 0...1
    private(set) var canGoBack: Bool
    private(set) var currentURL: URL?
    private(set) var unreadCount: Int          // unread DM threads (polled each minute)
    private(set) var loadError: String?        // show a retry state; reload() clears
    private(set) var toast: String?            // auto-clears after ~2.6 s
    private(set) var isUnlocked: Bool          // mirrors budget.isUnlocked
    private(set) var detectedUsername: String? // found automatically
    private(set) var manualUsername: String?   // set in Settings; wins
    private(set) var hasWebView: Bool          // tracked: flips true once the web view exists

    // derived
    var ownUsername: String?        // manual ?? detected (lowercase, no "@")
    var isUsingManualUsername: Bool
    var currentPath: String
    var isAtInbox: Bool
    var isOnReel: Bool              // a single reel page (/reel/<code>/, /<user>/reel/<code>/, /reels/<code>/)

    // actions
    func reload()
    func goInbox()
    func goActivity()               // notifications (/accounts/activity/)
    func goBack()
    func dismissToast()
    func showToast(_ text: String)
    @discardableResult func setManualUsername(_ raw: String?) -> Bool  // prefer SettingsViewModel
    func clearManualUsername()
    func signOut() async            // prefer SettingsViewModel.signOutOfInstagram()

    // Core-only plumbing (don't call from UI): webCoordinator, setUnlocked(_:),
    // webViewDidUpdate(...), didDetectUsername(_:), didBlock(reason:),
    // didUpdateUnread(_:), didFailLoading(_:), cageRules
}
```

Toast texts come from the cage, for example "Reels is locked. Start a scroll
session to open it." and "One reel at a time while you're locked". Show
`toast` as a small overlay and animate on its change. Suggested chrome:
the budget pill, plus Inbox, Notifications and Back buttons and an unread
badge. Don't recreate Instagram's own tab bar, because the cage hides
Home, Explore, Reels, Create and your own profile while locked.

What's caged while locked: the feed `/`, `/reels/`, bare `/reel/` and
`/<user>/reel/`, `/explore/...`, `/<user>/reels|tagged|saved/`, and your
own profile `/<ownUsername>/...`. Within a single reel, scrolling to the next reel is
also blocked. What's always open: DMs, notes, stories, other profiles,
notifications, a single post and a single reel.

---

## 5. Messages mode (`Messages/`)

iMessage can't be read by third-party apps. This mode is a launcher.

### Domain types

```swift
struct ContactHandle: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String { case phone, email }
    let kind: Kind
    let label: String      // localized "mobile"/"home" ("" if none)
    let value: String      // as stored
    var id: String
    var address: String    // sanitized for URLs/composer
}

struct Person: Identifiable, Hashable, Sendable {
    let id: String                 // CNContact.identifier
    let givenName, familyName, nickname, organization: String
    let phones: [ContactHandle]
    let emails: [ContactHandle]
    let thumbnailData: Data?       // UIImage(data:) for the avatar
    var displayName: String
    var shortName: String          // nickname ?? givenName ?? displayName
    var initials: String           // "AL" (fallback "?")
    var handles: [ContactHandle]   // phones + emails
    var primaryPhone: ContactHandle?
    var messageAddress: String?
    var canMessage: Bool
    var canCall: Bool
    var canFaceTime: Bool
    static let samples: [Person]   // previews
}

enum PersonAction: String, CaseIterable, Identifiable, Sendable {
    case message, openInMessages, call, faceTime, faceTimeAudio
    var title: String              // "Message", "Open in Messages", "Call", "FaceTime", "FaceTime Audio"
    var systemImage: String
}

enum ContactsAccess: Equatable, Sendable {
    case notDetermined, authorized, limited, denied, restricted
    var canRead: Bool
}
```

### `PeopleViewModel`

```swift
@Observable @MainActor final class PeopleViewModel {
    private(set) var access: ContactsAccess
    private(set) var people: [Person]          // sorted by displayName
    private(set) var isLoading: Bool
    private(set) var hasLoaded: Bool
    private(set) var errorMessage: String?
    private(set) var pinnedIDs: [String]
    var searchText: String                     // .searchable(text: $people.searchText)

    var pinnedPeople: [Person]                 // pin order, ignores search
    var filteredPeople: [Person]               // everyone matching search
    var otherPeople: [Person]                  // matching search, not pinned
    var isSearching: Bool

    func onAppear() async                      // .task
    func requestAccess() async                 // button on the "Allow Contacts" explainer
    func reload() async                        // pull to refresh
    func person(withID id: String) -> Person?
    func isPinned(_ person: Person) -> Bool
    func togglePin(_ person: Person)
    func pin(_ person: Person)
    func unpin(_ person: Person)
    func movePinned(fromOffsets: IndexSet, toOffset: Int)   // .onMove on the pinned section
    func unpin(atOffsets: IndexSet)                         // .onDelete on the pinned section
    func openSystemSettings()                  // when access == .denied
}
```

When access is `.notDetermined`, show an explainer with a button that calls
`requestAccess()`. When it's `.denied` or `.restricted`, show a button that
calls `openSystemSettings()`.

### `MessagesViewModel`

```swift
@Observable @MainActor final class MessagesViewModel {
    var composer: ComposeDraft?          // .sheet(item: $messages.composer)
    private(set) var lastOutcome: ComposeOutcome?
    var alertMessage: String?            // .alert, then nil / dismissAlert()
    var canSendText: Bool

    func perform(_ action: PersonAction, for person: Person, body: String = "")
    func isAvailable(_ action: PersonAction, for person: Person) -> Bool
    func message(_ person: Person, body: String = "")               // composer (falls back to Messages app)
    func message(_ person: Person, handle: ContactHandle, body: String = "")
    func compose(to recipients: [String], body: String = "", personName: String? = nil, contactID: String? = nil)
    func openInMessages(_ person: Person, body: String = "")        // sms: URL
    func call(_ person: Person)                                      // tel:
    func faceTime(_ person: Person)                                  // facetime:
    func faceTimeAudio(_ person: Person)                             // facetime-audio:
    func composerFinished(_ outcome: ComposeOutcome)                 // from MessageComposer's onFinish
    func dismissAlert()
}
```

### `MessageComposer` (representable, Core-owned)

```swift
enum ComposeOutcome: String, Equatable, Sendable { case sent, cancelled, failed }

struct ComposeDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var recipients: [String]
    var body: String
    var personName: String?
    var contactID: String?
}

struct MessageComposer: UIViewControllerRepresentable {
    init(recipients: [String], body: String = "", onFinish: @escaping (ComposeOutcome) -> Void)
    init(draft: ComposeDraft, onFinish: @escaping (ComposeOutcome) -> Void)
    static func canSendText() -> Bool
}
```

**Attach the composer sheet once, in `RootView`** (not inside
`MessagesView`), so that a nudge tap can open it:

```swift
@Bindable var messages = env.messages
...
.sheet(item: $messages.composer) { draft in
    MessageComposer(draft: draft) { outcome in messages.composerFinished(outcome) }
        .ignoresSafeArea()
}
```

### `SnippetsStore` (quick replies)

```swift
struct Snippet: Identifiable, Codable, Hashable, Sendable { var id: UUID; var text: String }

@Observable @MainActor final class SnippetsStore {
    static let defaultTexts: [String]
    private(set) var snippets: [Snippet]
    func snippet(withID id: UUID) -> Snippet?
    @discardableResult func add(_ text: String) -> Snippet?   // ignores blank
    func update(_ id: UUID, text: String)                     // blank deletes
    func delete(_ id: UUID)
    func delete(atOffsets offsets: IndexSet)                  // .onDelete
    func move(fromOffsets source: IndexSet, toOffset destination: Int)   // .onMove
    func resetToDefaults()
}
```

Typical flow: pick a person, then pick a snippet, then call
`messages.message(person, body: snippet.text)`.

### Nudges

```swift
enum NudgeRepeat: String, CaseIterable, Identifiable, Codable, Sendable {
    case never, daily, weekly
    var title: String   // "Once", "Every day", "Every week"
}

struct Nudge: Identifiable, Hashable, Sendable {
    let id: String
    let contactID: String?
    let name: String
    let address: String?
    let body: String
    let repeats: NudgeRepeat
    let nextFireDate: Date?
}

enum NotificationAccess: Equatable, Sendable { case notDetermined, authorized, denied }

@Observable @MainActor final class NudgesViewModel {
    private(set) var pending: [Nudge]          // soonest first
    private(set) var access: NotificationAccess
    private(set) var isLoading: Bool
    var errorMessage: String?                  // alert; set nil to dismiss
    var draftDate: Date                        // DatePicker
    var draftRepeat: NudgeRepeat               // Picker
    var draftBody: String                      // TextField (snippets can fill it)

    func onAppear() async                      // .task
    func refresh() async
    @discardableResult func requestAccess() async -> Bool
    @discardableResult func schedule(for person: Person, body: String? = nil,
                                     at date: Date? = nil, repeats: NudgeRepeat? = nil) async -> Bool
                                               // nil args use the draft fields; resets the draft on success
    func cancel(_ nudge: Nudge) async
    func cancel(atOffsets offsets: IndexSet, in list: [Nudge]? = nil) async   // .onDelete
    func cancelAll(for person: Person) async
    func nudges(for contactID: String) -> [Nudge]
    func resetDraft()
    func openSystemSettings()
    static func scheduleText(for nudge: Nudge, calendar: Calendar = .current) -> String
                                               // "Tomorrow, 7:00 PM" / "Every Monday, 6:30 PM"
    static func suggestedDate(after date: Date, calendar: Calendar = .current) -> Date
}
```

`schedule` asks for notification permission the first time. A notification
reads "Text Ada" with the body in quotes. Tapping it switches to Messages
mode and opens the composer pre-filled, all handled by Core.

---

## 6. Settings (`App/SettingsViewModel.swift`)

```swift
@Observable @MainActor final class SettingsViewModel {
    var usernameDraft: String                  // TextField, no autocaps/autocorrect
    private(set) var usernameError: String?
    private(set) var isInstagramAppInstalled: Bool   // show "offload the real Instagram app" warning when true
    private(set) var isSigningOut: Bool

    let instagram: InstagramViewModel
    let budget: BudgetViewModel
    let people: PeopleViewModel
    let nudges: NudgesViewModel
    let snippets: SnippetsStore

    var detectedUsername: String?
    var manualUsername: String?
    var effectiveUsernameText: String          // "@ada" or "Not detected yet"
    var contactsAccess: ContactsAccess
    var notificationAccess: NotificationAccess
    var appVersion: String                     // "1.0.0 (1)"
    var budgetRulesText: String
    static let platformLimits: [String]        // honest-limits bullets for an About section

    func onAppear()                            // .onAppear: fills usernameDraft, checks for the Instagram app
    @discardableResult func saveUsername() -> Bool   // empty clears the manual name
    func useDetectedUsername()
    func refreshInstagramAppCheck()
    func signOutOfInstagram() async
    func openSystemSettings()
}
```

Settings should cover these sections: your Instagram username (detected or
manual), the budget rules, sign out of Instagram, Contacts and notification
status, quick replies (`SnippetsView`), and About (`platformLimits`).

---

## 7. File map

| Path | Owner |
|---|---|
| `App/ThinkingOfYouApp.swift`, `AppDelegate.swift`, `AppEnvironment.swift`, `ModeShellViewModel.swift`, `SettingsViewModel.swift`, `Info.plist`, `ThinkingOfYou.entitlements` | Core |
| `Budget/*` | Core |
| `Instagram/*` (`Cage.js`, `CageRules`, `InstagramViewModel`, `InstagramWebCoordinator`, `InstagramWebContainer`) | Core |
| `Messages/*` (`Person`, `ContactsService`, `PeopleViewModel`, `MessagesViewModel`, `MessageComposer`, `SnippetsStore`, `NudgeScheduler`, `NudgesViewModel`) | Core |
| `Resources/Assets.xcassets` | Core (icon is generated by `scripts/make_icon.py` in CI) |
| `UI/*` (`RootView`, `InstagramView`, `MessagesView`, `PersonRowView`, `SnippetsView`, `NudgesView`, `BudgetPillView`, `SettingsView`, plus anything new) | UI |

New UI files go anywhere under `ThinkingOfYou/UI/`. XcodeGen picks them up
automatically.

---

## Contract changes

- 2026-10-22: `NudgesViewModel.scheduleText(for:calendar:)` and
  `NudgesViewModel.suggestedDate(after:calendar:)` are now `nonisolated static`
  (pure helpers, callable from any context). Call sites are unchanged. (Core)
- 2026-10-22: Reviewer pass 1 (Core).
  - `BudgetViewModel.earnedNotice` is now also set on a cold launch that paid
    the vault. The wording comes from the new
    `nonisolated static func earnedNoticeText(_:)`. The `init` calendar
    default is now `.autoupdatingCurrent`, and the midnight refresh
    reschedules on time-zone and significant-time changes.
  - `InstagramViewModel.hasWebView` is now a tracked `private(set) var` (it
    was a computed property that never updated views). It's read-only as
    before.
  - `InstagramViewModel.isOnReel` now also covers `/<user>/reel/<code>/` and
    `/reels/<code>/`.
  - `CageRules`: `reelCode(inPath:)` also matches `/<user>/reel/<code>/`.
    Bare `/<user>/reel/` is blocked as `.reels`. `blocksNextReel` accepts
    any reel form on either side. Two new helpers: `isProfileSegment(_:)`
    and `isSameReel(_:_:)`. The same reel in another form is always
    allowed, so it can't loop.
  - `PeopleViewModel.loadIfNeeded()` and `reload()` now wait for a contacts
    fetch that is already running instead of returning early.
  - Cage.js: these changes mirror the Swift rules. History-hook bounces
    force an inbox reload even when the URL already is the inbox. A
    one-shot guard stops the `/reels/<code>/` to `/reel/<code>/` redirect
    from looping.
- 2026-10-22: UI view inits (UI). `PersonRowView` is now
  `PersonRowView(person:isPinned:messages:snippets:nudgeText:)`. All sheet
  state now lives in `RootView` so a nudge tap can show the composer over any
  open sheet, which changes two more inits:
  `MessagesView(people:messages:snippets:nudges:sheet:)` takes a
  `Binding<MessagesSheet?>`, and `BudgetPillView(budget:isPresentingSheet:)`
  takes a `Binding<Bool>`. No model API changed.
