# Building Zoon without a Mac

iOS apps can only be compiled on macOS. Xcode is macOS-only and there is no
supported way around that on Windows or Linux — no cross-compiler, no emulator,
no workaround. That is an Apple constraint, not a gap in this project.

You do not, however, need to *own* a Mac. There are three separate problems,
and they have very different answers:

| | Cost |
|---|---|
| **Compiling it** | Free. Works today. |
| **Seeing it run** | Free. Works today. |
| **Running it on your own iPhone, reading your real sleep** | $99/year. Unavoidable. |

---

## Problem 1 — Compiling it (free, works today)

`.github/workflows/build.yml` builds both targets on a GitHub-hosted macOS
runner every time you push. **No Apple Developer account, no certificates, no
configuration.** Building for the Simulator with signing disabled skips
provisioning entirely.

### Using it

1. Push any commit to this repo.
2. Open the **Actions** tab on GitHub.
3. Open the newest **Build** run.

Compile errors appear in the run's **Summary** — deduplicated, capped at the
first 60, with warnings folded underneath. The complete log is attached as a
`build-log` artifact.

Copy the summary block back to whoever is fixing the code. That is the whole
loop, and it closes the gap that no-Mac otherwise leaves open.

### What it costs

| Repository | Cost |
|---|---|
| **Public** | Free, unlimited |
| **Private** | Free tier only. macOS minutes bill at **10×**, so 2,000 included minutes ≈ **200 macOS minutes/month**. A Zoon build is roughly 4–8 minutes, so ~25–50 builds a month. |

The workflow cancels superseded runs on the same branch to avoid burning that
allowance on builds nobody is waiting for.

> If the repo is private and you run low, making it public is the cheapest fix
> by a wide margin. Nothing in Zoon is secret — there are no keys, no endpoints,
> and no server.

---

## Problem 2 — Seeing it run (free, works today)

`.github/workflows/screenshots.yml` boots an **iOS Simulator on the runner**,
installs the app, launches it once per tab, and photographs each screen. Real
SwiftUI, real layout, real sizes — not a mockup.

### Using it

1. **Actions** tab → **Screenshots** → **Run workflow**.
2. Optionally change the device (default `iPhone 17 Pro`).
3. When it finishes, download the **screenshots** artifact.

The app is launched with `-zoonDemo YES`, which forces the mock dataset and
skips HealthKit entirely — the Simulator has a Health store but no sleep data
in it, and no one is there to tap the permission sheet. Every synthetic night
is badged **Sample data** on screen, so a demo capture can't be mistaken for a
real one.

This run is also the only automated proof the app *launches*. Building proves
it type-checks; it can still crash in `ModelContainer(for:)` on first run. The
job checks the process is still alive before each screenshot and fails with the
crash log if it isn't.

**What it can't do:** it can't tap. Screens reachable only by interaction
(sleep detail, soundscapes, nap timer, settings) aren't captured. Adding a
UI-test target would fix that — worth doing if the top-level captures prove
useful.

---

## Problem 3 — Running it on your iPhone

This is the one that costs money.

Installing an app on a physical iPhone requires a signed build. Signing requires
an Apple Developer account, and getting the signed build onto the phone requires
either a Mac with Xcode or TestFlight.

### Why the free-signing route doesn't work here

A free Apple ID gives you a **Personal Team**, which can sign an app for 7 days
at a time — and on Windows, tools like Sideloadly and AltStore will do that
signing and install for you, no Mac involved. That is a genuinely free path to
getting an app on your phone.

**It does not work for Zoon.** Personal Teams cannot use entitlement-backed
capabilities, and **HealthKit is one of them** (so are App Groups, push
notifications, iCloud, and Sign in with Apple). A free-signed Zoon would either
be rejected at signing or install and then read nothing — an app showing you
permanent sample data.

Since reading your sleep *is* the app, this route is a dead end. Not a
limitation worth working around; the capability is simply gated.

### Option A — TestFlight, driven from CI (no Mac at any point)

`.github/workflows/testflight.yml` does this: archives, signs, and uploads to
TestFlight on the same free macOS runner Build and Screenshots already use.
Nothing else to write — it exists, and is dormant until the four secrets below
exist. It fails fast and clearly if any are missing, rather than 20 minutes
into an archive.

**Once, in the Apple Developer / App Store Connect sites:**

1. **Enroll in the Apple Developer Program** — [developer.apple.com/programs](https://developer.apple.com/programs/),
   $99/year. Approval is usually a day or two for an individual account.
2. **Register the bundle identifiers**, at
   [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) →
   **+**. Register all four, as plain App IDs (no capabilities need ticking —
   Xcode's automatic signing adds HealthKit itself when it provisions):
   `com.zoon.sleep`, `com.zoon.sleep.ZoonWidget`, `com.zoon.sleep.watchkitapp`,
   `com.zoon.sleep.watchkitapp.complication`.
   *(Using your own reversed-domain prefix instead of `com.zoon.sleep`? Change
   it in `Tools/generate-pbxproj.py` — search `PRODUCT_BUNDLE_IDENTIFIER` — then
   run `python3 Tools/generate-pbxproj.py` and commit the regenerated project
   file before registering the new identifiers.)*
3. **Create the app record**, at [App Store Connect](https://appstoreconnect.apple.com/) →
   **Apps** → **+** → **New App**. Platform iOS, bundle ID `com.zoon.sleep`,
   any SKU. This is what lets a build with that bundle ID land in TestFlight —
   without it, upload fails with "no such app".
4. **Generate an App Store Connect API key**, at App Store Connect →
   **Users and Access** → **Integrations** → **App Store Connect API** → **+**.
   Role: **App Manager** (enough to upload builds; not full Admin).
   Downloads once, as a `.p8` file — Apple will not let you download it again,
   so save it somewhere before closing the tab.
5. **Find your Team ID** — App Store Connect → **Membership**, or
   [developer.apple.com/account](https://developer.apple.com/account/#/membership) →
   **Membership details**. A 10-character code like `A1B2C3D4E5`.

**Once, in this repo:** GitHub → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**, four times:

| Secret | Value |
|---|---|
| `APPSTORE_ISSUER_ID` | Shown next to the API key list in App Store Connect |
| `APPSTORE_KEY_ID` | The key's ID, shown in the same list |
| `APPSTORE_PRIVATE_KEY` | The full contents of the `.p8` file, pasted as-is (including the `-----BEGIN/END PRIVATE KEY-----` lines) |
| `APPLE_TEAM_ID` | The 10-character Team ID from step 5 |

**Every time after that:** **Actions** tab → **TestFlight** → **Run workflow**.
~15–20 minutes — archiving a Release build is slower than the Debug builds
Build and Screenshots use. Apple then takes a few more minutes to process the
build on their end before it appears in TestFlight; that part happens on
Apple's servers, not the runner, so a green workflow doesn't mean it's visible
on your phone *yet* — check the TestFlight tab in App Store Connect, or the
TestFlight app itself, a few minutes later.

First build on a fresh App Store Connect record needs one manual step Apple
doesn't let CI skip: **Export Compliance**. App Store Connect → TestFlight →
the build → answer "Does your app use encryption?" — **No** is correct here
(Zoon has no networking code, so nothing to declare). After that first
answer, later builds in the same app don't ask again.

Once all this exists, install TestFlight on your iPhone, accept the invite
App Store Connect emails you, and every future push through the workflow puts
a new build on your phone. You never touch a Mac.

### Option B — Rent a Mac by the hour

Useful for interactive debugging and Instruments, which CI can't give you. (For
screenshots, see Problem 2 — you don't need this.)

- **[MacinCloud](https://www.macincloud.com/)** — from around \$1/hour or ~\$25/month
- **[MacStadium](https://www.macstadium.com/)** — dedicated hardware, pricier
- **AWS EC2 Mac** — billed with a 24-hour minimum, so expensive for short sessions

### Option C — Buy a used Mac

A second-hand M1 Mac mini is the cheapest way to own the full toolchain
outright, and it runs current Xcode comfortably. Worth comparing against a year
of Option B if you expect to keep working on this.

---

## What you can do with no Mac and no money

- **Compile it**, and get every error listed — Problem 1.
- **Run it and see it**, screen by screen — Problem 2.
- **Confirm it launches without crashing** — Problem 2.
- **Read the code.** It's all here.

## What you genuinely cannot do

- **Read your real sleep data** without the \$99/year account. HealthKit is
  gated behind a paid team; free signing can't reach it.
- **Use the Simulator interactively** — CI can screenshot, it can't let you tap.
- **Run the widget with live data** — needs an App Group, also paid-only.
- **Use TestFlight** — paid-only.

---

## Recommended order

1. Push, let CI build. Free.
2. Run **Screenshots** and look at what you've got. Free.
3. Iterate on 1 and 2 until the app is what you want. Still free.
4. *Then* decide whether it's worth \$99/year to point it at your own sleep.

Steps 1–3 are the whole development loop, and none of it costs anything. Step 4
buys exactly one thing — real data on your own phone — and it's the last step,
not the first.
