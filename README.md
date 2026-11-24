# SiriAI

SwiftUI iPhone app (iOS 17+) with an AI assistant (Claude API).

- **Siri / Shortcuts / Spotlight / Action Button** (works without opening the app): Ask AI, Smart Reminder,
  Smart Calendar Event, Today's Agenda, Save Note, Summarize, Translate, Rewrite, Open Chat.
- **Home Screen + Lock Screen widget**: interactive buttons (Plan / Motivate / Fact / Idea) call the AI in the
  background and show the answer in the widget, no app launch.
- **App**: animated aurora background, glowing orb, spring-animated chat bubbles, typing dots, voice input,
  spoken replies, haptics.
- The AI can use tools: Reminders, Calendar, notes, battery/time, clipboard.

## Get an IPA without a Mac
1. Create a GitHub repo, upload this folder's contents, push to `main`.
2. Actions -> "Build IPA" -> download `SiriAI-ipa` (unsigned `SiriAI.ipa`, app-group entitlements embedded).
3. Sign + install with AltStore / Sideloadly / your Apple ID.

## With a Mac
`brew install xcodegen && xcodegen generate && open SiriAI.xcodeproj`, set your team on BOTH targets.

## Notes
- Change `com.example.siriai` (app, widget, and App Group `group.com.example.siriai`) in project.yml and
  `Sources/Shared/Shared.swift` to your own IDs.
- The widget shares the API key with the app through the App Group. If your signer cannot grant App Groups,
  Siri/Shortcuts still work in the app, but the widget will say the key is missing.
- First run: gear icon -> paste Anthropic API key.
