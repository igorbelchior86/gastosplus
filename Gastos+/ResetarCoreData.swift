import SwiftUI
import CoreData


final class CoreDataResetHelper {
    static func resetarCoreData() {
        guard let storeURL = CoreDataManager.shared.persistentContainer.persistentStoreDescriptions.first?.url else {
            print("Erro: URL do banco de dados não encontrada.")
            return
        }

        let coordinator = CoreDataManager.shared.persistentContainer.persistentStoreCoordinator

        do {
            try coordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
            print("Banco de dados resetado com sucesso.")
            
            // Recarregar o banco de dados com o modelo atualizado
            CoreDataManager.shared.persistentContainer.loadPersistentStores { _, error in
                if let error = error {
                    fatalError("Erro ao recarregar banco de dados: \(error)")
                }
            }
        } catch {
            print("Erro ao resetar o banco de dados: \(error)")
        }
    }
}

struct CoreDataResetPreview: View {
    @State private var showAlert = false
    
    var body: some View {
        VStack {
            Text("Core Data Reset Helper")
                .font(.title)
                .padding()
            
            Button(action: {
                showAlert = true
            }) {
                Text("Resetar Banco de Dados")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.red)
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Confirmar Reset"),
                    message: Text("Tem certeza de que deseja resetar o banco de dados? Todos os dados serão perdidos."),
                    primaryButton: .destructive(Text("Resetar")) {
                        CoreDataResetHelper.resetarCoreData()
                    },
                    secondaryButton: .cancel(Text("Cancelar"))
                )
            }
        }
        .padding()
    }
}

struct CoreDataResetPreview_Previews: PreviewProvider {
    static var previews: some View {
        CoreDataResetPreview()
    }
}
