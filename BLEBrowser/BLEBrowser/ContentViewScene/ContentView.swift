//
//  ContentView.swift
//  BLEBrowser
//
//  Created by Siarhei Yakushevich on 20/01/2025.
//

import SwiftUI

struct ConnectedPeripheralView: View {
    @ObservedObject var viewModel: ConnectedPeripheralViewModel
    var tapBlock: () -> Void //TODO: place into VM ...
    
    var body: some View {
        let tapGesture: () -> Void = {
            tapBlock()
        }
        if viewModel.connected {
            Circle()
                .fill(.green)
                .frame(size: type(of: viewModel).itemSize)
                .overlay {
                    Text(viewModel.title ?? "")
                        .foregroundStyle(.background)
                }
                .clipShape(Circle())
                .onTapGesture(perform: tapGesture)
        } else if !viewModel.connectable {
            Circle()
                .fill(.red)
                .frame(size: type(of: viewModel).itemSize)
                .overlay {
                    Text(viewModel.title ?? "")
                        .foregroundStyle(.background)
                }
                .clipShape(Circle())
                .onTapGesture(perform: tapGesture)
        } else {
            Circle()
                .fill(.foreground)
                .frame(size: type(of: viewModel).itemSize)
                .overlay {
                    Text(viewModel.title ?? "")
                        .foregroundStyle(.background)
                }
                .clipShape(Circle())
                .onTapGesture(perform: tapGesture)
        }
    }
}

struct ContentView: View {
    @Environment(\.openURL) var openURL
    
    @StateObject var viewModel = ContentViewModel()
    
    @ViewBuilder func connectedDeviceView(viewModel deviceVM: ConnectedPeripheralViewModel) -> some View {
        ConnectedPeripheralView(viewModel: deviceVM) {
            viewModel.onPeripheralClicked(viewModel: deviceVM)
        }
    }
    
    var body: some View {
        ZStack {
            GeometryReader { _ in
                ForEach(viewModel.connectedPeripherals) {
                    connectedDeviceView(viewModel: $0)
                        .position($0.position)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        
            /*ScrollView(.vertical.union(.horizontal)) {
                ForEach(viewModel.connectedPeripherals) {
                    connectedDeviceView(viewModel: $0)
                        .position($0.position)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity,
                    maxHeight: .infinity)
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.bounds.size
            } action: { _, newValue in
                //self.viewModel.canvasSize = newValue
            }*/.onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { newValue in
                self.viewModel.canvasSize = newValue
            }.overlay(alignment: .topTrailing) {
                Toggle(isOn: $viewModel.autoConnect) {
                    Text("Auto Connect")
                        .foregroundStyle(.primary)
                }.padding(.horizontal)
            }

            
            Button(action: viewModel.scanDevices) {
                Image(systemName: viewModel.isScanningPressed ? "pause.fill" :  "play.fill")
                    .imageScale(.large)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .padding()
            }
            .background(.secondary)
            .clipShape(Circle())
            .disabled(!viewModel.enableScanButon)
        }
        .alert(
            viewModel.bluetoothInfo?.title ?? "",
            isPresented: $viewModel.enableBluetoothAlert
                    ) {
                        Button("OK") {
                            // Handle the acknowledgement.
                            viewModel.onBluetoothClicked(enabled: true)
                        }
                        Button("Cancel") {
                            viewModel.onBluetoothClicked(enabled: false)
                        }
                    } message: {
                        Text(viewModel.bluetoothInfo?.message ?? "")
                    }
                    .onReceive(viewModel.$openURL) { url in
                        guard let url else {
                            return
                        }
                        openURL(url)
                    }
    }

}

#Preview {
    ContentView()
}
