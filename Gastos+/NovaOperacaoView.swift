import SwiftUI


struct NovaOperacaoView: View {
    
    let defaultDate: Date
    
    @EnvironmentObject var moneyManager: MoneyManager
    @EnvironmentObject var cardManager: CardManager

    @Environment(\.presentationMode) var presentationMode

    // MARK: - Estados Locais
    @State private var valorStr: String = ""
    @State private var descricao: String = ""
//    @State private var data: Date = Date()
    @State private var data: Date
    @State private var ehDespesa: Bool = true
    @State private var metodoPagamento: String = "Dinheiro"
    @State private var cartaoSelecionado: Cartao? = nil
    @State private var keyboardHeight: CGFloat = 0

    @State private var mostrarSelecaoRecorrencia: Bool = false
    @State private var mostrarCalendario: Bool = false
    @State private var mostrarSelecaoCartoes: Bool = false

    @State private var tipoRecorrencia: String = "Nunca"
    private let opcoesRecorrencia: [String] = ["Nunca", "Diária", "Semanal", "Quinzenal", "Mensal", "Anual"]

    // Alertas
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Focos
    @FocusState private var isValorFocused: Bool
    @FocusState private var isDescricaoFocused: Bool

    // Estilos e placeholders
    private let cardBackground = Color(hex: "#252527")
    private let groupPadding: CGFloat = 12
    private let cornerRadius: CGFloat = 8

    // Alternância de texto
    @State private var alternarTextoCartao = "Cartão"
    @State private var opacidadeTextoCartao = 1.0
    private let textosAlternativosCartao = ["Cartão", "Crédito"]

    @State private var alternarTextoDinheiro = "Dinheiro"
    @State private var opacidadeTexto = 1.0
    private let textosAlternativosDinheiro = ["Dinheiro", "Pix", "Débito"]

    // Parcelamento
    @State private var isParcelado: Bool = false
    @State private var showParceladoToggle: Bool = false
    @State private var numeroParcelas: Int = 2
    @State private var mostrarSelecaoParcelamento: Bool = false

    @State private var focoScroll: String? = nil
    
    init(defaultDate: Date) {
        self.defaultDate = defaultDate
        _data = State(initialValue: defaultDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        primeiroGrupo
                            .id("detalhes") // Define um ID para rolar automaticamente para esta seção
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                        metodoPagamentoSection
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                        if isParcelado {
                            parcelamentoSection
                                .id("parcelamento")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            recorrenciaSection
                                .id("recorrencia")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 16)
    //                .padding(.bottom, keyboardHeight) // Ajusta com base na altura do teclado
                    .onAppear {
                        setupKeyboardObserver()
                        // Garante o foco no campo valor e exibe o título corretamente
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isValorFocused = true
                            withAnimation {
                                proxy.scrollTo("detalhes", anchor: .top) // Rola para o título "Detalhes"
                            }
                        }
                        iniciarAlternanciaDeTexto()
                    }
                    .onDisappear {
                        removeKeyboardObserver()
                    }
                }
                
                // 1st Instance
                .onChange(of: mostrarSelecaoRecorrencia) { oldValue, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                proxy.scrollTo("recorrencia-expanded", anchor: .top)
                            }
                        }
                    }
                }

                // 2nd Instance
                .onChange(of: mostrarCalendario) { oldValue, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                proxy.scrollTo("calendario-expanded", anchor: .top)
                            }
                        }
                    }
                }

                // 3rd Instance
                .onChange(of: mostrarSelecaoParcelamento) { oldValue, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                proxy.scrollTo("parcelamento-expanded", anchor: .top)
                            }
                        }
                    }
                }

            }

            saveButton
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fechar") {
                    if isValorFocused {
                        isValorFocused = false
                    } else if isDescricaoFocused {
                        isDescricaoFocused = false
                    }
                }
                .foregroundColor(.white)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Erro"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
        .animation(.easeInOut, value: mostrarCalendario)
        .animation(.easeInOut, value: mostrarSelecaoRecorrencia)
        .animation(.easeInOut, value: isParcelado)
    }
    
    // MARK: - Componentes de UI

    private var headerSection: some View {
        HStack (spacing: 16){
            Image(systemName: "banknote")
                .foregroundColor(.white)
                .font(.title)
            Text("Nova Operação")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .bold()
                .padding(.leading, -1)
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
    }

    private var primeiroGrupo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalhes")
                .font(.headline)
                .foregroundColor(Color(hex: "#B3B3B3"))
                .padding(.bottom, 8)
            
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $valorStr)
                    .keyboardType(.decimalPad)
                    .focused($isValorFocused)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: valorStr) { oldValue, newValue in
                        let truncatedValue = String(newValue.prefix(16))
                        let formattedValue = formatarMoeda(truncatedValue.normalizarNumero())
                        valorStr = formattedValue
                    }
                    .padding(.trailing, 12)
                    .frame(height: 65)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.white)
                    .font(.system(size: 24, weight: .bold))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .placeholder(when: valorStr.isEmpty) {
                        Text("R$ 0,00")
                            .foregroundColor(.gray.opacity(0.6))
                            .font(.system(size: 24, weight: .bold))
                            .padding(.trailing, 6)
                    }
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $descricao)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
                    .focused($isDescricaoFocused)
                    .onChange(of: descricao) { oldValue, newValue in
                        descricao = String(newValue.prefix(50))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .placeholder(when: descricao.isEmpty) {
                        Text("Adicione uma descrição")
                            .foregroundColor(.gray.opacity(0.6))
                            .font(.body)
                            .padding(.trailing, 10)
                    }
            }
            
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        ehDespesa = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.red)
                        Text("Despesa")
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .overlay(
                                Text("Despesa")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.3))
                                    .offset(x: 0.5, y: 0.5)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .contentShape(Rectangle())
                    .background(
                        Color.red.opacity(ehDespesa ? 0.2 : 0.0)
                            .cornerRadius(8)
                            .shadow(color: ehDespesa ? Color.black.opacity(0.4) : Color.clear, radius: 4, x: 0, y: 2)
                            .offset(x: ehDespesa ? 0 : UIScreen.main.bounds.width / 2)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ehDespesa)
                    )
                }
                .disabled(cartaoSelecionado != nil)
                .opacity(cartaoSelecionado != nil ? 0.5 : 1.0)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        ehDespesa = false
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.green)
                        Text("Receita")
                            .fontWeight(.bold)
                            .foregroundColor(!ehDespesa ? .green : .gray)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .contentShape(Rectangle())
                    .background(
                        Color.green.opacity(!ehDespesa ? 0.2 : 0.0)
                            .cornerRadius(8)
                            .shadow(color: ehDespesa ? Color.black.opacity(0.4) : Color.clear, radius: 4, x: 0, y: 2)
                            .offset(x: !ehDespesa ? 0 : -UIScreen.main.bounds.width / 2)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ehDespesa)
                    )
                }
                .disabled(cartaoSelecionado != nil)
                .opacity(cartaoSelecionado != nil ? 0.5 : 1.0)
            }
            .background(cardBackground)
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            .cornerRadius(cornerRadius)
            
            Button(action: {
                withAnimation {
                    isValorFocused = false
                    isDescricaoFocused = false
                    mostrarCalendario.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Spacer()
                    Text(data.formatAsShortDate())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: 56) // Padroniza a altura
                .contentShape(Rectangle())
                .background(cardBackground)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .cornerRadius(cornerRadius)
            }
            
            if mostrarCalendario {
                VStack { // Envolvendo o DatePicker em um VStack
                    DatePicker("", selection: $data, displayedComponents: .date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .labelsHidden()
                        .padding()
                        .background(cardBackground)
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                        .cornerRadius(cornerRadius)
                        .onChange(of: data) { oldValue, newValue in
                            withAnimation {
                                mostrarCalendario = false
                            }
                        }
                        .colorScheme(.dark)
                        .accentColor(.blue)
                }
                .id("calendario-expanded") // ID único para a seção expandida do calendário
                .transition(.opacity)
            }
        }
        .padding(16)
    }

        // Método de Pagamento
        private var metodoPagamentoSection: some View {
            VStack(spacing: 12) {
                HStack {
                    Text("Método de Pagamento")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#B3B3B3"))
                        .padding(.bottom, 8)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            metodoPagamento = "Dinheiro"
                            cartaoSelecionado = nil
                            mostrarSelecaoCartoes = false
                            isParcelado = false
                            showParceladoToggle = false
                        }
                        // Rolagem opcional se necessário
                        // proxy.scrollTo("detalhes", anchor: .top)
                    }) {
                        HStack {
                            // Ícone fixo
                            HStack {
                                Image(systemName: "banknote")
                                    .foregroundColor(metodoPagamento == "Dinheiro" ? .blue : .gray)
                            }
                            .frame(width: 24)

                            // Texto alternado
                            HStack {
                                Text(alternarTextoDinheiro)
                                    .fontWeight(metodoPagamento == "Dinheiro" ? .bold : .regular)
                                    .foregroundColor(metodoPagamento == "Dinheiro" ? .blue : .white)
                                    .opacity(opacidadeTexto)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: opacidadeTexto)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .contentShape(Rectangle())
                        .background(
                            ZStack {
                                Color(hex: "#252527") // Fundo base
                                if metodoPagamento == "Dinheiro" {
                                    Color.blue.opacity(0.2)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                        )
                                }
                            }
                        )
                        .cornerRadius(8)
                    }

                    Button(action: {
                        fecharTeclados()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            metodoPagamento = "Cartão"
                            mostrarSelecaoCartoes = true
                            // Rolagem opcional se necessário
                            // proxy.scrollTo("cartao-section", anchor: .top)
                        }
                        // Rolagem opcional se necessário
                        // proxy.scrollTo("cartao-section", anchor: .top)
                    }) {
                        HStack {
                            // Ícone fixo
                            HStack {
                                Image(systemName: "creditcard")
                                    .foregroundColor(metodoPagamento == "Cartão" ? .blue : .gray)
                            }
                            .frame(width: 24)

                            // Texto alternado
                            HStack {
                                Text(alternarTextoCartao)
                                    .fontWeight(metodoPagamento == "Cartão" ? .bold : .regular)
                                    .foregroundColor(metodoPagamento == "Cartão" ? .blue : .white)
                                    .opacity(opacidadeTextoCartao)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: opacidadeTextoCartao)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .contentShape(Rectangle())
                        .background(
                            ZStack {
                                Color(hex: "#252527") // Fundo base
                                if metodoPagamento == "Cartão" {
                                    Color.blue.opacity(0.2)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                        )
                                }
                            }
                        )
                        .cornerRadius(8)
                    }
                }
                .background(Color(hex: "#252527")) // Fundo contínuo para toda a linha
                .cornerRadius(8)

                if metodoPagamento == "Cartão" && mostrarSelecaoCartoes {
                    VStack(spacing: 0) {
                        ForEach(cardManager.cartoes, id: \.id) { cartao in
                            Button(action: {
                                withAnimation {
                                    cartaoSelecionado = cartao
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    fecharSelecaoCartoes()
                                    if !ehDespesa {
                                        withAnimation {
                                            ehDespesa = true
                                        }
                                    }
                                    withAnimation {
                                        showParceladoToggle = true
                                    }
                                    // Rolagem opcional se necessário
                                    // proxy.scrollTo("parcelamento", anchor: .top)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "creditcard")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(Color(hex: "#B3B3B3"))
                                        .font(.system(size: 14, weight: .semibold))

                                    Text(cartao.apelido?.isEmpty == false ? cartao.apelido! : cartao.nome)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()

                                    if cartaoSelecionado?.id == cartao.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.green)
                                    }
                                }
                                .frame(height: 58) // Define a altura padrão
                                .padding(.horizontal, 20)
                                .background(cartaoSelecionado?.id == cartao.id ? Color.green.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }

                            if cartao.id != cardManager.cartoes.last?.id {
                                Divider().padding(.leading, 48).padding(.trailing, 16)
                            }
                        }
                    }
                    .transition(.opacity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: opacidadeTexto)
                }

                if metodoPagamento == "Cartão"
                    && cartaoSelecionado != nil
                    && showParceladoToggle {
                    Toggle(isOn: $isParcelado) {
                        Text("Essa compra é parcelada?")
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding()
                    .background(cardBackground)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .cornerRadius(cornerRadius)
                    .onChange(of: isParcelado) { oldValue, newValue in
                        withAnimation {
                            if newValue {
                                mostrarSelecaoRecorrencia = false
                            }
                        }
                    }
                }
            }
            .padding(16)
        }

        private var parcelamentoSection: some View {
            VStack(spacing: 16) {
                HStack {
                    Text("Parcelamento")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#B3B3B3"))
                        .padding(.bottom, 8)
                    Spacer()
                }
                .padding(.bottom, 4)

                Button(action: {
                    fecharTeclados()
                    withAnimation {
                        mostrarSelecaoParcelamento.toggle()
                        // Rolagem opcional se necessário
                        // proxy.scrollTo("parcelamento", anchor: .top)
                    }
                }) {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.blue)
                        Text(numeroParcelas > 1 ? "\(numeroParcelas)x" : "1x")
                            .font(.body)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: mostrarSelecaoParcelamento ? "chevron.up" : "chevron.down")
                            .foregroundColor(Color(hex: "#B3B3B3"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58) // Padroniza a altura
                    .background(Color(.darkGray))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity)

                if mostrarSelecaoParcelamento {
                    VStack(spacing: 16) { // Aumentei o espaçamento de 8 para 16
                        Divider().padding(.horizontal, 16)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) { // Alterei o espaçamento entre os botões
                                ForEach(2...18, id: \.self) { parcela in
                                    Button(action: {
                                        withAnimation {
                                            numeroParcelas = parcela
                                            mostrarSelecaoParcelamento = false
                                        }
                                        // Rolagem opcional se necessário
                                        // proxy.scrollTo("detalhamento", anchor: .top)
                                    }) {
                                        HStack {
                                            Text("\(parcela)x")
                                                .foregroundColor(.white)
                                            Spacer()
                                            if numeroParcelas == parcela {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .background(Color(.darkGray))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: 200)
                    }
                    .id("parcelamento-expanded") // ID único para a seção expandida do parcelamento
                    .background(Color(.darkGray))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            .padding(16)
        }

        private var recorrenciaSection: some View {
            VStack(spacing: 16) {
                HStack {
                    Text("Repetir")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#B3B3B3"))
                        .padding(.bottom, 8)
                    Spacer()
                }
                .padding(.bottom, 4)

                Button(action: {
                    fecharTeclados()
                    withAnimation {
                        mostrarSelecaoRecorrencia.toggle()
                        // Rolagem opcional se necessário
                        // proxy.scrollTo("recorrencia", anchor: .top)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundColor(.blue)
                        Text(tipoRecorrencia)
                            .font(.body)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: mostrarSelecaoRecorrencia ? "chevron.up" : "chevron.down")
                            .foregroundColor(Color(hex: "#B3B3B3"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58) // Padroniza a altura
                    .background(Color(.darkGray))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity)

                if mostrarSelecaoRecorrencia {
                    VStack(spacing: 16) { // Aumentei o espaçamento de 8 para 16
                        Divider().padding(.horizontal, 16)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) { // Alterei o espaçamento entre os botões
                                ForEach(opcoesRecorrencia, id: \.self) { opcao in
                                    Button(action: {
                                        withAnimation {
                                            tipoRecorrencia = opcao
                                            mostrarSelecaoRecorrencia = false
                                        }
                                        // Rolagem opcional se necessário
                                        // proxy.scrollTo("recorrencia", anchor: .top)
                                    }) {
                                        HStack {
                                            Text(opcao)
                                                .foregroundColor(.white)
                                            Spacer()
                                            if tipoRecorrencia == opcao {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .background(Color(.darkGray))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: 200)
                    }
                    .id("recorrencia-expanded") // ID único para a seção expandida
                    .background(Color(.darkGray))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            .padding(16)
        }

        private var saveButton: some View {
            Button(action: salvarOperacao) {
                Text("Salvar")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .contentShape(Rectangle())
                    .background(Color.green)
                    .cornerRadius(cornerRadius)
                    .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 2)
                    .padding()
            }
        }

        // MARK: - Ações

        private func fecharTeclados() {
            isValorFocused = false
            isDescricaoFocused = false
        }

    private func salvarOperacao() {
        // Validação: a descrição não pode estar vazia
        guard !descricao.isEmpty else {
            alertMessage = "Por favor, adicione uma descrição."
            showAlert = true
            return
        }
        
        // Validação: se o método for Cartão, um cartão deve estar selecionado
        if metodoPagamento == "Cartão" && cartaoSelecionado == nil {
            alertMessage = "Por favor, selecione um cartão."
            showAlert = true
            return
        }
        
        // Define o tipo da operação
        let tipoOp = ehDespesa ? "Despesa" : "Receita"
        let isRecorrente = tipoRecorrencia != "Nunca"
        
        // Se a operação for parcelada, utiliza o método correto
        if isParcelado {
            Task {
                await moneyManager.adicionarOperacao(
                    valor: extrairValorDouble(),
                    descricao: descricao,
                    data: data,
                    tipoOperacao: tipoOp,
                    metodoPagamento: metodoPagamento,
                    parcelas: numeroParcelas, // Já é um Int válido
                    recorrencia: isRecorrente ? tipoRecorrencia : nil,
                    cartao: cartaoSelecionado,
                    isRecorrente: isRecorrente,
                    operacaoOriginal: nil
                )
            }
        } else {
            // Operação normal (não parcelada)
            moneyManager.adicionarOperacao(
                valor: extrairValorDouble(),
                descricao: descricao,
                data: data,
                tipoOperacao: tipoOp,
                metodoPagamento: metodoPagamento,
                parcelas: 1, // Em operações normais, definimos parcelas como 1 para evitar erro
                recorrencia: isRecorrente ? tipoRecorrencia : nil,
                cartao: cartaoSelecionado,
                isRecorrente: isRecorrente,
                operacaoOriginal: nil
            )
        }
        
        // Fecha a view após salvar
        presentationMode.wrappedValue.dismiss()
    }

        private func extrairValorDouble() -> Double {
            let digits = valorStr.filter { $0.isNumber }
            let doubleValue = (Double(digits) ?? 0) / 100
            return doubleValue
        }

        private func iniciarAlternanciaDeTexto() {
            var indiceAtualDinheiro = 0
            var indiceAtualCartao = 0

            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                // Dinheiro
                withAnimation(.easeInOut(duration: 0.8)) {
                    opacidadeTexto = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    indiceAtualDinheiro = (indiceAtualDinheiro + 1) % textosAlternativosDinheiro.count
                    alternarTextoDinheiro = textosAlternativosDinheiro[indiceAtualDinheiro]
                    withAnimation(.easeInOut(duration: 0.8)) {
                        opacidadeTexto = 1
                    }
                }

                // Cartão
                withAnimation(.easeInOut(duration: 0.8)) {
                    opacidadeTextoCartao = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    indiceAtualCartao = (indiceAtualCartao + 1) % textosAlternativosCartao.count
                    alternarTextoCartao = textosAlternativosCartao[indiceAtualCartao]
                    withAnimation(.easeInOut(duration: 0.8)) {
                        opacidadeTextoCartao = 1
                    }
                }
            }
        }

        private func fecharSelecaoCartoes() {
            withAnimation(.easeInOut(duration: 0.3)) {
                mostrarSelecaoCartoes = false
            }
        }
        
        private func setupKeyboardObserver() {
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation {
                        self.keyboardHeight = keyboardFrame.height
                    }
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                withAnimation {
                    self.keyboardHeight = 0
                }
            }
        }

        private func removeKeyboardObserver() {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }

/*
    struct NovaOperacaoView_Previews: PreviewProvider {
        static var previews: some View {
            NovaOperacaoView()
                .environmentObject(MoneyManager.shared) // Certifique-se de que MoneyManager está configurado corretamente
                .environmentObject(CardManager.shared) // Certifique-se de que CardManager está configurado corretamente
                .previewLayout(.device)
                .preferredColorScheme(.dark) // Garante o tema dark
        }
    }
 */

