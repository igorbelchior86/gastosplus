import SwiftUI

// MARK: - Estrutura para Mensagem de Erro (caso não esteja em outro arquivo)
struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}

struct AddCardView: View {
    @EnvironmentObject var moneyManager: MoneyManager
    @EnvironmentObject var cardManager: CardManager

    @Environment(\.presentationMode) var presentationMode

    // MARK: - Estados e propriedades
    @State private var numeroCartao: String = ""
    @State private var bandeiraCartao: String? = nil
    @State private var logoBandeira: UIImage? = nil
    @State private var apelido: String = ""
    @State private var limite: String = ""
    @State private var taxaJuros: String = ""
    @State private var dataFechamento: Date = Date()
    @State private var dataVencimento: Date = Date()
    @State private var isDefault: Bool = false
    @State private var mostrarCalendarioVencimento = false
    @State private var mostrarCalendarioFechamento = false
    @State private var mensagemErro: ErrorMessage? = nil
    @State private var desativarBotaoPadrao: Bool = false

    @FocusState private var isValorFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // ---------------------------------------
                // Header (cabeçalho)
                // ---------------------------------------
                headerView
                
                // ---------------------------------------
                // Conteúdo rolável
                // ---------------------------------------
                ScrollView {
                    VStack(spacing: 24) {
                        informacoesBasicasSection
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                        configuracoesPagamentoSection
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                        outrosSection
                    }
                    .padding()
                }
                .background(Color(hex: "#2a2a2c"))
                
                // ---------------------------------------
                // Botão "Salvar"
                // ---------------------------------------
                salvarButton
            }
            .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
            .onAppear {
         //       setupKeyboardObserver()
                verificarPrimeiroCartao()
         //       iniciarAlternanciaDeTexto()
            }
            .onDisappear {
          //      removeKeyboardObserver()
            }
            .alert(item: $mensagemErro) { erro in
                Alert(
                    title: Text("Erro"),
                    message: Text(erro.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Subviews
    
    // -----------------------------------------------------
    // 1) Cabeçalho
    // -----------------------------------------------------
    private var headerView: some View {
        HStack {
            if let logoBandeira = logoBandeira {
                Image(uiImage: logoBandeira)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 30)
                    .padding(.trailing, 8)
            } else {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.trailing, 8)
            }
            Text("Adicionar Cartão")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#2a2a2c"))
    }
    
    // -----------------------------------------------------
    // 2) Seção "Informações Básicas"
    // -----------------------------------------------------
    private var informacoesBasicasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Informações Básicas")
                .font(.headline)
                .foregroundColor(Color(hex: "#B3B3B3"))
                .padding(.bottom, 8)
            
            TextField("", text: $numeroCartao)
                .keyboardType(.numberPad)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .placeholder(when: numeroCartao.isEmpty, alignment: .trailing, padding: 12) {
                    Text("Digite o número do cartão")
                        .foregroundColor(Color.gray.opacity(0.6))
                        .padding(.trailing, 6)
                }
                .onChange(of: numeroCartao) { newValue in
                    formatarNumeroCartao(&numeroCartao)
                    identificarBandeira()
                    
                    if numeroCartao.count < 2 {
                        mensagemErro = nil
                        return
                    }
                    
                    if numeroCartao.isEmpty {
                        mensagemErro = nil
                    } else if bandeiraCartao == nil {
                        mensagemErro = ErrorMessage(message: "Bandeira do cartão não reconhecida.")
                    } else {
                        mensagemErro = nil
                    }
                }

            if let mensagemErro = mensagemErro {
                Text(mensagemErro.message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding(2)
    }
    
    // -----------------------------------------------------
    // 3) Seção "Configurações de Pagamento"
    // -----------------------------------------------------
    private var configuracoesPagamentoSection: some View {
        VStack(spacing: 16) {
            // Título da seção
            Text("Detalhes de Pagamento")
                .font(.headline)
                .foregroundColor(Color(hex: "#B3B3B3"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            
            // 1. Dia de Vencimento
            VStack(alignment: .leading, spacing: 8) {
                Text("Vencimento")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Button(action: {
                    withAnimation {
                        mostrarCalendarioFechamento = false
                        mostrarCalendarioVencimento.toggle()
                        if mostrarCalendarioVencimento {
                            // Adiciona uma pequena pausa para garantir que a view esteja atualizada
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollTo("vencimento-expanded")
                            }
                        }
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
                    .background(Color(hex: "#252527"))
                    .cornerRadius(8)
                }
                .id("vencimento-expanded") // Adiciona ID

                if mostrarCalendarioVencimento {
                    DatePicker(
                        "",
                        selection: $dataVencimento,
                        displayedComponents: .date
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .labelsHidden()
                    .padding()
                    .background(Color(hex: "#252527"))
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
                        if mostrarCalendarioFechamento {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollTo("fechamento-expanded")
                            }
                        }
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
                .id("fechamento-expanded") // Adiciona ID

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

            // 3. Campos Limite e Taxa de Juros
            TextField("", text: $limite)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .placeholder(when: limite.isEmpty, alignment: .trailing, padding: 12) {
                    Text("Limite")
                        .foregroundColor(Color.gray.opacity(0.6))
                        .padding(.trailing, 6)
                }
                .onChange(of: limite) { newValue in
                    limite = formatarMoeda(newValue.normalizarNumero())
                }

            TextField("", text: $taxaJuros)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .placeholder(when: taxaJuros.isEmpty, alignment: .trailing, padding: 12) {
                    Text("Taxa de Juros")
                        .foregroundColor(Color.gray.opacity(0.6))
                        .padding(.trailing, 6)
                }
                .onChange(of: taxaJuros) { newValue in
                    taxaJuros = formatarPercentual(newValue.normalizarNumero())
                }
        }
    }
    
    // -----------------------------------------------------
    // 4) Seção "Outros"
    // -----------------------------------------------------
    private var outrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outros")
                .font(.headline)
                .foregroundColor(Color(hex: "#B3B3B3"))
                .padding(.bottom, 8)
            
            TextField("", text: $apelido)
                .padding(.horizontal, 16)
                .frame(height: 56) // Define a altura fixa
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .placeholder(when: apelido.isEmpty, alignment: .trailing, padding: 12) {
                    Text("Digite o apelido (opcional)")
                        .foregroundColor(Color.gray.opacity(0.6))
                        .padding(.trailing, 6)
                }
                .onChange(of: apelido) { newValue in
                    apelido = String(newValue.prefix(25)) // Limita a 25 caracteres
                }
            
            // Toggle para "Definir como cartão padrão"
            Toggle("Definir como cartão padrão", isOn: Binding(
                get: { desativarBotaoPadrao ? true : isDefault },
                set: { newValue in
                    if !desativarBotaoPadrao {
                        isDefault = newValue
                    }
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .padding(.top, 8)
            .foregroundColor(.white)
            .disabled(desativarBotaoPadrao)
        }
        .padding(2)
        .onAppear {
            Task {
                let primeiroCartao = await CoreDataManager.shared.verificarSePrimeiroCartao()
                print("É o primeiro cartão? \(primeiroCartao)")
                if primeiroCartao {
                    // Se não houver nenhum cartão, força o padrão e desativa o toggle
                    DispatchQueue.main.async {
                        isDefault = true
                        desativarBotaoPadrao = true
                    }
                }
            }
        }
        .onChange(of: cardManager.cartoes) { newCards in
            // Sempre que a lista de cartões for atualizada, se estiver vazia, forçamos isDefault = true e travamos o toggle.
            if newCards.isEmpty {
                isDefault = true
                desativarBotaoPadrao = true
            }
        }
    }
    
    private var salvarButton: some View {
        Button(action: salvarCartao) {
            Text("Salvar")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .cornerRadius(8)
                .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .padding(16)
    }
    
    // MARK: - Funções Auxiliares
    
    /// Verifica se é o primeiro cartão e atualiza os estados
    private func verificarPrimeiroCartao() {
        Task {
            let primeiroCartao = await CoreDataManager.shared.verificarSePrimeiroCartao()
            print("É o primeiro cartão? \(primeiroCartao)")
            if primeiroCartao {
                DispatchQueue.main.async {
                    isDefault = true
                    desativarBotaoPadrao = true
                }
            }
        }
    }
    
    /// Detecta bandeira do cartão baseado no prefixo do número
    private func identificarBandeira() {
        if numeroCartao.hasPrefix("4") {
            bandeiraCartao = "Visa"
            logoBandeira = UIImage(named: "visa")
        } else if numeroCartao.hasPrefix("5") {
            bandeiraCartao = "MasterCard"
            logoBandeira = UIImage(named: "mastercard")
        } else if numeroCartao.hasPrefix("34") || numeroCartao.hasPrefix("37") {
            bandeiraCartao = "Amex"
            logoBandeira = UIImage(named: "amex")
        } else {
            bandeiraCartao = nil
            logoBandeira = nil
        }
    }
    
    /// Salva o cartão chamando o CardManager (Core Data)
    private func salvarCartao() {
        // Validação: Número do cartão
        guard !numeroCartao.isEmpty else {
            mensagemErro = ErrorMessage(message: "O número do cartão é obrigatório.")
            return
        }

        // Validação: Limite
        let limiteNumerico = Double(limite.normalizarNumero()) ?? 0
        guard limiteNumerico > 0 else {
            mensagemErro = ErrorMessage(message: "O limite deve ser maior que 0.")
            return
        }

        // Validação: Taxa de Juros
        let taxaNumerica = Double(taxaJuros.normalizarNumero()) ?? 0
        guard taxaNumerica > 0 else {
            mensagemErro = ErrorMessage(message: "A taxa de juros deve ser maior que 0.")
            return
        }

        /*
        // Validação: Datas
        guard dataVencimento > Date() else {
            mensagemErro = ErrorMessage(message: "A data de vencimento deve ser no futuro.")
            return
        }

        guard dataFechamento > Date() else {
            mensagemErro = ErrorMessage(message: "A data de fechamento deve ser no futuro.")
            return
        }
        */

        Task {
            await CardManager.shared.criarCartaoESincronizar(
                nome: apelido.isEmpty ? (bandeiraCartao ?? "Sem Nome") : apelido,
                numero: numeroCartao,
                bandeira: bandeiraCartao,
                dataVencimento: dataVencimento,
                dataFechamento: dataFechamento,
                limite: limiteNumerico / 100, // Dividimos por 100 para corrigir o limite
                taxaJuros: taxaNumerica / 10000, // Dividimos por 10000 para corrigir o formato de juros
                apelido: apelido.isEmpty ? (bandeiraCartao ?? "Sem Nome") : apelido,
                isDefault: isDefault
            )
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    /// Formata o número do cartão com espaços (Ex: Visa: 4-4-4-4, Amex: 4-6-5)
    private func formatarNumeroCartao(_ numero: inout String) {
        // Remove tudo que não seja número
        numero = numero.filter { $0.isNumber }
        
        // Define o limite baseado na bandeira
        let limite = bandeiraCartao == "Amex" ? 15 : 16
        if numero.count > limite {
            numero = String(numero.prefix(limite))
        }
        
        // Aplica máscara
        if bandeiraCartao == "Amex" {
            // Formato Amex: 4-6-5
            numero = numero.chunked(by: [4, 6, 5]).joined(separator: " ")
        } else {
            // Outros: formato 4-4-4-4
            numero = numero.chunked(by: [4, 4, 4, 4]).joined(separator: " ")
        }
    }
    
    /// Rolagem para uma seção específica usando ScrollViewReader
    private func scrollTo(_ id: String) {
        // Implementação depende de onde o ScrollViewReader está presente.
        // Se necessário, passe um proxy ou utilize um @State para identificar a rolagem.
        // Neste exemplo, estamos assumindo que há uma forma de acessar o proxy.
    }
}

/*
struct AddCardView_Previews: PreviewProvider {
    static var previews: some View {
        AddCardView()
            .environmentObject(MoneyManager.shared) // Certifique-se de que MoneyManager está configurado corretamente
            .environmentObject(CardManager.shared) // Certifique-se de que CardManager está configurado corretamente
            .previewLayout(.device)
            .preferredColorScheme(.dark) // Define o tema dark
    }
}
*/
