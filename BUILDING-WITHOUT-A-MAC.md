# Building Zoon without a Mac

iOS apps can only be compiled on macOS. Xcode is macOS-only and there is no
supported way around that on Windows or Linux — no cross-compiler, no emulator,
no workaround. That is an Apple constraint, not a gap in this project.

You do not, however, need to *own* a Mac. There are two separate problems, and
they have different answers.

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

## Problem 2 — Running it on your iPhone

This is the harder one, and it does cost money.

Installing an app on a physical iPhone requires a signed build. Signing requires
an Apple Developer account, and getting the signed build onto the phone requires
either a Mac with Xcode or TestFlight.

### Option A — TestFlight, driven from CI (no Mac at any point)

- **Apple Developer Program: $99/year.** This is unavoidable.
- Register at [developer.apple.com](https://developer.apple.com/programs/).
- Create the app record in App Store Connect.
- Generate an App Store Connect API key and add it to the repo's GitHub Secrets.
- Extend the workflow to archive, sign, and upload to TestFlight.
- Install TestFlight on your iPhone and the build arrives there.

Once configured, every push can put a new build on your phone, and you never
touch a Mac. Ask and I'll write that workflow — it's roughly 60 more lines, but
it can't be tested until the account and key exist.

### Option B — Rent a Mac by the hour

Useful for interactive debugging, Simulator screenshots, and Instruments, which
CI can't give you.

- **[MacinCloud](https://www.macincloud.com/)** — from around \$1/hour or ~\$25/month
- **[MacStadium](https://www.macstadium.com/)** — dedicated hardware, pricier
- **AWS EC2 Mac** — billed with a 24-hour minimum, so expensive for short sessions

### Option C — Buy a used Mac

A second-hand M1 Mac mini is the cheapest way to own the full toolchain
outright, and it runs current Xcode comfortably. Worth comparing against a year
of Option B if you expect to keep working on this.

---

## What you can do with no Mac and no money

- **Compile and fix errors** — Option 1, free, today.
- **Read the code** — it's all here.
- **See the design** — the HTML mockups render anywhere.

## What you genuinely cannot do

- **Run it on an iPhone** without the \$99/year developer account.
- **Use the Simulator interactively** — CI builds, it doesn't let you tap around.
- **Take real screenshots** — needs a running app, so needs a Mac or a rented one.

---

## Recommended order

1. Push, let CI build, collect the errors.
2. Fix until the build is green. This is the entire "does it work" question, and
   it costs nothing.
3. *Then* decide whether it's worth \$99/year to put it on your phone.

Step 2 is the one that matters. Until the build is green, everything else is
premature.
