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
    let queue = DispatchQueue(label: "blecore.scanner.queue", qos: .default)
    public private(set)var managerState: CurrentValueSubject<CBManagerState, Never>
    public private(set)var authorizationState: CurrentValueSubject<CBManagerAuthorization, Never>
    public let advertisePublisher = PassthroughSubject<PeripheralAdvertisementInfo, Never>()
    public var isScanning: Bool { Self.isScanning(central: centralManager) }
    
    private let advertisingPeripherals = Mutex<[UUID : AdvertisementServiceInfo]>([:])
    private var connectingPeripheralsMap = [UUID: CBPeripheral]()
    private let connectedPeripherals = Mutex<Set<UUID>>(.init())
        
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
    
    
    private func removeAllPeripherals()  {
        connectingPeripheralsMap.removeAll()
    }
    
    func disconnectAllPeripherals() {
        queue.sync(flags: .barrier) { [weak self] in
            self?.disconnectAllPeripheralsCore()
        }
    }
    
    private func disconnectAllPeripheralsCore() {
        let identifiers = advertisingPeripherals.withLock {
            let keys = $0.keys
            $0.removeAll()
            return keys
        }.map { $0 }
        
        var extraIdentifiers = connectedPeripherals.withLock { set in
            let oldSet = set
            set.removeAll()
            return oldSet
        }
        extraIdentifiers.formUnion(identifiers)
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: extraIdentifiers.map { $0 })
        peripherals.forEach { peripheral in
            if peripheral.delegate === self {
                peripheral.delegate = nil
            }
            
            if peripheral.state.asMinimumConnecting {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
        
        removeAllPeripherals()
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
            peripheral = queue.sync { [weak self] in self?.connectingPeripheralsMap[uuid] }
        }
        
        guard let peripheral else {
            return false
        }
        
        connectingPeripheralsMap[uuid] = peripheral
        if !peripheral.state.asMinimumConnecting {
            centralManager.connect(peripheral, options: nil) //TODO: connection options...
            //central.retrieveConnectedPeripherals(withServices: <#T##[CBUUID]#>)
            return true
        }
        return false
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        switch state {
        case .poweredOn:
            print("Bluetooth is powered on and ready.")
        case .poweredOff:
            print("Bluetooth is turned off.")
        case .unauthorized:
            print("Bluetooth usage is unauthorized.")
        case .unsupported:
            print("Bluetooth is not supported on this device.")
        case .unknown:
            print("Bluetooth state is unknown.")
        case .resetting:
            print("Bluetooth state is resetting")
        @unknown default:
            print("A new Bluetooth state was detected.")
        }
        managerState.value = state
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        //assert(advertisingPeripherals[peripheral]?.isConnectable == true)
        let id = peripheral.identifier
        guard connectedPeripherals.withLock({
            let result = $0.insert(id).inserted
            return result
        }) else {
            return
        }
        connectingPeripheralsMap.removeValue(forKey: id)
        if peripheral.services == nil {
            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        //let uuid = peripheral.identifier
        //assert(advertisingPeripherals.withLock { $0[uu} [peripheral]?.isConnectable == false)
        let id = peripheral.identifier
        defer {
            connectingPeripheralsMap.removeValue(forKey: id)
        }
        
        guard let error else {
            return
        }
        
        debugPrint("!!! \(#function) error \(error)")
        _ = connectedPeripherals.withLock({
            $0.remove(id)
        })
    }
    
    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        
        if let services = peripheral.services, !services.isEmpty {
            
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
        service.characteristics?.forEach { characteristic in
            if characteristic.descriptors == nil {
                peripheral.discoverDescriptors(for: characteristic)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        if let descriptors = characteristic.descriptors {
            descriptors.forEach { descriptor in
                if descriptor.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString {
                    if let str = descriptor.value {
                        debugPrint("!!! Description \(str)")
                    } else {
                        peripheral.readValue(for: descriptor)
                    }
                }
                debugPrint("!!! didDiscoverDescriptorsFor \(descriptor.debugDescription)")
            }
            //peripheral.write
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        if let error {
            debugPrint("!!! \(#function) error \(error)")
            return
        }
        
        if descriptor.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString,
           let value = descriptor.value as? String {
                debugPrint("User Description: \(value)")
        }
    }
    
}
