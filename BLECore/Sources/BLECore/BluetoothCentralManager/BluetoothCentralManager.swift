//
//  File.swift
//  BLECore
//
//  Created by Siarhei Yakushevich on 20/01/2025.
//

import CoreBluetooth
import Combine
import Synchronization

public class BluetoothCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let centralManager: CBCentralManager
    let queue = DispatchQueue(label: "blecore.scanner.queue", qos: .userInitiated)
    public private(set)var managerState: CurrentValueSubject<CBManagerState, Never>
    public private(set)var authorizationState: CurrentValueSubject<CBManagerAuthorization, Never>
    public let advertisePublisher = PassthroughSubject<PeripheralAdvertisementInfo, Never>()
    public let connectedPublisher = PassthroughSubject<PeripheralInfo, Never>()
    public let peripheralCharacteristicsPublisher = PassthroughSubject<PeripheralCharacteristicsInfo, Never>() //TODO: start using..
    
    public var isScanning: Bool { Self.isScanning(central: centralManager) }
    
    private let advertisingPeripherals = Mutex<[UUID : AdvertisementServiceInfo]>([:])
    private var connectingPeripheralsMap = [UUID: CBPeripheral]()
    private let connectingPeripheralsMapLock = NSRecursiveLock()
    private let connectedPeripherals = Mutex<[UUID: PeripheralCharacteristicsInfo]>([ : ])
        
    
    public func advertisingPeripheralsMap() -> [UUID : AdvertisementServiceInfo] {
        advertisingPeripherals.withLock { $0 }
    }
    
    public convenience init(_ options: InitOptions...) {
        self.init(options: options.map { $0 })
    }
    
    public init(options: [InitOptions] = []) {
                
        let centralManager = CBCentralManager(delegate: nil,
                                              queue: queue,
                                              options: InitOptions.optionsDictionary(options))
        self.centralManager = centralManager
        managerState = .init(centralManager.state)
        authorizationState = .init(type(of: centralManager).authorization)
        super.init()
        configure()
    }
    
    private func configure() {
        centralManager.delegate = self
    }
    
    private func changeScan(flag: Bool, block: () -> Void) -> Bool {
        guard isScanning == flag else {
            return false
        }
        
        block()
        return isScanning != flag
    }
    
    @discardableResult
    public func scanForPeripherals(services: [CBUUID]? = nil, options: [String: Any]? = nil) -> Bool {
        changeScan(flag: false) {
            centralManager.scanForPeripherals(withServices: services, options: options)
        }
    }
    
    
    @discardableResult
    public func scanForPeripherals(services: [CBUUID]? = nil, options: ScanOptions...) -> Bool {
        scanForPeripherals(services: services, options: ScanOptions.optionsDictionary(options))
    }
    
    @discardableResult
    public func stopScanning() -> Bool {
        changeScan(flag: true) {
            centralManager.stopScan()
        }
    }
    
    public func disconnectPeripheral(uuid: UUID) {
        let info = advertisingPeripherals.withLock {
            $0.removeValue(forKey: uuid)
        }
        
        let extraInfo = connectedPeripherals.withLock {
            $0.removeValue(forKey: uuid)
        }
        
        var peripherals = [CBPeripheral]()
        if let extraInfo {
            peripherals = centralManager.retrieveConnectedPeripherals(withServices: [.init(nsuuid: extraInfo.id)])
        }
        
        if peripherals.isEmpty, info != nil {
            peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        }
        
        peripherals.forEach { peripheral in
            if peripheral.delegate === self {
                peripheral.delegate = nil
            }
            
            if peripheral.state.asMinimumConnecting {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            
            connectingPeripheralsMapLock.withLock {
                _ = self.connectingPeripheralsMap.removeValue(forKey: uuid)
            }
        }
    }
    
    private static func isScanning(central: CBCentralManager) -> Bool {
        central.isScanning
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard Self.isScanning(central: central) else {
            return
        }
        let info = AdvertisementServiceInfo(data: advertisementData,
                                            rssi: RSSI.intValue == 127 ? nil : RSSI.floatValue)
        
        debugPrint("!!! Info \(info)")
        let id = peripheral.identifier
        advertisingPeripherals.withLock { [info] in
            $0[id] = info
        }
        //advertisingPeripherals[peripheral] = info
        advertisePublisher.send(.init(id: id, info: info))
    }
    
    @discardableResult
    public func connectToPeripheral(uuid: UUID) -> Bool {
        var peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(nsuuid: uuid)]).first
        if peripheral == nil {
            peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
        }
        
        if peripheral == nil {
            peripheral = connectingPeripheralsMapLock.withLock {
                self.connectingPeripheralsMap[uuid]
            }
        }
        
        guard let peripheral else {
            return false
        }
        
        connectingPeripheralsMapLock.withLock {
            self.connectingPeripheralsMap[uuid] = peripheral
        }
        
        if !peripheral.state.asMinimumConnecting {
            centralManager.connect(peripheral, options: nil) //TODO: make enum for connection options...
            return true
        }
        return false
    }
    
    //TODO: add disconnect to Peripheral...
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        switch state {
        case .poweredOn:
            debugPrint("Bluetooth is powered on and ready.")
        case .poweredOff:
            debugPrint("Bluetooth is turned off.")
        case .unauthorized:
            debugPrint("Bluetooth usage is unauthorized.")
        case .unsupported:
            debugPrint("Bluetooth is not supported on this device.")
        case .unknown:
            debugPrint("Bluetooth state is unknown.")
        case .resetting:
            debugPrint("Bluetooth state is resetting")
        @unknown default:
            debugPrint("A new Bluetooth state was detected.")
        }
        managerState.value = state
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        //assert(advertisingPeripherals[peripheral]?.isConnectable == true)
        let id = peripheral.identifier
        guard connectedPeripherals.withLock({
            let result = $0[id] == nil
            $0[id] = .init(id: id,
                           characteristicsInfo: [])
            return result
        }) else {
            return
        }
        connectedPublisher.send(.init(peripheral: peripheral))
        
        discoverServices(peripheral: peripheral, ids: nil) //move it out to public API
    }
    
    private func discoverServices(peripheral: CBPeripheral, ids: [String]? = nil, force: Bool = false) {
        guard force || peripheral.services == nil else {
            return
        }
        
        peripheral.delegate = self //move it out to public API
        peripheral.discoverServices(ids.flatMap { ids in ids.compactMap { CBUUID(string: $0) } } )
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        defer {
            connectingPeripheralsMapLock.withLock {
                _ = self.connectingPeripheralsMap.removeValue(forKey: id)
            }
        }
        
        guard let error else {
            return
        }
        
        debugPrint("!!! \(#function) error \(error)")
        _ = connectedPeripherals.withLock({
            $0.removeValue(forKey: id)
        })
    }
    
    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        discoverServices(peripheral: peripheral, ids: invalidatedServices.map { $0.uuid.uuidString }, force: true) //move it out to public API
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        
        if let services = peripheral.services, !services.isEmpty { //TODO: access constants...
            debugPrint("!!! \(#function) services \(services)")
            services.forEach { service in
                if service.includedServices == nil {
                    peripheral.delegate = self
                    peripheral.discoverIncludedServices(nil, for: service)
                }
                if service.characteristics == nil {
                    peripheral.delegate = self
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        debugPrint("!!! \(#function) included services \(service.includedServices ?? [])")
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        
        let id = peripheral.identifier
        
        let characteristics = service.characteristics
        
        let characteristicsInfo = characteristics?.compactMap { PeripheralCharacteristicsInfo.CharacteristicInfo(chacteristic: $0) } ?? []
        
        guard let info: PeripheralCharacteristicsInfo = connectedPeripherals.withLock({ dic in
            if var value = dic[id] {
                value.characteristicsInfo = characteristicsInfo
                dic[id] = value
                return value
            }
            return nil
        }) else {
            return
        }
        
        characteristics?.forEach { characteristic in
            
            if !Self.accessDescriptors(peripheral: peripheral,
                                      characteristic: characteristic) {
                assert(characteristic.descriptors == nil)
                peripheral.discoverDescriptors(for: characteristic)
            }
            
            if characteristic.value == nil, characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
        
        peripheralCharacteristicsPublisher.send(info)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        
        if Self.accessDescriptors(peripheral: peripheral,
                                  characteristic: characteristic) {
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        if let value = characteristic.value {
            debugPrint("!!! \(characteristic) value \(value)")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        guard let userDescription = Self.characteristicUserDescription(descriptor: descriptor), !userDescription.isEmpty else {
            return
        }
            
        
        let id = peripheral.identifier
        
        guard let info: PeripheralCharacteristicsInfo = connectedPeripherals.withLock({ dic in
            if var infoKey = dic[id] {
                if let index = infoKey.characteristicsInfo.firstIndex(where: { $0.id == descriptor.uuid.uuidString }) {
                    infoKey.characteristicsInfo[index].usageDescription = .init(descriptor: descriptor)
                }
                dic[id] = infoKey
                return infoKey
            }
            return nil
        }) else {
            return
        }
        
        peripheralCharacteristicsPublisher.send(info)
            
    }
    
    // MARK: - Utils
    
    @discardableResult
    private static func accessDescriptors(peripheral: CBPeripheral, characteristic: CBCharacteristic) -> Bool {
        guard let descriptors = characteristic.descriptors else {
            return false
        }
        
        descriptors.forEach { descriptor in
            if let value = characteristicUserDescription(descriptor: descriptor) {
                if !value.isEmpty {
                    debugPrint("User Description: \(value)")
                } else if characteristic.properties.contains(.read), descriptor.value == nil {
                    peripheral.readValue(for: descriptor)
                }
            }
            debugPrint("!!! didDiscoverDescriptorsFor \(descriptor.debugDescription)")
        }
        return true
    }
    
    private static func characteristicValue<ValueType>(_ type: ValueType.Type = ValueType.self,
                                                       descriptor: CBDescriptor,
                                                       uuidString: String, idMatch: inout Bool) -> ValueType? {
        let sameIds = descriptor.uuid.uuidString == uuidString
        idMatch = sameIds
        guard sameIds else {
            return nil
        }
        
        let resValue = descriptor.value as? ValueType
        assert(resValue != nil || descriptor.value == nil)
        return resValue
    }
    
    private static func characteristicUserDescription(descriptor: CBDescriptor) -> String? {
        var idMatch = false
        return Self.characteristicValue(String.self,
                                        descriptor: descriptor,
                                        uuidString: CBUUIDCharacteristicUserDescriptionString, //FIXME: place into one entity..
                                        idMatch: &idMatch) ?? (idMatch ? "" : nil)
    }
}
