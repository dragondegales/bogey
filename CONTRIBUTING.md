# Contributing to Bogey

Bogey is small on purpose. Contributions that keep it that way are welcome.

## What we accept

- Bug fixes
- Accessibility improvements
- Legibility and layout improvements for the watch screen
- New scoring formats, with an issue opened for discussion first
- Course data corrections or additions
- watchOS API improvements as the platform evolves

## What we don't accept

Bogey's constraints are not gaps to fill — they are decisions. The following are out of scope:

- Analytics, tracking, or telemetry of any kind
- Advertising or sponsored placements
- Paid features, premium tiers, or paywalls
- Features designed to increase app opens or session length
- Social features beyond what is needed to play a round together
- GPS shot tracking, course mapping, or aerial views
- Anything that requires a server account or login
- Anything that breaks the app's ability to function without a network connection

## How to propose a change

For non-trivial changes, open an issue first and describe what you want to do and why. This avoids wasted effort if the change is out of scope.

For small bug fixes, a pull request without a prior issue is fine.

Fork the repo, make your changes on a branch, and open a pull request against `main`.

## Code style

Match the style of the existing code. The project uses SwiftUI and follows standard Swift conventions. There is no SwiftLint configuration — if in doubt, look at how the surrounding code is written.

## Reporting issues

When filing a bug, include:

- Apple Watch model (e.g. Series 9, Ultra 2)
- watchOS version
- Scoring format in use (stroke play, match play, points match, Stableford)
- Gross or net
- What happened
- What you expected

A short reproduction is more useful than a long one.
