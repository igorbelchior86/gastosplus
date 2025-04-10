import SwiftUI
import CoreData
import Firebase
import FirebaseAuth
import FirebaseFirestore
import LocalAuthentication
import UIKit
import Combine

// Definição da notificação para atualização de autenticação
extension Notification.Name {
    static let didAuthenticate = Notification.Name("didAuthenticate")
}

extension Notification.Name {
    static let faceIDDidAuthenticate = Notification.Name("faceIDDidAuthenticate")
}

// AppDelegate integrado no mesmo arquivo
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        print("Firebase configurado com sucesso no AppDelegate!")

        // Configuração do Firestore para suporte offline
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        Firestore.firestore().settings = settings
        print("Configuração de suporte offline do Firestore ativada.")

        // Reprocessar tarefas pendentes ao iniciar
        Task {
            SyncQueue.shared.processQueue()
        }

        return true
    }
}

@main
struct Gastos_App: App {
    // Vincula o AppDelegate personalizado
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Referência ao Core Data Helper
    let coreDataHelper = CoreDataManager.shared

    // Inicializa os gerenciadores como StateObjects
    @StateObject private var moneyManager = MoneyManager.shared
    @StateObject private var cardManager = CardManager.shared

    // Estados para controle de sessão e autenticação
    @State private var sessionExpirationTimer: Timer?
    @State private var isFirebaseLoggedIn: Bool = false
    @State private var isAuthenticated: Bool = false

    // Observador de estado de autenticação do Firebase
    @State private var authListener: AuthStateDidChangeListenerHandle?
    
    // Cancellables para escutar notificações
    @State private var cancellables = Set<AnyCancellable>()

    var body: some Scene {
        WindowGroup {
            NavigationView {
                if isFirebaseLoggedIn {
                    if isAuthenticated {
                        MainView(isLoggedIn: $isAuthenticated)
                            .environment(\.managedObjectContext, coreDataHelper.context)
                            .environmentObject(moneyManager)
                            .environmentObject(cardManager)
                            .onAppear {
                                iniciarMonitoramentoDeSessao()
                                configurarMonitoramentoDeInteracao()
                            }
                            .onDisappear {
                                cancelarMonitoramentoDeSessao()
                            }
                    } else {
                        // Força a autenticação antes de carregar a MainView
                        LoginView(isLoggedIn: $isAuthenticated)
                    }
                } else {
                    LoginView(isLoggedIn: $isAuthenticated)
                }
            }
            .onAppear {
                // Remove listener anterior se já existir para evitar duplicatas
                if let listener = authListener {
                    Auth.auth().removeStateDidChangeListener(listener)
                }
                
                // Adiciona um novo listener
                authListener = Auth.auth().addStateDidChangeListener { _, user in
                    if let user = user {
                        // Usuário está logado no Firebase
                        isFirebaseLoggedIn = true
                        print("FirebaseAuth: Usuário logado - \(user.email ?? "sem email")")
                    } else {
                        // Usuário está deslogado do Firebase
                        isFirebaseLoggedIn = false
                        isAuthenticated = false
                        print("FirebaseAuth: Usuário deslogado")
                    }
                }

                // Escuta a notificação de autenticação concluída
                NotificationCenter.default.publisher(for: .didAuthenticate)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        self.isAuthenticated = true
                        iniciarMonitoramentoDeSessao()
                        print("Autenticação adicional concluída. Usuário autenticado na aplicação.")
                    }
                    .store(in: &cancellables)
            }
            
            .onDisappear {
                // Remove o listener de autenticação ao sair do app
                if let listener = authListener {
                    Auth.auth().removeStateDidChangeListener(listener)
                    authListener = nil
                }
            }
        }
    }

    // MARK: - Monitoramento de Sessão

    /// Inicia o monitoramento de sessão baseado na atividade do usuário.
    private func iniciarMonitoramentoDeSessao() {
        cancelarMonitoramentoDeSessao()
        sessionExpirationTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in
            if UIApplication.shared.applicationState == .background {
                print("Sessão expirada por inatividade e app em background.")
                self.isAuthenticated = false
            } else {
                print("Usuário ativo, sessão não será encerrada.")
                self.iniciarMonitoramentoDeSessao()
            }
        }
        print("Monitoramento de sessão iniciado.")
    }

    /// Configura monitoramento para resetar a sessão a cada interação do usuário.
    /// Utiliza Combine para observar notificações, evitando o uso de @objc em structs.
    private func configurarMonitoramentoDeInteracao() {
        let notificacoes: [Notification.Name] = [
            UIApplication.userDidTakeScreenshotNotification,  // Exemplo de interação
            UIApplication.didBecomeActiveNotification,           // App ficou ativo
            UIApplication.willEnterForegroundNotification,       // App voltou do background
            UIApplication.didReceiveMemoryWarningNotification    // App recebeu alerta de memória
        ]
        
        for notificacao in notificacoes {
            NotificationCenter.default.publisher(for: notificacao)
                .sink { _ in
                    self.iniciarMonitoramentoDeSessao()
                }
                .store(in: &cancellables)
        }
    }

    /// Cancela o temporizador de monitoramento de sessão.
    private func cancelarMonitoramentoDeSessao() {
        sessionExpirationTimer?.invalidate()
        sessionExpirationTimer = nil
        print("Monitoramento de sessão cancelado.")
    }

    // MARK: - Estado Inicial e Autenticação

    /// Verifica o estado inicial ao abrir o app.
    private func verificarEstadoInicial() {
        guard let usuarioAtual = fetchUsuarioAtual() else {
            isAuthenticated = false
            return
        }

        Task {
            // Sincroniza dados locais com Firestore (upload e download)
            await sincronizarDadosComFirestore()

            if Auth.auth().currentUser != nil {
                // Usuário já autenticado, não precisa solicitar Face ID
                NotificationCenter.default.post(name: .didAuthenticate, object: nil)
            } else if usuarioAtual.usarFaceID {
                autenticarComFaceIDSeNecessario { sucesso in
                    DispatchQueue.main.async {
                        if sucesso && Auth.auth().currentUser != nil {
                            // Autenticação via FaceID bem-sucedida e usuário logado no Firebase
                            NotificationCenter.default.post(name: .didAuthenticate, object: nil)
                        } else {
                            // Se FaceID falhar ou não houver usuário logado, verificar PIN
                            if let pinSalvo = usuarioAtual.pin, !pinSalvo.isEmpty {
                                // Solicitar entrada do PIN via Notification (LoginView gerencia via sheets)
                            } else {
                                self.isAuthenticated = false
                            }
                        }
                    }
                }
            } else if let pinSalvo = usuarioAtual.pin, !pinSalvo.isEmpty {
                // Solicitar entrada do PIN via Notification (LoginView gerencia via sheets)
            } else {
                self.isAuthenticated = false
            }
        }
    }

    /// Autentica com FaceID se o usuário tiver optado por usar biometria.
    /// - Parameter completion: Closure que retorna `true` se a autenticação for bem-sucedida, caso contrário, `false`.
    private func autenticarComFaceIDSeNecessario(completion: @escaping (Bool) -> Void) {
        guard let usuario = fetchUsuarioAtual() else {
            // Nenhum usuário no Core Data, força o estado de logout
            completion(false)
            return
        }

        if usuario.usarFaceID {
            let context = LAContext()
            var error: NSError?

            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                let reason = "Autentique-se para acessar suas informações financeiras."
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                    DispatchQueue.main.async {
                        completion(success)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        } else {
            // FaceID desativado, mas usuário logado. Solicitar reautenticação manual
            completion(false)
        }
    }

    // MARK: - Sincronização com Firestore

    /// Sincroniza dados com o Firestore (upload e download).
    private func sincronizarDadosComFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }

        do {
            // Baixar cartões do Firestore
            let cartoesSnapshot = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("cards")
                .getDocuments()

            for document in cartoesSnapshot.documents {
                let cartaoData = document.data()
                await atualizarOuCriarCartaoComDados(cartaoData)
            }
            print("Cartões baixados e sincronizados com o Core Data.")

            // Baixar operações do Firestore
            let operacoesSnapshot = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("operations")
                .getDocuments()

            for document in operacoesSnapshot.documents {
                let operacaoData = document.data()
                await atualizarOuCriarOperacaoComDados(operacaoData)
            }
            print("Operações baixadas e sincronizadas com o Core Data.")

            // Baixar faturas do Firestore
            let faturasSnapshot = try await Firestore.firestore()
                .collectionGroup("invoices")
                .getDocuments()

            for document in faturasSnapshot.documents {
                let faturaData = document.data()
                await atualizarOuCriarFaturaComDados(faturaData)
            }
            print("Faturas baixadas e sincronizadas com o Core Data.")
        } catch {
            print("Erro ao sincronizar dados com o Firestore: \(error.localizedDescription)")
        }
    }

    /// Atualiza ou cria um cartão no Core Data com os dados do Firestore.
    private func atualizarOuCriarCartaoComDados(_ dados: [String: Any]) async {
        guard let idString = dados["id"] as? String,
              let id = UUID(uuidString: idString) else {
            print("Erro: Dados de cartão inválidos.")
            return
        }

        let contexto = CoreDataManager.shared.context

        let cartao = await CoreDataManager.shared.fetchCartaoPorId(id) ?? Cartao(context: contexto)
        cartao.id = id
        cartao.nome = dados["nome"] as? String ?? ""
        cartao.numero = dados["numero"] as? String
        cartao.bandeira = dados["bandeira"] as? String
        cartao.dataVencimento = (dados["dataVencimento"] as? Timestamp)?.dateValue() ?? Date()
        cartao.dataFechamento = (dados["dataFechamento"] as? Timestamp)?.dateValue() ?? Date()
        cartao.limite = dados["limite"] as? Double ?? 0.0
        cartao.taxaJuros = dados["taxaJuros"] as? Double ?? 0.0
        cartao.apelido = dados["apelido"] as? String
        cartao.isDefault = dados["isDefault"] as? Bool ?? false
        cartao.ativo = dados["ativo"] as? Bool ?? true

        CoreDataManager.shared.saveContext()
    }

    /// Atualiza ou cria uma operação no Core Data com os dados do Firestore.
    private func atualizarOuCriarOperacaoComDados(_ dados: [String: Any]) async {
        guard let idString = dados["id"] as? String,
              let id = UUID(uuidString: idString) else {
            print("Erro: Dados de operação inválidos.")
            return
        }

        let contexto = CoreDataManager.shared.context

        let operacao = await CoreDataManager.shared.fetchOperacaoPorId(id) ?? Operacao(context: contexto)
        operacao.id = id
        operacao.nome = dados["nome"] as? String ?? ""
        operacao.valor = dados["valor"] as? Double ?? 0.0
        operacao.data = (dados["data"] as? Timestamp)?.dateValue() ?? Date()
        operacao.metodoPagamento = dados["metodoPagamento"] as? String ?? ""
        operacao.recorrente = dados["recorrente"] as? Bool ?? false
        operacao.categoria = dados["categoria"] as? String
        operacao.nota = dados["nota"] as? String
        operacao.tipoString = dados["tipo"] as? String
        operacao.idRecorrencia = UUID(uuidString: dados["idRecorrencia"] as? String ?? "")
        operacao.numeroParcelas = Int16(dados["numeroParcelas"] as? Int ?? 1)

        CoreDataManager.shared.saveContext()
    }

    /// Atualiza ou cria uma fatura no Core Data com os dados do Firestore.
    private func atualizarOuCriarFaturaComDados(_ dados: [String: Any]) async {
        guard let idString = dados["id"] as? String,
              let id = UUID(uuidString: idString) else {
            print("Erro: Dados de fatura inválidos.")
            return
        }

        let contexto = CoreDataManager.shared.context

        let fatura = await CoreDataManager.shared.fetchFaturaPorId(id) ?? Fatura(context: contexto)
        fatura.id = id
        fatura.dataInicio = (dados["dataInicio"] as? Timestamp)?.dateValue() ?? Date()
        fatura.dataFechamento = (dados["dataFechamento"] as? Timestamp)?.dateValue() ?? Date()
        fatura.dataVencimento = (dados["dataVencimento"] as? Timestamp)?.dateValue() ?? Date()
        fatura.valorTotal = dados["valorTotal"] as? Double ?? 0.0
        fatura.paga = dados["paga"] as? Bool ?? false

        CoreDataManager.shared.saveContext()
    }

    /// Sincroniza dados locais do Core Data com o Firestore.
    private func sincronizarDadosLocaisComFirestore() async {
        guard Auth.auth().currentUser != nil else {
            print("Erro: Usuário não autenticado.")
            return
        }

        // Sincroniza cartões
        let cartoes = await CoreDataManager.shared.fetchCartoes()
        for cartao in cartoes {
            if cartao.hasChanges {
                await CardManager.shared.salvarCartaoNoFirestore(cartao)
            }
        }
        print("Cartões sincronizados com o Firestore.")

        // Sincroniza operações financeiras
        let operacoes = await CoreDataManager.shared.fetch("Operacao") as? [Operacao] ?? []
        for operacao in operacoes {
            if operacao.hasChanges {
                await MoneyManager.shared.salvarOperacaoNoFirestore(operacao)
            }
        }
        print("Operações financeiras sincronizadas com o Firestore.")

        // Sincroniza faturas
        let faturas = await CoreDataManager.shared.fetch("Fatura") as? [Fatura] ?? []
        for fatura in faturas {
            if let _ = fatura.cartao, fatura.hasChanges {
                await MoneyManager.shared.salvarFaturaNoFirestore(fatura) // ✅ AGORA FUNCIONA
            }
        }
        print("Faturas sincronizadas com o Firestore.")
    }

    // MARK: - Acesso ao Core Data

    /// Busca o usuário atual no Core Data.
    /// - Returns: Instância de `Usuario` se existir, caso contrário, `nil`.
    private func fetchUsuarioAtual() -> Usuario? {
        let fetchRequest: NSFetchRequest<Usuario> = Usuario.fetchRequest()

        do {
            let results = try coreDataHelper.context.fetch(fetchRequest)
            return results.first
        } catch {
            print("⚠️ Erro ao buscar usuário: \(error.localizedDescription)")
            return nil
        }
    }
}
