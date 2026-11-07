# DreamCAST TV: free Apple TV 4K device test

This is a **personal-device test**, not a TestFlight or App Store build.
Use the `free-device-testing` branch. The `main` branch keeps the full app setup.

## What this branch changes

- Uses bundle ID `com.skidazzit.dreamcasttv.dev` for the tvOS app.
- Leaves the Apple Development Team blank so you can choose **Personal Team** in Xcode.
- Removes paid-capability entitlements from the tvOS app's signing settings.
- Skips the Top Shelf and hosted asset-pack extensions for this test build.
- Keeps the DreamCAST TV logo, Live TV guide, playlist group ordering, and core media app code.

**Limitations:** iCloud sync, App Attest features, the Top Shelf extension, and
Apple-hosted speech-model assets are not configured for this free build.
Some features that use remote services or hosted assets may not work. Do not
enable iCloud sync in this build. This setup has not yet been compiled on a Mac.

## 1. Get the branch on your Mac

For a fresh checkout:

```bash
cd ~/Desktop
git clone --branch free-device-testing https://github.com/skidazzit/Dreamcast-TV.git DreamCAST-TV-Test
cd DreamCAST-TV-Test
cp DreamCASTCore/Config/Secrets.swift.template DreamCASTCore/Config/Secrets.swift
open DreamCAST.xcodeproj
```

If you already cloned the repository, commit or stash any local edits before switching:

```bash
cd ~/Desktop/Dreamcast-TV
git fetch origin
git switch --track origin/free-device-testing
cp DreamCASTCore/Config/Secrets.swift.template DreamCASTCore/Config/Secrets.swift
open DreamCAST.xcodeproj
```

The template contains placeholders. Do not commit personal keys, passwords, or tokens.

## 2. Add your free Apple Account

1. Open **Xcode → Settings → Accounts** and sign in.
2. Confirm your account appears as **Personal Team**.
3. In the project, select target **DreamCAST** (the tvOS app, branded DreamCAST TV).
4. Under **Signing & Capabilities**, enable **Automatically manage signing**.
5. Select your **Personal Team**. Do not select the original author's team.
6. Confirm bundle ID `com.skidazzit.dreamcasttv.dev`. If already taken in your Personal Team,
   choose another unique ID, such as `com.<yourname>.dreamcasttv.dev`.

Use the **DreamCAST** scheme for tvOS. Do not use **DreamCAST iOS**.

## 3. Pair the Apple TV 4K

1. Put the Mac and Apple TV on the same local network.
2. On Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**.
3. In Xcode, open **Window → Devices and Simulators** or **Device Hub**.
4. Select the discovered Apple TV, pair it, and enter the code from the TV.
5. Select the paired Apple TV as Xcode's run destination.

The app requires tvOS 26 or newer. Xcode must include tvOS platform support.

## 4. Build and run

1. Select **DreamCAST → Apple TV 4K** as scheme and run destination.
2. Select **Product → Run** (Command-R).
3. Let Xcode create the Personal Team provisioning profile and install the app.
4. Open DreamCAST TV and test the Live TV source, guide, and playlist group order.

Use **Settings → Live TV → Reorder Playlist Groups**. Hold Select on a group
and move it up or down. Reopen the guide and check that the order was saved.

## Troubleshooting

- **No Apple TV in Xcode:** Check both devices are on the same network, reopen
  the pairing screen, and ensure Xcode sees the device.
- **Signing error:** Confirm the DreamCAST tvOS target uses Personal Team,
  automatic signing, and your own unique bundle ID.
- **Unsupported capability:** Confirm you are on `free-device-testing`, not `main`.
  Send the full Xcode error so we can check the exact target.
- **OS or SDK mismatch:** Install tvOS support through Xcode and check that the
  Apple TV runs tvOS 26 or newer.
- **Build error:** Copy the first actual compiler error, not just "Build Failed".

Apple's free provisioning expires after seven days. Rebuild and install from
Xcode again to keep testing. A paid Apple Developer membership is needed for TestFlight.
