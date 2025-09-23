import SwiftUI

struct SendReceiveView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var sendViewModel: SendViewModel
    @StateObject private var receiveViewModel: ReceiveViewModel
    @State private var selectedTab = 0
    @State private var showImportSheet = false

    init(
        sendViewModel: @autoclosure @escaping () -> SendViewModel,
        receiveViewModel: @autoclosure @escaping () -> ReceiveViewModel
    ) {
        _sendViewModel = StateObject(wrappedValue: sendViewModel())
        _receiveViewModel = StateObject(wrappedValue: receiveViewModel())
    }
    
    init() {
        _sendViewModel = StateObject(wrappedValue: SendViewModel())
        _receiveViewModel = StateObject(wrappedValue: ReceiveViewModel())
    }

    var body: some View {
        NavigationView {
            VStack {
                Picker("", selection: $selectedTab) {
                    Text("Send").tag(0)
                    Text("Receive").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    SendView(viewModel: sendViewModel)
                } else {
                    ReceiveView(viewModel: receiveViewModel)
                }
            }
            .navigationTitle(selectedTab == 0 ? "Send Bitcoin" : "Receive Bitcoin")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "arrow.down.doc")
                    }
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportTransactionView()
        }
        .onAppear {
            receiveViewModel.updateCoordinator(coordinator)
        }
        .onChange(of: coordinator.selectedWallet?.id) { _ in
            receiveViewModel.updateCoordinator(coordinator)
        }
    }
}

#Preview {
    SendReceiveView()
        .environmentObject(AppCoordinator())
}
