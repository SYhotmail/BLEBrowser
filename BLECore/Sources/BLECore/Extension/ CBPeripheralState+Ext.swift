//
//  File.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import CoreBluetooth

extension CBPeripheralState {
    var asMinimumConnecting: Bool {
        self == .connecting || self == .connected
    }
}
