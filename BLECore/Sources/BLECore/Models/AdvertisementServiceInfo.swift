//
//  File.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import Foundation
import CoreBluetooth

public struct PeripheralAdvertisementInfo: Sendable, Hashable {
    public let id: UUID
    public let info: AdvertisementServiceInfo
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public struct AdvertisementServiceInfo: Sendable, Equatable {
    public let rssi: Float?
    public let localName: String?
    public let manufacturerData: String?
    public private(set)var serviceUUIDs = [String]()
    public private(set)var overflowUUIDs = [String]()
    public private(set)var solicitedUUIDs = [String]()
    public let transmitPower: Float?
    public let serviceDataDic: [String: Data]
    public let isConnectable: Bool
    
    init(data advertisementData: [String: Any], rssi: Float?) {
        self.rssi = rssi
        
        //debugPrint("!!! \(#function) data \(advertisementData)")
        self.localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        self.manufacturerData = manufacturerData?.hexEncodedBLEString()
        
        if let dic = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID : Data], !dic.isEmpty {
            var serviceDataDic = [String: Data]()
            dic.forEach { tuple in
                let uuid = tuple.key.uuidString
                serviceDataDic[uuid] = tuple.value
            }
            self.serviceDataDic = serviceDataDic
        } else {
            serviceDataDic = [:]
        }
        
        assert(!serviceDataDic.isEmpty || advertisementData[CBAdvertisementDataServiceDataKey] == nil)
        
        self.transmitPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.floatValue
        self.isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue == true
        
        let keyPaths: [WritableKeyPath<Self, [String]>] = [\.serviceUUIDs, \.overflowUUIDs, \.solicitedUUIDs]
        let keys: [String] = [CBAdvertisementDataServiceUUIDsKey, CBAdvertisementDataOverflowServiceUUIDsKey, CBAdvertisementDataSolicitedServiceUUIDsKey]
        
        zip(keyPaths, keys).forEach { tuple in
            let keyPath = tuple.0
            let key = tuple.1
            self[keyPath: keyPath] = (advertisementData[key] as? [CBUUID] ?? []).map { $0.uuidString }
            if !self[keyPath: keyPath].isEmpty {
                debugPrint("Is not empy \(self[keyPath: keyPath])")
            }
            assert(!self[keyPath: keyPath].isEmpty || advertisementData[key] == nil)
        }
    }
}
