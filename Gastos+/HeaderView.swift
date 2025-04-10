import SwiftUI


struct HeaderView: View {
    @Binding var mesAtual: Date
    var onAddCard: () -> Void

    var body: some View {
        ZStack {
            // Gradiente de fundo ajustado
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#2a2a2c"), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.top)

            HStack {
                // Título com padding inferior
                Text(formatarMes(mesAtual))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                    .padding(.bottom, 15) // Padding inferior apenas no botão

                Spacer()

                // Ícone com círculo reduzido
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onAddCard()
                }) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 18)) // Tamanho do ícone
                        .foregroundColor(.white)
                        .padding(6) // Padding interno ajustado
                        .background(
                            Circle()
                                .fill(Color(hex: "#007AFF"))
                                .frame(width: 36, height: 36) // Reduzindo o tamanho do círculo
                                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1) // Sombra mais suave
                        )
                }
                .padding(.trailing, 16)
                .padding(.bottom, 15) // Padding inferior apenas no botão
                .accessibilityLabel("Adicionar cartão")
            }
        }
        .frame(height: 50) // Altura reduzida
    }

    private func formatarMes(_ data: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: data).capitalized
    }
}
