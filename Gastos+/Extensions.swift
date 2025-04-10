//
//  Extensions.swift
//  BudgetApp
//
//  Created by SeuNome on 01/01/2023.
//

import Foundation
import SwiftUI
import LocalAuthentication

// MARK: - Extensão Color para inicialização com hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        r = (int >> 16) & 0xFF
        g = (int >> 8) & 0xFF
        b = int & 0xFF
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Extensões para View
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .trailing,
        padding: CGFloat = 8,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow {
                placeholder()
                    .padding(.trailing, padding)
            }
            self
        }
    }

    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    func customShadow(color: Color = .black, radius: CGFloat = 4, x: CGFloat = 0, y: CGFloat = 2) -> some View {
        self.shadow(color: color.opacity(0.2), radius: radius, x: x, y: y)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Extensões para Date
extension Date {
    func formatAsMedium(locale: String = "pt_BR") -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: locale)
        return formatter.string(from: self)
    }

    func formatAsShortDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }

    func formatAsMonth(locale: String = "pt_BR") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: locale)
        return formatter.string(from: self)
    }

    func daysInMonth() -> Int {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: self)
        return range?.count ?? 0
    }

    func isSameDay(as otherDate: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(self, inSameDayAs: otherDate)
    }

    func startOfMonth() -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: self)) ?? self
    }

    func endOfMonth() -> Date {
        let calendar = Calendar.current
        if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: self)) {
            return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? self
        }
        return self
    }

    func startOfDay() -> Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    func endOfDay() -> Date {
        let start = Calendar.current.startOfDay(for: self)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? self
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = self.dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    func endOfMonth(for date: Date) -> Date {
        let startOfMonth = self.startOfMonth(for: date)
        return self.date(byAdding: .month, value: 1, to: startOfMonth)?.addingTimeInterval(-1) ?? date
    }
}

// MARK: - Extensões para String
extension String {
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func chunked(by sizes: [Int]) -> [String] {
        var chunks: [String] = []
        var currentIndex = self.startIndex

        for size in sizes {
            guard currentIndex < self.endIndex else { break }
            let endIndex = self.index(currentIndex, offsetBy: size, limitedBy: self.endIndex) ?? self.endIndex
            chunks.append(String(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }

        return chunks
    }

    func isNumeric() -> Bool {
        return !self.isEmpty && self.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }

    func normalizarNumero() -> String {
        return self.filter { $0.isNumber }
    }
}

// MARK: - Extensões para Double
extension Double {
    func formatAsCurrency(locale: String = "pt_BR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: locale)
        return formatter.string(from: NSNumber(value: self)) ?? "R$ 0,00"
    }

    func formatAsPercentage(locale: String = "pt_BR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale(identifier: locale)
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "0%"
    }
}

// MARK: - Funções auxiliares para formatação de moeda/percentual
func formatarMoeda(_ valor: String) -> String {
    let digits = valor.filter { $0.isNumber }
    let doubleValue = (Double(digits) ?? 0) / 100
    return doubleValue.formatAsCurrency()
}

func formatarPercentual(_ valor: String) -> String {
    // Remove qualquer caractere não numérico, mas preserva zeros
    let digits = valor.filter { $0.isNumber }
    
    // Garante que a entrada sempre tenha pelo menos um zero
    guard !digits.isEmpty else { return "0,00%" }
    
    // Divide o valor bruto por 100 para exibição
    let doubleValue = (Double(digits) ?? 0) / 100

    // Configura o NumberFormatter para o formato brasileiro
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    formatter.locale = Locale(identifier: "pt_BR") // Define o formato brasileiro

    // Formata o valor como percentual no formato brasileiro
    let formattedValue = formatter.string(from: NSNumber(value: doubleValue)) ?? "0,00"
    return "\(formattedValue)%"
}

// MARK: - Extensões para Array
extension Array {
    func groupedBy<T: Hashable>(key: (Element) -> T) -> [T: [Element]] {
        var dict: [T: [Element]] = [:]
        for element in self {
            let groupKey = key(element)
            dict[groupKey, default: []].append(element)
        }
        return dict
    }
}

/*
// MARK: - DailyBalance (caso ainda não tenha um struct DailyBalance)
struct DailyBalance: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    var saldo: Double

    static func == (lhs: DailyBalance, rhs: DailyBalance) -> Bool {
        return lhs.date == rhs.date && lhs.saldo == rhs.saldo
    }
}
*/

// MARK: - Extensão para gerar DailyBalance ignorando operações em cartão
extension Array where Element == Operacao {
    /// Gera uma lista de DailyBalance **ignorando** operações cujo metodoPagamento seja "Cartão".
    /// Isso permite que as compras em cartão não modifiquem o saldo diário e mensal.
    func dailyBalancesExcludingCards() -> [DailyBalance] {
        let calendar = Calendar.current
        
        // Filtra operações que NÃO são cartão
        let opsNaoCartao = self.filter { $0.metodoPagamento != "Cartão" }
        
        // Agrupa por dia (startOfDay)
        let groupedByDay = Dictionary(grouping: opsNaoCartao) { operacao in
            calendar.startOfDay(for: operacao.data)
        }
        
        // Monta o array de DailyBalance
        var dailyBalances: [DailyBalance] = []
        for (dia, ops) in groupedByDay {
            let somaNoDia = ops.reduce(0.0) { $0 + $1.valor }
            dailyBalances.append(DailyBalance(date: dia, saldo: somaNoDia))
        }
        
        // Ordena por data crescente
        dailyBalances.sort { $0.date < $1.date }
        
        return dailyBalances
    }
}

// MARK: - AuthenticationManager
class AuthenticationManager {
    static let shared = AuthenticationManager()

    /// Autentica o usuário usando FaceID ou TouchID.
    /// - Parameter completion: Closure que retorna `true` se a autenticação for bem-sucedida, caso contrário, `false` e uma mensagem de erro opcional.
    func authenticateWithBiometrics(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?

        // Verifica se o dispositivo suporta autenticação biométrica
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Autentique-se com FaceID para acessar sua conta."

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        completion(true, nil) // Autenticação bem-sucedida
                    } else {
                        let message = authenticationError?.localizedDescription ?? "Falha na autenticação."
                        completion(false, message)
                    }
                }
            }
        } else {
            // Biometria não disponível
            let message = error?.localizedDescription ?? "Biometria não está configurada neste dispositivo."
            completion(false, message)
        }
    }
}
