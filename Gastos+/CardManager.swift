import Foundation
import CoreData
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class CardManager: ObservableObject {
    
    static let shared = CardManager()
    @Published var cartoes: [Cartao] = []
    private let db = Firestore.firestore() // Referência ao Firestore
    
    private init() {
        Task {
            await carregarCartoes()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidUpdateData),
            name: .didUpdateData,
            object: nil
        )

        print("🔄 Iniciando sincronização de cartões...")
        iniciarSincronizacao()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleDidUpdateData() {
        Task {
            await carregarCartoes()
        }
    }
    
    // MARK: - Carregar Cartões
    func carregarCartoes(apenasAtivos: Bool = true) async {
        let fetched = await CoreDataManager.shared.fetchCartoes(apenasAtivos: apenasAtivos)
        self.cartoes = fetched
    }
    
    // MARK: - Atualizar Cartão
    // Atualizar Cartão e Sincronizar
    func atualizarCartao(_ cartao: Cartao) async {
        // Atualizar o cartão no Core Data
        await CoreDataManager.shared.atualizarCartao(cartao)
        
        // Atualizar as faturas abertas do cartão
        if let faturasAssociadas = cartao.faturas {
            for fatura in faturasAssociadas {
                // Atualiza apenas faturas futuras (>= hoje) e não pagas
                if fatura.dataVencimento >= Date(), !fatura.paga {
                    // Extrai os componentes ano e mês da data atual da fatura
                    var comps = Calendar.current.dateComponents([.year, .month, .day],
                                                                from: fatura.dataVencimento)
                    
                    // Atualiza apenas o dia (day) com o novo dia do vencimento do cartão
                    let novoDia = Calendar.current.component(.day, from: cartao.dataVencimento)
                    comps.day = novoDia
                    
                    // Reconstrói a nova data de vencimento mantendo o mesmo ano/mês
                    if let novaData = Calendar.current.date(from: comps) {
                        fatura.dataVencimento = novaData
                        
                        // Atualiza a data de fechamento da fatura com base no cartao.dataFechamento
                        let dataFechamento = cartao.dataFechamento
                        comps.day = Calendar.current.component(.day, from: dataFechamento)
                        fatura.dataFechamento = Calendar.current.date(from: comps) ?? fatura.dataFechamento
                    }
                }
            }
        }

        // Salva as alterações no Core Data
        CoreDataManager.shared.saveContext()

        // Notifica o app sobre as mudanças
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        
        // Salvar as alterações no contexto
        do {
            try CoreDataManager.shared.context.save()
        } catch {
            print("Erro ao salvar alterações nas faturas: \(error)")
        }
        
        // Sincronizar o cartão com o Firestore
        Task {
            await salvarCartaoNoFirestore(cartao)
        }
        
        // Recarregar os cartões para refletir as mudanças
        await carregarCartoes()
        
        // Notificar sobre a atualização dos dados
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
    }
    
    // MARK: - Criar Novo Cartão e Sincronizar
    func criarCartaoESincronizar(
        nome: String,
        numero: String,
        bandeira: String?,
        dataVencimento: Date,
        dataFechamento: Date,
        limite: Double,
        taxaJuros: Double,
        apelido: String?,
        isDefault: Bool
    ) async {
        if let novoCartao = await CoreDataManager.shared.criarCartao(
            nome: nome,
            numero: numero,
            bandeira: bandeira,
            dataVencimento: dataVencimento,
            dataFechamento: dataFechamento,
            limite: limite,
            taxaJuros: taxaJuros,
            apelido: apelido,
            isDefault: isDefault
        ) {
            await salvarCartaoNoFirestore(novoCartao)

            // ✅ Criar a fatura automaticamente
            await criarESincronizarFatura(
                dataInicio: Date(),
                dataFechamento: dataFechamento,
                dataVencimento: dataVencimento,
                valorTotal: 0.0,
                paga: false,
                cartao: novoCartao
            )
        }
        await carregarCartoes()
    }
    
    // MARK: - Arquivar Cartão
    // Arquivar Cartão e Sincronizar
    func arquivarCartao(_ cartao: Cartao) async {
        await CoreDataManager.shared.arquivarCartao(cartao)
        Task {
            await salvarCartaoNoFirestore(cartao)
        }
        await carregarCartoes()
    }
    
    // MARK: - Definir Cartão Padrão
    func definirCartaoPadrao(_ cartao: Cartao) async {
        await CoreDataManager.shared.definirCartaoPadrao(cartao)
        await salvarCartaoNoFirestore(cartao)
        await carregarCartoes()
    }
    
    // MARK: - Sincronizar Cartão no Firestore
    func salvarCartaoNoFirestore(_ cartao: Cartao) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ Erro: Usuário não autenticado.")
            return
        }

        verificarGruposCompartilhados { grupos in
            let db = Firestore.firestore()
            let cartaoData: [String: Any] = [
                "id": cartao.id.uuidString,
                "nome": cartao.nome,
                "limite": cartao.limite,
                "fechamento": cartao.dataFechamento,
                "vencimento": cartao.dataVencimento,
                "numero": cartao.numero ?? "", // 🔥 Adicionando número do cartão
                "taxaJuros": cartao.taxaJuros, // 🔥 Adicionando taxa de juros
                "bandeira": cartao.bandeira ?? "",
                "apelido": cartao.apelido ?? "",
                "isDefault": cartao.isDefault,
                "ativo": cartao.ativo
            ]

            let userCollectionPath = "users/\(userId)/cards"

            Task {
                do {
                    try await db.collection(userCollectionPath).document(cartao.id.uuidString).setData(cartaoData)
                    print("✅ Cartão \(cartao.nome) salvo no Firestore para usuário.")
                } catch {
                    print("❌ Erro ao salvar cartão no Firestore: \(error.localizedDescription)")
                }
            }

            if let grupos = grupos {
                for grupo in grupos {
                    let groupCollectionPath = "shared_groups/\(grupo)/cards"

                    Task {
                        do {
                            try await db.collection(groupCollectionPath).document(cartao.id.uuidString).setData(cartaoData)
                            print("✅ Cartão \(cartao.nome) salvo no Firestore para grupo \(grupo).")
                        } catch {
                            print("❌ Erro ao salvar cartão no Firestore para grupo \(grupo): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    
    private var cardsListeners: [ListenerRegistration] = []
    private var operationsListeners: [ListenerRegistration] = []

    func configurarListeners() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ Erro: Usuário não autenticado.")
            return
        }
        let db = Firestore.firestore()

        // Remover listeners antigos antes de adicionar novos
        for listener in cardsListeners { listener.remove() }
        for listener in operationsListeners { listener.remove() }
        
        cardsListeners.removeAll()
        operationsListeners.removeAll()

        verificarGruposCompartilhados { grupos in
            guard let grupos = grupos else {
                print("❌ Nenhum grupo compartilhado encontrado. Listeners não serão configurados.")
                return
            }

            for grupo in grupos {
                print("✅ Configurando listener para o grupo: \(grupo)")

                // 🔥 **Listener para cartões**
                let cardListener = db.collection("shared_groups").document(grupo).collection("cards")
                    .addSnapshotListener { snapshot, error in
                        if let error = error {
                            print("❌ Erro no listener de cartões (grupo \(grupo)): \(error.localizedDescription)")
                            return
                        }
                        guard let snapshot = snapshot else {
                            print("⚠️ Snapshot de cartões veio vazio.")
                            return
                        }

                        print("🔥 Listener de cartões disparado no grupo \(grupo) – \(snapshot.documentChanges.count) mudança(s).")

                        Task {
                            for change in snapshot.documentChanges {
                                print("🔄 Alteração detectada no cartão: \(change.document.data())")
                                await CoreDataManager.shared.atualizarOuCriarCartaoDeGrupo(doc: change.document)
                            }
                        }
                    }
                self.cardsListeners.append(cardListener)

                // 🔥 **Listener para operações**
                let opListener = db.collection("shared_groups").document(grupo).collection("operations")
                    .addSnapshotListener { snapshot, error in
                        if let error = error {
                            print("❌ Erro no listener de operações (grupo \(grupo)): \(error.localizedDescription)")
                            return
                        }
                        guard let snapshot = snapshot else {
                            print("⚠️ Snapshot de operações veio vazio.")
                            return
                        }

                        print("🔥 Listener de operações disparado no grupo \(grupo) – \(snapshot.documentChanges.count) mudança(s).")

                        Task {
                            for change in snapshot.documentChanges {
                                switch change.type {
                                case .added, .modified:
                                    await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: change.document)
                                case .removed:
                                    await CoreDataManager.shared.removerOperacaoDeGrupo(doc: change.document)
                                }
                            }
                        }
                    }
                self.operationsListeners.append(opListener)

                // 🔥 **NEW: Listener para faturas**
                let billsListener = db.collection("shared_groups").document(grupo).collection("bills")
                    .addSnapshotListener { snapshot, error in
                        if let error = error {
                            print("❌ Erro no listener de faturas (grupo \(grupo)): \(error.localizedDescription)")
                            return
                        }
                        guard let snapshot = snapshot else {
                            print("⚠️ Snapshot de faturas veio vazio.")
                            return
                        }

                        print("🔥 Listener de faturas disparado no grupo \(grupo) – \(snapshot.documentChanges.count) mudança(s).")

                        Task {
                            for change in snapshot.documentChanges {
                                print("🔄 Alteração detectada na fatura: \(change.document.data())")
                                await CoreDataManager.shared.atualizarOuCriarFaturaDeGrupo(doc: change.document)
                            }
                        }
                    }
                self.operationsListeners.append(billsListener)
            }
        }
    }

    // Chamando essa função no `onAppear` ou ao iniciar o `CardManager`
    func iniciarSincronizacao() {
        configurarListeners()
    }
    
    /*
    func salvarFaturaNoFirestore(_ fatura: Fatura) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let faturaData: [String: Any] = [
            "id": fatura.id.uuidString,
            "cartaoId": fatura.cartao?.id.uuidString ?? "",
            "valorTotal": fatura.valorTotal,
            "dataVencimento": fatura.dataVencimento
        ]
        
        let db = Firestore.firestore()
        let userCollectionPath = "users/\(userId)/bills"
        
        // Salvar primeiro no Firestore do usuário
        do {
            try await db.collection(userCollectionPath).document(fatura.id.uuidString).setData(faturaData)
            print("Fatura salva no Firestore para usuário.")
        } catch {
            print("Erro ao salvar fatura no Firestore: \(error.localizedDescription)")
        }
        
        // Verificar grupos antes de salvar no Firestore
        verificarGruposCompartilhados { grupos in
            if let grupos = grupos, !grupos.isEmpty {
                for grupo in grupos {
                    let groupCollectionPath = "shared_groups/\(grupo)/bills"
                    Task {
                        do {
                            try await db.collection(groupCollectionPath).document(fatura.id.uuidString).setData(faturaData)
                            print("Fatura sincronizada com grupo \(grupo).")
                        } catch {
                            print("Erro ao salvar fatura no grupo \(grupo): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    */
    
    // MARK: - Criar e Sincronizar Faturas
    // Criar Fatura e Sincronizar
    func criarESincronizarFatura(
        dataInicio: Date,
        dataFechamento: Date,
        dataVencimento: Date,
        valorTotal: Double,
        paga: Bool,
        cartao: Cartao
    ) async {
        let context = CoreDataManager.shared.context
        let calendar = Calendar.current

        // Cria 12 faturas para os próximos 12 meses
        for i in 0..<12 {
            // Calcula as datas para cada fatura, adicionando i meses
            guard let faturaDataVencimento = calendar.date(byAdding: .month, value: i, to: dataVencimento),
                  let faturaDataFechamento = calendar.date(byAdding: .month, value: i, to: dataFechamento),
                  let faturaDataInicio = calendar.date(byAdding: .month, value: i, to: dataInicio)
            else {
                continue
            }
            
            // Verifica se já existe uma fatura para esse cartão com essa data de vencimento
            let fetchRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "cartao.id == %@ AND dataVencimento == %@",
                cartao.id as CVarArg, faturaDataVencimento as NSDate
            )
            
            do {
                let faturasExistentes = try context.fetch(fetchRequest)
                if !faturasExistentes.isEmpty {
                    print("⚠️ Já existe uma fatura para \(cartao.nome) com vencimento em \(faturaDataVencimento). Pulando criação.")
                    continue
                }
            } catch {
                print("⚠️ Erro ao verificar faturas existentes: \(error.localizedDescription)")
            }
            
            // Cria nova fatura
            let novaFatura = Fatura(context: context)
            novaFatura.id = UUID()
            novaFatura.dataInicio = faturaDataInicio
            novaFatura.dataFechamento = faturaDataFechamento
            novaFatura.dataVencimento = faturaDataVencimento
            novaFatura.valorTotal = valorTotal
            novaFatura.paga = paga
            novaFatura.cartao = cartao

            // Salva no Core Data
            CoreDataManager.shared.saveContext()

            // Recalcula o saldo do cartão (pode ser chamado uma vez depois do loop, se preferir)
            await recalcularSaldoDoCartao(cartao)

            // Tenta sincronizar a fatura no Firestore
            Task {
                print("📢 Tentando salvar fatura no Firestore!")
                await MoneyManager.shared.salvarFaturaNoFirestore(novaFatura)
            }

            print("✅ Fatura criada e enviada para sincronização: \(novaFatura.id.uuidString) - \(cartao.nome) - Vencimento: \(faturaDataVencimento)")
        }
    }
    
    // Excluir Fatura do Core Data
    func excluirFatura(_ fatura: Fatura) async {
        let context = CoreDataManager.shared.context
        context.delete(fatura)
        
        do {
            try context.save()
            print("Fatura excluída do Core Data.")
            await MoneyManager.shared.excluirFaturaNoFirestore(fatura)
        } catch {
            print("Erro ao excluir fatura do Core Data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Para realizar o cálculo de saldo do cartão
    private func recalcularSaldoDoCartao(_ cartao: Cartao) async {
        // Filtrar todas as operações associadas ao cartão
        let operacoes = cartao.operacoes ?? []
        
        // Calcular o saldo total gasto
        let totalGasto = operacoes.reduce(0.0) { $0 + $1.valor }
        
        // Atualizar o saldo disponível no cartão
        let saldoDisponivel = cartao.limite - totalGasto
        
        // Atualizar a propriedade do cartão (se existir no Core Data)
        await MainActor.run {
            cartao.limite = saldoDisponivel
        }
        
        // Salvar as alterações no contexto
        CoreDataManager.shared.saveContext()
        print("Saldo do cartão \(cartao.nome) recalculado: \(saldoDisponivel)")
    }
    
    // MARK: - Adicionar Operação
    func adicionarOperacao(
        valor: Double,
        descricao: String,
        cartao: Cartao,
        parcelas: Int = 1,
        dataOperacao: Date
    ) async {
        await CoreDataManager.shared.adicionarOperacao(
            valor: valor,
            descricao: descricao,
            cartao: cartao,
            parcelas: parcelas,
            dataOperacao: dataOperacao
        )
    }
    
    // MARK: - Desativar Cartão
    // Desativar Cartão e Sincronizar
    func desativarCartao(_ cartao: Cartao) async {
        await CoreDataManager.shared.desativarCartao(cartao)
        Task {
            await salvarCartaoNoFirestore(cartao)
        }
        await carregarCartoes()
    }
    
    // MARK: - Atualizar Faturas
    // Atualizar Fatura e Sincronizar
    func atualizarFatura(_ fatura: Fatura) async {
        await CoreDataManager.shared.saveContext()
        Task {
            await MoneyManager.shared.salvarFaturaNoFirestore(fatura) // ✅ Corrigido chamando do MoneyManager
        }
    }
    
    // MARK: - Buscar Operações do Dia
    func buscarOperacoesDoDia(data: Date) async -> [Operacao] {
        return await CoreDataManager.shared.buscarOperacoesDoDia(data: data)
    }
    
    // MARK: - Buscar Faturas do Dia
    func buscarFaturasFiltradas() async -> [Fatura] {
        return await CoreDataManager.shared.fetchFaturasFiltradas()
    }
}
