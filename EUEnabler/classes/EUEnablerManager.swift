//
//  EUEnablerManager.swift
//  EU Enabler
//

import Combine
import Foundation
import Darwin
import UIKit

struct Milestone: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

// Reads a launchd job's plist and returns the Mach service names it vends.
// Returns an empty array when the file can't be read (e.g. the app is sandboxed),
// in which case callers fall back to the service name they were given.
func machServiceNames(forLaunchdLabel label: String) -> [String] {
    let paths = [
        "/System/Library/LaunchDaemons/\(label).plist",
        "/System/Library/LaunchAgents/\(label).plist"
    ]
    for path in paths {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let mach = plist["MachServices"] as? [String: Any] else {
            continue
        }
        return Array(mach.keys)
    }
    return []
}

final class EUEnablerManager: ObservableObject {
    @Published var log: String = ""
    @Published var hasOffsets: Bool = false
    @Published var dsrunning: Bool = false
    @Published var dsready: Bool = false
    @Published var dsattempted: Bool = false
    @Published var dsfailed: Bool = false
    @Published var dsprogress: Double = 0.0
    @Published var kernbase: UInt64 = 0
    @Published var kernslide: UInt64 = 0

    #if !DISABLE_REMOTECALL
    @Published var rcrunning: Bool = false
    @Published var eligibilitystate: Bool?
    @Published var eu1progress: Double = 0.0
    @Published var eu1running: Bool = false
    @Published var eu2progress: Double = 0.0
    @Published var eu2running: Bool = false
    @Published var rcLastError: String?
    #endif

    @Published var rcready: Bool = false
    @Published var rcfailed: Bool = false
    @Published var showrespring: Bool = false

    // Single-line progress shown in the UI. Everything else goes to EUEnabler.log.
    @Published var stepText: String = "Ready"
    @Published var stepProgress: Double = 0.0

    // Broad success/error lines shown under the progress bar. The full engine log
    // still goes to EUEnabler.log on disk.
    @Published var milestones: [Milestone] = []

    var sbProc: RemoteCall?

    static let shared = EUEnablerManager()

    private let euPokeQueue = DispatchQueue(label: "EUEnabler.poke")

    init() {}

    func setStatus(_ text: String, _ progress: Double) {
        DispatchQueue.main.async {
            self.stepText = text
            self.stepProgress = min(max(progress, 0), 1)
        }
    }

    func milestone(_ text: String, isError: Bool = false) {
        DispatchQueue.main.async {
            self.milestones.append(Milestone(text: text, isError: isError))
            if self.milestones.count > 60 {
                self.milestones.removeFirst(self.milestones.count - 60)
            }
        }
    }

    func run(completion: ((Bool) -> Void)? = nil) {
        guard !dsrunning else { return }
        dsrunning = true
        milestone("Exploit started")
        dsready = false
        dsfailed = false
        dsattempted = true
        dsprogress = 0.0
        log = ""

        ds_set_log_callback { messageCStr in
            guard let messageCStr else { return }
            let message = String(cString: messageCStr)
            DispatchQueue.main.async {
                EUEnablerManager.shared.logmsg("(ds) \(message)")
            }
        }
        ds_set_progress_callback { progress in
            DispatchQueue.main.async {
                EUEnablerManager.shared.dsprogress = progress
                EUEnablerManager.shared.stepText = "Running exploit… \(Int(progress * 100))%"
                EUEnablerManager.shared.stepProgress = min(max(0.30 * progress, 0), 1)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ds_run()

            DispatchQueue.main.async {
                guard let self else { return }
                self.dsrunning = false
                let success = result == 0 && ds_is_ready()
                if success {
                    self.dsready = true
                    self.dsfailed = false
                    self.stepText = "Exploit succeeded"
                    self.stepProgress = 0.30
                    self.milestone("Exploit succeeded")
                    self.kernbase = ds_get_kernel_base()
                    self.kernslide = ds_get_kernel_slide()
                    self.logmsg("\n(ds) exploit success!")
                    self.logmsg(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    self.logmsg(String(format: "(ds) kernel_slide: 0x%llx\n", self.kernslide))
                    globallogger.log("(ds) exploit success!")
                    globallogger.log(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    globallogger.log(String(format: "(ds) kernel_slide: 0x%llx", self.kernslide))
                    globallogger.divider()
                } else {
                    self.dsfailed = true
                    self.stepText = "Exploit failed"
                    self.stepProgress = 0.0
                    self.milestone("Exploit failed", isError: true)
                    self.logmsg("\nexploit failed.\n")
                    globallogger.log("exploit failed.")
                    globallogger.divider()
                }
                self.dsprogress = 1.0
                completion?(success)
            }
        }
    }

    func logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.log += message + "\n"
            globallogger.log(message)
        }
    }

    func respring() {
        showrespring = true
    }

    #if !DISABLE_REMOTECALL
    func rcinit(process: String, migbypass: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard dsready, !rcready else {
            completion?(false)
            return
        }

        rcrunning = true
        rcLastError = nil
        rcfailed = false
        logmsg("initializing remote call on \(process)...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.sbProc = RemoteCall(process: process, useMigFilterBypass: migbypass)

            DispatchQueue.main.async {
                guard let self = self else { return }
                let success = self.sbProc != nil
                if success {
                    self.logmsg("remote call initialized on \(process)")
                    self.rcLastError = nil
                    self.rcfailed = false
                    self.rcrunning = false
                    self.rcready = true
                } else {
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    self.rcfailed = true
                    if let error, !error.isEmpty {
                        self.logmsg("remote call init failed on \(process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(process)")
                    }
                    self.rcrunning = false
                }
                completion?(success)
            }
        }
    }

    func rcinitDaemon(serviceName: String, framework: String? = nil, process: String, migbypass: Bool = false, forceWake: Bool = false, keepAwake: Bool = false, timeoutMs: Int = 120000, scanAllThreads: Bool = false, completion: ((RemoteCall?) -> Void)? = nil) {
        guard dsready, let sbProc else {
            completion?(nil)
            return
        }

        rcrunning = true
        logmsg("initializing remote call on \(process)...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Ask launchd what this daemon's Mach services are actually called,
            // instead of trusting the hard-coded name.
            let label = "com.apple." + process
            let discovered = machServiceNames(forLaunchdLabel: label)
            let serviceNames: [String]
            if discovered.isEmpty {
                serviceNames = [serviceName]
                self?.logmsg("(rc) \(process): \(label).plist unreadable; using \(serviceName)")
            } else {
                serviceNames = discovered
                self?.logmsg("(rc) \(process): \(label) MachServices = \(discovered.joined(separator: ", "))")
                if !discovered.contains(serviceName) {
                    self?.milestone("\(process): service is \(discovered.joined(separator: ", "))")
                }
            }

            // These are on-demand daemons. proc_find_by_name can fail simply because
            // launchd hasn't started them yet, so wake them and wait for the process
            // to actually appear before attaching.
            if forceWake || process.withCString({ proc_find_by_name($0) == 0 }) {
                for name in serviceNames {
                    wake_up_daemon(sbProc, name, framework)
                }
                var waited = 0.0
                while process.withCString({ proc_find_by_name($0) == 0 }) && waited < 12.0 {
                    usleep(2_000_000)
                    waited += 2.0
                    // Re-wake while we wait: launchd may need a moment, and an
                    // on-demand daemon can be slow to come up the first time.
                    if process.withCString({ proc_find_by_name($0) == 0 }) {
                        for name in serviceNames {
                            wake_up_daemon(sbProc, name, framework)
                        }
                    }
                }
                if process.withCString({ proc_find_by_name($0) == 0 }) {
                    self?.logmsg("(rc) \(process) did not start after wake")
                    self?.milestone("\(process): did not start", isError: true)
                } else {
                    self?.logmsg("(rc) \(process) started after \(String(format: "%.1f", waited))s")
                    self?.milestone("\(process): started")
                }
            }

            // The injected guard exception only fires when the target thread next
            // runs. A purely on-demand daemon (e.g. managedappdistributiond) parks
            // its main thread, so waking it *before* we attach is useless: it
            // services the wake, goes back to sleep, and the guard is then placed
            // on a parked thread. Keep prodding it while we attach so a wake lands
            // after the guard is installed.
            var pokeTimer: DispatchSourceTimer?
            if keepAwake, let pokeQueue = self?.euPokeQueue {
                let timer = DispatchSource.makeTimerSource(queue: pokeQueue)
                timer.schedule(deadline: .now() + 0.75, repeating: 2.0)
                timer.setEventHandler {
                    wake_up_daemon(sbProc, serviceName, framework)
                }
                timer.resume()
                pokeTimer = timer
            }

            let proc = RemoteCall(process: process, useMigFilterBypass: migbypass, firstExceptionTimeoutMs: Int32(timeoutMs), scanAllThreads: scanAllThreads)
            pokeTimer?.cancel()
            pokeTimer = nil
            completion?(proc)

            DispatchQueue.main.async {
                guard let self = self else { return }
                let success = proc != nil
                if success {
                    self.logmsg("remote call initialized on \(process)")
                    self.rcrunning = false
                } else {
                    let error = RemoteCall.lastInitError()
                    if let error, !error.isEmpty {
                        self.logmsg("remote call init failed on \(process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(process)")
                    }
                    self.rcrunning = false
                }
            }
        }
    }

    func rcdestroy(completion: (() -> Void)? = nil) {
        guard rcready else { return }

        logmsg("destroying remote call session...")
        rcready = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.sbProc?.destroy()

            DispatchQueue.main.async {
                self?.logmsg("remote call session destroyed")
                completion?()
            }
        }
    }

    func stashKRWToLaunchd(completion: ((Bool) -> Void)? = nil) {
        guard dsready, !rcrunning else {
            completion?(false)
            return
        }

        rcrunning = true
        rcLastError = nil
        logmsg("(persist) manually transferring KRW primitives to launchd...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = transfer_krw_to_launchd()

            DispatchQueue.main.async {
                guard let self else { return }
                self.rcrunning = false
                if success {
                    self.rcLastError = nil
                    self.logmsg("(persist) manual KRW transfer to launchd succeeded")
                } else {
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    if let error, !error.isEmpty {
                        self.logmsg("(persist) manual KRW transfer to launchd failed: \(error)")
                    } else {
                        self.logmsg("(persist) manual KRW transfer to launchd failed")
                    }
                }
                completion?(success)
            }
        }
    }

    //  params:
    //  - name: function to call
    //  - args: up to 8 args in registers (x0-x7) and extra args passed to stack pointer
    //  - timeout: timeout in ms
    //  ret: return value from rc
    func rccall(name: String, args: [UInt64] = [], timeout: Int32 = 100) -> UInt64 {
        guard rcready else { return 0 }
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        let ptr = dlsym(RTLD_DEFAULT, name)
        var argsCopy = args
        return name.withCString { (cName: UnsafePointer<CChar>) -> UInt64 in
            UInt64(argsCopy.withUnsafeMutableBufferPointer { buffer in
                sbProc?.doStable(
                    withTimeout: timeout,
                    functionName: UnsafeMutablePointer(mutating: cName),
                    functionPointer: ptr,
                    args: buffer.baseAddress,
                    argCount: UInt(args.count)
                ) ?? 0
            })
        }
    }
    #endif
}
