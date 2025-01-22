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
#if os(iOS)
import UIKit
#endif

struct EnableBluetoothInfo {
    var message: String = "Enable Bluetooth"
    var title: String = "Check that app can use bluetooth. System Settings -> Bluetooth"
}

final class ContentViewModel: ObservableObject {
    let centralManager = BluetoothCentralManager(.showPowerAlert(true))
    private(set)var disposeBag = Set<AnyCancellable>()
    
    var bluetoothInfo: EnableBluetoothInfo!

    @Published var enableBluetoothAlert = false
    @Published var openURL: URL?
    @Published var enableScanButon = false
    @Published var isScanningPressed = false
    
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
        centralManager.scanForPeripherals()
    }
    
    func scanDevices() {
        isScanningPressed.toggle()
        if isScanningPressed {
            scanForPeripherals()
        } else {
            stopScanning()
        }
    }
    
    private func bind() {
        
        centralManager.advertisePublisher.receive(on: DispatchQueue.main).sink { info in
            self.centralManager.connectToPeripheral(uuid: info.id)
        }.store(in: &disposeBag)
        
        enableBluetoothAlert = centralManager.authorizationState.value == .denied
        $enableBluetoothAlert.map { $0 ? EnableBluetoothInfo() : nil }.sink { [unowned self] in
            self.bluetoothInfo = $0
        }.store(in: &disposeBag)
        
        centralManager.authorizationState.receive(on: DispatchQueue.main).sink { [unowned self] state in
            self.enableBluetoothAlert = state == .denied
            print("!!! Auth \(state)")
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
