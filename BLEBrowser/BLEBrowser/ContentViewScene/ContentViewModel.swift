//
//  ContentViewModel.swift
//  BLEBrowser
//
//  Created by Siarhei Yakushevich on 20/01/2025.
//

import Foundation
import BLECore
import Combine
import CoreBluetooth
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct EnableBluetoothInfo {
    var message: String = "Enable Bluetooth"
    var title: String = "Check that app can use bluetooth. System Settings -> Bluetooth"
}

final class ConnectedPeripheralViewModel: ObservableObject {
    var info: PeripheralInfo
    var position: CGPoint
    var signalStrength: Float?
    
    var title: String?
    @Published var connected: Bool
    
    var rect: CGRect {
        .init(center: position,
              size: Self.itemSize).integral
    }
    
    init(info: PeripheralInfo,
         position: CGPoint,
         signalStrength: Float? = nil,
         title: String? = nil,
         connected: Bool = true) {
        self.info = info
        self.position = position
        self.signalStrength = signalStrength
        self.title = title ?? info.name
        self.connected = connected
    }
    
    static let itemSize = CGSize(width: 100, height: 100)
}

extension ConnectedPeripheralViewModel: Identifiable {
    var id: PeripheralInfo.ID { info.id }
}

final class ContentViewModel: ObservableObject {
    let centralManager = BluetoothCentralManager(.showPowerAlert(true))
    private(set)var disposeBag = Set<AnyCancellable>()
    
    var bluetoothInfo: EnableBluetoothInfo!

    @Published var enableBluetoothAlert = false
    @Published var openURL: URL?
    @Published var enableScanButon = false
    @Published var isScanningPressed = false
    @Published var connectedPeripherals = [ConnectedPeripheralViewModel]()
    @Published var autoConnect = true
    @Published var canvasSize: CGSize = .zero
    
    init() {
        bind()
    }
    
    func onBluetoothClicked(enabled: Bool) {
        if enabled {
            let str: String
#if os(macOS)
            str = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
#endif
#if os(iOS)
            str = UIApplication.openSettingsURLString
#endif
            openURL = URL(string: str)
        }
    }
    
    private var isScanning: Bool {
        centralManager.isScanning
    }
    
    private func stopScanning() {
        centralManager.stopScanning()
    }
    
    private func scanForPeripherals() {
        centralManager.scanForPeripherals(options: .allowDuplicateKey(false))
    }
    
    func scanDevices() {
        isScanningPressed.toggle()
        if isScanningPressed {
            scanForPeripherals()
        } else {
            stopScanning()
        }
    }
    
    var itemSize: CGSize { ConnectedPeripheralViewModel.itemSize }
    
    private func randomPosition(canvasSize: CGSize) -> CGPoint {
        let itemW = itemSize.width
        let itemH = itemSize.height
        guard canvasSize.width >= itemW, canvasSize.height >= itemH else {
            return .zero
        }
        return .init(x: CGFloat(Int.random(in: Int(itemW * 0.5)...Int(canvasSize.width - itemW * 0.5))),
                     y: CGFloat(Int.random(in: Int(itemH * 0.5)...Int(canvasSize.height - itemH * 0.5))))
    }
    
    func onPeripheralClicked(viewModel: ConnectedPeripheralViewModel) {
        let uuid = viewModel.id
        if viewModel.connected {
            centralManager.connectToPeripheral(uuid: uuid)
        } else {
            centralManager.disconnectPeripheral(uuid: uuid)
        }
    }
    
    private func randomPosition() -> CGPoint {
        randomPosition(canvasSize: canvasSize)
    }
    
    private func changePeripheral(info: PeripheralInfo, connected: Bool) {
        
        if let index = self.connectedPeripherals.firstIndex(where: { $0.id == info.id }) {
            self.connectedPeripherals[index].info = info
            self.connectedPeripherals[index].connected = connected
            return
        }
        
        var rect: CGRect = .zero
        var index = 0
        var stop = false
        while !stop {
            rect = .init(center: randomPosition(),
                         size: itemSize)
            stop = index == 50 || self.connectedPeripherals.allSatisfy { !$0.rect.intersects(rect) }
            index += 1
        }
        
        debugPrint("!!! center \(rect.center) size \(canvasSize)")
        withAnimation { [weak self] in
            self?.connectedPeripherals.append(.init(info: info,
                                                    position: rect.center,
                                                    connected: connected))
        }
    }
    
    private func bind() {
        
        $autoConnect.removeDuplicates().filter { $0 }.map { _ in () }.sink { [unowned self] in
            self.centralManager.advertisingPeripheralsMap().forEach { keyValue in
                self.centralManager.connectToPeripheral(uuid: keyValue.key)
            }
        }.store(in: &disposeBag)
        
        centralManager.advertisePublisher.receive(on: DispatchQueue.main).sink { [unowned self] info in
            let id = info.id
            if self.autoConnect {
                self.centralManager.connectToPeripheral(uuid: id) // connect to discover characteristics to display something better on UI...
            }
            if let index = self.connectedPeripherals.firstIndex(where: { $0.id == id }) {
                self.connectedPeripherals[index].signalStrength = info.info.rssi
            }
            
            if !self.autoConnect {
                self.changePeripheral(info: .init(id: id,
                                                  name: info.info.localName),
                                      connected: false)
            }
        }.store(in: &disposeBag)
        
        $canvasSize.removeDuplicates().sink { [unowned self] canvasSize in
            self.connectedPeripherals = self.connectedPeripherals.map {
                var newInfo = $0
                var position = newInfo.position
                position.x *= canvasSize.width/max(1, self.canvasSize.width)
                position.y *= canvasSize.height/max(1, self.canvasSize.height)
                newInfo.position = position
                debugPrint("!!! position new \(position) old size \(self.canvasSize) new size \(canvasSize)")
                return newInfo
            }
        }.store(in: &disposeBag)
        
        centralManager.connectedPublisher.receive(on: DispatchQueue.main).sink { [unowned self] info in
            //assert(self.connectedPeripherals.allSatisfy({ $0.id != info.id })) //duplicate...
            self.changePeripheral(info: info,
                                  connected: true)
        }.store(in: &disposeBag)
        
        enableBluetoothAlert = centralManager.authorizationState.value == .denied
        $enableBluetoothAlert.map { $0 ? EnableBluetoothInfo() : nil }.sink { [unowned self] in
            self.bluetoothInfo = $0
        }.store(in: &disposeBag)
        
        let unsupportedPublisher = centralManager.managerState.map { $0 == .unsupported }
        let deniedPublisher = centralManager.authorizationState.map { $0 == .denied }
            
        deniedPublisher
            .combineLatest(unsupportedPublisher)
            .map { $0.0 || $0.1 }
            .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink { [unowned self] in
            self.enableBluetoothAlert = $0
        }.store(in: &disposeBag)
        
        
        centralManager.managerState.map { $0 == .poweredOn }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
        .sink { [unowned self] isOn in
            guard self.enableScanButon != isOn else {
                return
            }
            
            self.enableScanButon = isOn
            if !isOn {
                self.stopScanning()
            }
        }.store(in: &disposeBag)
        
    }
    
    deinit {
        disposeBag.removeAll()
    }
}
