//
//  EUEnablerApp.swift
//  EU Enabler
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

let g_isunsupported: Bool = isunsupported()
var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct EUEnabler: App {
    @StateObject private var mgr = EUEnablerManager.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("keepAlive") private var keepalive: Bool = false

    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif

        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)

        if keepalive {
            toggleka()
        }

        globallogger.capture()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mgr)
                .overlay {
                    if mgr.showrespring {
                        respringview()
                            .brightness(-1.0)
                            .ignoresSafeArea()
                    }
                }
                .onAppear {
                    if !isunsupported() {
                        init_offsets()
                        offsets_init()
                        mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
                    } else {
                        Alertinator.shared.alert(title: "This device is not supported!", body: "We apologize, but this device is currently not supported. Possible reasons: \n- You are on an unsupported iOS version (Supported: iOS 16.0 - iOS 18.7.1, iOS 26.0 - iOS 26.0.1) \n- Your device has MIE (A19+ or M5+) \n- A debugger is attached.", actionLabel: "Exit App", action: { exitinator() })
                    }
                }
                .onChange(of: scenephase, perform: handleScenePhase)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            handlebg()
            globallogger.stopcapture()

        case .active:
            globallogger.capture()

        @unknown default:
            break
        }
    }

    // Leaving the SpringBoard RemoteCall session alive when the app is backgrounded
    // or killed makes SpringBoard respring. Tear it down first.
    private func handlebg() {
        guard mgr.rcready else { return }
        let keepSpringBoardRemoteCallAlive = UserDefaults.standard.bool(forKey: "keepSpringBoardRemoteCallAliveIOS16")
        if isIOS16() && keepSpringBoardRemoteCallAlive {
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RemoteCallCleanup") {
            endbgtask(&bgTask)
        }

        mgr.rcdestroy {
            self.endbgtask(&bgTask)
        }
    }

    private func endbgtask(_ task: inout UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

// file picker fixes
extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

// make strings compatiable with errors
extension String: @retroactive Error {}
