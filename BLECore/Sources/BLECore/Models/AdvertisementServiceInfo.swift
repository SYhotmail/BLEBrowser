//
//  File.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 22/01/2025.
//

import Foundation
import CoreBluetooth

public struct PeripheralAdvertisementInfo: UUIDIdentifiableSendableType, Hashable {
    public let id: UUID
    public let info: AdvertisementServiceInfo
}

public struct PeripheralCharacteristicsInfo: UUIDIdentifiableSendableType, Hashable {
    public let id: UUID
    public var characteristicsInfo: [CharacteristicInfo]
    
    public struct CharacteristicInfo: Sendable, Identifiable {
        public let id: String
        public var usageDescription: DescriptorInfo<String>?
        
        public struct DescriptorInfo<Value: Sendable>: Sendable, Identifiable {
            public let id: String
            public let value: Value?
            
            init(id: String, value: Value?) {
                self.id = id
                self.value = value
            }
            
            init(descriptor: CBDescriptor) {
                let id = descriptor.uuid.uuidString
                self.init(id: id,
                          value: descriptor.value as? Value)
            }
        }
        
        init(id: String, usageDescription: DescriptorInfo<String>?) {
            self.id = id
            self.usageDescription = usageDescription
        }
        
        init(chacteristic: CBCharacteristic) {
            let id = chacteristic.uuid.uuidString
            self.init(id: id,
                      usageDescription: chacteristic.descriptors?.first(where: { $0.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString }).flatMap { $0.value as? String }.map { .init(id: CBUUIDCharacteristicUserDescriptionString,
                                                                                                                                                                                        value: $0)  })
        }
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
        let manufacturerDataStr = manufacturerData?.hexEncodedBLEString()
        self.manufacturerData = manufacturerDataStr
#if DEBUG
        if manufacturerDataStr != nil, let manufacturerData {
            debugPrint("!!! hex str \(manufacturerDataStr) \(String(data: manufacturerData, encoding: .utf8))")
        }
#endif
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
            assert(!self[keyPath: keyPath].isEmpty || advertisementData[key] == nil)
        }
    }
}
