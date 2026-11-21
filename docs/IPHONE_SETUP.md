---
id: iphone
slug: /iphone
title: Connect your iPhone
description: Install Zoop, connect your WHOOP and sign in to your server.
---

# Connect your iPhone

You need a WHOOP 5.0 or MG, an iPhone on iOS 17+, and a running
[Zoop server](SELF_HOSTING.md).

## Install Zoop

Zoop is not on the App Store yet. Until it is available, use the
[build instructions below](#build-from-source).

## Connect to your server

1. Open Zoop and enter your server’s HTTP or HTTPS address.
2. Sign in with the account created on that server.
3. Pair your band in the official WHOOP app first, then quit that app and connect
   with Zoop. Keep the existing Bluetooth bond.

Your account must own the band’s serial number; see [server setup](SELF_HOSTING.md#connect-your-iphone).
Saved history is available without a connected band. New recordings need the band.
For HTTP, use a trusted LAN or VPN and allow local-network access when iOS asks.

## Build from source

This section is for installing before the App Store release or working on the app.
You need a Mac, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple
development team with HealthKit signing support. The verified toolchain is
Xcode 27.2 / XcodeGen 2.46.0.

```sh
git clone https://github.com/MakisChristou/zoop.git
cd zoop
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

1. Set your development team and a unique bundle ID in `Config/Local.xcconfig`.
   This file is ignored by Git.
2. Generate and open the project:

   ```sh
   xcodegen generate
   open Zoop.xcodeproj
   ```

3. Select the **Zoop** scheme and your iPhone, then Run.
4. Follow [Connect to your server](#connect-to-your-server) above.

A simulator can preview the interface, but cannot collect band data.
