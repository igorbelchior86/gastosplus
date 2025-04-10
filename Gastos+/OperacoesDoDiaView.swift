import SwiftUI
import Foundation
import Lottie


// MARK: - LottieView
struct LottieView: UIViewRepresentable {
    var name: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> some UIView {
        let view = UIView(frame: .zero)
        let animationView = LottieAnimationView(name: name)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.play()

        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor),
            animationView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {}
}

// MARK: - Shimmer Modifier
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .foregroundColor(Color.white.opacity(0.3)) // Cor base do texto
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.6), Color.clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .rotationEffect(.degrees(30)) // Rotaciona para um efeito diagonal
                    .frame(width: geometry.size.width * 2, height: geometry.size.height)
                    .offset(x: phase * geometry.size.width)
                    .animation(Animation.linear(duration: 4.0).repeatForever(autoreverses: false), value: phase)
                }
            )
            .mask(content.foregroundColor(.white)) // Aplica a máscara para revelar apenas o brilho
            .onAppear {
                phase = 2.0 // Inicia a animação
            }
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(Shimmer())
    }
}

// MARK: - ShimmeringTextView Utilizando o Modifier
struct ShimmeringTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(nil) // Permite múltiplas linhas
            .shimmer() // Aplica o efeito de shimmer
            .fixedSize(horizontal: false, vertical: true) // Permite expansão vertical
            .frame(maxWidth: .infinity) // Ocupa a largura máxima disponível
            .padding(.horizontal) // Adiciona padding horizontal para evitar que o texto toque as bordas
    }
}

// MARK: - OperacoesDoDiaView
struct OperacoesDoDiaView: View {
    let data: Date
    let cartoes: [Cartao]
    
    @State private var activeMenuId: UUID? = nil
    @State private var mostrandoNovaOperacao = false
    @State private var isFaturasExpanded: Bool = false
    
    @State private var operacoesDinheiro: [Operacao] = []
    @State private var operacoesCartao: [Operacao] = []
    @State private var faturas: [Fatura] = []
    
    @State private var isDinheiroExpanded: Bool = false
    @State private var isCartaoExpanded: Bool = false
    
    @State private var showingEditView = false
    @State private var showingDeleteOptions = false
    @State private var currentOperacao: Operacao? = nil
    @State private var selectedOperacao: Operacao? = nil
    @State private var faturasFiltradas: [Fatura] = []
    
    @State private var editScope: EditScope? = nil
    @Environment(\.managedObjectContext) private var contexto
    
    @EnvironmentObject var moneyManager: MoneyManager
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(hex: "#2A2A2C").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Verifica se há operações antes de exibir o cabeçalho
                    if !operacoesDinheiro.isEmpty || !operacoesCartao.isEmpty || !faturas.isEmpty {
                        saudacaoSection
                            .padding(.bottom, 8)
                    }
                    
                    if operacoesDinheiro.isEmpty && operacoesCartao.isEmpty && faturas.isEmpty {
                        estadoVazioView
                            .padding(.top, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            listaOperacoes
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    carregarDados()
                    
                    // Buscar faturas filtradas
                    let faturas = await filtrarFaturasDoDia(data: data)
                    await MainActor.run {
                        faturasFiltradas = faturas
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didUpdateData)) { _ in
                Task {
                    // Recarrega as operações do dia e as faturas
                    carregarDados()
                    let novasFaturas = await filtrarFaturasDoDia(data: data)
                    await MainActor.run {
                        faturasFiltradas = novasFaturas
                    }
                }
            }
            .sheet(isPresented: $mostrandoNovaOperacao) {
                NovaOperacaoView(defaultDate: data)
            }
            .sheet(item: $currentOperacao) { operacaoParaEditar in
                EditarOperacaoView(
                    operacao: Binding(
                        get: { operacaoParaEditar },
                        set: { updatedOperacao in
                            // Atualiza arrays locais
                            if let index = operacoesDinheiro.firstIndex(where: { $0.id == updatedOperacao.id }) {
                                operacoesDinheiro[index] = updatedOperacao
                            } else if let index = operacoesCartao.firstIndex(where: { $0.id == updatedOperacao.id }) {
                                operacoesCartao[index] = updatedOperacao
                            }
                            // Atualiza também via moneyManager
                            moneyManager.atualizarOperacao(updatedOperacao)
                        }
                    )
                )
                .environmentObject(moneyManager)
                .environmentObject(CardManager.shared)
            }
        }
        .confirmationDialog("Excluir Operação", isPresented: $showingDeleteOptions) {
            if let operacao = selectedOperacao {
                switch operacao.tipoOperacao {
                case .unica, .despesa, .receita:
                    Button("Excluir esta operação", role: .destructive) {
                        removerOperacao(operacao)
                    }
                case .recorrente:
                    Button("Somente esta operação", role: .destructive) {
                        removerOperacao(operacao)
                    }
                    Button("Esta e futuras operações", role: .destructive) {
                        removerOperacaoFuturas(operacao)
                    }
                    Button("Toda a série", role: .destructive) {
                        removerTodasOperacoes(operacao)
                    }
                case .parcelada:
                    Button("Remover esta parcela", role: .destructive) {
                        removerOperacao(operacao)
                    }
                    Button("Esta e futuras parcelas", role: .destructive) {
                        removerOperacaoFuturas(operacao)
                    }
                    Button("Todo o parcelamento", role: .destructive) {
                        removerTodasOperacoes(operacao)
                    }
                case .desconhecido:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
    
    // MARK: - Estado Vazio Corrigido
    private var estadoVazioView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Lottie Animation
            LottieView(name: "empty-wallet", loopMode: .loop)
                .frame(width: 150, height: 150)

            // Mensagem Principal Dinâmica
            ShimmeringTextView(text: mensagemPrincipalVazio())

            // Botão
            Button(action: {
                mostrandoNovaOperacao = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(Color(hex: "#00CFFF"))
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Lógica Dinâmica para Mensagem Principal
    private func mensagemPrincipalVazio() -> String {
        let hora = Calendar.current.component(.hour, from: Date())
        
        let mensagensManha = [
            "Bom dia! Nada foi lançado ainda.",
            "Amanheceu e suas finanças estão vazias. Vamos adicionar algo?",
            "Comece o dia organizando suas despesas!",
            "Nada registrado ainda. Que tal iniciar o dia com planejamento?"
        ]
        
        let mensagensTarde = [
            "Boa tarde! Nenhuma operação foi encontrada.",
            "Nada por aqui ainda. Que tal adicionar algo à tarde?",
            "Suas finanças estão vazias por enquanto. Vamos mudar isso?",
            "Boa tarde! Registre uma despesa ou receita para continuar."
        ]
        
        let mensagensNoite = [
            "Boa noite! Ainda não há operações hoje.",
            "Final do dia sem registros. Que tal adicionar uma operação?",
            "Suas finanças do dia estão vazias. Vamos organizar antes de dormir?",
            "Boa noite! Nenhuma operação registrada. Planeje o dia amanhã!"
        ]
        
        let mensagensMadrugada = [
            "Bem-vindo à madrugada! Nenhuma operação foi lançada.",
            "Ainda acordado? Que tal adicionar suas finanças agora?",
            "Planeje agora para garantir um dia mais tranquilo amanhã.",
            "Nenhuma operação por enquanto. Vamos ajustar suas finanças?"
        ]
        
        // Seleciona o conjunto de mensagens com base no horário
        let mensagensSelecionadas: [String]
        switch hora {
        case 5..<12:
            mensagensSelecionadas = mensagensManha
        case 12..<18:
            mensagensSelecionadas = mensagensTarde
        case 18..<22:
            mensagensSelecionadas = mensagensNoite
        default:
            mensagensSelecionadas = mensagensMadrugada
        }
        
        // Retorna uma mensagem aleatória
        return mensagensSelecionadas.randomElement() ?? "Nenhuma operação encontrada. Vamos começar?"
    }
    
    // MARK: - Lista de Operações
    private var listaOperacoes: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Seção de Dinheiro
                if !operacoesDinheiro.isEmpty {
                    VStack(spacing: 0) {
                        CollapsibleHeader(
                            title: "💵 Dinheiro",
                            total: operacoesDinheiro.reduce(0.0, { $0 + $1.valor }),
                            isExpanded: $isDinheiroExpanded,
                            onToggle: {
                                withAnimation {
                                    activeMenuId = nil // Fecha qualquer menu ativo
                                }
                            }
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color(hex: "#2A2A2C"))
                        .zIndex(isDinheiroExpanded ? 1 : 0)
                        
                        if isDinheiroExpanded {
                            VStack(spacing: 16) {
                                ForEach(operacoesDinheiro, id: \.id) { operacao in
                                    OperacaoRowView(
                                        operacao: operacao,
                                        exibirHorario: true,
                                        activeMenuId: $activeMenuId,
                                        onEdit: { op in
                                            currentOperacao = op
                                        },
                                        onDelete: { op in
                                            selectedOperacao = op
                                            showingDeleteOptions = true
                                        }
                                    )
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 10)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: isDinheiroExpanded)
                }
                
                // Seção de Cartão
                if !operacoesCartao.isEmpty {
                    VStack(spacing: 0) {
                        CollapsibleHeader(
                            title: "💳 Cartão",
                            total: operacoesCartao.reduce(0.0, { $0 + $1.valor }),
                            isExpanded: $isCartaoExpanded,
                            onToggle: {
                                withAnimation {
                                    activeMenuId = nil // Fecha qualquer menu ativo
                                }
                            }
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color(hex: "#2A2A2C"))
                        .zIndex(isCartaoExpanded ? 1 : 0)
                        
                        if isCartaoExpanded {
                            VStack(spacing: 16) {
                                ForEach(operacoesCartao.sorted { $0.data > $1.data }, id: \.id) { operacao in
                                    OperacaoRowView(
                                        operacao: operacao,
                                        exibirHorario: true,
                                        activeMenuId: $activeMenuId,
                                        onEdit: { op in
                                            currentOperacao = op
                                        },
                                        onDelete: { op in
                                            selectedOperacao = op
                                            showingDeleteOptions = true
                                        }
                                    )
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 10)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: isCartaoExpanded)
                }
                
                // Seção de Faturas
                if !faturasFiltradas.isEmpty {
                    VStack(spacing: 0) {
                        Text("📋 Faturas")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(Color(hex: "#2A2A2C"))
                            .zIndex(1)
                        
                        ForEach(faturasFiltradas, id: \.id) { fatura in
                            FaturaCollapsibleView(fatura: fatura)
                                .listRowBackground(Color(hex: "#2A2A2C"))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
            .background(Color(hex: "#2A2A2C")) // Fundo uniforme
        }
        .onTapGesture {
            withAnimation {
                activeMenuId = nil // Fecha qualquer menu de reação ativo
            }
        }
        .clipped(antialiased: false)
        .background(Color(hex: "#2A2A2C").ignoresSafeArea())
        .animation(.easeInOut, value: isDinheiroExpanded) // Animação suave ao expandir/retrair
        .animation(.easeInOut, value: isCartaoExpanded)
        .animation(.easeInOut, value: isFaturasExpanded)
        /*
        .sheet(isPresented: $showingEditView) {
            if let operacaoParaEditar = currentOperacao {
                EditarOperacaoView(
                    operacao: Binding(
                        get: { operacaoParaEditar },
                        set: { updatedOperacao in
                            if let index = operacoesDinheiro.firstIndex(where: { $0.id == updatedOperacao.id }) {
                                operacoesDinheiro[index] = updatedOperacao
                            } else if let index = operacoesCartao.firstIndex(where: { $0.id == updatedOperacao.id }) {
                                operacoesCartao[index] = updatedOperacao
                            }
                            // Atualize também no `moneyManager`
                            moneyManager.atualizarOperacao(updatedOperacao)
                        }
                    )
                )
                .environmentObject(moneyManager)
                .environmentObject(CardManager.shared)
            } else {
                Text("Operação inválida")
                    .foregroundColor(.red)
                    .font(.headline)
            }
        }
        */
    }
    
    // SaudacaoSection ajustado
    private var saudacaoSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // Lottie Animation
                LottieView(name: lottieNameForTime(), loopMode: .loop)
                    .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    // Saudação Dinâmica
                    ShimmeringTextView(text: saudacaoDinamica())
                        .font(.title3)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "#2A2A2C"))
            .cornerRadius(8)
            
            // Divider entre a saudação e a data
            Divider()
                .background(Color(hex: "#3e3e40"))
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 10)

            // Data já existente ajustada aqui
            HStack {
                Text(data, formatter: fullDateFormatterPT)
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func lottieNameForTime() -> String {
        let hora = Calendar.current.component(.hour, from: Date())
        switch hora {
        case 5..<12: return "sun-rise"
        case 12..<18: return "sun-shine"
        case 18..<22: return "sunset"
        default: return "night"
        }
    }

    private func saudacaoDinamica() -> String {
        let hora = Calendar.current.component(.hour, from: Date())
        switch hora {
        case 5..<12: return "Bom dia!"
        case 12..<18: return "Boa tarde!"
        case 18..<22: return "Boa noite!"
        default: return "Bem-vindo à madrugada!"
        }
    }

    private func dataFormatada() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, dd 'de' MMMM 'de' yyyy"
        return formatter.string(from: Date()).capitalized
    }
    
    struct SaudacaoDinamicaView: View {
        @State private var saudacaoPrincipal: String = ""
        @State private var mensagemSecundaria: String = ""
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Saudação Principal
                        Text(saudacaoPrincipal)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
                        
                        // Mensagem Secundária
                        Text(mensagemSecundaria)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(hex: "#B3B3B3"))
                            .lineSpacing(4)
                    }
                    
                    Spacer()
                    
                    /*
                    // Ícone Dinâmico
                    Image(systemName: saudacaoIcone())
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(Color(hex: "#00CFFF"))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                     */
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                atualizarSaudacao()
            }
        }
        
        /*
        private func saudacaoIcone() -> String {
            let hora = Calendar.current.component(.hour, from: Date())
            switch hora {
            case 5..<12: return "sunrise.fill"
            case 12..<18: return "sun.max.fill"
            case 18..<22: return "moon.stars.fill"
            default: return "moon.fill"
            }
        }
         */
        
        private func atualizarSaudacao() {
            let hora = Calendar.current.component(.hour, from: Date())
            
            let saudacoesManha = [
                "Bom dia!", "Bom dia! Que tal começar o dia organizando suas finanças?",
                "Amanheceu! Vamos revisar suas operações?", "Comece o dia com planejamento!"
            ]
            
            let saudacoesTarde = [
                "Boa tarde!", "Boa tarde! Como estão suas operações?",
                "Que tal organizar agora para relaxar depois?", "Boa tarde! Ajuste seu orçamento!"
            ]
            
            let saudacoesNoite = [
                "Boa noite!", "Finalize seu dia com planejamento e organização.",
                "Hora de se preparar para um amanhã ainda melhor.", "Revisar hoje, dormir tranquilo amanhã."
            ]
            
            let saudacoesMadrugada = [
                "Bem-vindo à madrugada!", "Ainda acordado? Hora de revisar suas finanças.",
                "Planeje agora para um dia melhor amanhã!", "Organização nunca dorme!"
            ]
            
            let saudacoesSelecionadas: [String]
            switch hora {
            case 5..<12:
                saudacoesSelecionadas = saudacoesManha
            case 12..<18:
                saudacoesSelecionadas = saudacoesTarde
            case 18..<22:
                saudacoesSelecionadas = saudacoesNoite
            default:
                saudacoesSelecionadas = saudacoesMadrugada
            }
            
            saudacaoPrincipal = saudacoesSelecionadas.randomElement() ?? "Bem-vindo!"
            mensagemSecundaria = "Pronto para organizar suas finanças de hoje?"
        }
    }
    
    private var operacoesDinheiroSection: some View {
        Section {
            CollapsibleHeader(
                title: "💵 Dinheiro",
                total: operacoesDinheiro.reduce(0.0, { $0 + $1.valor }),
                isExpanded: $isDinheiroExpanded
            )
            .listRowBackground(Color(hex: "#2A2A2C"))
            
            if isDinheiroExpanded {
                // Ajustar para usar id: \.id
                ForEach(operacoesDinheiro.sorted { $0.data > $1.data }, id: \.id) { operacao in
                    OperacaoRowView(
                        operacao: operacao,
                        exibirHorario: true,
                        activeMenuId: $activeMenuId // Passa o binding para o activeMenuId
                    )
                    .listRowBackground(Color(hex: "#2A2A2C"))
                }
            }
        }
    }
    
    private var operacoesCartaoSection: some View {
        Section {
            CollapsibleHeader(
                title: "💳 Cartão",
                total: operacoesCartao.reduce(0.0, { $0 + $1.valor }),
                isExpanded: $isCartaoExpanded
            )
            .listRowBackground(Color(hex: "#2A2A2C"))
            
            if isCartaoExpanded {
                // Ajustar para usar id: \.id
                ForEach(operacoesCartao.sorted { $0.data > $1.data }, id: \.id) { operacao in
                    OperacaoRowView(
                        operacao: operacao,
                        exibirHorario: true,
                        activeMenuId: $activeMenuId // Passa o binding para o activeMenuId
                    )
                    .listRowBackground(Color(hex: "#2A2A2C"))
                }
            }
        }
    }
    
    private var faturasSection: some View {
        Section {
            // Já está usando id: \.id
            ForEach(faturas, id: \.id) { fatura in
                FaturaCollapsibleView(fatura: fatura)
                    .listRowBackground(Color(hex: "#2A2A2C"))
            }
        }
    }
    
    // MARK: - Botões de Exclusão
    private var botoesExclusao: some View {
        Group {
            if let operacao = selectedOperacao {
                switch operacao.tipoOperacao {
                case .unica:
                    Button("Excluir esta operação", role: .destructive) {
                        removerOperacao(operacao)
                    }
                case .recorrente:
                    Button("Somente esta operação", role: .destructive) {
                        removerOperacao(operacao)
                    }
                    Button("Esta e futuras operações", role: .destructive) {
                        removerOperacaoFuturas(operacao)
                    }
                    Button("Toda a série", role: .destructive) {
                        removerTodasOperacoes(operacao)
                    }
                case .parcelada:
                    Button("Remover esta parcela", role: .destructive) {
                        removerOperacao(operacao)
                    }
                    Button("Esta e futuras parcelas", role: .destructive) {
                        removerOperacaoFuturas(operacao)
                    }
                    Button("Todo o parcelamento", role: .destructive) {
                        removerTodasOperacoes(operacao)
                    }
                case .desconhecido:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
            Button("Cancelar", role: .cancel) { }
        }
    }
    
    // MARK: - Funções Auxiliares
    private func obterSaudacao() -> String {
        let hora = Calendar.current.component(.hour, from: Date())
        
        // Frases organizadas por bloco de horário
        let frasesManha = [
            "Bom dia! Que tal começar o dia organizando suas finanças?",
            "🌅 Amanheceu! Vamos revisar suas operações?",
            "Comece o dia com planejamento! Pronto para organizar suas despesas?",
            "Bom dia! Hoje é um ótimo dia para atingir suas metas financeiras.",
            "Hora de começar o dia com foco e organização!"
        ]
        
        let frasesTarde = [
            "Boa tarde! Como estão suas operações até agora?",
            "☀️ Que tal dar uma olhada no que foi registrado hoje?",
            "Organizar agora significa menos preocupação depois!",
            "Pronto para revisar suas finanças da tarde?",
            "Boa tarde! Um pequeno esforço agora, grandes resultados depois."
        ]
        
        let frasesNoite = [
            "Boa noite! Vamos revisar o que aconteceu hoje?",
            "🌙 Hora de se preparar para um amanhã ainda melhor.",
            "Finalize seu dia com planejamento e organização.",
            "Pronto para revisar as operações de hoje?",
            "Uma noite tranquila começa com finanças organizadas!"
        ]
        
        let frasesMadrugada = [
            "🌌 Bem-vindo à madrugada! Que tal revisar suas finanças?",
            "Ainda acordado? Vamos dar uma olhada nas suas operações.",
            "Planejar agora garante um amanhã mais tranquilo.",
            "Organizar suas despesas agora pode ajudar a clarear a mente.",
            "🌠 Noite produtiva começa com finanças organizadas."
        ]
        
        // Seleciona o conjunto de frases com base no horário
        let frasesSelecionadas: [String]
        switch hora {
        case 5..<12:
            frasesSelecionadas = frasesManha
        case 12..<18:
            frasesSelecionadas = frasesTarde
        case 18..<22:
            frasesSelecionadas = frasesNoite
        default:
            frasesSelecionadas = frasesMadrugada
        }
        
        // Retorna uma frase aleatória
        return frasesSelecionadas.randomElement() ?? "Bem-vindo! Pronto para organizar suas finanças?"
    }
    
    private func carregarDados() {
        Task {
            let todasOperacoes = await MoneyManager.shared.buscarOperacoesDoDia(data: data)
            operacoesDinheiro = todasOperacoes.filter { $0.metodoPagamento == "Dinheiro" }
            operacoesCartao = todasOperacoes.filter { $0.metodoPagamento == "Cartão" }
            faturas = await filtrarFaturasDoDia(data: data)
        }
    }
    
    private func atualizarOperacao(_ operacao: Operacao) {
        if let index = operacoesDinheiro.firstIndex(where: { $0.id == operacao.id }) {
            operacoesDinheiro[index] = operacao
        } else if let index = operacoesCartao.firstIndex(where: { $0.id == operacao.id }) {
            operacoesCartao[index] = operacao
        }
        currentOperacao = operacao
    }
    
    private func filtrarFaturasDoDia(data: Date) async -> [Fatura] {
        return await CardManager.shared.buscarFaturasFiltradas()
            .filter { Calendar.current.isDate($0.dataVencimento, inSameDayAs: data) }
    }
    
    // ---- CORREÇÃO PRINCIPAL: REMOÇÃO LOCAL ANTES/DEPOIS DE CHAMAR O MONEYMANAGER ----
    /// Exclui apenas esta operação (não recorrente OU uma única ocorrência da recorrência).
    private func removerOperacao(_ operacao: Operacao) {
        Task {
            // 1. Remove imediatamente do array local (para o SwiftUI parar de exibir)
            await MainActor.run {
                self.operacoesDinheiro.removeAll { $0.id == operacao.id }
                self.operacoesCartao.removeAll  { $0.id == operacao.id }
            }

            // 2. Exclui do Core Data via MoneyManager
            await moneyManager.excluirOperacaoUnica(operacao)

            // 3. Recarrega os dados para refletir alterações
            await moneyManager.carregarDados()
            await MainActor.run {
                self.carregarDados() // método local que repopula operacoesDinheiro e operacoesCartao
            }
        }
    }

    /// Exclui esta operação e TODAS as futuras ligadas à mesma recorrência a partir da data desta.
    private func removerOperacaoFuturas(_ operacao: Operacao) {
        Task {
            guard let idRecorrencia = operacao.idRecorrencia else { return }

            // 1. Remove do array local tudo que pertence à mesma recorrência e data >= desta
            await MainActor.run {
                self.operacoesDinheiro.removeAll {
                    $0.idRecorrencia == idRecorrencia && $0.data >= operacao.data
                }
                self.operacoesCartao.removeAll {
                    $0.idRecorrencia == idRecorrencia && $0.data >= operacao.data
                }
            }

            // 2. Exclui do Core Data
            await moneyManager.excluirOperacoesFuturas(
                idRecorrencia: idRecorrencia,
                dataReferencia: operacao.data
            )

            // 3. Recarrega os dados
            await moneyManager.carregarDados()
            await MainActor.run {
                self.carregarDados()
            }
        }
    }

    /// Exclui TODA a série (operação original + futuras + passadas) vinculada a essa recorrência.
    private func removerTodasOperacoes(_ operacao: Operacao) {
        Task {
            guard let idRecorrencia = operacao.idRecorrencia else { return }

            // 1. Remove do array local todas as operações que tenham o mesmo idRecorrencia
            await MainActor.run {
                self.operacoesDinheiro.removeAll { $0.idRecorrencia == idRecorrencia }
                self.operacoesCartao.removeAll    { $0.idRecorrencia == idRecorrencia }
            }

            // 2. Exclui do Core Data a série completa
            await moneyManager.excluirSerieRecorrente(idRecorrencia: idRecorrencia)

            // 3. Recarrega os dados
            await moneyManager.carregarDados()
            await MainActor.run {
                self.carregarDados()
            }
        }
    }
}

// MARK: - CollapsibleHeader
struct CollapsibleHeader: View {
    let title: String
    let total: Double
    @Binding var isExpanded: Bool
    var onToggle: (() -> Void)? = nil // Novo callback para reagir ao toggle

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isExpanded.toggle()
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                onToggle?() // Chama o callback ao expandir/fechar
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Total: \(total.formatAsCurrency())")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.blue)
                    .animation(.easeInOut, value: isExpanded)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.gray.opacity(0.2))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - EditScopeSelectionView
struct EditScopeSelectionView: View {
    var onSelect: (EditScope) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Escolha como deseja editar a operação")
                .font(.headline)
                .padding()
            
            ForEach(EditScope.allCases) { scope in
                Button(action: {
                    onSelect(scope)
                }) {
                    Text(scope.rawValue)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            
            Button(action: {
                onSelect(.single)
            }) {
                Text("Cancelar")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(15)
        .padding()
    }
}

// MARK: - FaturaCollapsibleView
struct FaturaCollapsibleView: View {
    let fatura: Fatura
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // CollapsibleHeader para a fatura
            CollapsibleHeader(
                title: "Fatura - \(fatura.cartao?.nome ?? "Cartão")",
                total: fatura.valorTotal,
                isExpanded: $isExpanded
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                Color(hex: "#2A2A2C") // Fundo uniforme
            )
            .zIndex(isExpanded ? 1 : 0)

            // Conteúdo das operações dentro da fatura
            if isExpanded {
                VStack(spacing: 8) {
                    if let operacoes = fatura.operacoes, !operacoes.isEmpty {
                        ForEach(Array(operacoes).sorted(by: { $0.data > $1.data }), id: \.id) { operacao in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(operacao.nome)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text("Horário: \(operacao.data, formatter: timeFormatter)")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#B3B3B3"))
                                }
                                Spacer()
                                Text(operacao.valor.formatAsCurrency())
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(operacao.valor >= 0 ? Color(hex: "#00FF00") : Color(hex: "#FF0000"))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#3E3E40")) // Fundo uniforme como o header
                                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4) // Sombra sutil
                            )
                        }
                    } else {
                        Text("Nenhuma operação associada.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .offset(y: isExpanded ? 0 : -100) // Subitens começam fora da viewport
                .opacity(isExpanded ? 1 : 0)     // Subitens começam invisíveis
                .animation(.easeInOut(duration: 0.35), value: isExpanded) // Animação suave
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isExpanded)
        .padding(.vertical, 5)
    }
}

// MARK: - OperacaoRowView (Menu Acima do Item)
struct OperacaoRowView: View {
    let operacao: Operacao
    let exibirHorario: Bool
    
    @Binding var activeMenuId: UUID? // Novo binding
    
    var onEdit: ((Operacao) -> Void)? = nil
    var onDelete: ((Operacao) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack {
                            Text(operacao.nome)
                                .font(.body)
                                .foregroundColor(.white)
                            
                            if operacao.tipoOperacao == .recorrente {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.blue)
                                    .padding(.leading, 4)
                            } else if operacao.tipoOperacao == .parcelada {
                                Text("Parcelada")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                            }
                            
                            Spacer()
                        }
                        Spacer()
                        Text(operacao.valor.formatAsCurrency())
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(operacao.valor >= 0 ? .green : .red)
                    }
                    if exibirHorario {
                        Text("Horário: \(operacao.data, formatter: timeFormatter)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Data: \(operacao.data, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#3E3E40"))
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4)
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        activeMenuId = operacao.id // Ativa o menu para este item
                    }
                }
                .onLongPressGesture(minimumDuration: 0.3) { // Tempo customizado (0.8 segundos neste caso)
                    withAnimation {
                        activeMenuId = operacao.id // Ativa o menu para este item
                    }
                }
                
                // Menu de Reação
                if activeMenuId == operacao.id { // Mostra menu apenas se for o item ativo
                    menuReacao
                        .zIndex(9999)
                        .offset(x: 8, y: -geometry.size.height * 0.6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(minHeight: 50)
    }
    
    // MARK: - Menu de Reação (Pill-shaped com Haptic Feedback)
    private var menuReacao: some View {
        HStack(spacing: 16) {
            Button {
                onEdit?(operacao) // Chama a closure para iniciar o processo de edição
                withAnimation {
                    activeMenuId = nil // Fecha o menu
                }
            } label: {
                Image(systemName: "pencil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.blue))
            }
            
            Button {
                onDelete?(operacao)
                withAnimation {
                    activeMenuId = nil // Fecha o menu
                }
            } label: {
                Image(systemName: "trash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.red))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(hex: "#3E3E40")) // Fundo do menu
        )
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4) // Sombra para destaque
        .onAppear {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity)) // Animação suave
    }
}

// MARK: - EditScope Enum
enum EditScope: String, CaseIterable, Identifiable {
    case single = "Somente essa"
    case future = "Essa e futuras"
    case all = "Todas"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .single:
            return "Somente esta operação será editada."
        case .future:
            return "Esta e todas as futuras operações serão editadas."
        case .all:
            return "Todas as ocorrências serão editadas."
        }
    }
}

// MARK: - Formatadores (sem extensões)
private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "pt_BR")
    formatter.dateFormat = "dd 'de' MMMM 'de' yyyy"
    return formatter
}()

private let fullDateFormatterPT: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "pt_BR")
    formatter.dateFormat = "EEEE, dd 'de' MMMM 'de' yyyy"
    return formatter
}()


/*
// MARK: - Preview
struct OperacoesDoDiaView_Previews: PreviewProvider {
    static var previews: some View {
        OperacoesDoDiaView(
            data: Date(),
            cartoes: [] // Forneça um array vazio ou dados fictícios, se necessário
        )
        .environmentObject(MoneyManager.shared) // Certifique-se de configurar corretamente
        .preferredColorScheme(.dark) // Garante o tema dark
    }
}
*/
