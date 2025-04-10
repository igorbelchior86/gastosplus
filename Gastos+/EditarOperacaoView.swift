import SwiftUI


struct EditarOperacaoView: View {
    @EnvironmentObject var moneyManager: MoneyManager
    @EnvironmentObject var cardManager: CardManager
    
    // Recebemos a operação como Binding para refletir as alterações
    @Binding var operacao: Operacao
    
    @Environment(\.presentationMode) var presentationMode

    // MARK: - Estados Locais
    @State private var valorStr: String = ""
    @State private var descricao: String = ""
    @State private var data: Date = Date()
    @State private var ehDespesa: Bool = true
    @State private var metodoPagamento: String = "Dinheiro"
    @State private var cartaoSelecionado: Cartao? = nil
    @State private var keyboardHeight: CGFloat = 0
    
    // Recorrência (exibida só se a operação original tiver)
    @State private var mostrarRecorrencia = false
    @State private var tipoRecorrencia: String = "Nunca"
    @State private var mostrarSelecaoRecorrencia = false
    @State private var mostrarCalendario: Bool = false
    private let opcoesRecorrencia: [String] = ["Nunca", "Diária", "Semanal", "Quinzenal", "Mensal", "Anual"]
    
    // Parcelamento (exibido só se tiver)
    @State private var mostrarParcelamento = false
    @State private var numeroParcelas: Int = 1
    @State private var mostrarSelecaoParcelamento = false
    
    // Alertas
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Focos
    @FocusState private var isValorFocused: Bool
    @FocusState private var isDescricaoFocused: Bool

    // Estilos e placeholders
    private let cardBackground = Color(hex: "#252527")
    private let cornerRadius: CGFloat = 8
    
    // Alternância de texto (apenas efeito visual para botões Dinheiro/Cartão)
    @State private var alternarTextoCartao = "Cartão"
    @State private var opacidadeTextoCartao = 1.0
    private let textosAlternativosCartao = ["Cartão", "Crédito"]
    
    @State private var alternarTextoDinheiro = "Dinheiro"
    @State private var opacidadeTextoDinheiro = 1.0
    private let textosAlternativosDinheiro = ["Dinheiro", "Pix", "Débito"]

    // Scroll auxiliar
    @State private var focoScroll: String? = nil

    // Construtor
    init(operacao: Binding<Operacao>) {
        self._operacao = operacao
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        primeiroGrupo
                            .id("detalhes")
                        
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                        
                        metodoPagamentoSection
                        
                        // Só exibe Divider se mostrarRecorrencia ou mostrarParcelamento
                        if mostrarRecorrencia || mostrarParcelamento {
                            Divider()
                                .background(Color(hex: "#3e3e40"))
                                .padding(.horizontal, 24)
                        }
                        
                        // Parcelamento
                        if mostrarParcelamento {
                            parcelamentoSection
                                .id("parcelamento")
                        }
                        // Recorrência
                        else if mostrarRecorrencia {
                            recorrenciaSection
                                .id("recorrencia")
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, keyboardHeight)
                    .onAppear {
                        // Preenche valores iniciais
                        configurarEstadosComOperacao()
                        setupKeyboardObserver()
                        
                        // Dá foco inicial no valor
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isValorFocused = true
                            withAnimation {
                                proxy.scrollTo("detalhes", anchor: .top)
                            }
                        }
                        iniciarAlternanciaDeTexto()
                    }
                    .onDisappear {
                        removeKeyboardObserver()
                    }
                }
                
                .onChange(of: mostrarSelecaoRecorrencia) { value in
                    if value {
                        // Introduz um pequeno atraso para garantir que a interface esteja atualizada
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                proxy.scrollTo("recorrencia-expanded", anchor: .top)
                            }
                        }
                    }
                }
                .onChange(of: mostrarCalendario) { value in
                    if value {
                        // Introduz um pequeno atraso para garantir que a interface esteja atualizada
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                proxy.scrollTo("calendario-expanded", anchor: .top)
                            }
                        }
                    }
                }
                .onChange(of: mostrarSelecaoParcelamento) { value in
                    if value {
                        // Introduz um pequeno atraso para garantir que a interface esteja atualizada
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
                    isValorFocused = false
                    isDescricaoFocused = false
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
        .animation(.easeInOut, value: mostrarSelecaoRecorrencia)
        .animation(.easeInOut, value: mostrarSelecaoParcelamento)
        .animation(.easeInOut, value: keyboardHeight)
    }

    // MARK: - Componentes de UI

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .foregroundColor(.white)
                .font(.title)
            Text("Editar Operação")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#2a2a2c"))
    }

    private var primeiroGrupo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalhes")
                .font(.headline)
                .foregroundColor(Color(hex: "#B3B3B3"))
                .padding(.bottom, 8)

            // Campo valor
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $valorStr)
                    .keyboardType(.decimalPad)
                    .focused($isValorFocused)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: valorStr) { newValue in
                        valorStr = String(newValue.prefix(16))
                        valorStr = formatarMoeda(valorStr.normalizarNumero())
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

            // Campo descrição
            VStack(alignment: .trailing, spacing: 4) {
                TextField("", text: $descricao)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
                    .focused($isDescricaoFocused)
                    .onChange(of: descricao) { newValue in
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

            // Despesa/Receita
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation {
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
                    .background(
                        Color.red.opacity(ehDespesa ? 0.2 : 0.0)
                            .cornerRadius(8)
                    )
                }
                .disabled(cartaoSelecionado != nil)
                .opacity(cartaoSelecionado != nil ? 0.5 : 1.0)

                Button(action: {
                    withAnimation {
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
                    .background(
                        Color.green.opacity(!ehDespesa ? 0.2 : 0.0)
                            .cornerRadius(8)
                    )
                }
                .disabled(cartaoSelecionado != nil)
                .opacity(cartaoSelecionado != nil ? 0.5 : 1.0)
            }
            .background(cardBackground)
            .cornerRadius(cornerRadius)
  //          .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)

            // Data
            Button(action: {
                withAnimation {
                    fecharTeclados()
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
                .frame(height: 56)
                .background(cardBackground)
                .cornerRadius(cornerRadius)
  //              .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }

            // DatePicker Condicional
            if mostrarCalendario {
                VStack { // Envolvendo o DatePicker em um VStack
                    DatePicker("", selection: $data, displayedComponents: .date)
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .labelsHidden()
                        .padding()
                        .background(cardBackground)
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                        .cornerRadius(cornerRadius)
                        .onChange(of: data) { _ in
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

    private var metodoPagamentoSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Método de Pagamento")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                Spacer()
            }
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button(action: {
                    fecharTeclados()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation {
                        metodoPagamento = "Dinheiro"
                        cartaoSelecionado = nil
                    }
                }) {
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundColor(metodoPagamento == "Dinheiro" ? .blue : .gray)
                            .frame(width: 24)

                        Text(alternarTextoDinheiro)
                            .fontWeight(metodoPagamento == "Dinheiro" ? .bold : .regular)
                            .foregroundColor(metodoPagamento == "Dinheiro" ? .blue : .white)
                            .opacity(opacidadeTextoDinheiro)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(
                        ZStack {
                            Color(hex: "#252527")
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
                    withAnimation {
                        metodoPagamento = "Cartão"
                    }
                }) {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(metodoPagamento == "Cartão" ? .blue : .gray)
                            .frame(width: 24)

                        Text(alternarTextoCartao)
                            .fontWeight(metodoPagamento == "Cartão" ? .bold : .regular)
                            .foregroundColor(metodoPagamento == "Cartão" ? .blue : .white)
                            .opacity(opacidadeTextoCartao)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .background(
                        ZStack {
                            Color(hex: "#252527")
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
            .background(Color(hex: "#252527"))
            .cornerRadius(8)

            // Se for "Cartão", escolhe qual
            if metodoPagamento == "Cartão" {
                VStack(spacing: 0) {
                    ForEach(cardManager.cartoes, id: \.id) { cartao in
                        Button {
                            withAnimation {
                                cartaoSelecionado = cartao
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "creditcard")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(Color(hex: "#B3B3B3"))

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
                            .frame(height: 58)
                            .padding(.horizontal, 20)
                            .background(
                                cartaoSelecionado?.id == cartao.id
                                ? Color.green.opacity(0.2)
                                : Color.clear
                            )
                            .contentShape(Rectangle())
                        }

                        if cartao.id != cardManager.cartoes.last?.id {
                            Divider()
                                .padding(.leading, 48)
                                .padding(.trailing, 16)
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
                Spacer()
            }
            .padding(.bottom, 4)

            Button(action: {
                fecharTeclados()
                withAnimation {
                    mostrarSelecaoParcelamento.toggle()
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
                .frame(height: 58)
                .background(Color(.darkGray))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }

            if mostrarSelecaoParcelamento {
                VStack(spacing: 16) {
                    Divider().padding(.horizontal, 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(2...18, id: \.self) { parcela in
                                Button(action: {
                                    withAnimation {
                                        numeroParcelas = parcela
                                        mostrarSelecaoParcelamento = false
                                    }
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
                Spacer()
            }
            .padding(.bottom, 4)

            Button(action: {
                fecharTeclados()
                withAnimation {
                    mostrarSelecaoRecorrencia.toggle()
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
                .frame(height: 58)
                .background(Color(.darkGray))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }

            if mostrarSelecaoRecorrencia {
                VStack(spacing: 16) {
                    Divider().padding(.horizontal, 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(opcoesRecorrencia, id: \.self) { opcao in
                                Button(action: {
                                    withAnimation {
                                        tipoRecorrencia = opcao
                                        mostrarSelecaoRecorrencia = false
                                    }
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
                .background(Color.green)
                .cornerRadius(cornerRadius)
                .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 2)
                .padding()
        }
    }

    // MARK: - Ações

    private func configurarEstadosComOperacao() {
        // Carrega os dados do Binding `operacao` para os estados locais
        valorStr = formatarMoeda(String(format: "%.2f", operacao.valor))
        descricao = operacao.nome
        data = operacao.data
        ehDespesa = (operacao.tipoString == "Despesa")
        metodoPagamento = operacao.metodoPagamento
        cartaoSelecionado = operacao.cartao
        
        // Verifica se há recorrência e habilita sua exibição
        if let recorrencia = operacao.recorrencia {
            mostrarRecorrencia = true
            tipoRecorrencia = recorrencia.tipo // Acesse a propriedade correta do objeto Recorrencia
        } else {
            mostrarRecorrencia = false
        }
        
        // Verifica e configura o parcelamento
        if operacao.numeroParcelas > 1 {
            mostrarParcelamento = true
            numeroParcelas = Int(operacao.numeroParcelas)
        } else {
            mostrarParcelamento = false
            numeroParcelas = 1
        }
    }

    private func fecharTeclados() {
        isValorFocused = false
        isDescricaoFocused = false
    }

    private func salvarOperacao() {
        // Validações
        guard !descricao.isEmpty else {
            alertMessage = "Por favor, adicione uma descrição."
            showAlert = true
            return
        }
        
        if metodoPagamento == "Cartão", cartaoSelecionado == nil {
            alertMessage = "Por favor, selecione um cartão."
            showAlert = true
            return
        }
        
        // Atualiza a operação (que é Binding)
        $operacao.wrappedValue.valor = extrairValorDouble()
        $operacao.wrappedValue.nome = descricao
        $operacao.wrappedValue.data = data
        $operacao.wrappedValue.tipoString = ehDespesa ? "Despesa" : "Receita"
        $operacao.wrappedValue.metodoPagamento = metodoPagamento
        $operacao.wrappedValue.cartao = cartaoSelecionado

        // Configuração de recorrência
        if mostrarRecorrencia {
            if tipoRecorrencia != "Nunca" {
                let novaRecorrencia = Recorrencia(
                    context: CoreDataManager.shared.context,
                    tipo: tipoRecorrencia,
                    intervalo: 1, // Ajuste conforme necessário
                    dataInicial: data,
                    operacao: $operacao.wrappedValue
                )
                $operacao.wrappedValue.recorrencia = novaRecorrencia
            } else {
                $operacao.wrappedValue.recorrente = mostrarRecorrencia && tipoRecorrencia != "Nunca"
            }
        } else {
            $operacao.wrappedValue.recorrente = mostrarRecorrencia && tipoRecorrencia != "Nunca"
        }

        // Configuração de parcelamento
        if mostrarParcelamento {
            operacao.numeroParcelas = Int16(numeroParcelas)
        } else {
            operacao.numeroParcelas = 1
        }

        // Atualiza a operação usando o MoneyManager
        moneyManager.atualizarOperacao($operacao.wrappedValue)
        
        // Fecha o calendário se estiver aberto
        withAnimation {
            mostrarCalendario = false
        }
        
        // Fecha a tela
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
                opacidadeTextoDinheiro = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                indiceAtualDinheiro = (indiceAtualDinheiro + 1) % textosAlternativosDinheiro.count
                alternarTextoDinheiro = textosAlternativosDinheiro[indiceAtualDinheiro]
                withAnimation(.easeInOut(duration: 0.8)) {
                    opacidadeTextoDinheiro = 1
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

    private func setupKeyboardObserver() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation {
                    self.keyboardHeight = keyboardFrame.height
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation {
                self.keyboardHeight = 0
            }
        }
    }

    private func removeKeyboardObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
}

/*
// Preview de exemplo
struct EditarOperacaoView_Previews: PreviewProvider {
    @State static var exemploOperacao: Operacao = Operacao()

    static var previews: some View {
        EditarOperacaoView(operacao: $exemploOperacao)
            .environmentObject(MoneyManager.shared)
            .environmentObject(CardManager.shared)
            .preferredColorScheme(.dark)
    }
}
*/
