# Sift

Free iOS photo cleanup: swipe right to keep, left to delete, tap to undo. Deletes are queued and committed together with one confirmation.

Swift + SwiftUI + PhotoKit, iOS 17+, no dependencies. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and built on GitHub Actions (`.github/workflows`): `ios-release` uploads to TestFlight, `ios-dev` produces a development `.ipa` for Firebase App Distribution.
