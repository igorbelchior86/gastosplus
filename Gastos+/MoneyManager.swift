import SwiftUI
import Foundation
import CoreData
import FirebaseFirestore
import FirebaseAuth

// ======================================================
// MARK: - Enum SyncStatus
// ======================================================
enum SyncStatus {
    case idle
    case syncing
    case completed
    case failed
    case synced
}

// ======================================================
// MARK: - MoneyManager (Singleton + ObservableObject)
// ======================================================
@MainActor
final class MoneyManager: ObservableObject {
    // MARK: - Singleton & Core Data Context
    static let shared = MoneyManager()
    private let context = CoreDataManager.shared.context
    
    // MARK: - Flags de Controle Interno
    private var isInternalUpdate = false
    private var isProcessingRecurrences = false
    private var dailyTimer: Timer? = nil
    private var operationsListener: ListenerRegistration? // Armazena o listener
    private var observadoresConfigurados = false
    
    // MARK: - Published Properties (Estado do App)
    @Published var saldoDoDia: Double = 0.0
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncError: String? = nil
    @Published var saldoFinal: Double = 0.0
    @Published var operacoes: [Operacao] = []
    @Published var cartoes: [Cartao] = []
    @Published var saldosPorDia: [DailyBalance] = []
    
    
    /// Mês que o usuário está visualizando na UI
    @Published var mesAtual: Date = Date() {
        didSet {
            Task {
                await carregarDados()
            }
        }
    }
    
    // MARK: - Inicializador Privado + Observadores
    private init() {
        Task {
            await carregarDados() // 1. Carregar dados inicialmente
        }
        
        // 2. Observa .didUpdateData e recarrega dados
        NotificationCenter.default.addObserver(
            forName: .didUpdateData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                guard let self = self, !self.isInternalUpdate else {
                    print("Atualização interna em andamento. Ignorando notificação.")
                    return
                }
                await self.carregarDados()
            }
        }
        
        // *** NOVO: Observe as mudanças do contexto do Core Data ***
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
            object: CoreDataManager.shared.context,
            queue: .main
        ) { [weak self] _ in
            Task {
                // Recarrega os dados sempre que houver alterações no contexto
                await self?.carregarDados()
            }
        }
        
        // 3. Configurar timer para verificar operações recorrentes diariamente
        setupDailyTimer()
    }
    
    // MARK: - Deinit
    deinit {
        NotificationCenter.default.removeObserver(self)
        dailyTimer?.invalidate()
    }
    
    // ======================================================
    // MARK: - Timer Diário (setupDailyTimer)
    // ======================================================
    private func setupDailyTimer() {
        let calendar = Calendar.current
        let now = Date()
        
        // Próxima meia-noite
        if let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour:0, minute:0, second:0),
            matchingPolicy: .nextTime
        ) {
            let timeInterval = nextMidnight.timeIntervalSince(now)
            print("Configurando Timer para daqui a \(timeInterval) seg, às \(nextMidnight)")
            
            dailyTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                Task {
                    print("Timer disparou às \(Date())")
                    await self?.carregarDados()
                    self?.setupDailyTimer() // Reconfigura para o próximo dia
                }
            }
        } else {
            print("Erro: Não foi possível calcular a próxima meia-noite. Tentando novamente em 1 minuto.")
            dailyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                Task {
                    await self?.setupDailyTimer()
                }
            }
        }
    }
    
    // ======================================================
    // MARK: - Carregamento de Dados (carregarDados, etc.)
    // ======================================================
    func carregarDados() async {
        guard !isInternalUpdate else {
            print("Carregamento de dados interno em andamento. Ignorando chamada.")
            return
        }
        isInternalUpdate = true
        defer { isInternalUpdate = false }
        
        let calendar = Calendar.current
        let startOfCurrentMonth = calendar.startOfMonth(for: mesAtual)
        guard let endOfNextMonth = calendar.date(byAdding: .month, value: 2, to: startOfCurrentMonth) else {
            print("Erro ao calcular a data de fim do intervalo.")
            return
        }

        // 1) Atualizar cartões do MoneyManager
        let fetchedCartoes = await CoreDataManager.shared.fetchCartoes(apenasAtivos: true)
        await MainActor.run {
            self.cartoes = fetchedCartoes
        }

        // 2) Buscar todas as operações nesse intervalo
        let todasOperacoes = await carregarOperacoes(inicio: startOfCurrentMonth, fim: endOfNextMonth)
        await MainActor.run {
            self.operacoes = todasOperacoes
        }
        
        // 3) Processar recorrências
        await processarOperacoesRecorrentesParaIntervalo(inicio: startOfCurrentMonth, fim: endOfNextMonth)
        
        // 4) Atualizar saldos
        await atualizarSaldos()
        
        // Configure os observadores uma única vez:
        if !observadoresConfigurados {
            CoreDataManager.shared.configurarObservadoresFirestore()
            observadoresConfigurados = true
        }
    }
    
    // MARK: Atualizar Saldos (saldoDoDia, saldoFinal, etc.)
    func atualizarSaldos() async {
        await calcularSaldosCumulativos()
        let saldoAteHoje = await calcularSaldoAteHoje() // ✅ Obtém antes
        await MainActor.run {
            self.saldoFinal = self.saldosPorDia.last?.saldo ?? 0.0
            self.saldoDoDia = saldoAteHoje // ✅ Agora é síncrono dentro do MainActor
            self.saldosPorDia = Array(self.saldosPorDia)
        }
    }
    
    // MARK: Calcular Saldo até Hoje (ignorando cartão)
    private func calcularSaldoAteHoje() async -> Double {
        let hoje = Date()
        
        // A. Buscar todas Operacoes <= hoje
        let predicate = NSPredicate(format: "data <= %@", hoje as NSDate)
        let todasOps = await CoreDataManager.shared.fetch("Operacao", predicate: predicate, sortDescriptors: nil) as? [Operacao] ?? []
        
        // B. Somar apenas as que NÃO são de cartão
        let saldoOps = todasOps
            .filter { $0.metodoPagamento != "Cartão" }
            .reduce(0.0) { $0 + $1.valor }
        
        // C. Subtrair Faturas que já venceram
        let faturasVencidas = cartoes
            .flatMap { $0.faturas ?? [] }
            .filter { $0.dataVencimento <= hoje }
        
        let impactoFaturas = faturasVencidas.reduce(0.0) { $0 + $1.valorTotal }
        
        // D. Retorna saldo final
        return saldoOps - impactoFaturas
    }
    
    // MARK: Calcular Saldos Cumulativos (do Mês)
    func calcularSaldosCumulativos() async {
        let calendar = Calendar.current
        let dataReferencia = mesAtual
        
        // 1. Início/fim do mês
        let startOfMonth = calendar.startOfMonth(for: dataReferencia)
        let endOfMonth   = calendar.endOfMonth(for: dataReferencia)
        
        // 2. Saldo acumulado antes do mês
        let predBeforeMonth = NSPredicate(format: "data < %@", startOfMonth as NSDate)
        let opsBeforeMonth = await CoreDataManager.shared.fetch("Operacao", predicate: predBeforeMonth, sortDescriptors: nil) as? [Operacao] ?? []
        
        let saldoBeforeOps = opsBeforeMonth
            .filter { $0.metodoPagamento != "Cartão" }
            .reduce(0.0) { $0 + $1.valor }
        
        // 2.x) Faturas vencidas antes do início do mês
        let allFaturas = cartoes.flatMap { $0.faturas ?? [] }
        let faturasVencidasAteStart = allFaturas.filter { $0.dataVencimento < startOfMonth }
        let totalFaturasVencidas = faturasVencidasAteStart.reduce(0.0) { $0 + $1.valorTotal }
        
        let saldoBeforeMonth = saldoBeforeOps - totalFaturasVencidas
        
        // 3. Filtra operações do mês (ignora Cartão)
        let calendarOps = operacoes.filter {
            let compOp  = calendar.dateComponents([.year, .month], from: $0.data)
            let compRef = calendar.dateComponents([.year, .month], from: dataReferencia)
            return (compOp.year == compRef.year &&
                    compOp.month == compRef.month &&
                    $0.metodoPagamento != "Cartão")
        }
        .sorted { $0.data < $1.data }
        
        // 4. Gera dia a dia
        var currentDate = startOfMonth
        var cumulativeSaldo = saldoBeforeMonth
        var saldos: [DailyBalance] = []
        var operIndex = 0
        
        while currentDate <= endOfMonth {
            while operIndex < calendarOps.count,
                  calendar.isDate(calendarOps[operIndex].data, inSameDayAs: currentDate) {
                cumulativeSaldo += calendarOps[operIndex].valor
                operIndex += 1
            }
            saldos.append(DailyBalance(date: currentDate, saldo: cumulativeSaldo))
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        // 5. Se não há operações neste mês, ainda gerar os dias
        if calendarOps.isEmpty {
            saldos.removeAll()
            var tempDate = startOfMonth
            while tempDate <= endOfMonth {
                saldos.append(DailyBalance(date: tempDate, saldo: saldoBeforeMonth))
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: tempDate) else { break }
                tempDate = nextDate
            }
        }
        
        // 6. Subtrair valor da fatura no dia do vencimento
        var mutableSaldos = saldos
        let faturasMes = allFaturas
        
        for i in 0..<mutableSaldos.count {
            let dia = mutableSaldos[i].date
            // Faturas que vencem nesse dia
            let faturasDoDia = faturasMes.filter { calendar.isDate($0.dataVencimento, inSameDayAs: dia) }
            let totalFaturasDoDia = faturasDoDia.reduce(0.0) { $0 + $1.valorTotal }
            
            if totalFaturasDoDia != 0 {
                for j in i..<mutableSaldos.count {
                    mutableSaldos[j].saldo -= totalFaturasDoDia
                }
            }
        }
        
        // 7. Atualiza saldosPorDia
        saldosPorDia = mutableSaldos
    }
    
    // ======================================================
    // MARK: - Processamento de Operações Recorrentes
    // ======================================================
    func processarOperacoesRecorrentes() async {
        guard !isProcessingRecurrences else {
            print("Processamento de recorrências já está em andamento.")
            return
        }
        isProcessingRecurrences = true
        defer { isProcessingRecurrences = false }
        
        let agora = Date()
        let limiteSuperior = Calendar.current.date(byAdding: .day, value: 60, to: agora) ?? agora
        print("Processando operações recorrentes até: \(limiteSuperior)")
        
        let opsRecorrentes = operacoes.filter {
            $0.recorrente && ($0.recorrencia?.proximaData ?? Date.distantFuture) <= limiteSuperior
        }
        print("Operações recorrentes encontradas: \(opsRecorrentes.count)")
        
        guard !opsRecorrentes.isEmpty else {
            print("Nenhuma operação recorrente para processar.")
            return
        }
        
        for operacao in opsRecorrentes {
            guard let recorrencia = operacao.recorrencia else {
                print("Operação \(operacao.nome) não possui recorrência.")
                continue
            }
            
            var proximaData = recorrencia.proximaData
            while proximaData <= limiteSuperior {
                let calendar = Calendar.current
                let existeOpNoDia = operacoes.first { op in
                    op.idRecorrencia == operacao.idRecorrencia && calendar.isDate(op.data, inSameDayAs: proximaData)
                }
                
                if existeOpNoDia != nil {
                    print("Operação já existente para data \(proximaData). Pulando.")
                    proximaData = calcularProximaDataRecorrencia(tipo: recorrencia.tipo, dataAtual: proximaData)
                    continue
                }
                
                // Cria nova operação (não recorrente)
                let valorFinal = operacao.valor < 0 ? -abs(operacao.valor) : abs(operacao.valor)
                adicionarOperacao(
                    valor: valorFinal,
                    descricao: operacao.nome,
                    data: proximaData,
                    tipoOperacao: operacao.valor < 0 ? "despesa" : "receita",
                    metodoPagamento: operacao.metodoPagamento,
                    recorrencia: recorrencia.tipo,
                    cartao: operacao.cartao,
                    isRecorrente: false,
                    operacaoOriginal: operacao
                )
                
                proximaData = calcularProximaDataRecorrencia(tipo: recorrencia.tipo, dataAtual: proximaData)
            }
            
            recorrencia.proximaData = proximaData
            print("Próxima data para \(operacao.nome) atualizada para: \(proximaData)")
        }
        
        await salvarContexto()
        print("Processamento de recorrências concluído.")
    }
    
    func processarOperacoesRecorrentesParaIntervalo(inicio: Date, fim: Date) async {
        let calendar = Calendar.current
        let recorrencias = await CoreDataManager.shared.fetchRecorrencias()
        
        for recorrencia in recorrencias {
            guard let operacao = recorrencia.operacao else {
                print("Recorrência não possui operação associada.")
                continue
            }
            
            var proximaData = recorrencia.proximaData
            while proximaData <= fim {
                let existeOpNoDia = operacoes.first { op in
                    op.idRecorrencia == recorrencia.id && calendar.isDate(op.data, inSameDayAs: proximaData)
                }
                if existeOpNoDia != nil {
                    print("Operação já existe para data \(proximaData). Pulando duplicação.")
                    proximaData = calcularProximaDataRecorrencia(tipo: recorrencia.tipo, dataAtual: proximaData)
                    continue
                }
                
                let valorFinal = operacao.valor < 0 ? -abs(operacao.valor) : abs(operacao.valor)
                adicionarOperacao(
                    valor: valorFinal,
                    descricao: operacao.nome,
                    data: proximaData,
                    tipoOperacao: operacao.tipoOperacao.rawValue,
                    metodoPagamento: operacao.metodoPagamento,
                    recorrencia: recorrencia.tipo,
                    cartao: operacao.cartao,
                    isRecorrente: false,
                    operacaoOriginal: operacao
                )
                
                proximaData = calcularProximaDataRecorrencia(tipo: recorrencia.tipo, dataAtual: proximaData)
            }
            
            recorrencia.proximaData = proximaData
            print("Próxima data para \(operacao.nome) atualizada para: \(proximaData)")
        }
        await CoreDataManager.shared.saveContext()
    }
    
    private func calcularProximaDataRecorrencia(tipo: String, dataAtual: Date) -> Date {
        let calendar = Calendar.current
        switch tipo.lowercased() {
        case "diária":
            return calendar.date(byAdding: .day, value: 1, to: dataAtual) ?? dataAtual
        case "semanal":
            let novaData = calendar.date(byAdding: .weekOfYear, value: 1, to: dataAtual)
            return novaData ?? dataAtual
        case "quinzenal":
            return calendar.date(byAdding: .day, value: 14, to: dataAtual) ?? dataAtual
        case "mensal":
            return calendar.date(byAdding: .month, value: 1, to: dataAtual) ?? dataAtual
        case "anual":
            return calendar.date(byAdding: .year, value: 1, to: dataAtual) ?? dataAtual
        default:
            return calendar.date(byAdding: .day, value: 1, to: dataAtual) ?? dataAtual
        }
    }
    
    // ======================================================
    // MARK: - Operações (Adicionar, Editar, Excluir, etc.)
    // ======================================================
    func excluirOperacaoUnica(_ operacao: Operacao) async {
        let operacaoID = operacao.id.uuidString

        // Primeiro excluímos no Firestore
        await excluirOperacaoNoFirestore(operacaoID)

        // Depois removemos do Core Data
        if let fatura = operacao.fatura {
            fatura.removerOperacao(operacao)
        }
        CoreDataManager.shared.context.delete(operacao)
        CoreDataManager.shared.saveContext()

        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        print("Operação única excluída do Core Data: \(operacao.nome)")

        // Atualizar dados na UI
        await MoneyManager.shared.carregarDados()
    }
    
    func adicionarOperacao(
        valor: Double,
        descricao: String,
        data: Date,
        tipoOperacao: String,
        metodoPagamento: String,
        parcelas: Int = 1,            // <--- Adicionado este parâmetro com valor padrão
        recorrencia: String? = nil,
        cartao: Cartao? = nil,
        isRecorrente: Bool = true,
        operacaoOriginal: Operacao? = nil
    ) {
        // --------------------------------------
        // Se for compra no cartão COM mais de 1 parcela,
        // chamamos a lógica do CardManager (o for parcel in 1...parcelas).
        // --------------------------------------
        if metodoPagamento.lowercased() == "cartão",
           let cartaoValido = cartao,
           parcelas > 1
        {
            Task {
                await CardManager.shared.adicionarOperacao(
                    valor: valor,
                    descricao: descricao,
                    cartao: cartaoValido,
                    parcelas: parcelas,
                    dataOperacao: data
                )
            }
            return // já encerra, pois a parcelada foi criada no CardManager
        }
        
        // --------------------------------------
        // CASO CONTRÁRIO, cria apenas UMA operação
        // (lógica original do seu método).
        // --------------------------------------
        
        // Cria apenas UMA operação.
        let novaOperacao = Operacao(
            context: context,
            nome: descricao,
            // Se NÃO há operação original, atribuímos o valor conforme o parâmetro 'tipoOperacao'
            // Se há operação original, copiamos o valor (e o sinal) da operação original.
            valor: operacaoOriginal == nil
                ? (tipoOperacao.lowercased() == "despesa" ? -abs(valor) : abs(valor))
                : operacaoOriginal!.valor,
            data: data,
            metodoPagamento: metodoPagamento,
            recorrente: isRecorrente && recorrencia != nil,
            cartao: cartao
        )

        // Se for parte de uma série (isto é, se operacaoOriginal existir),
        // force o tipo da nova operação a ser o mesmo da original.
        if let original = operacaoOriginal {
            // IMPORTANTE: Mesmo que o valor de 'tipoOperacao' passado seja "despesa" ou "receita",
            // queremos que todas as instâncias de uma série recorrente sejam marcadas como .recorrente.
            novaOperacao.tipoOperacao = original.tipoOperacao == .recorrente ? .recorrente : original.tipoOperacao
        } else if isRecorrente, recorrencia != nil {
            // Se não há operação original mas o usuário está criando uma operação recorrente,
            // force o tipo para .recorrente.
            novaOperacao.tipoOperacao = .recorrente
        } else {
            // Caso contrário, defina o tipo conforme o parâmetro.
            switch tipoOperacao.lowercased() {
            case "despesa":
                novaOperacao.tipoOperacao = .despesa
            case "receita":
                novaOperacao.tipoOperacao = .receita
            default:
                // Se não bater em nenhum dos casos acima, atribua única.
                novaOperacao.tipoOperacao = .unica
            }
        }
        
        // ID de Recorrência (se for recorrente)
        let recurrenceID: UUID?
        if let original = operacaoOriginal {
            recurrenceID = original.idRecorrencia ?? UUID()
        } else if isRecorrente {
            recurrenceID = UUID()
        } else {
            recurrenceID = nil
        }
        novaOperacao.idRecorrencia = recurrenceID
        
        // Criar ou vincular Recorrencia
        if let tipoRec = recorrencia,
           isRecorrente,
           let recID = recurrenceID
        {
            let fetchReq: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
            fetchReq.predicate = NSPredicate(format: "id == %@", recID as CVarArg)
            
            let existingRec = try? context.fetch(fetchReq)
            if existingRec?.isEmpty == true {
                let intervalo = calcularIntervalo(tipoRec)
                let novaRec = Recorrencia(
                    context: context,
                    tipo: tipoRec,
                    intervalo: intervalo,
                    dataInicial: data,
                    operacao: novaOperacao
                )
                novaRec.id = recID
                novaOperacao.recorrencia = novaRec
                print("Recorrência criada: \(novaOperacao.nome), Data: \(novaRec.proximaData), ID: \(novaRec.id)")
            } else {
                print("Recorrência já existe para ID: \(recID)")
                if let existing = existingRec?.first {
                    novaOperacao.recorrencia = existing
                }
            }
        }
        
        // Se for cartão (porém parcelas == 1), ainda vincula à fatura normalmente
        if let cartao = cartao {
            Task {
                await CoreDataManager.shared.vincularOperacaoAFatura(novaOperacao)
                print("Operação vinculada à fatura do cartão: \(cartao.nome)")
            }
        }
        
        // Salvar em background e disparar upload imediato para o Firestore
        Task {
            await salvarContexto()
            print("Operação adicionada (única): \(novaOperacao.nome), IDRecorrência: \(novaOperacao.idRecorrencia?.uuidString ?? "Nenhum")")
            // Adicione a chamada de upload:
            await MoneyManager.shared.salvarOperacaoNoFirestore(novaOperacao)
        }
    }
    
    private func calcularIntervalo(_ tipo: String) -> Int32 {
        let norm = tipo.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        switch norm {
        case "diaria":
            return 1
        case "semanal":
            return 7
        case "quinzenal":
            return 14
        case "mensal":
            return Int32(Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30)
        case "anual":
            return 365
        default:
            print("Tipo de recorrência desconhecido: \(tipo). Usando intervalo padrão: 1 dia")
            return 1
        }
    }
    
    func salvarContexto() async {
        isInternalUpdate = true
        CoreDataManager.shared.saveContext()
        isInternalUpdate = false
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        print("Contexto salvo.")
    }
    
    func buscarOperacoesDoDia(data: Date, metodoPagamento: String? = nil, tipo: TipoOperacao? = nil) async -> [Operacao] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: data)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        
        var predicateString = "data >= %@ AND data < %@"
        var predicateValues: [Any] = [startOfDay as NSDate, endOfDay as NSDate]
        
        if let metodoPagamento = metodoPagamento {
            predicateString += " AND metodoPagamento == %@"
            predicateValues.append(metodoPagamento)
        }
        
        if let tipo = tipo {
            predicateString += " AND tipoString == %@"
            predicateValues.append(tipo.rawValue)
        }
        
        let predicate = NSPredicate(format: predicateString, argumentArray: predicateValues)
        let ops = await CoreDataManager.shared.fetch("Operacao", predicate: predicate, sortDescriptors: nil) as? [Operacao] ?? []
        return ops
    }
    
    func carregarOperacoes(inicio: Date? = nil, fim: Date? = nil) async -> [Operacao] {
        let calendar = Calendar.current
        let startDate = inicio ?? calendar.startOfMonth(for: mesAtual)
        let endDate   = fim ?? (calendar.date(byAdding: .month, value: 2, to: startDate) ?? startDate)
        
        let predicate = NSPredicate(format: "data >= %@ AND data <= %@", startDate as NSDate, endDate as NSDate)
        let sortDescriptor = NSSortDescriptor(key: "data", ascending: true)
        let ops = await CoreDataManager.shared.fetch("Operacao", predicate: predicate, sortDescriptors: [sortDescriptor]) as? [Operacao] ?? []
        
        print("Operações carregadas: \(ops.count)")
        return ops
    }
    
    // MARK: - Carregar Dados para Intervalo Específico
    func carregarDadosParaIntervalo(inicio: Date, fim: Date) async {
        await processarOperacoesRecorrentesParaIntervalo(inicio: inicio, fim: fim)
        let ops = await carregarOperacoes(inicio: inicio, fim: fim)
        let saldos = calcularSaldosCumulativos(operacoes: ops, inicio: inicio, fim: fim)
        
        DispatchQueue.main.async {
            self.saldosPorDia = saldos
        }
    }
    
    private func calcularSaldosCumulativos(operacoes: [Operacao], inicio: Date, fim: Date) -> [DailyBalance] {
        let calendar = Calendar.current
        var saldos: [DailyBalance] = []
        var cumulativeSaldo: Double = 0.0
        var currentDate = inicio
        
        while currentDate <= fim {
            let opsDoDia = operacoes.filter { calendar.isDate($0.data, inSameDayAs: currentDate) }
            let saldoDoDia = opsDoDia.reduce(0.0) { $0 + $1.valor }
            cumulativeSaldo += saldoDoDia
            
            saldos.append(DailyBalance(date: currentDate, saldo: cumulativeSaldo))
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return saldos
    }
    
    // MARK: - Excluir Operações
    func excluirOperacao(_ operacao: Operacao) async {
        // 1. Captura o ID antes de excluir a operação
        let operacaoID = operacao.id.uuidString
        let opNome = operacao.nome
        
        // 2. Remove a operação do Core Data
        context.delete(operacao)
        do {
            try context.save()
            print("Operação excluída do Core Data: \(opNome)")

            // 3. Exclui também no Firestore
            await excluirOperacaoNoFirestore(operacaoID)
            
            // 4. Atualiza os dados na UI (sincronização local)
            await MoneyManager.shared.carregarDados()
        } catch {
            print("Erro ao excluir operação: \(error.localizedDescription)")
        }
    }
    
    private func excluirOperacaoNoFirestore(_ operacaoID: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let db = Firestore.firestore()
        
        // 1. Excluir na coleção do usuário
        let userCollectionPath = "users/\(userId)/operations"
        let userDocRef = db.collection(userCollectionPath).document(operacaoID)
        
        print("Tentando excluir operação com ID: \(operacaoID) no caminho: \(userCollectionPath)")
        
        do {
            try await userDocRef.delete()
            print("Operação \(operacaoID) excluída do Firestore em \(userCollectionPath).")
        } catch {
            print("Erro ao excluir operação no Firestore (user): \(error)")
        }
        
        // 2. Buscar grupos compartilhados do usuário e excluir na coleção de cada grupo
        let sharedGroups: [String] = await withCheckedContinuation { continuation in
            verificarGruposCompartilhados { groupCodes in
                continuation.resume(returning: groupCodes ?? [])
            }
        }
        
        for group in sharedGroups {
            let groupCollectionPath = "shared_groups/\(group)/operations"
            let groupDocRef = db.collection(groupCollectionPath).document(operacaoID)
            
            print("Tentando excluir operação com ID: \(operacaoID) no caminho: \(groupCollectionPath)")
            
            do {
                try await groupDocRef.delete()
                print("Operação \(operacaoID) excluída do Firestore no grupo \(group).")
            } catch {
                print("Erro ao excluir operação no Firestore (grupo \(group)): \(error)")
            }
        }
    }
    
    func excluirOperacoesFuturas(idRecorrencia: UUID, dataReferencia: Date) async {
        // 1) Buscar todas as operações futuras localmente
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "idRecorrencia == %@ AND data >= %@",
            idRecorrencia as NSUUID,
            dataReferencia as NSDate
        )

        do {
            let futurasOperacoes = try context.fetch(fetchRequest)
            guard !futurasOperacoes.isEmpty else {
                print("Nenhuma operação futura encontrada p/ IDRecorrencia: \(idRecorrencia.uuidString)")
                return
            }

            // 2) Remover cada operação da fatura (se houver) e excluir do Core Data
            for op in futurasOperacoes {
                if let fatura = op.fatura {
                    fatura.removerOperacao(op)
                    // fatura.removerOperacao() já chama fatura.calcularValorTotal()
                }
                context.delete(op)
            }
            try context.save()
            print("Excluídas \(futurasOperacoes.count) operações futuras no Core Data.")

            // 3) Excluir do Firestore (em lote)
            do {
                try await excluirOperacoesFuturasNoFirestore(idRecorrencia: idRecorrencia, dataReferencia: dataReferencia)
            } catch {
                print("Erro ao excluir futuras operações no Firestore: \(error.localizedDescription)")
            }

            // 4) Consertar a recorrência para não recriar
            //    Precisamos buscar a Recorrencia e jogar sua proximaData para .distantFuture
            let fetchRec: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
            fetchRec.predicate = NSPredicate(format: "id == %@", idRecorrencia as NSUUID)
            let recs = try context.fetch(fetchRec)

            if let rec = recs.first {
                rec.proximaData = .distantFuture
                try context.save()
                print("Recorrência \(rec.id) congelada definindo proximaData = .distantFuture.")
            } else {
                print("Não existe Recorrencia com ID \(idRecorrencia.uuidString) para congelar.")
            }
        } catch {
            print("Erro ao buscar/excluir operações futuras no Core Data: \(error.localizedDescription)")
        }
    }
    
    private func excluirOperacoesFuturasNoFirestore(idRecorrencia: UUID, dataReferencia: Date) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let collectionPath = "users/\(userId)/operations"
        
        // 1) Buscar todas as operações no Firestore cujo idRecorrencia == ... e data >= ...
        //    Necessário que seu campo “data” no Firestore seja salvo como Timestamp.
        let snapshot = try await db.collection(collectionPath)
            .whereField("idRecorrencia", isEqualTo: idRecorrencia.uuidString)
            .whereField("data", isGreaterThanOrEqualTo: dataReferencia)
            .getDocuments()
        
        guard !snapshot.isEmpty else {
            print("Nenhuma operação futura encontrada no Firestore p/ \(idRecorrencia.uuidString)")
            return
        }
        
        print("Excluindo do Firestore \(snapshot.documents.count) ops futuras para recID \(idRecorrencia)")
        
        // 2) Excluir em lote para otimizar
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        print("Excluídas do Firestore \(snapshot.documents.count) operações futuras (idRecorrencia=\(idRecorrencia))")
    }
    
    func excluirSerieRecorrente(idRecorrencia: UUID) async {
        // 1) Excluir TODAS as Operacoes dessa recorrência (sem filtrar data)
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "idRecorrencia == %@", idRecorrencia as NSUUID)

        do {
            let todasOperacoes = try context.fetch(fetchRequest)

            // Remover da fatura antes de excluir do Core Data
            for op in todasOperacoes {
                if let fatura = op.fatura {
                    fatura.removerOperacao(op)
                }
                context.delete(op)
            }
            print("Operações da série excluídas localmente: \(todasOperacoes.count)")

        } catch {
            print("Erro ao buscar operações p/ exclusão da série: \(error.localizedDescription)")
            return
        }

        // 2) Excluir a Recorrencia
        let fetchRecorrencia: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
        fetchRecorrencia.predicate = NSPredicate(format: "id == %@", idRecorrencia as NSUUID)

        do {
            let recorrencias = try context.fetch(fetchRecorrencia)
            recorrencias.forEach { context.delete($0) }
            print("Recorrências excluídas: \(recorrencias.count)")
        } catch {
            print("Erro ao buscar Recorrência p/ exclusão: \(error.localizedDescription)")
        }

        // 3) Salvar no Core Data
        do {
            try context.save()
            print("Série completa excluída p/ recorrência: \(idRecorrencia)")
        } catch {
            print("Erro ao salvar exclusão da série completa: \(error.localizedDescription)")
        }

        // 4) Excluir do Firestore
        do {
            try await excluirSerieRecorrenteNoFirestore(idRecorrencia: idRecorrencia)
        } catch {
            print("Erro ao excluir a série no Firestore: \(error.localizedDescription)")
        }
    }
    
    private func excluirSerieRecorrenteNoFirestore(idRecorrencia: UUID) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let collectionPath = "users/\(userId)/operations"
        
        // Busca TODAS as operações (sem filtrar data) com idRecorrencia = X
        let snapshot = try await db.collection(collectionPath)
            .whereField("idRecorrencia", isEqualTo: idRecorrencia.uuidString)
            .getDocuments()
        
        guard !snapshot.isEmpty else {
            print("Nenhuma operação dessa série encontrada no Firestore (\(idRecorrencia.uuidString))")
            return
        }
        print("Excluindo do Firestore \(snapshot.documents.count) ops da série \(idRecorrencia.uuidString)")
        
        // Excluir em batch
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
        print("Excluída do Firestore a série inteira (\(snapshot.documents.count) docs)")
        
        // Excluir a Recorrência em si (opcional, se você estiver salvando Recorrencia no Firestore)
        // Ex: db.collection("users/\(userId)/recurrences").document(idRecorrencia.uuidString).delete()
    }
    
    func excluirParcelamento(idRecorrencia: UUID) async {
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        // <-- Alteração aqui também:
        fetchRequest.predicate = NSPredicate(format: "idRecorrencia == %@", idRecorrencia as NSUUID)
        
        do {
            let parcelas = try context.fetch(fetchRequest)
            guard !parcelas.isEmpty else {
                print("Nenhuma parcela encontrada p/ ID: \(idRecorrencia.uuidString)")
                return
            }
            parcelas.forEach { context.delete($0) }
            print("Parcelas excluídas: \(parcelas.count)")
        } catch {
            print("Erro ao buscar Parcelas p/ exclusão: \(error.localizedDescription)")
            return
        }
        
        do {
            try context.save()
            print("Parcelamento completo excluído: \(idRecorrencia)")
        } catch {
            print("Erro ao salvar exclusão do parcelamento: \(error.localizedDescription)")
        }
    }
    
    // ======================================================
    // MARK: - Sincronização de Operações com Firestore
    // ======================================================
    // ------------------------------------------------------------
    // ✅ Correção aplicada: Agora a função busca operações do grupo compartilhado
    // ------------------------------------------------------------
    func sincronizarOperacoesComFirestore() async {
        syncStatus = .syncing
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            syncStatus = .failed
            syncError = "Erro: Usuário não autenticado."
            return
        }

        let userPath = "users/\(userId)/operations"
        let db = Firestore.firestore()

        do {
            // 🔹 1. Buscar operações individuais do usuário
            let userSnapshot = try await db.collection(userPath).getDocuments()
            for doc in userSnapshot.documents {
                await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: doc)
            }

            // 🔹 2. Buscar operações do grupo compartilhado
            let groupCodes = await buscarGruposDoUsuario(userId: userId)

            for groupCode in groupCodes {
                let groupSnapshot = try await db.collection("shared_groups").document(groupCode).collection("operations").getDocuments()
                for doc in groupSnapshot.documents {
                    await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: doc)
                }
            }

            syncStatus = .synced
            print("✅ Operações sincronizadas com sucesso!")

        } catch {
            print("❌ Erro ao sincronizar operações: \(error.localizedDescription)")
            syncStatus = .failed
            syncError = "Erro ao sincronizar operações."
        }
    }

    // ------------------------------------------------------------
    // ✅ Nova função para buscar os grupos do usuário
    // ------------------------------------------------------------
    func buscarGruposDoUsuario(userId: String) async -> [String] {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("shared_groups").whereField("participants", arrayContains: userId).getDocuments()
            return snapshot.documents.map { $0.documentID }
        } catch {
            print("❌ Erro ao buscar grupos do usuário: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Salvar Operação no Firestore (para grupos + user)
    @MainActor
    func salvarOperacaoNoFirestore(_ operacao: Operacao) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let dataOperacao: [String: Any] = [
            "id": operacao.id.uuidString,
            "nome": operacao.nome,
            "valor": operacao.valor,
            "data": operacao.data,
            "metodoPagamento": operacao.metodoPagamento,
            "recorrente": operacao.recorrente,
            "categoria": operacao.categoria ?? "",
            "nota": operacao.nota ?? "",
            "tipo": operacao.tipoString ?? "",
            "idRecorrencia": operacao.idRecorrencia?.uuidString ?? "",
            "numeroParcelas": operacao.numeroParcelas
        ]
        
        let db = Firestore.firestore()
        
        // Obtenha os grupos compartilhados de forma assíncrona:
        let grupos = await withCheckedContinuation { continuation in
            verificarGruposCompartilhados { groupCodes in
                continuation.resume(returning: groupCodes)
            }
        }
        
        if let grupos = grupos, !grupos.isEmpty {
            // Se estiver em grupo, grave somente nos grupos:
            for groupCode in grupos {
                let groupPath = "shared_groups/\(groupCode)/operations"
                do {
                    try await db.collection(groupPath).document(operacao.id.uuidString).setData(dataOperacao)
                    print("Operação \(operacao.nome) sincronizada no grupo \(groupCode).")
                } catch {
                    print("Erro ao salvar operação no grupo \(groupCode): \(error.localizedDescription)")
                }
            }
        } else {
            // Se não estiver em grupo, grave no caminho do usuário:
            let pathUser = "users/\(userId)/operations"
            do {
                try await db.collection(pathUser).document(operacao.id.uuidString).setData(dataOperacao)
                print("Operação \(operacao.nome) salva no Firestore do usuário.")
            } catch {
                print("Erro ao salvar operação no Firestore: \(error.localizedDescription)")
            }
        }
    }
    
    // ======================================================
    // MARK: - Funções Relacionadas a Recorrência
    // ======================================================
    func listarOperacoesRecorrentes() async {
        let opsRecorrentes = operacoes.filter { $0.recorrente }
        if opsRecorrentes.isEmpty {
            print("Nenhuma operação recorrente encontrada.")
        } else {
            print("Operações Recorrentes:")
            for op in opsRecorrentes {
                if let pd = op.recorrencia?.proximaData {
                    print(" - \(op.nome): Próxima Data - \(pd)")
                } else {
                    print(" - \(op.nome): Próxima Data - Não definida")
                }
            }
        }
    }
    
    func validarOperacoesRecorrentes() async {
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "recorrente == YES AND idRecorrencia == nil")
        
        do {
            let opsInvalidas = try context.fetch(fetchRequest)
            for op in opsInvalidas {
                op.idRecorrencia = UUID()
                if let rec = op.recorrencia {
                    rec.id = op.idRecorrencia!
                } else {
                    let novaRec = Recorrencia(
                        context: context,
                        tipo: "mensal",
                        intervalo: calcularIntervalo("mensal"),
                        dataInicial: op.data,
                        operacao: op
                    )
                    novaRec.id = op.idRecorrencia!
                    op.recorrencia = novaRec
                }
                print("Atualizada op recorrente \(op.nome) com IDRecorrencia: \(op.idRecorrencia!.uuidString)")
            }
            if !opsInvalidas.isEmpty {
                try context.save()
                print("Operações recorrentes inválidas atualizadas.")
            }
        } catch {
            print("Erro ao validar ops recorrentes: \(error.localizedDescription)")
        }
    }
    
    // ======================================================
    // MARK: - Cartões & Faturas (Exemplo de carregamento)
    // ======================================================
    func carregarCartoes() async -> [Cartao] {
        return await CoreDataManager.shared.fetchCartoesOrdenadosPorApelido()
    }
    
    @MainActor
    func salvarFaturaNoFirestore(_ fatura: Fatura) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ Erro: Usuário não autenticado.")
            return
        }

        let db = Firestore.firestore()
        let faturaData: [String: Any] = [
            "id": fatura.id.uuidString,
            "cartaoId": fatura.cartao?.id.uuidString ?? "",
            "valorTotal": fatura.valorTotal,
            "dataVencimento": fatura.dataVencimento,
            "dataInicio": fatura.dataInicio,
            "dataFechamento": fatura.dataFechamento
        ]

        let userPath = "users/\(userId)/bills"

        do {
            print("📢 Salvando fatura no Firestore: \(fatura.id.uuidString)")
            try await db.collection(userPath).document(fatura.id.uuidString).setData(faturaData)
            print("✅ Fatura \(fatura.id.uuidString) salva no Firestore.")
        } catch {
            print("❌ Erro ao salvar fatura no Firestore: \(error.localizedDescription)")
        }

        // 🔥 Sincronizar a fatura nos grupos compartilhados, se houver
        Task {
            let grupos = await withCheckedContinuation { continuation in
                verificarGruposCompartilhados { groupCodes in
                    continuation.resume(returning: groupCodes ?? [])
                }
            }
            if !grupos.isEmpty {
                for groupCode in grupos {
                    let groupPath = "shared_groups/\(groupCode)/bills"
                    do {
                        try await db.collection(groupPath).document(fatura.id.uuidString).setData(faturaData)
                        print("✅ Fatura \(fatura.id.uuidString) sincronizada no grupo \(groupCode).")
                    } catch {
                        print("❌ Erro ao salvar fatura no grupo \(groupCode): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: Excluir Fatura no Firestore
    @MainActor
    func excluirFaturaNoFirestore(_ fatura: Fatura) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        let path = "users/\(userId)/bills"
        do {
            try await Firestore.firestore().collection(path).document(fatura.id.uuidString).delete()
            print("Fatura excluída do Firestore.")
        } catch {
            print("Erro ao excluir fatura no Firestore: \(error.localizedDescription)")
        }
    }
    
    // ======================================================
    // MARK: - Métodos Auxiliares de UI (Ex.: handleHomeTap)
    // ======================================================
    func handleHomeTap() {
        let hoje = Date()
        if Calendar.current.isDate(mesAtual, equalTo: hoje, toGranularity: .month) {
            trazerDiaAtualParaTopo()
        } else {
            mesAtual = hoje
            trazerDiaAtualParaTopo()
        }
    }
    
    func trazerDiaAtualParaTopo() {
        let hoje = Date()
        if let index = saldosPorDia.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: hoje) }) {
            let itemAtual = saldosPorDia.remove(at: index)
            saldosPorDia.insert(itemAtual, at: 0)
            saldosPorDia = saldosPorDia // Force update
        }
    }
    
    func atualizarOperacao(_ operacao: Operacao) {
        do {
            if context.hasChanges {
                try context.save()
                print("Operação atualizada com sucesso!")
            }
        } catch {
            print("Erro ao atualizar a operação: \(error.localizedDescription)")
        }
    }
    
    // ======================================================
    // MARK: - Criação/Salvamento de Recorrência no Firestore
    // ======================================================
    private func salvarRecorrenciaNoFirestore(_ recorrencia: Recorrencia) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let recorrenciaData: [String: Any] = [
            "id": recorrencia.id.uuidString,
            "tipo": recorrencia.tipo,
            "intervalo": recorrencia.intervalo,
            "proximaData": recorrencia.proximaData
        ]
        
        let path = "users/\(userId)/recurrences"
        
        do {
            try await Firestore.firestore()
                .collection(path)
                .document(recorrencia.id.uuidString)
                .setData(recorrenciaData)
            print("Recorrência \(recorrencia.tipo) salva no Firestore.")
        } catch {
            print("Erro ao salvar recorrência no Firestore: \(error.localizedDescription)")
        }
    }
    
    func criarRecorrencia(
        tipo: String,
        intervalo: Int,
        dataInicial: Date,
        operacao: Operacao
    ) async {
        if let novaRec = await CoreDataManager.shared.criarRecorrencia(
            tipo: tipo,
            intervalo: intervalo,
            dataInicial: dataInicial,
            operacao: operacao
        ) {
            await salvarRecorrenciaNoFirestore(novaRec)
        }
    }
    
    // ======================================================
    // MARK: - Sincronização de Operações Compartilhadas
    // ======================================================
    func verificarGruposCompartilhados(completion: @escaping ([String]?) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(nil)
            return
        }
        db.collection("shared_groups")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Erro ao verificar grupos compartilhados: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    print("Nenhum grupo compartilhado encontrado.")
                    completion(nil)
                    return
                }
                let groupCodes = docs.map { $0.documentID }
                print("Grupos encontrados para o usuário: \(groupCodes)")
                completion(groupCodes)
            }
    }
    
    func sincronizarOperacoesCompartilhadas() async {
        verificarGruposCompartilhados { [weak self] groupCodes in
            guard let self = self, let gCodes = groupCodes else { return }
            
            for groupCode in gCodes {
                let db = Firestore.firestore()
                db.collection("shared_groups")
                    .document(groupCode)
                    .collection("operations")
                    .getDocuments { snapshot, error in
                        if let error = error {
                            print("Erro ao sincronizar operações (grupo \(groupCode)): \(error.localizedDescription)")
                            return
                        }
                        guard let docs = snapshot?.documents else { return }
                        
                        for doc in docs {
                            let data = doc.data()
                            let opId = UUID(uuidString: data["id"] as? String ?? "")
                            let nome = data["nome"] as? String ?? "Sem nome"
                            let valor = data["valor"] as? Double ?? 0.0
                            let dOp = (data["data"] as? Timestamp)?.dateValue() ?? Date()
                            let metodoPagamento = data["metodoPagamento"] as? String ?? "Outro"
                            
                            Task {
                                if let opId = opId {
                                    let existente = await CoreDataManager.shared.fetchOperacaoPorId(opId)
                                    if existente == nil {
                                        await CoreDataManager.shared.criarOperacao(
                                            nome: nome,
                                            valor: valor,
                                            data: dOp,
                                            metodoPagamento: metodoPagamento,
                                            recorrente: false
                                        )
                                    }
                                }
                            }
                        }
                    }
            }
        }
    }
    
    
    
    private func sincronizarAoIniciar() async {
        await sincronizarOperacoesComFirestore()
        await sincronizarOperacoesCompartilhadas()
    }
    
    // ======================================================
    // MARK: - Edição de Operação
    // ======================================================
    func editarOperacao(_ operacao: Operacao, novosDados: [String: Any]) async {
        for (chave, valor) in novosDados {
            operacao.setValue(valor, forKey: chave)
        }
        do {
            try context.save()
            print("Operação editada com sucesso: \(operacao.nome)")
            await salvarOperacaoNoFirestore(operacao)
            await atualizarSaldos()
            await carregarDados()
        } catch {
            print("Erro ao editar operação: \(error.localizedDescription)")
        }
    }
}

// ======================================================
// MARK: - Sincronização de Cartões (Globais @MainActor)
// ======================================================
@MainActor
func salvarCartaoNoFirestore(_ cartao: Cartao) async {
    guard let userId = Auth.auth().currentUser?.uid else {
        print("❌ Erro: Usuário não autenticado.")
        return
    }
    
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

    let db = Firestore.firestore()
    let userPath = "users/\(userId)/cards"
    
    do {
        try await db.collection(userPath).document(cartao.id.uuidString).setData(cartaoData)
        print("✅ Cartão \(cartao.nome) salvo no Firestore do usuário.")
    } catch {
        print("❌ Erro ao salvar cartão no Firestore: \(error.localizedDescription)")
    }
    
    verificarGruposCompartilhados { groupCodes in
        guard let gCodes = groupCodes else { return }
        for gCode in gCodes {
            let groupPath = "shared_groups/\(gCode)/cards"
            Task {
                do {
                    try await db.collection(groupPath).document(cartao.id.uuidString).setData(cartaoData)
                    print("✅ Cartão \(cartao.nome) sincronizado no grupo \(gCode).")
                } catch {
                    print("❌ Erro ao salvar cartão no grupo \(gCode): \(error.localizedDescription)")
                }
            }
        }
    }
}


// ------------------------------------------------------------
// ✅ Função para salvar operações no CoreData
// ------------------------------------------------------------
extension CoreDataManager {
    func salvarOperacoesNoCoreData(_ operacoes: [Operacao]) async {
        let context = persistentContainer.viewContext
        for operacao in operacoes {
            let db = Firestore.firestore()
            guard let userId = Auth.auth().currentUser?.uid else {
                print("Erro: Usuário não autenticado.")
                return
            }

            let collectionPath = "users/\(userId)/operations"
            do {
                let snapshot = try await Firestore.firestore().collection(collectionPath).getDocuments()
                for document in snapshot.documents {
                    await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: document)
                }
            } catch {
                print("Erro ao buscar documentos do Firestore: \(error.localizedDescription)")
            }

            do {
                let snapshot = try await db.collection(collectionPath).getDocuments()
                for document in snapshot.documents {
                    await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: document)
                }
            } catch {
                print("Erro ao buscar documentos do Firestore: \(error.localizedDescription)")
            }
        }
        salvarContexto()
    }
}

@MainActor
func excluirCartaoNoFirestore(_ cartao: Cartao) async {
    guard let userId = Auth.auth().currentUser?.uid else {
        print("Erro: Usuário não autenticado.")
        return
    }
    let path = "users/\(userId)/cards"
    do {
        try await Firestore.firestore().collection(path).document(cartao.id.uuidString).delete()
        print("Cartão \(cartao.nome) excluído do Firestore.")
    } catch {
        print("Erro ao excluir cartão no Firestore: \(error.localizedDescription)")
    }
}

// ======================================================
// MARK: - Sincronizar Fatura em Grupo (Global @MainActor)
// ======================================================
@MainActor
func sincronizarFaturaNoGrupo(_ fatura: Fatura, grupoId: String) async {
    let db = Firestore.firestore()
    let faturaData: [String: Any] = [
        "id": fatura.id.uuidString,
        "cartaoId": fatura.cartao?.id.uuidString ?? "",
        "valorTotal": fatura.valorTotal,
        "dataVencimento": fatura.dataVencimento
    ]
    let path = "shared_groups/\(grupoId)/bills"
    
    do {
        try await db.collection(path).document(fatura.id.uuidString).setData(faturaData)
        print("Fatura \(fatura.id.uuidString) sincronizada no grupo \(grupoId).")
    } catch {
        print("Erro ao sincronizar fatura no grupo \(grupoId): \(error.localizedDescription)")
    }
}

// ======================================================
// MARK: - Sincronizar Operação em Grupo (Global @MainActor)
// ======================================================
@MainActor
func sincronizarOperacaoNoGrupo(_ operacao: Operacao, grupoId: String) async {
    let db = Firestore.firestore()
    let opData: [String: Any] = [
        "id": operacao.id.uuidString,
        "nome": operacao.nome,
        "valor": operacao.valor,
        "data": operacao.data,
        "metodoPagamento": operacao.metodoPagamento,
        "recorrente": operacao.recorrente,
        "categoria": operacao.categoria ?? "",
        "nota": operacao.nota ?? "",
        "tipo": operacao.tipoString ?? "",
        "idRecorrencia": operacao.idRecorrencia?.uuidString ?? "",
        "numeroParcelas": operacao.numeroParcelas
    ]
    let path = "shared_groups/\(grupoId)/operations"
    
    do {
        try await db.collection(path).document(operacao.id.uuidString).setData(opData)
        print("Operação \(operacao.nome) sincronizada no grupo \(grupoId).")
    } catch {
        print("Erro ao sincronizar operação no grupo \(grupoId): \(error.localizedDescription)")
    }
}

// ======================================================
// MARK: - Struct Auxiliar DailyBalance (seu array de saldosPorDia usa isso)
// ======================================================
// (Assumindo que você já tenha algo como:)
public struct DailyBalance: Identifiable, Equatable {
    public var id: UUID = UUID()
    public var date: Date
    public var saldo: Double

    public init(date: Date, saldo: Double) {
        self.date = date
        self.saldo = saldo
    }

    // Implementação de Equatable para permitir comparação de arrays
    public static func == (lhs: DailyBalance, rhs: DailyBalance) -> Bool {
        return lhs.date == rhs.date && lhs.saldo == rhs.saldo
    }
}

// ======================================================
// MARK: - Fila de Sincronização (SyncQueue)
// ======================================================
@MainActor
final class SyncQueue {
    static let shared = SyncQueue()
    
    private var tasks: [() async -> Void] = []
    private var isProcessing: Bool = false
    
    private init() {}
    
    func addTask(_ task: @escaping () async -> Void) {
        tasks.append(task)
        processQueue()
    }
    
    func processQueue() {
        guard !isProcessing, !tasks.isEmpty else { return }
        isProcessing = true
        
        Task {
            while !tasks.isEmpty {
                let task = tasks.removeFirst()
                await task()
            }
            isProcessing = false
        }
    }
}

// ======================================================
// MARK: - Função Global para verif. grupos compartilhados
// ======================================================
func verificarGruposCompartilhados(completion: @escaping ([String]?) -> Void) {
    let db = Firestore.firestore()
    guard let userId = Auth.auth().currentUser?.uid else {
        print("Erro: Usuário não autenticado.")
        completion(nil)
        return
    }
    db.collection("shared_groups")
        .whereField("participants", arrayContains: userId)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao verificar grupos compartilhados: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let docs = snapshot?.documents, !docs.isEmpty else {
                print("Nenhum grupo compartilhado encontrado.")
                completion(nil)
                return
            }
            let groupCodes = docs.map { $0.documentID }
            print("Grupos encontrados para o usuário: \(groupCodes)")
            completion(groupCodes)
        }
}

// MARK: - Gerenciamento de Grupos Compartilhados

extension CoreDataManager {
    /// Remove o usuário do grupo compartilhado no Firestore
    func sairDoGrupoCompartilhado(grupoId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(false)
            return
        }

        let groupRef = db.collection("shared_groups").document(grupoId)

        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao buscar grupo compartilhado: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let document = document, document.exists else {
                print("Erro: Grupo não encontrado.")
                completion(false)
                return
            }

            groupRef.updateData([
                "participants": FieldValue.arrayRemove([userId])
            ]) { error in
                if let error = error {
                    print("Erro ao sair do grupo: \(error.localizedDescription)")
                    completion(false)
                } else {
                    // Força atualização no documento para disparar o listener
                    groupRef.updateData(["lastUpdate": FieldValue.serverTimestamp()]) { updateError in
                        if let updateError = updateError {
                            print("Erro ao atualizar lastUpdate: \(updateError.localizedDescription)")
                        } else {
                            print("Campo lastUpdate atualizado com sucesso.")
                        }
                        completion(true)
                    }
                }
            }
        }
    }
}


extension MoneyManager {
    func configurarListenerOperacoes() {
        // Certifique-se de que o usuário está autenticado:
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        // Adiciona o listener na coleção de operações do usuário:
        // Local: Dentro de MoneyManager.swift, função configurarListenerOperacoes()
        db.collection("users").document(userId).collection("operations")
            .addSnapshotListener { [weak self] snapshot, error in
                 if let error = error {
                     print("Erro no listener de operações: \(error.localizedDescription)")
                     return
                 }
                 guard let snapshot = snapshot else { return }
                 
                 for change in snapshot.documentChanges {
                     switch change.type {
                     case .added, .modified:
                         Task {
                             await CoreDataManager.shared.atualizarOuCriarOperacaoDeGrupo(doc: change.document)
                         }
                     case .removed:
                         Task {
                             await CoreDataManager.shared.removerOperacaoDoUsuario(doc: change.document)
                         }
                     }
                 }
                 // Opcionalmente, recarregue os dados
                 Task { await self?.carregarDados() }
            }
    }
}
