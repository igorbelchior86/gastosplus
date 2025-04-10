import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import LocalAuthentication
import Combine

enum AuthState {
    case loggedOut
    case authenticating
    case faceID
    case pinSetup
    case pin
    case loggedIn
}

// LoginView.swift
struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var authState: AuthState = .loggedOut
    @State private var errorMessage = ""
    @State private var isAuthenticating: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo escuro
                Color(hex: "#2a2a2a")
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    VStack(spacing: 8) {
                        ZStack {
                            Text("Gastos +")
                                .font(.system(size: 54, weight: .regular))
                                .foregroundColor(.gray)
                                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)

                            ShimmerView()
                                .frame(height: 54)
                                .mask(
                                    Text("Gastos +")
                                        .font(.system(size: 54, weight: .regular, design: .rounded))
                                )
                        }

                        Text("Finança simplificada")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 40)

                    Spacer()

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding(.bottom, 20)
                    }

                    if authState == .loggedOut {
                        Button(action: loginWithGoogle) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.green)

                                HStack {
                                    Image("google_icon")
                                        .resizable()
                                        .frame(width: 34, height: 34)
                                        .padding(.leading, 20)

                                    Spacer()

                                    Text("Continuar com Google")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.trailing, 90)
                                }
                            }
                            .frame(height: 50)
                            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }

                if isAuthenticating {
                    ProgressView("Autenticando...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                // Observa notificações para atualizar o authState
                NotificationCenter.default.addObserver(forName: .didUpdateData, object: nil, queue: .main) { notification in
                    if let userInfo = notification.userInfo,
                       let newAuthState = userInfo["authState"] as? AuthState {
                        self.authState = newAuthState
                    }
                }

                // Observa a notificação de autenticação bem-sucedida
                NotificationCenter.default.addObserver(forName: .didAuthenticate, object: nil, queue: .main) { _ in
                    self.authState = .loggedIn
                }

                verificarAutenticacaoInicial()
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: .didUpdateData, object: nil)
                NotificationCenter.default.removeObserver(self, name: .didAuthenticate, object: nil)
            }
            .sheet(isPresented: Binding<Bool>(
                get: { authState == .pin && !isLoggedIn },
                set: { _ in }
            )) {
                if authState == .pin {
                    if let usuarioAtual = CoreDataManager.shared.fetchUsuarioAtual(),
                       let pinSalvo = usuarioAtual.pin, !pinSalvo.isEmpty {
                        PinEntryView(isLoggedIn: $isLoggedIn, authState: $authState, pinSalvo: pinSalvo)
                    } else {
                        Text("Erro: Não foi possível encontrar o PIN.")
                            .foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: Binding<Bool>(
                get: { authState == .pinSetup },
                set: { _ in }
            )) {
                PinSetupView(isLoggedIn: $isLoggedIn, authState: $authState)
            }
        }
    }

    func verificarAutenticacaoInicial() {
        DispatchQueue.main.async {
            if let usuarioAtual = CoreDataManager.shared.fetchUsuarioAtual() {
                if usuarioAtual.usarFaceID {
                    autenticarComFaceID(usuario: usuarioAtual)
                } else if let pinSalvo = usuarioAtual.pin, !pinSalvo.isEmpty {
                    authState = .pin
                } else {
                    authState = .loggedOut
                }
            } else {
                authState = .loggedOut
            }
        }
    }

    func autenticarComFaceID(usuario: Usuario) {
        isAuthenticating = true
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Confirme o uso do FaceID para continuar."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { sucesso, _ in
                DispatchQueue.main.async {
                    isAuthenticating = false
                    if sucesso {
                        if Auth.auth().currentUser != nil {
                            self.authState = .loggedIn
                            self.isLoggedIn = true // 🚀 Aqui definimos que o usuário autenticou com sucesso
                            NotificationCenter.default.post(name: .didAuthenticate, object: nil)
                            print("Autenticação via FaceID bem-sucedida.")
                        } else {
                            print("FaceID autenticou, mas não há usuário logado.")
                            self.authState = .loggedOut
                        }
                    } else {
                        print("Falha na autenticação via FaceID.")
                        if let pinSalvo = usuario.pin, !pinSalvo.isEmpty {
                            self.authState = .pin
                        } else {
                            self.authState = .loggedOut
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                isAuthenticating = false
                print("FaceID não está disponível neste dispositivo.")
                if let pinSalvo = usuario.pin, !pinSalvo.isEmpty {
                    self.authState = .pin
                } else {
                    self.authState = .loggedOut
                }
            }
        }
    }

    func loginWithGoogle() {
        isAuthenticating = true
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Erro ao carregar configurações do Firebase."
            isAuthenticating = false
            return
        }
        
        // Define a configuração global para o GoogleSignIn
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        
        // Obtenha o rootViewController para apresentar a tela de login
        guard let rootViewController = UIApplication.shared.windows.first?.rootViewController else {
            errorMessage = "Erro: Root view controller não encontrado."
            isAuthenticating = false
            return
        }
        
        // Chame o novo método de signIn
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint: nil, additionalScopes: []) { result, error in
            if let error = error {
                print("Erro no login com Google: \(error.localizedDescription)")
                self.isAuthenticating = false
                return
            }
            
            guard let result = result else {
                print("Erro: Resultado da autenticação nulo.")
                self.isAuthenticating = false
                return
            }
            
            // Acessa o usuário autenticado
            let user = result.user
            
            // Obtém a autenticação do usuário (com idToken e accessToken)
            guard let idTokenString = user.idToken?.tokenString else {
                print("Erro ao obter o idToken do Google.")
                self.isAuthenticating = false
                return
            }
            let accessTokenString = user.accessToken.tokenString

            let credential = GoogleAuthProvider.credential(withIDToken: idTokenString, accessToken: accessTokenString)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Erro ao autenticar com Firebase: \(error.localizedDescription)")
                    self.isAuthenticating = false
                    return
                }
                
                guard let authResult = authResult else {
                    print("Erro: Resultado da autenticação no Firebase nulo.")
                    self.isAuthenticating = false
                    return
                }
                
                let userId = authResult.user.uid
                let email = authResult.user.email ?? "desconhecido"
                let nome = authResult.user.displayName ?? "Usuário"
                
                print("Login bem-sucedido com Google: \(email)")
                
                // Atualiza o Core Data
                let usuario = CoreDataManager.shared.fetchUsuario(email: email)
                    ?? CoreDataManager.shared.criarUsuario(email: email, nome: nome)
                
                // Atualiza o authState para refletir o login
                self.authState = .loggedIn
                
                // Se FaceID já estiver ativado, autentica imediatamente
                if usuario.usarFaceID {
                    self.autenticarComFaceID(usuario: usuario)
                } else {
                    // Pergunta se quer ativar FaceID
                    self.mostrarAlertaFaceID()
                }
                
                self.isAuthenticating = false
            }
        }
    }

    func mostrarAlertaFaceID() {
        guard let usuarioAtual = CoreDataManager.shared.fetchUsuarioAtual() else { return }

        let alert = UIAlertController(
            title: "Ativar FaceID?",
            message: "Deseja usar o FaceID para logins futuros?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Sim", style: .default, handler: { _ in
            CoreDataManager.shared.atualizarPreferenciaFaceID(usuario: usuarioAtual, usarFaceID: true)
            print("FaceID ativado para o usuário.")

            // 🔹 CHAMAR AUTENTICAÇÃO IMEDIATA
            autenticarComFaceID(usuario: usuarioAtual)
        }))

        alert.addAction(UIAlertAction(title: "Não", style: .cancel, handler: { _ in
            print("Redirecionando para configuração de PIN.")
            authState = .pinSetup
        }))

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.present(alert, animated: true, completion: nil)
        }
    }
}

func criarUsuarioNoFirestore(userId: String, email: String, nome: String, usarFaceID: Bool, customProfileImageURL: String? = nil, pin: String? = nil) {
    let db = Firestore.firestore()
    
    // Dados do usuário
    let userData: [String: Any] = [
        "id": userId,
        "email": email,
        "nome": nome,
        "usarFaceID": usarFaceID,
        "customProfileImageURL": customProfileImageURL ?? "",
        "pin": pin ?? ""
    ]
    
    // Adiciona o usuário na coleção "users"
    db.collection("users").document(userId).setData(userData) { error in
        if let error = error {
            print("Erro ao criar usuário no Firestore: \(error.localizedDescription)")
        } else {
            print("Usuário criado com sucesso no Firestore!")
        }
    }
}

struct PinSetupView: View {
    @Binding var isLoggedIn: Bool
    @Binding var authState: AuthState // Adicione isto
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var errorMessage: String = ""

    enum Field: Hashable {
        case pin
        case confirmPin
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            Color(hex: "#2a2a2a")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Configure um PIN")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)

                SecureField("Digite um PIN de 4 dígitos", text: $pin)
                    .keyboardType(.numberPad)
                    .padding()
                    .foregroundColor(.white.opacity(0.6))
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .focused($focusedField, equals: .pin)
                    .onChange(of: pin) { newValue in
                        if newValue.count > 4 {
                            pin = String(newValue.prefix(4))
                        }

                        if pin.count == 4 {
                            focusedField = .confirmPin
                        }
                    }

                SecureField("Confirme o PIN", text: $confirmPin)
                    .keyboardType(.numberPad)
                    .padding()
                    .foregroundColor(.white.opacity(0.6))
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .focused($focusedField, equals: .confirmPin)
                    .onChange(of: confirmPin) { newValue in
                        if newValue.count > 4 {
                            confirmPin = String(newValue.prefix(4))
                        }

                        if confirmPin.count == 4 {
                            verificarPin()
                        }
                    }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focusedField = .pin
            }
        }
    }

    func verificarPin() {
        guard pin == confirmPin else {
            errorMessage = "Os PINs não coincidem. Por favor, tente novamente."
            pin = ""
            confirmPin = ""
            focusedField = .pin
            return
        }

        if let usuarioAtual = CoreDataManager.shared.fetchUsuarioAtual() {
            CoreDataManager.shared.atualizarPin(usuario: usuarioAtual, pin: pin)
            print("PIN atualizado no Core Data para o usuário: \(usuarioAtual.email ?? "desconhecido").")
            print("PIN configurado com sucesso!")

            DispatchQueue.main.async {
                // Posta a notificação para indicar que a autenticação adicional foi concluída
                NotificationCenter.default.post(name: .didAuthenticate, object: nil)
                // Atualiza o authState para refletir o login
                authState = .loggedIn
            }
            print("Usuário autenticado após configuração do PIN.")
        } else {
            errorMessage = "Erro ao salvar o PIN. Tente novamente."
        }
    }
}

struct PinEntryView: View {
    @Binding var isLoggedIn: Bool
    @Binding var authState: AuthState
    let pinSalvo: String
    @State private var pinDigitado: String = ""
    @State private var errorMessage: String = ""
    @FocusState private var isPinFieldFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: "#2a2a2a")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Digite seu PIN")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)

                SecureField("PIN de 4 dígitos", text: $pinDigitado)
                    .keyboardType(.numberPad)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .focused($isPinFieldFocused)
                    .onChange(of: pinDigitado) { newValue in
                        if newValue.count > 4 {
                            pinDigitado = String(newValue.prefix(4))
                        }

                        if pinDigitado.count == 4 {
                            verificarPin()
                        }
                    }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isPinFieldFocused = true
            }
        }
    }

    func verificarPin() {
        if pinDigitado == pinSalvo {
            print("Autenticação via PIN bem-sucedida.")
            DispatchQueue.main.async {
                // Posta a notificação para indicar que a autenticação adicional foi concluída
                NotificationCenter.default.post(name: .didAuthenticate, object: nil)
                // Atualiza o authState para refletir o login
                authState = .loggedIn
            }
        } else {
            errorMessage = "PIN incorreto. Tente novamente."
            pinDigitado = ""
            isPinFieldFocused = true
            print("Falha na autenticação via PIN.")
        }
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.white.opacity(0.5),
                Color.white.opacity(0.7),
                Color.white.opacity(0.5),
                Color.clear
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .rotationEffect(.degrees(120))
        .offset(x: phase * 350 - 200)
        .animation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false), value: phase)
        .mask(
            Rectangle()
                .fill(Color.white)
        )
        .onAppear {
            phase = 1.0
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(isLoggedIn: .constant(false))
    }
}

// MARK: - Monitor de app em background
class SessionManager: ObservableObject {
    @Published var isSessionActive: Bool = true
    private var backgroundTimestamp: Date?

    func appDidEnterBackground() {
        backgroundTimestamp = Date()
    }

    func appWillEnterForeground() {
        guard let lastBackgroundDate = backgroundTimestamp else { return }
        let timeInBackground = Date().timeIntervalSince(lastBackgroundDate)
        isSessionActive = timeInBackground < 300 // 5 minutos de limite
    }

    func resetSession() {
        isSessionActive = false
    }
}
