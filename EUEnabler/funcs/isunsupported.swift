//
//  isunsupported.swift
//  EU Enabler
//
//  Created by ruter on 30.03.26.
//

import UIKit
import Darwin

func devicemachine() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)

    let mirror = Mirror(reflecting: sysinfo.machine)
    return mirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func hasmie() -> Bool {
    let machine = devicemachine()
    
    if machine.contains("iPhone18,") {
        return true
    }
    
    return false
}

func isunsupported() -> Bool {
    // Version gate lives in offsets.m so the UI and the offsets module can't
    // disagree about what is supported (16.0 - 26.0.1).
    if !euenabler_version_supported() {
        return true
    }

    if hasmie() {
        return true
    }
    
    if isdebugged() {
        return true
    }
    
    return false
}
