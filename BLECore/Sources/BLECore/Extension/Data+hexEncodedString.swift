//
//  File.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import Foundation

extension Data {
    func hexEncodedBLEString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
