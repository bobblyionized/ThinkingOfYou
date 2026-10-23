# Thinking Of You

An iPhone app for staying close to people without falling into a feed. It has
two modes, and you switch between them with a swipe or a tap.

- **Instagram mode** is Instagram's own website in a caged web view. DMs,
  notes, stories, profiles, notifications, and a single post or reel that a
  friend sends you all work. The feed, Reels, Explore, profile Reels/Tagged/
  Saved tabs and **your own profile** (your own posts and videos) are locked.
  On a single reel you can't scroll on to the next one.
- **Scroll budget.** You get 10 minutes of real scrolling a day, and it
  resets at midnight. Starting a session unlocks the feeds. Time is only
  spent while the session is running, the app is on screen and Instagram
  mode is showing. Every day you don't scroll at all banks another 10 minutes
  in the **vault**, including days you never open the app. When the time runs
  out, Instagram re-locks and goes back to your inbox.
- **Messages mode** is a launcher for the people you care about. You can pin
  contacts, search, and one-tap Message (in-app composer), Open in Messages,
  Call, FaceTime or FaceTime Audio. Editable quick-reply snippets and
  **nudges** ("Text Mum" at 7 PM, once, daily or weekly) open the composer
  pre-filled when you tap them.

There's no onboarding survey and no account to create. Your contacts, pins,
snippets and budget stay on your phone. The only network traffic is
Instagram's own website.

## Platform limits (read these)

- **iMessage can't be read.** iOS gives third-party apps no access to your
  message history, so Messages mode can't show conversations. It starts
  them.
- **The limit only applies inside this app.** iOS doesn't let a sideloaded
  app block other apps. **Delete or offload the real Instagram app**
  (Settings › General › iPhone Storage › Instagram › Offload App), or
  the cage is one tap away from being skipped. Settings in the app warns you
  while Instagram is still installed.
- Instagram changes its website often. The cage has two layers. Injected
  JavaScript (`Cage.js`) handles Instagram's in-page navigation, and a
  native navigation policy (`CageRules.swift`) blocks full page loads. If
  Instagram ships a new layout, something may slip through until the rules
  are updated.
- Your own username is detected automatically, from the tab bar or from
  Instagram's own data. If detection fails, set it in Settings ›
  "Your Instagram username" so your profile stays locked.
- Moving the phone's clock forward can farm vault time. Moving it back
  can't refund time you've already spent.

## Build (no Mac needed)

GitHub Actions is the compiler. Each push to `main` runs
`.github/workflows/build.yml` on a macOS 26 runner with the newest Xcode 26.
The workflow:

1. generates the app icon (`scripts/make_icon.py`, Pillow),
2. generates the Xcode project from `project.yml` (XcodeGen),
3. runs the unit tests on an iPhone simulator (`scripts/pick_simulator.py`),
4. archives an **unsigned** Release build, ad-hoc signs the binary with `ldid`,
   and zips `Payload/` into `ThinkingOfYou.ipa`,
5. checks the IPA: display name, bundle id `com.thinkingofyou.app`, the app
   icon, `LSApplicationQueriesSchemes`, the Contacts usage text and the
   bundled `Cage.js`.

Download the **ThinkingOfYou-ipa** artifact from the workflow run. Pushing a
tag such as `v1.0.0` also attaches the IPA to a GitHub Release.

To regenerate the icon locally: `python scripts/make_icon.py ThinkingOfYou/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

## Sideload

The IPA is unsigned, so sign it with your own Apple ID using any sideloading
tool (AltStore, SideStore, Sideloadly, or a signing service). The app needs no
special entitlements, so a free Apple ID works. Free-account installs expire
after 7 days and need a refresh.

1. Install the IPA with your tool of choice.
2. On first launch, sign in to Instagram inside the app. The session is kept
   in the app's own website data store.
3. In Messages mode, tap **Allow Contacts**.
4. Offload the real Instagram app.

## Layout

```
project.yml                       XcodeGen spec (app + unit tests)
.github/workflows/build.yml       CI: icon → xcodegen → tests → unsigned IPA
scripts/make_icon.py              1024×1024 heart icon (Pillow)
scripts/pick_simulator.py         picks a simulator for the test step
ThinkingOfYou/
  App/        entry point, AppDelegate (notification taps), AppEnvironment, modes, settings, Info.plist
  Budget/     ScrollBudgetEngine (pure rules), BudgetState, BudgetViewModel (1 s timer)
  Instagram/  Cage.js (injected), CageRules (native mirror), web view coordinator + container, view model
  Messages/   contacts, people/pins, actions + MessageComposer, snippets, nudges
  UI/         SwiftUI views
  Resources/  asset catalog (AppIcon, AccentColor)
  CONTRACT.md the UI ↔ Core contract
ThinkingOfYouTests/               budget engine, cage rules, URL builders, stores
```

The cage is a port of the Instagram cage from the Hush desktop app (`rules.js`
and `cage.js`).
