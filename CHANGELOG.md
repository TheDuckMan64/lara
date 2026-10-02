# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3] - 2026-10-02

First release as **EU Enabler**, a slimmed-down fork of
[lara](https://github.com/rooootdev/lara) that only does the EU Enabler.

### Added

- One-click run that performs every step in order: exploit → kernelcache →
  RemoteCall (SpringBoard) → eligibility overwrite → EU region spoof, and then
  closes the RemoteCall session. Individual steps remain available for retries.
- Progress bar with a live percentage and a single status line.
- Status list of broad success/error milestones. The full engine log is still
  written to `EUEnabler.log` on disk.
- Active-thread targeting for the iOS 17+ RemoteCall path: when attaching to a
  daemon it re-scans the target's thread list and injects into every thread it
  hasn't caught yet, so a short-lived worker thread is picked up. The thread that
  actually fires is recovered from the exception reply and used as the call thread.
- Keep-awake pokes while attaching, so a wake lands *after* the guard is installed.
- Wake-and-wait for on-demand daemons: wake, then poll for the process to appear
  (up to 12s, re-waking every 2s).
- Launchd plist lookup that reads a daemon's real `MachServices` names instead of
  trusting a hard-coded service string.
- Configurable first-exception timeout, so a failed attach fails fast.
- Settings → Advanced → "Allow unsupported iOS version" to experiment with a
  build that has no verified offsets yet (MIE/debugger checks still apply).
- Single source of truth for the supported iOS range
  (`euenabler_version_supported()` / `ksupportedranges`), so the UI gate and the
  offsets module can't disagree. Adding a version is a one-file change.
- `scripts/make_appicon.swift`, which turns a rounded-square-on-white artwork into
  a full-bleed, opaque 1024x1024 app icon.

### Changed

- Rebranded from lara to EU Enabler throughout: bundle identifier
  (`com.roooot.euenabler`), target/scheme/product (`EUEnabler`), source folder,
  bridging header, entitlements, log file (`EUEnabler.log`), UserDefaults keys
  (`euenabler.*`), C/Swift symbols, build scripts, CI workflow and docs.
- New app icon, generated full-bleed from `eu_enabler.png`.
- The two marketplace daemons are now set up **one at a time**. Initializing both
  concurrently made one of them fail with "Failed to receive first exception".
- `appstorecomponentsd` and `managedappdistributiond` both use the wake-and-wait +
  active-thread scan path, and each retries before giving up.
- `appstorecomponentsd` runs first, so the reliable half completes immediately.
- Fail fast on the marketplace daemon: a failed attach waits 60s once instead of
  3 × 120s.
- Version bumped to 0.3.

### Fixed

- RemoteCall could not attach to `managedappdistributiond` ("Failed to receive
  first exception"). The daemon parks its main thread, and the engine only ever
  injected into the first thread in the list. The active-thread scan now also
  catches a runnable worker.
- `appstorecomponentsd` never started: `wake_up_daemon`'s special case matched on
  the process name while being passed the Mach service name, so it never fired and
  the daemon was never contacted. The AppStoreComponents poke is now best-effort
  and always falls through to the generic Mach-service wake, which is what makes
  launchd start the daemon.
- A failed attach on iOS 17+ left the injected `EXC_GUARD` set on the target
  thread. It is now cleared on timeout (the iOS 16 path already did this).
- UI freeze caused by rendering the whole engine log. Only broad milestones are
  rendered now, and the in-memory buffer is bounded.
- SpringBoard respring when the app was backgrounded or killed while the
  SpringBoard RemoteCall session was alive; the background teardown is restored.
- The EU spoof now closes the RemoteCall session once it succeeds, from both the
  one-click run and the standalone button.
- Removed a per-write `fsync` in the logger that stalled heavy logging.

### Removed

- Everything that isn't the EU Enabler: the file manager, the entire tweaks
  system (SpringBoard customizer, Liquid Glass, dirtyZero, passcode themes,
  DarkBoard, MobileGestalt, font/colour/icon overrides, app decrypt, JIT,
  3-app bypass, OTA and Screen Time disablers), and the VFS/SBX/APFS/vnode
  subsystem they relied on.
- Dead leftovers: the `OverwriteFiles` resource tree (and its entries in the
  app's Resources phase), stale project references to already-deleted sources,
  an unused third-party licence, and unused UI-kit sources.

## Earlier

Versions before 0.3 were the upstream lara toolbox; see
[lara's repository](https://github.com/rooootdev/lara) for that history.
