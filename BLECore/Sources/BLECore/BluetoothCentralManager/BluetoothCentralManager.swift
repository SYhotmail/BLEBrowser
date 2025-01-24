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
    public let failedToConnectPublisher = PassthroughSubject<FailedPeripheralInfo, Never>()
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
    
    @discardableResult
    public func disconnectPeripheral(uuid: UUID) -> Bool {
        let extraInfo = connectedPeripherals.withLock {
            $0.removeValue(forKey: uuid)
        }
        
        var peripherals = [CBPeripheral]()
        if let extraInfo {
            peripherals = centralManager.retrieveConnectedPeripherals(withServices: [.init(nsuuid: extraInfo.id)])
        }
        
        let info = advertisingPeripherals.withLock {
            $0.removeValue(forKey: uuid)
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
        
        return !peripherals.isEmpty
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
            centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnConnectionKey: true]) //TODO: make enum for connection options...
            return true
        } else if peripheral.state == .connected {
            didConnectCore(central: centralManager, peripheral: peripheral)
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
    
    private func didConnectCore(central: CBCentralManager, peripheral: CBPeripheral) {
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
        
        discoverServices(peripheral: peripheral, ids: nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        didConnectCore(central: central, peripheral: peripheral)
    }
    
    private func discoverServices(peripheral: CBPeripheral, ids: [String]? = nil, force: Bool = false) {
        guard force || peripheral.services == nil else {
            if peripheral.services != nil {
                didDiscoverServicesCore(peripheral: peripheral)
            }
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
        
        
        if let error  {
            debugPrint("!!! Error \(error) \(#function)")
        }
        
        _ = connectedPeripherals.withLock({
            $0.removeValue(forKey: id)
        })
        
        failedToConnectPublisher.send(.init(peripheralInfo: .init(peripheral: peripheral), error: error))
    }
    
    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        discoverServices(peripheral: peripheral, ids: invalidatedServices.map { $0.uuid.uuidString }, force: true) //move it out to public API
    }
    
    private func didDiscoverServicesCore(peripheral: CBPeripheral) {
        if let services = peripheral.services, !services.isEmpty { //TODO: access constants...
            debugPrint("!!! \(#function) services \(services)")
            debugPrint("!!! \(#function) services.uuidString \(services.map { $0.uuid.uuidString })")
            //debugPrint("!!! \(#function) services.data \(services.compactMap { $0.uuid.data.encodeToString() })")
            services.forEach { service in
                if service.includedServices == nil {
                    peripheral.delegate = self
                    peripheral.discoverIncludedServices(nil, for: service)
                }
                if service.characteristics == nil {
                    peripheral.delegate = self
                    peripheral.discoverCharacteristics(nil, for: service)
                } else {
                    didDiscoverCharacteristicsCore(peripheral: peripheral, service: service)
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        
        didDiscoverServicesCore(peripheral: peripheral)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        debugPrint("!!! \(#function) included services \(service.includedServices ?? [])")
    }
    
    private func didDiscoverCharacteristicsCore(peripheral: CBPeripheral, service: CBService) {
        let id = peripheral.identifier
        
        let characteristics = service.characteristics
        
        let characteristicsInfo = characteristics?.map { PeripheralCharacteristicsInfo.CharacteristicInfo(chacteristic: $0) } ?? []
        
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
            } else {
                readValue(characteristic: characteristic)
            }
        }
        
        peripheralCharacteristicsPublisher.send(info)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        
        didDiscoverCharacteristicsCore(peripheral: peripheral, service: service)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        
        if Self.accessDescriptors(peripheral: peripheral,
                                  characteristic: characteristic) {
        }
    }
    
    private func readValue(characteristic: CBCharacteristic) {
        guard let value = characteristic.value else  {
            return
        }
            
        debugPrint("!!! \(characteristic) value \(value)")
        if characteristic.service?.uuid.uuidString == BLECoreCBServiceDeviceInfoCBUUIDString, let textValue = value.encodeToString() { //device information...
            switch characteristic.uuid.uuidString {
            case BLECoreCharacteristicManufactureNameString :
                debugPrint("Manufacturer Name: \(textValue)")
            case BLECoreCharacteristicModelNameString:
                debugPrint("Model Number: \(textValue)")
            default:
                debugPrint("Characteristic \(characteristic.uuid) value: \(textValue)")
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        
        if let error {
            if let cbError = error as? CBATTError, cbError.code == .insufficientAuthentication {
                debugPrint("Authentication is insufficient. Initiating pairing process. id: \(peripheral.identifier)")
                // Pairing may automatically be triggered here depending on the peripheral.
                if characteristic.properties.contains(.read) {
                    //TODO: try just once in a hope that pairing will run...
                    //peripheral.readValue(for: characteristic)
                }
            } else {
                debugPrint("Error reading characteristic: \(error.localizedDescription)")
            }
        }
        
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        
        readValue(characteristic: characteristic)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        if let error {
            debugPrint("!!! Error \(error) \(#function)")
            return
        }
        
        guard let userDescription = Self.userDescriptionValue(descriptor: descriptor), !userDescription.isEmpty else {
            debugPrint("!!! \(#function) \(descriptor)")
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
            if let value = userDescriptionValue(descriptor: descriptor) {
                if !value.isEmpty {
                    debugPrint("User Description: \(value)")
                    return
                }
            }
            
            if characteristic.properties.contains(.read), descriptor.value == nil {
                peripheral.readValue(for: descriptor)
            }
            
            debugPrint("!!! didDiscoverDescriptorsFor \(descriptor.debugDescription)")
        }
        return true
    }
    
    private static func descriptorValue<ValueType>(_ type: ValueType.Type = ValueType.self,
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
    
    private static func userDescriptionValue(descriptor: CBDescriptor) -> String? {
        var idMatch = false
        return Self.descriptorValue(String.self,
                                        descriptor: descriptor,
                                        uuidString: CBUUIDCharacteristicUserDescriptionString, //FIXME: place into one entity..
                                        idMatch: &idMatch) ?? (idMatch ? "" : nil)
    }
}
