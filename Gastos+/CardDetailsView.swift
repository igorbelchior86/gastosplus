import SwiftUI


// MARK: - DetailRowContent
struct DetailRowContent: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

// MARK: - DetailBlock
struct DetailBlock: View {
    var title: String
    var items: [DetailRowContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold)) // Título da seção
                .foregroundColor(Color(hex: "#D1D1D1")) // Texto secundário mais claro
                .padding(.bottom, 8) // Espaço maior para destacar o título

            VStack(spacing: 8) {
                ForEach(items) { item in
                    DetailRow(title: item.title, value: item.value)
                        .padding(.vertical, 8) // Linhas mais grossas
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12) // Maior altura para blocos
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 2) // Uniformizar com a tela inicial
    }
}

// MARK: - DetailRow
struct DetailRow: View {
    var title: String
    var value: String

    private func iconForTitle(_ title: String) -> String {
        switch title.lowercased() {
        case "número do cartão": return "creditcard.fill"
        case "bandeira": return "flag.fill"
        case "dia de vencimento": return "calendar"
        case "dia de fechamento": return "calendar.badge.clock"
        case "limite": return "dollarsign.circle.fill"
        case "taxa de juros": return "percent"
        default: return "info.circle"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: iconForTitle(title))
                .foregroundColor(Color(hex: "#B3B3B3")) // Cor para o ícone
                .frame(width: 24, height: 24) // Tamanho fixo para consistência
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hex: "#D1D1D1"))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#FFFFFF"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - CardDetailsView
struct CardDetailsView: View {
    @ObservedObject var cardManager: CardManager
    @State var cartao: Cartao
    @Environment(\.presentationMode) var presentationMode
    @State private var isDefault: Bool
    @State private var mostrarNumeroCompleto: Bool = false
    @State private var mostrandoEditarCartao: Bool = false

    init(cardManager: CardManager, cartao: Cartao) {
        self.cardManager = cardManager
        self.cartao = cartao
        _isDefault = State(initialValue: cartao.isDefault)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Customizado
                HStack(spacing: 12) {
                    if let logo = UIImage(named: cartao.bandeira?.lowercased() ?? "") {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 50)
                    } else {
                        Image(systemName: "creditcard")
                            .font(.title)
                            .foregroundColor(Color(hex: "#B3B3B3"))
                    }
                    Text(cartao.apelido ?? "Sem Apelido")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                    Spacer()
                    Button(action: { mostrandoEditarCartao = true }) {
                        Text("Editar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.white) // Texto branco para contraste
                            .padding(.vertical, 8) // Espaçamento interno vertical
                            .padding(.horizontal, 16) // Espaçamento interno horizontal
                            .background(Color(hex: "#007AFF")) // Fundo azul claro
                            .cornerRadius(20) // Bordas arredondadas para o formato de pílula
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2) // Sombreamento
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(Color(hex: "#2a2a2c"))
                
                // Conteúdo Principal
                ScrollView {
                    VStack(spacing: 16) { // Espaçamento maior entre blocos
                        DetailBlock(title: "Detalhes do Cartão", items: [
                            DetailRowContent(title: "Número do Cartão", value: mostrarNumeroCompleto ? (cartao.numero ?? "•••• •••• •••• ••••") : "•••• \(cartao.numero?.suffix(4) ?? "••••")"),
                            DetailRowContent(title: "Bandeira", value: cartao.bandeira ?? "N/A")
                        ])
                        
                        Divider()
                            .background(Color(hex: "#3e3e40"))
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                        
                        DetailBlock(title: "Configurações de Pagamento", items: [
                            DetailRowContent(
                                title: "Dia de Vencimento",
                                value: "\(Calendar.current.component(.day, from: cartao.dataVencimento))" // No need for nil check
                            ),
                            DetailRowContent(
                                title: "Dia de Fechamento",
                                value: "\(Calendar.current.component(.day, from: cartao.dataFechamento))" // No need for nil check
                            ),
                            DetailRowContent(
                                title: "Limite",
                                value: cartao.limite > 0 ? cartao.limite.formatAsCurrency() : "Não definido"
                            ),
                            DetailRowContent(
                                title: "Taxa de Juros",
                                value: cartao.taxaJuros > 0 ? cartao.taxaJuros.formatAsPercentage() : "Não definida"
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    Divider()
                        .background(Color(hex: "#3e3e40"))
                        .padding(.horizontal, 24)
                        .padding(.top, 15)
                        .padding(.bottom, 15)
                    
                    VStack {
                        Toggle("Definir como cartão padrão", isOn: Binding(
                            get: { cartao.isDefault },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        await cardManager.definirCartaoPadrao(cartao)
                                    }
                                } else {
                                    // Se for o único cartão, não permite desmarcar
                                    if cardManager.cartoes.count == 1 {
                                        // Opcional: pode exibir um alerta ou simplesmente ignorar
                                    } else {
                                        // Para múltiplos cartões, você pode optar por não permitir desmarcar sem definir outro como padrão.
                                        // Aqui, simplesmente não alteramos o valor.
                                    }
                                }
                            }
                        ))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                        .disabled(cardManager.cartoes.count == 1)
                        
                        Text("Para ser usado por padrão em novas operações.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "#B3B3B3"))
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, 16) // Padding uniforme
                }
                
                // Botão "Arquivar Cartão"
                Button(action: {
                    Task {
                        await cardManager.arquivarCartao(cartao)
                    }
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Arquivar Cartão")
                        .font(.system(size: 18, weight: .bold)) // Texto maior e mais destacado
                        .foregroundColor(Color(hex: "#FFFFFF"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#FF3B30")) // Cor de fundo vibrante
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2) // Adiciona um sombreamento sutil
                }
                .padding(.bottom, 16) // Espaçamento no rodapé
            }
            .background(Color(hex: "#2a2a2c")) // Aplicar fundo diretamente
            .sheet(isPresented: $mostrandoEditarCartao) {
                EditCardView(
                    cardManager: cardManager,
                    cartao: cartao,
                    onSave: { cartaoAtualizado in
                        atualizarCartao(cartaoAtualizado)
                        mostrandoEditarCartao = false
                    }
                )
            }
        }
    }

        private func atualizarCartao(_ cartaoAtualizado: Cartao) {
            Task {
                await cardManager.atualizarCartao(cartaoAtualizado)
            }
            if cartao.id == cartaoAtualizado.id {
                cartao = cartaoAtualizado
            }
        }
    }

/*
    struct CardDetailsView_Previews: PreviewProvider {
        static var previews: some View {
            Group {
                if let cartao = CardManager.shared.cartoes.first {
                    CardDetailsView(cardManager: CardManager.shared, cartao: cartao)
                        .environmentObject(CardManager.shared)
                        .previewLayout(.device)
                        .preferredColorScheme(.dark)
                } else {
                    Text("Nenhum cartão disponível para pré-visualização.")
                        .foregroundColor(.white)
                        .background(Color.black)
                        .previewLayout(.sizeThatFits)
                        .preferredColorScheme(.dark)
                }
            }
        }
    }
*/
