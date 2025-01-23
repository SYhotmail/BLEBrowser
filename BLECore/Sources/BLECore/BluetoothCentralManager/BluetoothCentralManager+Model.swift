//
//  BluetoothCentralManager+Model.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import CoreBluetooth
import Combine

// MARK: - OptionsDictionaryConvertable
protocol OptionsDictionaryConvertable {
    static func optionsDictionary(_ options: [Self]) -> [String: Any]
}

@available(macOS 10.15, *) //Kind of a namespace, easier with nested enums
public extension BluetoothCentralManager {
    enum InitOptions: Sendable, OptionsDictionaryConvertable { //TODO: ExpressibleByBooleanLiteral, ExpressibleByStringLiteral
        case showPowerAlert(_ value: Bool)
        case restoreIdentifier(uuid: UUID)
        
        var uuid: UUID? {
            if case .restoreIdentifier(let uuid) = self {
                return uuid
            }
            return nil
        }
        
        var showPowerAlert: Bool? {
            if case .showPowerAlert(let value) = self {
                return value
            }
            return nil
        }
        
        static func optionsDictionary(_ options: [Self]) -> [String: Any] {
            var result = [String: Any]()
            if let showPowerAlert = options.lazy.compactMap({ $0.showPowerAlert }).first {
                result[CBCentralManagerOptionShowPowerAlertKey] = showPowerAlert
            }
            
            if let uuid = options.lazy.compactMap({ $0.uuid }).first {
                result[CBCentralManagerOptionRestoreIdentifierKey] = uuid
            }
            return result
        }
    }
    
    enum ScanOptions: Sendable, OptionsDictionaryConvertable, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
        public typealias ArrayLiteralElement = UUID
        
        case allowDuplicateKey(_ value: Bool)
        case solicitedService(uuids: [UUID])
        
        public init(booleanLiteral value: Bool) {
            self = .allowDuplicateKey(value)
        }
        
        public init(arrayLiteral elements: UUID...) {
            self = .solicitedService(uuids: elements.map { $0 })
        }
        
        var uuids: [UUID]? {
            if case .solicitedService(let uuids) = self {
                return uuids
            }
            return nil
        }
        
        var allowDuplicateKey: Bool? {
            if case .allowDuplicateKey(let value) = self {
                return value
            }
            return nil
        }
        
        static func optionsDictionary(_ options: [Self]) -> [String : Any] {
            var result = [String: Any]()
            if let allowDuplicateKey = options.lazy.compactMap({ $0.allowDuplicateKey }).first {
                result[CBCentralManagerScanOptionAllowDuplicatesKey] = allowDuplicateKey
            }
            
            if let uuids = options.lazy.compactMap({ $0.uuids }).first {
                result[CBCentralManagerScanOptionSolicitedServiceUUIDsKey] = uuids.map { CBUUID(nsuuid: $0) }
            }
            return result
        }
    }
}
