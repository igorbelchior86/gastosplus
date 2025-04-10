import SwiftUI
import Combine


// ====================================================
// MARK: - IconManager
// ====================================================

class IconManager {
    static let shared = IconManager()

    // Busca o nome do ícone salvo em Assets com base na bandeira
    func iconName(for brand: String) -> String? {
        switch brand.lowercased() {
        case "visa":
            return "visa_icon" // Substitua pelo nome exato no Assets
        case "mastercard":
            return "mastercard_icon" // Substitua pelo nome exato no Assets
        case "amex":
            return "amex_icon" // Substitua pelo nome exato no Assets
        default:
            return nil
        }
    }

    // Retorna a imagem correspondente à bandeira
    func fetchIcon(for brand: String, completion: @escaping (UIImage?) -> Void) {
        if let iconName = iconName(for: brand),
           let image = UIImage(named: iconName) {
            completion(image)
        } else {
            print("Ícone não encontrado para a bandeira: \(brand)")
            completion(nil)
        }
    }
}

// ====================================================
// MARK: - AllCardsView (Unificado)
// ====================================================
struct AllCardsView: View {
    @EnvironmentObject var cardManager: CardManager
    @State private var mostrarAddCardView: Bool = false
    @State private var cartaoSelecionado: Cartao? = nil
    @State private var mostrarFeedbackAbertura: Bool = false
    @State private var mostrarFeedbackAdicionar: Bool = false

    var apenasAtivos: Bool = true // Permite filtrar cartões ativos

    var body: some View {
        NavigationView {
            ZStack {
                fundo
                conteudo
                if mostrarFeedbackAbertura {
                    Text("Abrindo cartão...")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.opacity)
                        .zIndex(1)
                }
                if mostrarFeedbackAdicionar {
                    Text("Adicionando cartão...")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await cardManager.carregarCartoes(apenasAtivos: apenasAtivos) // Inicializa os cartões
            }
        }
        .sheet(isPresented: $mostrarAddCardView) {
            AddCardView()
                .environmentObject(cardManager)
        }
        .sheet(item: $cartaoSelecionado) { cartao in
            CardDetailsView(cardManager: cardManager, cartao: cartao)
                .environmentObject(cardManager)
        }
    }

    // Fundo do Modal
    private var fundo: some View {
        Color(hex: "#2a2a2c") // Cor de fundo do guia de estilo
            .edgesIgnoringSafeArea(.all)
    }

    // Conteúdo principal
    private var conteudo: some View {
        VStack(spacing: 0) {
            cabecalho
            listaCartoes
        }
    }

    // Cabeçalho
    private var cabecalho: some View {
        HStack (spacing: 4) {
            Image(systemName: "creditcard")
                .foregroundColor(.white)
                .font(.title)
            Text(apenasAtivos ? "Meus Cartões" : "Todos os Cartões")
                .font(.system(size: 28, weight: .bold, design: .rounded)) // Fonte do guia de estilo
                .foregroundColor(Color(hex: "#FFFFFF"))
                .padding(.leading, 16) // Ajusta o espaçamento à esquerda
            Spacer()
        }
        .padding(.vertical, 16) // Uniformiza o espaçamento vertical
        .padding(.horizontal, 16) // Uniformiza o espaçamento vertical
        .background(Color(hex: "#2a2a2c")) // Fundo do cabeçalho
    }

    // Lista de Cartões
    private var listaCartoes: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], // Espaçamento entre colunas
                spacing: 16 // Espaçamento entre linhas
            ) {
                if cardManager.cartoes.isEmpty {
                    /*
                    Text("Nenhum cartão encontrado.")
                        .foregroundColor(Color(hex: "#B3B3B3")) // Texto descritivo
                        .font(.system(size: 14)) // Fonte descritiva
                        .padding()
                     */
                }
                ForEach(cardManager.cartoes) { cartao in
                    cartaoItem(cartao)
                }
                botaoAdicionar
            }
            .padding(16) // Margens externas ao redor do grid
        }
    }

    // Item Individual de Cartão
    private func cartaoItem(_ cartao: Cartao) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if let bandeiraNome = cartao.bandeira?.lowercased(),
                   let logo = UIImage(named: bandeiraNome) {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 50)
                } else {
                    Image(systemName: "creditcard")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 50)
                        .foregroundColor(Color(hex: "#B3B3B3")) // Ícone cinza claro
                }

                VStack(spacing: 6) {
                    Text(cartao.apelido ?? "Sem Nome")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#FFFFFF"))

                    Text("•••• \(cartao.numero?.suffix(4) ?? "XXXX")")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#D1D1D1")) // Texto secundário mais claro

                    Text("Limite: \(cartao.limite.rounded(to: 2).formatAsCurrency())")
                        .font(.footnote)
                        .foregroundColor(Color(hex: "#D1D1D1")) // Texto secundário mais claro

                    Text("Vencimento: \(Calendar.current.component(.day, from: cartao.dataVencimento))")
                        .font(.footnote)
                        .foregroundColor(Color(hex: "#D1D1D1")) // Texto secundário mais claro

                    if !cartao.ativo {
                        Text("Inativo")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#FF0000")) // Vermelho para inativo
                    }
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.44, height: UIScreen.main.bounds.width * 0.44)
            .background(Color(hex: "#3a3a3c")) // Fundo do cartão mais claro
            .cornerRadius(12) // Bordas mais arredondadas
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "#3e3e40"), lineWidth: 1) // Adicionando borda
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4) // Sombra mais pronunciada
            .onTapGesture {
                cartaoSelecionado = cartao
            }

            if cartao.isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#00FF00"))
                    .padding(8)
            }
        }
    }

    // Botão de Adicionar Cartão
    private var botaoAdicionar: some View {
        Button(action: {
            withAnimation {
                mostrarFeedbackAdicionar = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                mostrarAddCardView = true
                withAnimation {
                    mostrarFeedbackAdicionar = false
                }
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Color(hex: "#00FF00")) // Verde para o botão
                Text("Adicionar")
                    .font(.subheadline).bold()
                    .foregroundColor(Color(hex: "#00FF00"))
            }
            .frame(width: UIScreen.main.bounds.width * 0.44, height: UIScreen.main.bounds.width * 0.44)
            .background(Color(hex: "#3a3a3c")) // Fundo do cartão mais claro
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "#3e3e40"), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
}

/*
struct AllCardsView_Previews: PreviewProvider {
    static var previews: some View {
        AllCardsView()
            .environmentObject(CardManager.shared)
            .previewLayout(.device)
            .preferredColorScheme(.dark) // Garante o tema escuro
    }
}
*/
