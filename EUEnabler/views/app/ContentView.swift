//
//  ContentView.swift
//  EU Enabler
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: EUEnablerManager

    @State private var showSettings: Bool = false
    @State private var dlingkcache: Bool = false
    @State private var oneClickRunning: Bool = false

    init() {
        globallogger.capture()
    }

    var body: some View {
        NavigationStack {
            List {
                RunAllSection
                ProgressSection
                AlertsSection
                SetupSection
                EUSection
                ToolsSection
                ActivitySection
            }
            .navigationTitle("EU Enabler")
            .toolbar {
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var RunAllSection: some View {
        Group {
            if #available(iOS 17.4, *) {
                Section {
                    Button {
                        runEverything()
                    } label: {
                        HStack {
                            if oneClickRunning {
                                ProgressView()
                                    .frame(width: 18, height: 18)
                                Text("Running…")
                            } else {
                                Image(systemName: "play.circle.fill")
                                Text("Run EU Enabler")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(oneClickRunning || isdebugged())
                } footer: {
                    Text("One-click run")
                }
            }
        }
    }

    private var ProgressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mgr.stepText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int((mgr.stepProgress * 100).rounded()))%")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                ProgressView(value: mgr.stepProgress)
                    .progressViewStyle(.linear)
            }
            .padding(.vertical, 2)
        }
    }

    // Broad success / error lines only. The full engine log still goes to EUEnabler.log.
    private var ActivitySection: some View {
        Section {
            if mgr.milestones.isEmpty {
                Text("No activity yet")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mgr.milestones.reversed()) { milestone in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: milestone.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(milestone.isError ? .red : .green)
                            Text(milestone.text)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HeaderLabel(text: "Status", icon: "list.bullet")
        }
    }

    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets && mgr.dsready {
                PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Fetch or import the kernelcache to continue.")
            }
        }
    }

    private var SetupSection: some View {
        Section {
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("Run Exploit", action: {
                    stepRunExploit { _ in }
                })
                .disabled(mgr.dsready || mgr.dsrunning || oneClickRunning || isdebugged())
            }

            if !mgr.hasOffsets {
                Button {
                    stepKernelcache { _ in }
                } label: {
                    if dlingkcache {
                        HStack {
                            Text("Fetching Kernelcache...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Fetch Kernelcache")
                    }
                }
                .disabled(dlingkcache || !mgr.dsready || oneClickRunning)
            } else {
                LabeledContent("Kernelcache") {
                    Image(systemName: "checkmark.circle")
                }
            }

            LabeledContent(content: {
                if mgr.rcready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.rcrunning {
                    HStack {
                        Text("Running...")
                        ProgressView()
                    }
                } else if mgr.rcfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("Initialize RemoteCall", action: {
                    stepRemoteCall { _ in }
                })
                .disabled(!mgr.dsready || isdebugged() || mgr.rcrunning || mgr.rcready || oneClickRunning)
            }

            if mgr.rcready {
                Button("Destroy Remotecall", role: .destructive) {
                    stepDestroyRemoteCall { }
                }
                .disabled(oneClickRunning)
            }
        } header: {
            HeaderLabel(text: "Setup", icon: "ant")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error = mgr.rcLastError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                }
                if isdebugged() {
                    Text("Not available while a debugger is attached.")
                }
                Text("Run the exploit, fetch the kernelcache and initialize RemoteCall before using the EU Enabler.")
            }
            .font(.footnote)
        }
    }

    private var EUSection: some View {
        Group {
            if #available(iOS 17.4, *) {
                Section {
                    Button {
                        stepEligibility { ok in
                            if !ok {
                                Alertinator.shared.alert(title: "Eligibility failed", body: "The eligibility overwrite could not be applied. Make sure RemoteCall is initialized and try again.")
                            }
                        }
                    } label: {
                        HStack {
                            Text("Overwrite eligibility (one time setup)")
                            if let state = mgr.eligibilitystate {
                                Spacer()
                                if state {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .disabled((mgr.eligibilitystate ?? false) || isdebugged() || mgr.rcrunning || !mgr.rcready || oneClickRunning)

                    Button {
                        stepEUSpoof { ok in
                            if ok {
                                stepDestroyRemoteCall {
                                    showAppliedAlert()
                                }
                            } else {
                                Alertinator.shared.alert(title: "EU spoof incomplete", body: "One of the marketplace daemons could not be reached. Make sure RemoteCall is initialized and try again. If a daemon never starts, open the App Store once (or start an install) so it launches, then run this again — a respring also helps.")
                            }
                        }
                    } label: {
                        HStack {
                            if mgr.eu1running || mgr.eu2running {
                                ProgressView(value: (mgr.eu1progress + mgr.eu2progress)/2)
                                    .progressViewStyle(.circular)
                                    .frame(width: 18, height: 18)
                                Text("Running...")
                                Spacer()
                                Text("\(Int((mgr.eu1progress + mgr.eu2progress)/2 * 100))%")
                            } else {
                                Text("Enable Spoof EU Region")
                                Spacer()
                                if mgr.eu1progress + mgr.eu2progress == 2 {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .disabled(mgr.eu1running || mgr.eu2running || mgr.eu1progress+mgr.eu2progress == 2 || isdebugged() || mgr.rcrunning || !mgr.rcready || oneClickRunning)
                } header: {
                    HeaderLabel(text: "EU Enabler", icon: "globe.europe.africa")
                } footer: {
                    Text("Enables installing of EU/Japan Marketplace apps. Apple still checks your network location when you install, so connect to a VPN in the EU or Japan for the installation itself — you can disconnect afterwards.")
                }
            }
        }
    }

    private var ToolsSection: some View {
        Section(header: HeaderLabel(text: "Tools", icon: "wrench.and.screwdriver")) {
            Button("Respring", action: {
                mgr.respring()
            })
        }
    }

    // MARK: - One click

    private func runEverything() {
        guard !oneClickRunning else { return }
        oneClickRunning = true

        stepRunExploit { ok in
            guard ok else { return finishOneClick(error: "Exploit failed") }
            self.stepKernelcache { ok in
                guard ok else { return self.finishOneClick(error: "Kernelcache failed") }
                self.stepRemoteCall { ok in
                    guard ok else { return self.finishOneClick(error: "RemoteCall failed") }
                    self.stepEligibility { ok in
                        guard ok else { return self.finishOneClick(error: "Eligibility overwrite failed") }
                        self.stepEUSpoof { ok in
                            // Always close the session once we're done: leaving the
                            // SpringBoard RemoteCall alive makes SpringBoard respring.
                            self.stepDestroyRemoteCall {
                                self.finishOneClick(error: ok ? nil : "EU spoof incomplete")
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishOneClick(error: String?) {
        oneClickRunning = false

        if let error {
            mgr.milestone("Run stopped: \(error)", isError: true)
            Alertinator.shared.alert(title: "EU Enabler", body: "\(error). Check the status list to see which step failed — you can retry the individual steps below.")
        } else {
            showAppliedAlert()
        }
    }

    private func showAppliedAlert() {
        mgr.setStatus("EU Enabler applied", 1.0)
        mgr.milestone("EU Enabler applied")
        Alertinator.shared.alert(
            title: "EU Enabler applied",
            body: "RemoteCall session closed. Respring so the App Store picks up the new region, then reopen it. Install EU/Japan marketplace apps while connected to a VPN in that region.",
            actionLabel: "Respring"
        ) {
            self.mgr.respring()
        }
    }

    // MARK: - Steps
    //
    // Each step is a standalone async unit so the one-click run and the individual
    // buttons share exactly the same behaviour. Every completion is called on the
    // main queue.

    private func stepRunExploit(completion: @escaping (Bool) -> Void) {
        if mgr.dsready { completion(true); return }
        guard !isdebugged() else { completion(false); return }

        mgr.setStatus("Running exploit…", 0.0)
        offsets_init()
        mgr.run { success in completion(success) }
    }

    private func stepKernelcache(completion: @escaping (Bool) -> Void) {
        if mgr.hasOffsets { completion(true); return }
        guard !dlingkcache, mgr.dsready else { completion(false); return }

        dlingkcache = true
        mgr.setStatus("Fetching kernelcache…", 0.35)
        mgr.milestone("Kernelcache: fetching")

        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            if fetchkcache() {
                ok = dlkcache()
            }

            DispatchQueue.main.async {
                mgr.hasOffsets = ok
                mgr.setStatus(ok ? "Kernelcache ready" : "Kernelcache fetch failed", ok ? 0.45 : 0.30)
                mgr.milestone(ok ? "Kernelcache ready" : "Kernelcache fetch failed", isError: !ok)
                dlingkcache = false
                completion(ok)
            }
        }
    }

    private func stepRemoteCall(completion: @escaping (Bool) -> Void) {
        if mgr.rcready { completion(true); return }
        guard mgr.dsready, !isdebugged() else { completion(false); return }

        mgr.setStatus("Initializing RemoteCall…", 0.45)
        mgr.milestone("RemoteCall: initializing")
        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
            if success {
                mgr.setStatus("RemoteCall ready", 0.55)
                mgr.milestone("RemoteCall ready")
            } else {
                mgr.setStatus("RemoteCall failed", 0.45)
                mgr.milestone("RemoteCall failed", isError: true)
            }
            completion(success)
        }
    }

    private func stepEligibility(completion: @escaping (Bool) -> Void) {
        guard mgr.rcready else { completion(false); return }

        mgr.setStatus("Overwriting eligibility…", 0.55)
        mgr.milestone("Eligibility: overwriting")
        mgr.rcinitDaemon(serviceName: "com.apple.xpc.amsaccountsd", process: "amsaccountsd", migbypass: false) { proc in
            var ok = false
            if let proc {
                mgr.logmsg("rc init succeeded!")
                ok = euenabler_overwrite_eligibility(proc) == 0
                mgr.logmsg("overwrite_eligibility() returned: \(ok ? "success" : "failure")")
                proc.destroy()
            } else {
                mgr.logmsg("rc init failed")
            }

            DispatchQueue.main.async {
                mgr.eligibilitystate = ok
                mgr.setStatus(ok ? "Eligibility overwritten" : "Eligibility overwrite failed", ok ? 0.70 : 0.55)
                mgr.milestone(ok ? "Eligibility overwritten" : "Eligibility overwrite failed", isError: !ok)
                completion(ok)
            }
        }
    }

    private func stepEUSpoof(completion: @escaping (Bool) -> Void) {
        startEUSpoof(completion: completion)
    }

    private func stepDestroyRemoteCall(completion: @escaping () -> Void) {
        guard mgr.rcready else { completion(); return }

        mgr.setStatus("Closing RemoteCall session…", 0.98)
        mgr.milestone("RemoteCall: closing session")
        mgr.rcdestroy {
            mgr.milestone("RemoteCall session closed")
            completion()
        }
    }

    // MARK: - EU spoof

    // The two marketplace daemons must be set up one at a time: the RemoteCall
    // engine keeps global state, so initializing both concurrently makes one of
    // them fail with "Failed to receive first exception". Each is retried a few
    // times (force-waking the daemon on retries) since this step is flaky.
    private func startEUSpoof(completion: @escaping (Bool) -> Void) {
        mgr.eu1progress = 0.0
        mgr.eu2progress = 0.0
        mgr.eu1running = true
        mgr.eu2running = true

        // appstorecomponentsd attaches reliably, so run it first and let the user
        // see that half succeed immediately. managedappdistributiond is the flaky
        // one (idle on-demand daemon) and is retried with keep-awake pokes.
        spoofDaemon(
            serviceName: "com.apple.appstorecomponentsd.xpc",
            process: "appstorecomponentsd",
            label: "Spoofing EU region (app info daemon)",
            keepAwake: true,
            scanAllThreads: true,
            timeoutMs: 120000,
            setProgress: { self.mgr.eu2progress = $0 },
            stageBase: 0.70,
            stageSpan: 0.15,
            totalAttempts: 2,
            attemptsLeft: 2
        ) { appstoreOK in
            self.spoofDaemon(
                serviceName: "com.apple.managedappdistributiond.xpc",
                process: "managedappdistributiond",
                label: "Spoofing EU region (marketplace daemon)",
                keepAwake: true,
                scanAllThreads: true,
                timeoutMs: 60000,
                setProgress: { self.mgr.eu1progress = $0 },
                stageBase: 0.85,
                stageSpan: 0.15,
                totalAttempts: 1,
                attemptsLeft: 1
            ) { managedOK in
                self.mgr.eu1running = false
                self.mgr.eu2running = false
                if managedOK { self.mgr.eu1progress = 1.0 }
                if appstoreOK { self.mgr.eu2progress = 1.0 }
                completion(appstoreOK && managedOK)
            }
        }
    }

    private func spoofDaemon(serviceName: String, process: String, label: String, keepAwake: Bool, scanAllThreads: Bool, timeoutMs: Int, setProgress: @escaping (Double) -> Void, stageBase: Double, stageSpan: Double, totalAttempts: Int, attemptsLeft: Int, done: @escaping (Bool) -> Void) {
        let attempt = totalAttempts - attemptsLeft + 1
        mgr.logmsg("(eu) \(process) setup attempt \(attempt)...")
        if attempt == 1 {
            mgr.setStatus("\(label)…", stageBase)
            mgr.milestone("\(process): attaching")
        }

        mgr.rcinitDaemon(serviceName: serviceName, process: process, migbypass: false, forceWake: attempt > 1, keepAwake: keepAwake, timeoutMs: timeoutMs, scanAllThreads: scanAllThreads) { proc in
            guard let proc else {
                if attemptsLeft > 1 {
                    self.mgr.logmsg("(eu) \(process) init failed, retrying...")
                    Thread.sleep(forTimeInterval: 1.0)
                    DispatchQueue.main.async {
                        self.spoofDaemon(serviceName: serviceName, process: process, label: label, keepAwake: keepAwake, scanAllThreads: scanAllThreads, timeoutMs: timeoutMs, setProgress: setProgress, stageBase: stageBase, stageSpan: stageSpan, totalAttempts: totalAttempts, attemptsLeft: attemptsLeft - 1, done: done)
                    }
                } else {
                    self.mgr.logmsg("(eu) \(process) init failed after retries")
                    self.mgr.setStatus("\(label) failed", stageBase)
                    self.mgr.milestone("\(process): attach failed", isError: true)
                    DispatchQueue.main.async { done(false) }
                }
                return
            }

            self.mgr.logmsg("(eu) \(process) ready, applying region override...")
            euenabler_override_country_code(proc) { progress in
                DispatchQueue.main.async {
                    setProgress(progress)
                    self.mgr.setStatus("\(label)… \(Int(progress * 100))%", stageBase + stageSpan * progress)
                }
            }
            proc.destroy()
            self.mgr.logmsg("(eu) \(process) region override applied")
            self.mgr.setStatus("\(label) applied", stageBase + stageSpan)
            self.mgr.milestone("\(process): patched")
            DispatchQueue.main.async { done(true) }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(EUEnablerManager())
}
