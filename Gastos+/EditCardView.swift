import SwiftUI


// Estrutura IdentifiableString (coloque isso no topo ou fora de qualquer struct)
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct EditCardView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var cardManager: CardManager
    var cartao: Cartao
    var onSave: (Cartao) -> Void
    
    @State private var nome: String
    @State private var limite: String
    @State private var taxaJuros: String
    @State private var dataFechamento: Date
    @State private var dataVencimento: Date
    @State private var isDefault: Bool
    @State private var mensagemErro: ErrorMessage?
    @State private var mensagemSucesso: String?
    @State private var mostrarCalendarioFechamento = false
    @State private var mostrarCalendarioVencimento = false
    @State private var mostrarFeedbackSucesso: Bool = false
    
    init(cardManager: CardManager, cartao: Cartao, onSave: @escaping (Cartao) -> Void) {
        self.cardManager = cardManager
        self.cartao = cartao
        self.onSave = onSave
        _nome = State(initialValue: cartao.nome)
        _limite = State(initialValue: cartao.limite > 0 ? cartao.limite.formatAsCurrency() : "")
        _taxaJuros = State(initialValue: cartao.taxaJuros > 0 ? formatarPercentual(String(format: "%.2f", cartao.taxaJuros * 100)) : "") // Removido o * 100
        _dataFechamento = State(initialValue: cartao.dataFechamento)
        _dataVencimento = State(initialValue: cartao.dataVencimento)
        _isDefault = State(initialValue: cartao.isDefault)
    }
    
    var body: some View {
        ZStack {
            Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all) // Fundo principal
            VStack(spacing: 0) {
                // Título principal com ícone
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.title)
                    Text("Editar Cartão")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "#2a2a2c"))
                .zIndex(1)
            
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Título Informações Básicas
                        // Títulos das Seções
                        Text("Informações Básicas")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "#D1D1D1"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 20)

                        // Contêiner 1: Informações Básicas
                        VStack(spacing: 16) {
                            // Campo Nome com Legenda
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nome")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "#B3B3B3"))
                                TextField("", text: $nome)
                                    .keyboardType(.default)
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                                    .placeholder(when: nome.isEmpty, alignment: .leading) {
                                        Text("Nome")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                if let mensagemErro = mensagemErro, mensagemErro.message.contains("nome") {
                                    Text(mensagemErro.message)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.top, 4)
                                }
                            }

                            // Campo Limite com Legenda
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Limite")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "#B3B3B3"))
                                TextField("", text: $limite)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                                    .placeholder(when: limite.isEmpty) {
                                        Text("Limite (opcional)")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .onChange(of: limite) { _, newValue in
                                        limite = formatarMoeda(newValue.normalizarNumero())
                                    }
                                if let mensagemErro = mensagemErro, mensagemErro.message.contains("limite") {
                                    Text(mensagemErro.message)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.top, 4)
                                }
                            }

                            // Campo Taxa de Juros com Legenda
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Taxa de Juros")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "#B3B3B3"))
                                TextField("", text: $taxaJuros)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                                    .placeholder(when: taxaJuros.isEmpty) {
                                        Text("Taxa de Juros (opcional)")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .onChange(of: taxaJuros) { _, newValue in
                                        taxaJuros = formatarPercentual(newValue.normalizarNumero())
                                    }
                                if let mensagemErro = mensagemErro, mensagemErro.message.contains("taxa de juros") {
                                    Text(mensagemErro.message)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.bottom, 10)

                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)

                        Text("Configurações de Pagamento")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "#D1D1D1"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 10)

                        // Configurações de Pagamento
                        VStack(spacing: 16) {
                            // Campo Vencimento
                            // 1. Dia de Vencimento
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Vencimento")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                Button(action: {
                                    withAnimation {
                                        mostrarCalendarioFechamento = false
                                        mostrarCalendarioVencimento.toggle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Text(dataVencimento.formatAsShortDate())
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(Color(hex: "#252527")) // Ajuste aplicado
                                    .cornerRadius(8)
                                }

                                if mostrarCalendarioVencimento {
                                    DatePicker(
                                        "",
                                        selection: $dataVencimento,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(GraphicalDatePickerStyle())
                                    .labelsHidden()
                                    .padding()
                                    .background(Color(hex: "#252527")) // Ajuste aplicado
                                    .cornerRadius(8)
                                    .colorScheme(.dark)
                                    .onChange(of: dataVencimento) { _ in
                                        withAnimation {
                                            mostrarCalendarioVencimento = false
                                        }
                                    }
                                }
                            }
                            
                            // 2. Dia de Fechamento
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Fechamento")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                
                                Button(action: {
                                    withAnimation {
                                        mostrarCalendarioVencimento = false
                                        mostrarCalendarioFechamento.toggle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.blue)
                                        Spacer()
                                        Text(dataFechamento.formatAsShortDate())
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(Color(hex: "#252527"))
                                    .cornerRadius(8)
                                }
                                
                                if mostrarCalendarioFechamento {
                                    DatePicker(
                                        "",
                                        selection: $dataFechamento,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(GraphicalDatePickerStyle())
                                    .labelsHidden()
                                    .padding()
                                    .background(Color(hex: "#252527"))
                                    .cornerRadius(8)
                                    .colorScheme(.dark)
                                    .onChange(of: dataFechamento) { _ in
                                        withAnimation {
                                            mostrarCalendarioFechamento = false
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)

                        // Toggle padrão – usando binding centralizado que lê de cartao.isDefault
                        Toggle("Definir como cartão padrão", isOn: Binding(
                            get: { cartao.isDefault },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        await cardManager.definirCartaoPadrao(cartao)
                                    }
                                } else {
                                    // Se for o único cartão, não permite desmarcar.
                                    if cardManager.cartoes.count == 1 {
                                        // Opcional: pode exibir um alerta ou simplesmente ignorar a tentativa
                                    } else {
                                        // Para múltiplos cartões, ignoramos a tentativa de desmarcar
                                        // (mantendo o cartão como padrão)
                                    }
                                }
                            }
                        ))
                        .padding(2)
                        .disabled(cardManager.cartoes.count == 1)
                    }
                    .padding()
                }
                .onAppear {
                    // Se houver apenas um cartão, força o toggle como true
                    if cardManager.cartoes.count == 1 {
                        isDefault = true
                    }
                }

                // Botão fixo no final da tela
                VStack {
                        HStack {
                            Button(action: salvarAlteracoes) {
                                Text("Salvar")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.green.opacity(0.9), Color.green.opacity(0.7)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                                    .shadow(color: Color.green.opacity(0.4), radius: 5, x: 0, y: 3)
                            }
                        }
                        .padding()
                        .background(Color(hex: "#2a2a2c"))
                    }
                }
                .overlay(
                    // Feedback visual
                    Group {
                        if mostrarFeedbackSucesso {
                            Text("Alterações salvas com sucesso!")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(8)
                                .shadow(radius: 5)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(1)
                                .padding(.top, 20)
                        }
                    },
                    alignment: .top
                )
            }
        }

    private func salvarAlteracoes() {
        guard validarDados() else { return }
        
        // Normaliza o valor de limite, removendo formatação e ajustando para o formato bruto
        let limiteNumerico = Double(limite.normalizarNumero()) ?? 0.0
        print("Valor normalizado do limite:", limiteNumerico)
        
        cartao.nome = nome
        cartao.apelido = nome // Sincroniza apelido com o nome
        cartao.limite = limiteNumerico / 100 // Divide por 100 para salvar o valor correto no Core Data
        print("Valor final salvo para limite:", cartao.limite)
        
        // Processa taxa de juros
        let taxaNumerica = Double(taxaJuros.normalizarNumero()) ?? 0.0
        cartao.taxaJuros = taxaNumerica / 10000 // Divide por 100 para converter de porcentagem para decimal
        
        cartao.dataFechamento = dataFechamento
        cartao.dataVencimento = dataVencimento
        cartao.isDefault = isDefault
        
        onSave(cartao)
        mensagemSucesso = "Cartão atualizado com sucesso!"
        
        // Exibir feedback visual
        withAnimation {
            mostrarFeedbackSucesso = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                mostrarFeedbackSucesso = false
            }
        }

        presentationMode.wrappedValue.dismiss()
    }
        
    private func desativarCartao() {
        Task {
            do {
                try await cardManager.desativarCartao(cartao)
                mensagemSucesso = "Cartão desativado com sucesso."
                presentationMode.wrappedValue.dismiss()
            } catch {
                mensagemErro = ErrorMessage(message: "Erro ao desativar o cartão: \(error.localizedDescription)")
            }
        }
    }
        
        private func validarDados() -> Bool {
            guard !nome.isEmpty else {
                mensagemErro = ErrorMessage(message: "O nome não pode estar vazio.")
                return false
            }
            
            guard limite.isEmpty || Double(limite.normalizarNumero()) != nil else {
                mensagemErro = ErrorMessage(message: "Por favor, insira um limite válido.")
                return false
            }
            
            guard taxaJuros.isEmpty || Double(taxaJuros.normalizarNumero()) != nil else {
                mensagemErro = ErrorMessage(message: "Por favor, insira uma taxa de juros válida.")
                return false
            }
            
            return true
        }
    }

// MARK: - CustomTextField
struct CustomTextField: View {
    var title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 14, weight: .semibold)) // Texto do input
                .foregroundColor(Color(hex: "#B3B3B3")) // Cor secundária
            TextField("", text: $text)
                .padding()
                .keyboardType(keyboardType)
                .background(Color(hex: "#2b2b2d")) // Fundo do input
                .cornerRadius(8)
                .foregroundColor(Color(hex: "#FFFFFF")) // Texto primário
        }
    }
}

// MARK: - CustomDatePicker
struct CustomDatePicker: View {
    var title: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 14, weight: .semibold)) // Texto do date picker
                .foregroundColor(Color(hex: "#B3B3B3")) // Cor secundária
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .padding()
                .background(Color(hex: "#2b2b2d")) // Fundo do date picker
                .cornerRadius(8)
        }
    }
}

/*
struct EditCardView_Previews: PreviewProvider {
    static var previews: some View {
        let exemploCartao = Cartao(
            context: CoreDataManager.shared.context,
            nome: "Cartão Exemplo",
            limite: 5000.0,
            dataFechamento: Date(),
            dataVencimento: Date(),
            isDefault: false,
            bandeira: "Visa",
            numero: "1234 5678 9012 3456",
            taxaJuros: 0.035,
            apelido: "Meu Cartão",
            ativo: true
        )
        
        return EditCardView(
            cardManager: CardManager.shared,
            cartao: exemploCartao,
            onSave: { _ in }
        )
        .environmentObject(CardManager.shared)
        .previewLayout(.device)
        .preferredColorScheme(.dark)
    }
}
*/
