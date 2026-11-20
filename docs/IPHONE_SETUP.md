# Connect your iPhone

You need a WHOOP 5.0 or MG, an iPhone on iOS 17+, and your own
[Zoop API server](../server/README.md). Build with Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen); the verified toolchain is
Xcode 27.2 / XcodeGen 2.46.0. Device builds need an Apple development team with
HealthKit signing support.

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
4. Enter your server's HTTPS URL and sign in with an account created by its administrator.

Pair the strap in the official WHOOP app first, then quit that app before connecting
with Zoop. Keep the existing Bluetooth bond. A simulator can preview the interface,
but cannot collect strap data.
