import SwiftUI
import CoreData
import Foundation

enum Screen {
    case home
    case profile
}

struct DiaSelecionado: Identifiable {
    let id = UUID()
    let data: Date
}

struct MainView: View {
    @EnvironmentObject var moneyManager: MoneyManager
    @EnvironmentObject var cardManager: CardManager
    
    @Binding var isLoggedIn: Bool // Recebe o binding

    @State private var mostrandoNovaOperacao = false
    @State private var mostrandoDetalhesCartao = false
    @State private var mostrandoCartoesView = false
    @State private var diaSelecionado: DiaSelecionado?
    @State private var currentScreen: Screen = .home // Nova propriedade de estado
    @State private var faturasPorDia: [Date: [Fatura]] = [:]

    @State private var deslocamentoSwipe: CGFloat = 0.0
    @State private var direcaoBloqueada: Axis? = nil
    @State private var scrollingDisabled = false
    @State private var mainActiveAlert: MainActiveAlert?

    enum MainActiveAlert: Identifiable {
        case syncError(String)
        var id: String {
            switch self {
            case .syncError(let msg):
                return msg
            }
        }
    }

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        return calendar
    }
    
    // <-- NOVA PROPRIEDADE COMPUTADA para verificar se o FaceID está ativado
    private var isFaceIDEnabled: Bool {
        if let usuario = CoreDataManager.shared.fetchUsuarioAtual() {
            return usuario.usarFaceID
        }
        return false
    }
    
    // -----------------------------------------------
    // MARK: - Body
    // -----------------------------------------------
    var body: some View {
        // 1) We wrap the main content in a simpler container:
        //    A plain 'NavigationView' with no big chain of modifiers.
        NavigationView {
            mainZStack
        }
        .onReceive(NotificationCenter.default.publisher(for: .faceIDDidAuthenticate)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    self.currentScreen = .home
                }
            }
        }
        // 2) Then apply your side-effect modifiers here, so we don't chain them onto the large ZStack:
        .onChange(of: moneyManager.syncError) { newError in
            if moneyManager.syncStatus == .failed, let newError {
                mainActiveAlert = .syncError(newError)
            }
        }
        .alert(item: $mainActiveAlert) { alertCase in
            switch alertCase {
            case .syncError(let message):
                return Alert(
                    title: Text("Erro de Sincronização"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $mostrandoNovaOperacao) {
            NovaOperacaoView(defaultDate: Date())
        }
        .sheet(item: $diaSelecionado) { diaSelecionado in
            // Exibe a tela de operações do dia
            OperacoesDoDiaView(data: diaSelecionado.data, cartoes: cardManager.cartoes)
        }
        .onAppear {
            Task {
                // Sincroniza Firestore e carrega dados
                await moneyManager.sincronizarOperacoesComFirestore()
                await atualizarDados()
                await atualizarFaturasPorDia()
                // Adicione a configuração do listener:
                moneyManager.configurarListenerOperacoes()
            }
            // Observa mudanças no CoreData e recarrega faturas
            NotificationCenter.default.addObserver(
                forName: .didUpdateData,
                object: nil,
                queue: .main
            ) { _ in
                Task {
                    await atualizarFaturasPorDia()
                }
            }
        }
        .onReceive(moneyManager.$saldosPorDia) { _ in
            // Força a atualização das faturas por dia sempre que os saldos forem alterados
            Task {
                await atualizarFaturasPorDia()
            }
        }
        .onChange(of: cardManager.cartoes) { _ in
            Task {
                print("🔄 Recebido evento de atualização. Recarregando faturas...")
                await atualizarFaturasPorDia()
            }
        }
        .navigationBarHidden(true)
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .sheet(isPresented: Binding(
            get: { !isLoggedIn && !isFaceIDEnabled },
            set: { _ in }
        )) {
            // Tente obter o usuário atual e o PIN salvo:
            if let usuario = CoreDataManager.shared.fetchUsuarioAtual(),
               let pin = usuario.pin, !pin.isEmpty {
                PinEntryView(isLoggedIn: $isLoggedIn, authState: .constant(.pin), pinSalvo: pin)
            } else {
                PinSetupView(isLoggedIn: $isLoggedIn, authState: .constant(.pinSetup))
            }
        }
    }
    
    
    // -----------------------------------------------
    // MARK: - mainZStack
    // -----------------------------------------------
    /// This is the ZStack(alignment: .top) part of your original code,
    /// but *without* the `.onChange`, `.alert`, `.sheet`, etc. chaining.
    private var mainZStack: some View {
        ZStack(alignment: .top) {
            
            // Se estiver sincronizando, mostra o spinner.
            if moneyManager.syncStatus == .syncing {
                VStack {
                    ProgressView("Sincronizando...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(Color(hex: "#252527"))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
                .zIndex(1)
            }
            
            // O "conteúdo principal" que muda conforme currentScreen
            mainContent
            
            // Mostra o cabeçalho somente se na Home
            if currentScreen == .home {
                homeHeader
            }
            
            // FooterView no rodapé
            footer
        }
    }

    // -----------------------------------------------
    // MARK: - mainContent (Switch para Home/Profile)
    // -----------------------------------------------
    private var mainContent: AnyView {
        switch currentScreen {
        case .home:
            return AnyView(homeContent)
        case .profile:
            return AnyView(profileContent)
        }
    }
    
    // -----------------------------------------------
    // MARK: - sub-View: Home
    // -----------------------------------------------
    private var homeContent: some View {
        homeView
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.easeInOut(duration: 0.3), value: currentScreen)
            .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
            .scrollDisabled(scrollingDisabled)
            .offset(x: direcaoBloqueada == .horizontal ? deslocamentoSwipe : 0)
            .gesture(dragGesture)
    }

    // -----------------------------------------------
    // MARK: - sub-View: Profile
    // -----------------------------------------------
    private var profileContent: some View {
        ProfileView(isLoggedIn: $isLoggedIn)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.easeInOut(duration: 0.3), value: currentScreen)
            .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
    }

    // -----------------------------------------------
    // MARK: - HomeView Principal
    // -----------------------------------------------
    private var homeView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // espaço top
                    Spacer().frame(height: 220)
                    
                    // Lista dos DailyBalance
                    ForEach(sortedSaldosPorDia) { dailyBalance in
                        let dataInicioDoDia = calendar.startOfDay(for: dailyBalance.date)
                        let faturasDoDia = faturasPorDia[dataInicioDoDia] ?? []
                        
                        DiaView(
                            date: dailyBalance.date,
                            saldoDoDia: dailyBalance.saldo,
                            operacoesDoDia: filtrarOperacoesDoDia(data: dailyBalance.date),
                            faturasDoDia: faturasDoDia,
                            isHoje: isHoje(date: dailyBalance.date),
                            feedbackGenerator: feedbackGenerator,
                            abrirDetalhesDoDia: abrirDetalhesDoDia
                        )
                        .padding(.horizontal, 16)
                        .id(isHoje(date: dailyBalance.date) ? "hoje" : nil)
                        .task {
                            debugFaturasParaData(dataInicioDoDia)
                        }
                    }
                    
                    Spacer().frame(height: 80)
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .onChange(of: moneyManager.saldosPorDia) { _ in
                withAnimation {
                    proxy.scrollTo("header", anchor: .top)
                }
            }
        }
    }
    
    private var sortedSaldosPorDia: [DailyBalance] {
        moneyManager.saldosPorDia.sorted { $0.date < $1.date }
    }

    private func isHoje(date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    // -----------------------------------------------
    // MARK: - Home Header
    // -----------------------------------------------
    private var homeHeader: some View {
        VStack(spacing: 0) {
            // 1) HeaderView
            HeaderView(
                mesAtual: $moneyManager.mesAtual,
                onAddCard: { mostrandoCartoesView = true }
            )
            .sheet(isPresented: $mostrandoCartoesView) {
                AllCardsView()
            }
            .padding(.top, 16)
            .background(Color(hex: "#2a2a2c"))
            
            // 2) CombinedCardView
            CombinedCardView(
                mesAtual: $moneyManager.mesAtual,
                saldoDoDia: $moneyManager.saldoDoDia,
                saldoFinal: .constant(moneyManager.saldosPorDia.last?.saldo ?? 0),
                saldosPorDia: $moneyManager.saldosPorDia
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            
            // 3) Títulos de colunas
            HStack {
                Text("Dia")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Descrição")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Text("Saldo")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .id("header")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "#2a2a2c"))
        }
        .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.top))
    }

    // -----------------------------------------------
    // MARK: - Footer
    // -----------------------------------------------
    private var footer: some View {
        VStack {
            Spacer()
            FooterView(
                currentScreen: $currentScreen,
                moneyManager: moneyManager,
                onAddOperation: { mostrandoNovaOperacao = true }
            )
            .background(Color(hex: "#2a2a2c"))
        }
    }

    // -----------------------------------------------
    // MARK: - Drag Gesture (Swipes para Avançar/Voltar mês)
    // -----------------------------------------------
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                if direcaoBloqueada == nil {
                    if abs(gesture.translation.width) > abs(gesture.translation.height) {
                        direcaoBloqueada = .horizontal
                        scrollingDisabled = true
                    } else {
                        direcaoBloqueada = .vertical
                        scrollingDisabled = false
                    }
                }
                if direcaoBloqueada == .horizontal {
                    deslocamentoSwipe = gesture.translation.width / 2
                }
            }
            .onEnded { gesture in
                if direcaoBloqueada == .horizontal {
                    if gesture.translation.width < -50 {
                        avancarMes()
                    } else if gesture.translation.width > 50 {
                        retrocederMes()
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        deslocamentoSwipe = 0
                    }
                }
                direcaoBloqueada = nil
                scrollingDisabled = false
            }
    }

    // -----------------------------------------------
    // MARK: - Funções Auxiliares
    // -----------------------------------------------
    private func atualizarDados() async {
        await moneyManager.carregarDados()
        await cardManager.carregarCartoes()
        feedbackGenerator.impactOccurred()
    }

    private func avancarMes() {
        if let novoMes = calendar.date(byAdding: .month, value: 1, to: moneyManager.mesAtual) {
            moneyManager.mesAtual = novoMes
            feedbackGenerator.impactOccurred()
        }
    }

    private func retrocederMes() {
        if let novoMes = calendar.date(byAdding: .month, value: -1, to: moneyManager.mesAtual) {
            moneyManager.mesAtual = novoMes
            feedbackGenerator.impactOccurred()
        }
    }

    private func abrirDetalhesDoDia(_ data: Date) {
        diaSelecionado = DiaSelecionado(data: data)
    }

    private func filtrarOperacoesDoDia(data: Date) -> [Operacao] {
        moneyManager.operacoes.compactMap { operacao in
            // Se o objeto foi deletado, retorna nil
            guard !operacao.isDeleted else { return nil }
            // Tente obter a data
            if let opData = operacao.value(forKey: "data") as? Date,
               calendar.isDate(opData, inSameDayAs: data) {
                return operacao
            }
            return nil
        }
        .sorted { (op1, op2) in
            let d1 = op1.value(forKey: "data") as? Date ?? Date()
            let d2 = op2.value(forKey: "data") as? Date ?? Date()
            return d1 > d2
        }
    }

    private func debugFaturasParaData(_ dataInicioDoDia: Date) {
        // Executa em background
        DispatchQueue.global(qos: .background).async {
            print("🔍 Acessando faturas para a data \(dataInicioDoDia)")
            
            if let faturasEncontradas = faturasPorDia[dataInicioDoDia] {
                print("✅ Faturas encontradas: \(faturasEncontradas.count)")
            } else {
                print("❌ Nenhuma fatura encontrada para \(dataInicioDoDia)")
            }
        }
    }

    // -----------------------------------------------
    // MARK: - Atualizar Faturas por Dia
    // -----------------------------------------------
    private func atualizarFaturasPorDia() async {
        let faturas = await cardManager.buscarFaturasFiltradas()
        await MainActor.run {
            // Agrupa as faturas pela data de vencimento (startOfDay)
            faturasPorDia = Dictionary(grouping: faturas) { fatura in
                calendar.startOfDay(for: fatura.dataVencimento)
            }

            // Imprime debug sem usar interpolação com aspas conflitantes
            print("📌 Faturas agrupadas por data:")
            for (data, faturas) in faturasPorDia {
                let faturasStrings = faturas.map { fatura -> String in
                    let nomeCartao = fatura.cartao?.nome ?? "Sem Nome"
                    let valor = fatura.valorTotal
                    return "\(nomeCartao) - \(valor)"
                }
                print("📅 Data: \(data), 🧾 Faturas: \(faturasStrings)")
            }
        }
    }
}

// ------------------------------------------------------
// MARK: - DiaView (igual ao seu, sem mudar nada)
// ------------------------------------------------------
struct DiaView: View {
    let date: Date
    let saldoDoDia: Double
    let operacoesDoDia: [Operacao]
    let faturasDoDia: [Fatura]
    let isHoje: Bool
    let feedbackGenerator: UIImpactFeedbackGenerator
    let abrirDetalhesDoDia: (Date) -> Void

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        return calendar
    }

    var body: some View {
        let dia = calendar.component(.day, from: date)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                diaView(dia: dia, isHoje: isHoje)
                descricaoView(operacoesDoDia: operacoesDoDia, faturasDoDia: faturasDoDia)
                saldoView(saldoDoDia: saldoDoDia)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isHoje ? Color.cyan.opacity(0.15) : Color(hex: "#3e3e40"))
                    if isHoje {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                    }
                }
            )
            .shadow(color: isHoje ? Color.cyan.opacity(0.3) : Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .onTapGesture {
                feedbackGenerator.impactOccurred()
                abrirDetalhesDoDia(date)
            }
            .onLongPressGesture {
                feedbackGenerator.impactOccurred()
                abrirDetalhesDoDia(date)
            }
        }
    }

    private func diaView(dia: Int, isHoje: Bool) -> some View {
        VStack(spacing: 4) {
            Text("\(dia)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(isHoje ? Color.cyan : .white)
            Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                .font(.caption)
                .foregroundColor(Color(hex: "#B3B3B3"))
        }
        .frame(width: 50, alignment: .center)
    }

    private func descricaoView(operacoesDoDia: [Operacao], faturasDoDia: [Fatura]) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Mostra até 2 operações
                    ForEach(operacoesDoDia.prefix(2), id: \.id) { operacao in
                        HStack(spacing: 4) {
                            Image(systemName: operacao.valor >= 0 ? "dollarsign.circle.fill" : "creditcard")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.white)
                            Text(operacao.nome)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            operacao.valor >= 0
                                ? Color(hex: "#4CAF50")
                                : Color(hex: "#FF6B6B")
                        )
                        .cornerRadius(8)
                    }

                    // Se tem mais que 2 ops, exibe "+ x mais"
                    if operacoesDoDia.count > 2 {
                        Text("+ \(operacoesDoDia.count - 2) mais")
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#B3B3B3"))
                    }

                    // Exibe as faturas do dia
                    ForEach(faturasDoDia, id: \.id) { fatura in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.white)
                            Text("Fatura - \(fatura.cartao?.nome ?? "Cartão")")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            fatura.valorTotal > 0
                                ? Color(hex: "#FFC107")
                                : Color.gray.opacity(0.7)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func saldoView(saldoDoDia: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("R$")
                .font(.footnote)
                .foregroundColor(saldoDoDia >= 0 ? Color.green : Color.red)
            Text(saldoDoDia.formatAsCurrency().replacingOccurrences(of: "R$", with: ""))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(saldoDoDia >= 0 ? Color.green : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .truncationMode(.tail)
        }
        .frame(width: 100, alignment: .trailing)
    }
    
    // Preview corrigido
    struct MainView_Previews: PreviewProvider {
        static var previews: some View {
            StatefulPreviewWrapper(false) { isLoggedIn in
                MainView(isLoggedIn: isLoggedIn)
                    .environment(\.managedObjectContext, CoreDataManager.shared.context)
                    .environmentObject(MoneyManager.shared)
                    .environmentObject(CardManager.shared)
            }
        }
    }

    /// Wrapper para permitir usar @Binding em Previews
    struct StatefulPreviewWrapper<Value>: View {
        @State private var value: Value
        let content: (Binding<Value>) ->  AnyView
        
        init(_ initialValue: Value, _ content: @escaping (Binding<Value>) -> some View) {
            self._value = State(initialValue: initialValue)
            self.content = { AnyView(content($0)) }
        }
        
        var body: some View {
            content($value)
        }
    }
}
