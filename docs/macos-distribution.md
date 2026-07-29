# macOS distribution channels

Talkify uses one target and one bundle identifier (`com.objc.chat`) for two
mutually exclusive macOS distribution channels.

## Mac App Store

- Scheme: `Talkify-MacAppStore`
- Build configurations: `Debug-MacAppStore` / `Release-MacAppStore`
- Entitlements: `Talkify/TalkifyMacAppStore.entitlements`
- App Sandbox: enabled
- AgentKit embedded runtime profile: `sandboxed`
- Native Sign in with Apple: enabled

Select `Talkify-MacAppStore` and **Any Mac**, then use **Product > Archive**.
Distribute the archive through **App Store Connect**.

## Direct download

- Scheme: `Talkify-MacDirect`
- Build configurations: `Debug-MacDirect` / `Release-MacDirect`
- Entitlements: none
- App Sandbox: disabled
- Restricted App Group/shared Keychain entitlements: disabled, so Developer ID
  signing does not need a provisioning profile
- AgentKit embedded runtime profile: `fullDesktop`
- Native Sign in with Apple: hidden because Developer ID profiles do not
  support that entitlement

Select `Talkify-MacDirect` and **Any Mac**, then use **Product > Archive**.
In Organizer choose **Distribute App > Direct Distribution**, sign with
Developer ID, notarize, and package the exported `.app` as a `.zip` or `.dmg`.

Phone login remains available in both channels. A future web-based Apple OAuth
flow can be added to the direct-download channel without changing its signing
or runtime profile.
