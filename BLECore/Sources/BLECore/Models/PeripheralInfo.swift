//
//  PeripheralInfo.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import Foundation
import CoreBluetooth

public protocol UUIDIdentifiableSendableType: Sendable, Identifiable {
    var id: UUID { get }
}

extension UUIDIdentifiableSendableType where Self: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public struct FailedPeripheralInfo: UUIDIdentifiableSendableType {
    public var id: UUID { peripheralInfo.id }
    public let peripheralInfo: PeripheralInfo
    public let error: (any Error)?
}

public struct PeripheralInfo: UUIDIdentifiableSendableType {
    public let id: UUID
    public let name: String?
    
    public init(peripheral: CBPeripheral) {
        self.init(id: peripheral.identifier,
                  name: peripheral.name)
    }
    
    public init(id: UUID,
                name: String?) {
        self.id = id
        self.name = name
    }
}
