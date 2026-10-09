# Running on a physical iPhone

`make device` builds a Debug build, signs it with your Apple Developer team, and installs
and launches it on your iPhone. Signing is automatic: on the first run Xcode creates the
development certificate and provisioning profile, and registers the iPhone with the team,
so nothing has to be set up by hand in the Apple Developer portal.

A paid team's profile lasts a year. A free personal team works too, but its installs expire
after 7 days (run `make device` again) and it may refuse the bundle ID `ai.assistantlink.app`
if that is registered to another team; see [Bundle ID](#bundle-id).

## One-time setup

### 1. Sign in to Xcode

1. Open Xcode and choose **Xcode › Settings… (⌘,) › Apple Accounts**.
2. If your Apple Account is not listed, click **Add Apple Account…** and sign in.
3. Select it and check that the team you want to sign with is listed under **Teams**.

### 2. Prepare the iPhone

1. Pair it with this Mac: connect it with a cable once and tap **Trust** on the phone.
   After that it also works over the same Wi-Fi network.
2. Turn on **Settings › Privacy & Security › Developer Mode**. The phone restarts; confirm
   when it asks.

### 3. Tell the Makefile your team ID

Find your team ID under **Membership details** at
[developer.apple.com/account](https://developer.apple.com/account), or read it from any of
the team's certificates on this Mac (it is the `OU`):

```sh
security find-certificate -c "<team name>" -p | openssl x509 -noout -subject
```

Put it in `Local.mk` at the repository root, which is git-ignored so the team ID is never committed:

```make
DEVELOPMENT_TEAM := ABCDE12345
```

`make device DEVELOPMENT_TEAM=ABCDE12345` works too, without a `Local.mk`.

### Bundle ID

The app's bundle ID is `ai.assistantlink.app`. To sign with a team that cannot use it, set
your own in `Local.mk`:

```make
DEVICE_BUNDLE_ID := com.yourname.assistantlink
```

## Install and launch

With the iPhone unlocked:

```sh
make device
```

With several iPhones paired, pick one with `make device DEVICE="Your iPhone"` (its name or
UDID, from `xcrun devicectl list devices`).

If the first launch fails because the developer is not trusted, open
**Settings › General › VPN & Device Management** on the iPhone, tap your team's
**Apple Development** entry, tap **Trust**, and run `make device` again.
