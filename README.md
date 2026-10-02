# EU Enabler

An EU Enabler for iOS, built on the DarkSword kernel exploit. It allows installing
EU/Japan Marketplace apps by overriding App Store eligibility and spoofing the
device's region.

This project is a slimmed-down fork of [lara](https://github.com/rooootdev/lara):
everything except the EU Enabler has been removed.

## Support

| iOS Version | Support Status |
| - | - |
| iOS 16.0 – iOS 16.7.x | Supported ¹ |
| iOS 17.0 – iOS 17.7.x | Supported |
| iOS 18.0 – iOS 18.7.x | Supported |
| iOS 26.0 – iOS 26.0.1 | Supported |
| Anything else | Not Supported |

The supported range is defined in one place — `euenabler_version_supported()` in
`EUEnabler/kexploit/offsets.m` — and both the UI and the offsets module use it, so they
can't disagree. The per-version kernel structure offsets live in the version
branches of that same file (16.0, 17.1, 17.4, 18.0, 18.1, 18.4, 18.6 and 26.0).
Anything outside 16.0 – 26.0.1 lacks offsets.

### Adding a new iOS version

Adding a version (for example 26.0.2 once its offsets are known) is a one-file
change in `EUEnabler/kexploit/offsets.m`:

1. Add a `SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO` branch in `offsets_init()`
   with that build's kernel struct offsets (or point at the existing branch if
   the structs are unchanged).
2. Add the range to `ksupportedranges`, or just widen the current range's
   `maxVersion` (e.g. change `"26.0.2"` to `"26.1"`).

That table is the only place the supported range is defined: `offsets_init()`
and the app's support check both read it, and the log prints which branch was
chosen (`(offs) offsets branch: iOS 26.0`).

For testing a build *before* offsets are confirmed, Settings → Advanced has an
opt-out ("Allow unsupported iOS version"). It only bypasses the version gate —
MIE and debugger checks still apply — and you're expected to set the offsets
yourself with "Modify Offsets". Wrong offsets can panic the kernel.

¹ Some older iOS 16 builds are untested, and a few of them may still be missing
offsets.

Important Notes:
- Does **not** work on M5 or A19 (Pro) devices regardless of iOS version, because of MIE.
- YMMV on M-series CPUs. On an M-series device, try Settings → Modify Offsets and set
  `t1sz_boot` to `0x11`.
- The EU Enabler options require **iOS 17.4 or later**.
- Installing EU/Japan marketplace apps also requires a VPN with an EU or Japan exit,
  because Apple checks the network location at install time.

## Usage

**One-click run** does everything in order:

1. **Run Exploit** — gets kernel read/write.
2. **Fetch Kernelcache** — resolves the offsets the exploit needs (or import a
   kernelcache manually from Settings).
3. **Initialize RemoteCall** — opens a remote-call session on SpringBoard.
4. **Overwrite eligibility** — forces the marketplace eligibility domains to
   "eligible".
5. **Spoof EU region** — spoofs the App Store country code in
   `appstorecomponentsd` and `managedappdistributiond`.

It then closes the RemoteCall session, because leaving the SpringBoard session
alive makes SpringBoard respring. The individual steps are also available as
buttons, so a failed step can be retried on its own.

The rest of the UI is a live progress line, a status list of broad success/error
milestones, and settings. The full engine log is written to `EUEnabler.log` in the
app's Documents directory.

## Releases

Builds are produced by the GitHub Actions workflow as `EUEnabler.ipa` and
published to the `nightly` release.

Add the AltStore source for either channel:

- Stable: [`source.json`](https://raw.githubusercontent.com/TheDuckMan64/lara/main/source.json)
- Nightly: [`source_nightly.json`](https://raw.githubusercontent.com/TheDuckMan64/lara/main/source_nightly.json)

## Credits

- wh1te4ever for darksword-kexploit-fun
- opa334 for ChOma and XPF
- Duy Tran for RemoteCall
- AppInstalleriOS for help with offsets
- Everyone who contributed to EU Enabler

## License

See [LICENSE](LICENSE).
