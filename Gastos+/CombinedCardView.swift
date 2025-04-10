import SwiftUI


struct CombinedCardView: View {
    @Binding var mesAtual: Date
    @Binding var saldoDoDia: Double
    @Binding var saldoFinal: Double
    @Binding var saldosPorDia: [DailyBalance]

    @State private var valoresVisiveis: Bool = true
    @State private var legendaMesAtual: String = "" // Estado intermediário da legenda

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                saldoDoDiaView
                Divider()
                    .frame(width: 1, height: 40)
                    .background(Color(hex: "#3e3e40")) // Ajustado para seguir o guia
                    .padding(.horizontal, 8)
                saldoFinalView
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 24) // Altura reduzida para compactar o design
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#2a2a2c"), Color(hex: "#3a3a3c")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16) // Cantos mais arredondados
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#3e3e40"), lineWidth: 1) // Borda sutil
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                valoresVisiveis.toggle()
            }
            feedbackGenerator.impactOccurred()
        }
        .onChange(of: mesAtual) { newValue in
            withAnimation(.easeOut(duration: 0.2)) {
                legendaMesAtual = newValue.endOfMonth().formatAsMedium()
            }
        }
        .onAppear {
            // Inicializa a legenda ao carregar
            legendaMesAtual = mesAtual.endOfMonth().formatAsMedium()
        }
    }

    // MARK: - Subview: Saldo do Dia
    private var saldoDoDiaView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saldo do Dia")
                .font(.caption)
                .foregroundColor(Color(hex: "#B3B3B3"))
            if valoresVisiveis {
                Text(saldoDoDia.formatAsCurrency())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(saldoDoDia >= 0 ? Color(hex: "#00FF00") : Color(hex: "#FF0000"))
                    .lineLimit(1) // Limita o texto a 1 linha
                    .minimumScaleFactor(0.5) // Reduz a escala para 50% caso necessário
                    .truncationMode(.tail) // Trunca no final se o texto não couber
            } else {
                Text("•••••••")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.gray)
                    .lineLimit(1) // Limita o texto a 1 linha
                    .minimumScaleFactor(0.5) // Reduz a escala para 50% caso necessário
                    .truncationMode(.tail)
            }
            Text("em \(Date().formatAsMedium())")
                .font(.footnote)
                .foregroundColor(Color(hex: "#B3B3B3"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Subview: Saldo Final do Mês
    private var saldoFinalView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Saldo no Fim do Mês")
                .font(.caption)
                .foregroundColor(Color(hex: "#B3B3B3"))
            if valoresVisiveis {
                Text(saldoFinal.formatAsCurrency())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(saldoFinal >= 0 ? Color(hex: "#00FF00") : Color(hex: "#FF0000"))
                    .lineLimit(1) // Limita o texto a 1 linha
                    .minimumScaleFactor(0.5) // Reduz a escala para 50% caso necessário
                    .truncationMode(.tail) // Trunca no final se o texto não couber
            } else {
                Text("•••••••")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.gray)
                    .lineLimit(1) // Limita o texto a 1 linha
                    .minimumScaleFactor(0.5) // Reduz a escala para 50% caso necessário
                    .truncationMode(.tail)
            }
            Text("em \(legendaMesAtual)")
                .font(.footnote)
                .foregroundColor(Color(hex: "#B3B3B3"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
