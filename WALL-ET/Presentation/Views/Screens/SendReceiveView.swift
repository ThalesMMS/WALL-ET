import SwiftUI

struct SendReceiveView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var sendViewModel: SendViewModel
    @StateObject private var receiveViewModel: ReceiveViewModel
    @State private var selectedTab = 0
    @State private var showImportSheet = false

    init(
        sendViewModel: @autoclosure @escaping () -> SendViewModel = SendViewModel(),
        receiveViewModel: @autoclosure @escaping () -> ReceiveViewModel = ReceiveViewModel()
    ) {
        _sendViewModel = StateObject(wrappedValue: sendViewModel())
        _receiveViewModel = StateObject(wrappedValue: receiveViewModel())
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
    final class PreviewSendBitcoinUseCase: SendBitcoinUseCaseProtocol {
        func execute(request: SendTransactionRequest) async throws -> Transaction {
            Transaction(
                id: UUID().uuidString,
                hash: UUID().uuidString,
                type: .send,
                amount: request.amount,
                fee: 0,
                toAddress: request.toAddress,
                memo: request.memo
            )
        }
    }

    let coordinator = AppCoordinator()
    let sendViewModel = SendViewModel(
        sendBitcoinUseCase: PreviewSendBitcoinUseCase(),
        initialBalance: 1.0,
        initialPrice: 62000,
        skipInitialLoad: true
    )

    return SendReceiveView(sendViewModel: sendViewModel)
        .environmentObject(coordinator)
}
