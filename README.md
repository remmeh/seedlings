# Seedlings — native iPad prototype

A SwiftUI + SpriteKit territory game. You are a small fruit with big ambitions: leave a seed trail, return home to capture the enclosed area, steal rival territory, and wear the crown when your kingdom is largest.

## Open and run

1. On a Mac with **Xcode 15 or later**, open `Seedlings.xcodeproj`.
2. Select the **Seedlings** scheme and an **iPad simulator running iPadOS 17 or later**.
3. Press **⌘R**. No dependencies, package resolution, API keys, or downloaded art are required.
4. For a physical iPad, select your Apple development team in **Signing & Capabilities**, change `com.example.Seedlings` to your own unique bundle identifier, and select the connected device. Xcode handles development signing. This source archive is not a signed installable app or an App Store submission.

Run the included XCTest suite with **⌘U**. From a Mac terminal, substituting an installed simulator name if needed:

```sh
xcodebuild -project Seedlings.xcodeproj -scheme Seedlings \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)' test
```

## Play

- Choose watermelon, orange, blueberry, or kiwi on the home screen.
- Touch anywhere on the board and drag in a direction. Keep your finger down to move; lift it to stop. Holding the arrow buttons moves continuously, and tapping moves one cell. Buttons also support VoiceOver.
- Your colored territory is home. Leaving it creates an exposed seed trail. Reconnect to your land to claim the trail and the enclosed cells, including opponents' land.
- Touching an opponent's exposed trail snips it and sends them home. Crossing your own trail has the same consequence. You keep previously owned land. If all of a fruit's land is stolen, it receives a small new foothold.
- The largest territory wears the crown. Ties favor You, then rival order. The round ends **only when every playable cell is allocated**. There is no round timer or automatic allocation.
- The next island uses the same 64 × 48 logical canvas and a newly generated organic outline. Rivals become slightly faster over successive levels, up to a fixed limit.
- Pause, restart, how-to-play, best completed score, haptics, and automatic pause when the app becomes inactive are included. Best score and haptic preferences stay on this device. A round in progress is not restored after the app is terminated.

## Implementation

`Game/GameEngine.swift` contains the rules and seeded random island generation using only Foundation. Characters move on four-connected cells. Capturing closes an exposed trail with a shortest path through connected home territory, then applies point-in-polygon membership. This supports captures against the island boundary without flood-filling into the ocean. If a rival has disconnected the departure anchor from the return point, reconnecting claims the trail alone. A cut gives a brief 1.5-second protection period.

`Game/GameScene.swift` draws all terrain, trails, fruit characters, and the crown with SpriteKit paths. `Views/` supplies native SwiftUI menus, responsive layout, scores, controls, instructions, and results. The app is iPad-only, supports portrait and landscape, and targets iPadOS 17+. It uses no web views or online services.

Three computer-controlled rivals complete loops and compete for the same land. This prototype does **not** include online multiplayer, Game Center, audio, in-app purchases, or production analytics. Those require separate product and implementation work; there is no simulated multiplayer connection.

## Verification status

The project was authored in a Linux environment, which does not have Xcode, Apple's iPadOS SDK, or an iPad simulator. The included XCTest cases cover loop capture, open trails, stealing, cuts, invalid moves, crown changes, complete allocation, connected randomized islands, and bot ownership invariants. **An Apple-platform build and simulator/device run are still required.** Do not treat this source delivery as a tested App Store binary.

## Useful next milestones

1. Build and play on an iPad; tune movement speed, visual scale, and capture feedback.
2. Add persistent round recovery and an onboarding practice island.
3. For human opponents, choose local-network or online play and implement an authoritative shared simulation before adding matchmaking.
4. Complete device accessibility, performance, and App Store preparation.
