//
//  ContentView.swift
//  BLEBrowser
//
//  Created by Siarhei Yakushevich on 20/01/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) var openURL
    
    @StateObject var viewModel = ContentViewModel()
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Button(action: viewModel.scanDevices) {
                Image(systemName: viewModel.isScanningPressed ? "pause.fill" :  "play.fill")
                    .imageScale(.large)
                    .padding()
            }.disabled(!viewModel.enableScanButon)
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

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
