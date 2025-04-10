import SwiftUI
import Foundation


struct FooterView: View {
    @Binding var currentScreen: Screen
    var moneyManager: MoneyManager
    var onAddOperation: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "#2a2a2c")
                .edgesIgnoringSafeArea(.bottom)

            HStack(alignment: .center) {
                VStack(spacing: 4) {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        currentScreen = .home
                        moneyManager.handleHomeTap() // Novo método
                    }) {
                        VStack {
                            Image(systemName: "house.fill")
                                .font(.system(size: 24))
                            Text("Home")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(currentScreen == .home ? Color(hex: "#007AFF") : Color(hex: "#B3B3B3"))
                }
                .frame(maxWidth: .infinity)

                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onAddOperation()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(hex: "#00CFFF"), Color(hex: "#007AFF")]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 68, height: 68)
                            .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 2)

                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                VStack(spacing: 4) {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        currentScreen = .profile
                    }) {
                        VStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 24))
                            Text("Perfil")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(currentScreen == .profile ? Color(hex: "#007AFF") : Color(hex: "#B3B3B3"))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 80)
    }
}
