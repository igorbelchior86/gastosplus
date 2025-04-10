import Foundation
import UserNotifications


final class NotificationsManager {
    static let shared = NotificationsManager()

    private init() {}

    // MARK: - Solicitar Permissão do Usuário
    func solicitarPermissaoNotificacoes() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Erro ao solicitar permissão para notificações: \(error.localizedDescription)")
            }
            print("Permissão concedida: \(granted)")
        }
    }

    // MARK: - Agendar Notificação de Vencimento de Fatura
    func agendarNotificacaoFatura(fatura: Fatura) {
        let dataVencimento = fatura.dataVencimento

        let content = UNMutableNotificationContent()
        content.title = "Fatura Vencendo"
        content.body = "A fatura do cartão \(fatura.cartao?.apelido ?? "Sem Nome") vence hoje. Não esqueça de realizar o pagamento!"
        content.sound = .default

        // Configurar o gatilho para a data de vencimento (à 9h do dia)
        let gatilho = criarGatilhoParaData(dataVencimento)

        // Criar a solicitação
        let request = UNNotificationRequest(
            identifier: "fatura_\(fatura.id.uuidString)",
            content: content,
            trigger: gatilho
        )

        // Adicionar a solicitação
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao agendar notificação de fatura: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Agendar Notificação de Contas do Dia
    func agendarNotificacaoContas(data: Date, operacoes: [Operacao]) {
        guard !operacoes.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Contas do Dia"
        content.body = "Você tem \(operacoes.count) conta(s) agendada(s) para hoje. Não esqueça de confirmar o pagamento!"
        content.sound = .default

        // Configurar o gatilho para 8h do dia
        let gatilho = criarGatilhoParaData(data)

        // Criar a solicitação
        let request = UNNotificationRequest(
            identifier: "contas_\(data.timeIntervalSince1970)",
            content: content,
            trigger: gatilho
        )

        // Adicionar a solicitação
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao agendar notificação de contas: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cancelar Todas as Notificações
    func cancelarTodasNotificacoes() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("Todas as notificações pendentes foram canceladas.")
    }

    // MARK: - Helpers

    /// Cria um gatilho para uma notificação agendada para uma data específica
    private func criarGatilhoParaData(_ data: Date) -> UNCalendarNotificationTrigger {
        let calendario = Calendar.current
        let componentes = calendario.dateComponents([.year, .month, .day, .hour, .minute, .second], from: data)

        return UNCalendarNotificationTrigger(dateMatching: componentes, repeats: false)
    }
}
