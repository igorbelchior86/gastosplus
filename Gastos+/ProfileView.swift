import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit
import CryptoKit

enum ActiveActionSheet: Identifiable {
    case reset, share

    var id: Int {
        switch self {
        case .reset: return 0
        case .share: return 1
        }
    }
}

struct ProfileView: View {
    // Suas @FetchRequests e outras propriedades
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Cartao.nome, ascending: true)],
        animation: .default
    ) private var cartoes: FetchedResults<Cartao>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Operacao.data, ascending: true)],
        animation: .default
    ) private var operacoes: FetchedResults<Operacao>
    
    @State private var notificacoesAtivadas: Bool = true
    @State private var userName: String = ""
    @State private var userEmail: String = ""
    @State private var profileImageURL: URL?
    @State private var selectedImage: UIImage?
    @State private var isImagePickerPresented = false
    @State private var usarFaceID: Bool = false
    
    @Binding var isLoggedIn: Bool
    
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var isUploading: Bool = false
    @State private var isProcessingSignOut: Bool = false
    
    @State private var generatedCode: String = ""
    @State private var enteredCode: String = ""
    @State private var showTextFieldAlert: Bool = false
    @State private var grupoAtual: String? = nil
    @State private var participantes: [Usuario] = []
    
    @State private var showSignOutAlert: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var showSuccessAlert: Bool = false
    
    // Nova variável de controle: só mostra o alerta de "sucesso" uma vez
    @AppStorage("notifiedGroupJoin") private var notifiedGroupJoin: Bool = false
    
    // Estado para controlar o ActionSheet consolidado
    @State private var activeActionSheet: ActiveActionSheet?

    // Estado para controlar a apresentação da ProgressView
    @State private var isProcessingReset: Bool = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header customizado
                headerSection
                
                // Conteúdo rolável
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Seção: Perfil
                        Section(header: sectionHeader(title: "Informações Pessoais")) {
                            profileInfo()
                        }
                        
                        // Seção: Preferências
                        Section(header: sectionHeader(title: "Preferências")) {
                            preferences()
                        }
                        
                        // Seção: Compartilhamento
                        Section(header: sectionHeader(title: "Compartilhamento")) {
                            sharingSection()
                        }
                        
                        // Seção: Ajuda
                        Section(header: sectionHeader(title: "Ajuda")) {
                            appInfo()
                        }
                        
                        // Seção: Gerenciamento
                        Section(header: sectionHeader(title: "Gerenciamento")) {
                            management()
                        }
                    }
                    .padding(.vertical, 16)
                    .background(Color(hex: "#2a2a2c")) // Fundo para o conteúdo
                }
                
                // Footer fixo
                FooterView(
                    currentScreen: .constant(.profile),
                    moneyManager: MoneyManager.shared,
                    onAddOperation: {
                        print("Adicionar operação clicado")
                    }
                )
                .background(Color(hex: "#2a2a2c"))
            }
            
            .onAppear {
                fetchUserData()
                usarFaceID = CoreDataManager.shared.fetchUsuarioAtual()?.usarFaceID ?? false

                if let userId = Auth.auth().currentUser?.uid {
                    let db = Firestore.firestore()
                    
                    // Observar mudanças no Firestore em tempo real
                    db.collection("shared_groups")
                        .whereField("participants", arrayContains: userId)
                        .addSnapshotListener { snapshot, error in
                            if let error = error {
                                print("Erro ao observar grupos compartilhados: \(error.localizedDescription)")
                                return
                            }

                            guard let documents = snapshot?.documents, !documents.isEmpty else {
                                DispatchQueue.main.async {
                                    self.grupoAtual = nil
                                    self.participantes = []
                                }
                                return
                            }

                            if let primeiroGrupo = documents.first {
                                let groupId = primeiroGrupo.documentID
                                primeiroGrupo.reference.getDocument { document, error in
                                    if let data = document?.data(),
                                       let participantes = data["participants"] as? [String] {
                                        
                                        DispatchQueue.main.async {
                                            // Atualiza o estado do grupo independentemente da contagem.
                                            self.grupoAtual = groupId
                                            self.participantes = participantes.map { id in
                                                let usuario = Usuario(context: CoreDataManager.shared.context)
                                                usuario.email = ""
                                                usuario.nome = "Carregando..."
                                                // Se você não precisa armazenar o ID do Firebase, não defina nada aqui.
                                                return usuario
                                            }
                                            // Dispara o alerta de sucesso (apenas quando houver 2 ou mais participantes)
                                            if participantes.count > 1 && !self.notifiedGroupJoin {
                                                self.alertMessage = "Os usuários entraram no grupo!"
                                                self.showSuccessAlert = true
                                                self.notifiedGroupJoin = true
                                            }
                                        }

                                        // Buscar dados detalhados dos participantes
                                        CoreDataManager.shared.buscarParticipantesDoGrupo(grupoId: groupId) { usuarios in
                                            DispatchQueue.main.async {
                                                self.participantes = usuarios
                                            }
                                        }
                                    }
                                }
                            }
                        }
                }
            }
            
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(selectedImage: $selectedImage, onImagePicked: { image in
                    uploadProfileImage(image: image)
                })
            }
            
            /// Encerrar sessão
            .alert("Encerrar Sessão", isPresented: $showSignOutAlert) {
                Button("Cancelar", role: .cancel) {
                    // Fecha o alerta
                }
                Button("Sim", role: .destructive) {
                    iniciarProcessoSignOut()
                }
            } message: {
                Text("Sua conta será desconectada. Deseja prosseguir?")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Erro"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showSuccessAlert) {
                Alert(
                    title: Text("Sucesso"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            
            /// Resetar dados
            .alert("Resetar Dados", isPresented: $showResetAlert) {
                Button("Não", role: .cancel) {
                    // Fecha o alerta
                }
                Button("Sim", role: .destructive) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        activeActionSheet = .reset
                    }
                }
            } message: {
                Text("Todos os dados serão apagados permanentemente. Esta ação não pode ser desfeita. Deseja continuar?")
            }
            
            // Modificador de ActionSheet consolidado
            .actionSheet(item: $activeActionSheet) { actionSheetType in
                switch actionSheetType {
                case .reset:
                    return ActionSheet(
                        title: Text("Apagar todos os dados"),
                        message: Text("Deseja realmente apagar todos os dados?"),
                        buttons: [
                            .destructive(Text("Continuar")) {
                                iniciarProcessoReset()
                            },
                            .cancel(Text("Cancelar")) {
                                print("Usuário cancelou a segunda confirmação")
                            }
                        ]
                    )
                case .share:
                    return ActionSheet(
                        title: Text("Código Gerado"),
                        message: Text("Compartilhe este código com o usuário:\n\(generatedCode)")
                            .font(.headline),
                        buttons: [
                            .default(Text("Copiar Código e Compartilhar")) {
                                copiarCodigoECompartilhar()
                            },
                            .cancel(Text("Cancelar"))
                        ]
                    )
                }
            }
            
            // Overlay com ProgressView quando isProcessingReset ou isProcessingSignOut é true
            if isProcessingReset || isProcessingSignOut {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    VStack(spacing: 20) {
                        if isProcessingReset {
                            ProgressView("Apagando dados...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color(hex: "#252527"))
                                .cornerRadius(10)
                        } else if isProcessingSignOut {
                            ProgressView("Desconectando...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color(hex: "#252527"))
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
    
    private func copiarCodigoECompartilhar() {
        // Copia o código para a área de transferência
        UIPasteboard.general.string = generatedCode
        print("Código \(generatedCode) copiado para a área de transferência.")
        
        // Abre o Share Sheet
        let activityVC = UIActivityViewController(
            activityItems: ["Participe do meu grupo no Gastos+ com este código: \(generatedCode)"],
            applicationActivities: nil
        )
        
        // Exibe o Share Sheet
        if let topController = UIApplication.shared.windows.first?.rootViewController {
            topController.present(activityVC, animated: true, completion: nil)
        }
    }
    
    // MARK: - Validar Código de Compartilhamento no Firestore
    func validarCodigoCompartilhamento(codigo: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let groupRef = db.collection("shared_groups").document(codigo)

        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao buscar grupo: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let document = document, document.exists else {
                alertMessage = "Código de grupo não encontrado."
                completion(false)
                return
            }

            if let participants = document.get("participants") as? [String], participants.count >= 2 {
                alertMessage = "O grupo já atingiu o limite de participantes."
                showErrorAlert = true
                completion(false)
                return
            }

            guard let userId = Auth.auth().currentUser?.uid else {
                alertMessage = "Erro ao identificar usuário."
                completion(false)
                return
            }

            groupRef.updateData([
                "participants": FieldValue.arrayUnion([userId])
            ]) { error in
                if let error = error {
                    alertMessage = "Erro ao entrar no grupo: \(error.localizedDescription)"
                    showErrorAlert = true
                    completion(false)
                } else {
                    print("Usuário \(userId) adicionado ao grupo \(codigo).")
                    self.notificarParticipantes(grupoId: codigo)
                    completion(true)
                }
            }
        }
    }
    
    private func notificarParticipantes(grupoId: String) {
        let db = Firestore.firestore()
        let groupRef = db.collection("shared_groups").document(grupoId)
        
        groupRef.updateData([
            "lastUpdate": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Erro ao notificar participantes: \(error.localizedDescription)")
            } else {
                print("Participantes notificados com sucesso.")
            }
        }
    }
    
    // Header customizado
    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle")
                .foregroundColor(.white)
                .font(.title)
            Text("Perfil")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .bold()
                .padding(.leading, -1)
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(Color(hex: "#2a2a2c").edgesIgnoringSafeArea(.all))
    }
    
    // Header das seções
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
    }
    
    // Informações do perfil
    private func profileInfo() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    if isUploading {
                        ProgressView("Carregando...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.white)
                            .frame(width: 100, height: 100)
                    } else if let profileImageURL = profileImageURL {
                        if profileImageURL.isFileURL {
                            // Carregar imagem localmente
                            if let image = UIImage(contentsOfFile: profileImageURL.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        isImagePickerPresented = true
                                    }
                            } else {
                                // Fallback caso a imagem não seja encontrada
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Text("Foto")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
                                    .onTapGesture {
                                        isImagePickerPresented = true
                                    }
                            }
                        } else {
                            // Carregar imagem remota via AsyncImage
                            AsyncImage(url: profileImageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            isImagePickerPresented = true
                                        }
                                case .failure:
                                    Circle()
                                        .fill(Color.gray)
                                        .frame(width: 100, height: 100)
                                        .overlay(
                                            Text("Foto")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                        )
                                        .onTapGesture {
                                            isImagePickerPresented = true
                                        }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    } else {
                        // Imagem de fallback quando profileImageURL é nil
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text("Foto")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            )
                            .onTapGesture {
                                isImagePickerPresented = true
                            }
                    }
                    
                    // Botão de editar
                    if !isUploading {
                        Button(action: {
                            isImagePickerPresented = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color(hex: "#007AFF"))
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .offset(x: 6, y: 6) // Posiciona no canto inferior direito
                    }
                }
                
                // Nome e E-mail
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Nome:")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    Text(userName)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#B3B3B3"))
                    
                    HStack {
                        Text("E-mail:")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#B3B3B3"))
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#252527"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    /// Busca os dados do usuário atual.
    private func fetchUserData() {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            print("Erro: Usuário não autenticado ou email inválido.")
            return
        }
        
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        
        // 🔍 Verifica se o usuário existe no Firestore
        userRef.getDocument { (document, error) in
            if let document = document, document.exists {
                print("Usuário encontrado no Firestore.")
            } else {
                print("Usuário não encontrado. Criando novo perfil...")
                self.criarUsuarioNoFirestore(user: user)
            }
        }
        
        // 🔍 Verifica se o usuário já existe no Core Data
        if let usuario = CoreDataManager.shared.fetchUsuario(email: email) {
            self.userName = usuario.nome
            self.userEmail = usuario.email
            self.usarFaceID = usuario.usarFaceID

            if usuario.hasCustomProfilePhoto, let customURLString = usuario.customProfileImageURL {
                let customURL = URL(fileURLWithPath: customURLString)
                if FileManager.default.fileExists(atPath: customURL.path) {
                    self.profileImageURL = customURL
                    print("Carregando imagem de perfil customizada: \(customURL.path)")
                }
            } else if let photoURL = user.photoURL {
                self.profileImageURL = photoURL
                print("Carregando imagem de perfil do Firebase: \(photoURL.absoluteString)")
            } else {
                self.profileImageURL = nil
                print("Nenhuma URL de imagem de perfil disponível.")
            }
        } else {
            // 🔄 Cria o usuário no Core Data se não existir
            let novoUsuario = CoreDataManager.shared.criarUsuario(email: email, nome: user.displayName ?? "Usuário")
            self.userName = novoUsuario.nome
            self.userEmail = novoUsuario.email
            self.usarFaceID = novoUsuario.usarFaceID

            if let photoURL = user.photoURL {
                self.profileImageURL = photoURL
                print("Carregando imagem de perfil do Firebase para novo usuário: \(photoURL.absoluteString)")
            } else {
                self.profileImageURL = nil
                print("Nenhuma URL de imagem de perfil disponível para novo usuário.")
            }
        }
    }
    
    private func criarUsuarioNoFirestore(user: User) {
        let db = Firestore.firestore()
        
        db.collection("users").document(user.uid).setData([
            "nome": user.displayName ?? "Usuário",
            "email": user.email ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Erro ao criar usuário: \(error.localizedDescription)")
            } else {
                print("Novo usuário criado no Firestore.")
            }
        }
    }
    
    private func monitorarParticipantes() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("shared_groups")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Erro ao monitorar participantes: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents, let primeiroGrupo = documents.first else {
                    DispatchQueue.main.async {
                        self.grupoAtual = nil
                        self.participantes = []
                    }
                    return
                }

                let groupId = primeiroGrupo.documentID
                primeiroGrupo.reference.getDocument { document, error in
                    if let data = document?.data(),
                       let participantes = data["participants"] as? [String] {

                        DispatchQueue.main.async {
                            self.grupoAtual = groupId
                            self.participantes = participantes.map { id in
                                let usuario = Usuario(context: CoreDataManager.shared.context)
                                usuario.email = ""
                                usuario.nome = "Carregando..."
                                return usuario
                            }
                        }
                    }
                }
            }
    }

    // ✅ AGORA SIM: `carregarParticipantes()` FORA de `fetchUserData()`
    private func carregarParticipantes() {
        CoreDataManager.shared.verificarGrupoCompartilhado { grupos in
            if let grupos = grupos, let primeiroGrupo = grupos.first {
                DispatchQueue.main.async {
                    self.grupoAtual = primeiroGrupo
                    CoreDataManager.shared.buscarParticipantesDoGrupo(grupoId: primeiroGrupo) { usuarios in
                        DispatchQueue.main.async {
                            self.participantes = usuarios
                        }
                    }
                }
            }
        }
    }
    
    /// Atualiza as preferências do FaceID no Core Data.
    private func atualizarPreferenciaFaceID(usarFaceID: Bool) {
        guard let usuario = CoreDataManager.shared.fetchUsuarioAtual() else {
            print("Erro: Usuário atual não encontrado.")
            return
        }
        usuario.usarFaceID = usarFaceID
        CoreDataManager.shared.salvarContexto()
        
        // Força a atualização do estado local
        DispatchQueue.main.async {
            self.usarFaceID = usuario.usarFaceID
        }
        
        if let userId = Auth.auth().currentUser?.uid {
            let db = Firestore.firestore()
            db.collection("users").document(userId).updateData(["usarFaceID": usarFaceID]) { error in
                if let error = error {
                    print("Erro ao atualizar FaceID no Firestore: \(error.localizedDescription)")
                } else {
                    print("FaceID atualizado no Firestore com sucesso.")
                }
            }
        }
    }
    
    /// Faz o upload da imagem de perfil para o armazenamento local.
    /// - Parameter image: Imagem selecionada pelo usuário.
    private func uploadProfileImage(image: UIImage) {
        isUploading = true
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Erro: Não foi possível converter a imagem para JPEG.")
            self.alertMessage = "Erro ao processar a imagem selecionada."
            self.showErrorAlert = true
            self.isUploading = false
            return
        }
        
        let fileName = "profile_images/\(UUID().uuidString).jpg"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        let profileImagesDirectory = documentsDirectory.appendingPathComponent("profile_images")
        
        if !FileManager.default.fileExists(atPath: profileImagesDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: profileImagesDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Diretório 'profile_images' criado.")
            } catch {
                print("Erro ao criar diretório profile_images: \(error.localizedDescription)")
                self.alertMessage = "Erro ao criar diretório para salvar a imagem."
                self.showErrorAlert = true
                self.isUploading = false
                return
            }
        }
        
        do {
            try imageData.write(to: fileURL)
            print("Imagem salva localmente em: \(fileURL.path)")
        } catch {
            print("Erro ao salvar a imagem localmente: \(error.localizedDescription)")
            self.alertMessage = "Erro ao salvar a imagem localmente."
            self.showErrorAlert = true
            self.isUploading = false
            return
        }
        
        DispatchQueue.main.async {
            self.profileImageURL = fileURL
            self.isUploading = false
            
            if let userEmail = Auth.auth().currentUser?.email,
               let usuario = CoreDataManager.shared.fetchUsuario(email: userEmail) {
                usuario.customProfileImageURL = fileURL.path // Salva a URL da imagem
                usuario.hasCustomProfilePhoto = true                 // Marca que o usuário escolheu uma foto customizada
                CoreDataManager.shared.saveContext()
                print("URL da imagem de perfil customizada salva no Core Data: \(fileURL.absoluteString)")
            } else {
                print("Erro: Não foi possível recuperar o usuário para salvar a URL da imagem.")
            }
        }
    }
    
    // Seção de Preferências
    private func preferences() -> some View {
        VStack(spacing: 0) {
            // Linha: Moeda Padrão
            preferenceRow(title: "Moeda Padrão", value: "Placeholder")
                .padding(.vertical, 2)
            
            // Divisor
            Divider()
                .background(Color(hex: "#3e3e40"))
            
            // Linha: Idioma do App
            preferenceRow(title: "Idioma do App", value: "Placeholder")
                .padding(.vertical, 2)
            
            // Divisor
            Divider()
                .background(Color(hex: "#3e3e40"))
            
            // Linha: Notificações
            preferenceToggleRow(title: "Notificações", isOn: $notificacoesAtivadas)
                .padding(.vertical, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "#252527"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func preferenceRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(Color(hex: "#B3B3B3"))
        }
        .frame(height: 48) // Garante altura consistente
    }
    
    private func preferenceToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#007AFF")))
        }
        .frame(height: 48) // Garante altura consistente
    }
    
    // Seção de Gerenciamento
    private func management() -> some View {
        VStack(spacing: 0) {
            // Linha: Ativar/Desativar FaceID
            HStack {
                Text("Usar FaceID para login")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                Toggle("", isOn: $usarFaceID)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#007AFF")))
                    .onChange(of: usarFaceID) { newValue in
                        atualizarPreferenciaFaceID(usarFaceID: newValue)
                    }
            }
            .padding()
            .background(Color(hex: "#252527"))
            
            // Divisor
            Divider()
                .background(Color(hex: "#3e3e40"))
            
            // Linha: Resetar Dados
            Button(action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showResetAlert = true
                }
            }) {
                HStack {
                    Text("Resetar Dados")
                        .font(.headline)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "#252527"))
                .cornerRadius(12)
            }
            
            // Divisor
            Divider()
                .background(Color(hex: "#3e3e40"))
            
            // Linha: Encerrar Sessão
            Button(action: {
                print("Encerrar Sessão clicado")
                encerrarSessaoInitiate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print("📢 Estado Atual de showSignOutAlert: \(showSignOutAlert)")
                }
            }) {
                HStack {
                    Text("Encerrar Sessão")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "#007AFF"))
                .cornerRadius(12)
            }
        }
        .padding(.bottom, 80)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    // Seção de Informações do App
    private func appInfo() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Versão do App")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("1.0.0")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                    .padding(.vertical, 4)
            }
            
            // Divisor
            Divider()
                .background(Color(hex: "#3e3e40"))
            
            HStack {
                Text("Sobre o App")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("Organizador Financeiro")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#B3B3B3"))
                    .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(Color(hex: "#252527"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func placeholderOption(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(Color(hex: "#B3B3B3"))
        }
        .padding(16)
        .background(Color(hex: "#252527"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    /// Função para iniciar o processo de reset e logout
    private func iniciarProcessoReset() {
        isProcessingReset = true
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: usuário não autenticado.")
            self.isProcessingReset = false
            return
        }

        let db = Firestore.firestore()
        
        // 1) Sair de TODOS os grupos que este usuário participa
        db.collection("shared_groups")
          .whereField("participants", arrayContains: userId)
          .getDocuments { snapshot, error in
              if let error = error {
                  print("Erro ao buscar grupos do usuário: \(error.localizedDescription)")
              } else if let snapshot = snapshot {
                  for doc in snapshot.documents {
                      let groupId = doc.documentID
                      // Remove o usuário do array "participants" de cada grupo
                      // ...
                      db.collection("shared_groups").document(groupId).updateData([
                          "participants": FieldValue.arrayRemove([userId])
                      ]) { err in
                          if let err = err {
                              print("Erro ao remover do grupo \(groupId): \(err.localizedDescription)")
                          } else {
                              print("Usuário removido do grupo \(groupId).")

                              // VERIFICA SE O GRUPO FICOU VAZIO
                              db.collection("shared_groups").document(groupId).getDocument { docSnapshot, _ in
                                  guard let data = docSnapshot?.data() else { return }
                                  let part = data["participants"] as? [String] ?? []

                                  // Se ficou vazio (ou 0 participantes), apaga totalmente
                                  if part.isEmpty {
                                      CoreDataManager.shared.encerrarCompartilhamento(grupoId: groupId) { success in
                                          if success {
                                              print("Grupo \(groupId) excluído do Firestore pois não tinha mais participantes.")
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
              
              // 2) Apagar todos os dados do Firestore relativos a este usuário
              let userDoc = db.collection("users").document(userId)

              // Exemplo: apaga a subcoleção "cards"
              userDoc.collection("cards").getDocuments { cardsSnap, _ in
                  cardsSnap?.documents.forEach { $0.reference.delete() }
                  
                  // Exemplo: apaga a subcoleção "operations"
                  userDoc.collection("operations").getDocuments { opsSnap, _ in
                      opsSnap?.documents.forEach { $0.reference.delete() }
                      
                      // Se tiver outras subcoleções (faturas, recurrences etc.) faça o mesmo
                      // ...

                      // Por fim, apaga o próprio documento do usuário
                      userDoc.delete { delError in
                          if let delError = delError {
                              print("Erro ao apagar doc do user: \(delError.localizedDescription)")
                          } else {
                              print("Documento do usuário removido do Firestore com sucesso.")
                          }

                          // 3) Agora limpa local (Core Data)
                          self.resetarDados()
                          
                          // 4) E faz logout
                          self.logout()
                          
                          DispatchQueue.main.async {
                              self.isProcessingReset = false
                          }
                      }
                  }
              }
          }
    }
    
    // Função para iniciar o fluxo de logout com confirmação
    private func encerrarSessaoInitiate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showSignOutAlert = true
        }
    }

    /// Inicia o processo de logout
    private func iniciarProcessoSignOut() {
        isProcessingSignOut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            logout()
        }
    }

    /// Exibe o alerta de reset de dados
    private func resetarDadosInitiate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showResetAlert = true
        }
    }
    
    /// Função para resetar os dados
    private func resetarDados() {
        CoreDataManager.shared.resetPersistentStore()
        print("Persistent store resetada com sucesso.")
        // Depois do reset, recarregue os dados para atualizar a UI
        Task {
            await MoneyManager.shared.carregarDados()
        }
    }

    /// Função de logout que desloga do Firebase e atualiza o estado de login.
    private func logout() {
        do {
            if let usuario = CoreDataManager.shared.fetchUsuarioAtual() {
                usuario.usarFaceID = false
                CoreDataManager.shared.saveContext()
                print("FaceID desativado para o usuário.")
            }
            
            try Auth.auth().signOut()
            isLoggedIn = false
            print("Usuário deslogado com sucesso.")
            
        } catch let error {
            print("Erro ao deslogar: \(error.localizedDescription)")
            alertMessage = "Erro ao deslogar: \(error.localizedDescription)"
            showErrorAlert = true
        }
        
        isProcessingSignOut = false
    }
    
    private func sharingSection() -> some View {
        VStack(spacing: 0) {
            // Opção: Convidar Usuário
            Button(action: {
                if participantes.count >= 2 {
                    // 🔴 Já há dois participantes, impedir nova criação
                    alertMessage = "Você já está em um compartilhamento ativo. Saia primeiro para criar um novo."
                    showErrorAlert = true
                } else {
                    // 🟢 Permitir gerar um código de compartilhamento
                    gerarCodigoCompartilhamento()
                }
            }) {
                HStack {
                    Text("Convidar Usuário")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "#252527"))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .background(Color(hex: "#3e3e40"))

            // Opção: Entrar no Compartilhamento
            Button(action: {
                if participantes.count >= 2 {
                    // 🔴 Já há dois participantes, impedir nova entrada
                    alertMessage = "Você já está em um compartilhamento ativo. Saia primeiro para entrar em outro."
                    showErrorAlert = true
                } else {
                    // 🟢 Permitir a entrada no grupo digitando um código
                    DispatchQueue.main.async {
                        enteredCode = "" // 🔹 Garante que o campo de código está limpo
                        showTextFieldAlert = true
                    }
                }
            }) {
                HStack {
                    Text("Entrar no Compartilhamento")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .background(Color(hex: "#252527"))
                .cornerRadius(12)
            }
            .alert("Entrar no Compartilhamento", isPresented: $showTextFieldAlert) {
                TextField("Código do grupo", text: $enteredCode)
                Button("Cancelar", role: .cancel) { }
                Button("Confirmar") {
                    if enteredCode.isEmpty {
                        alertMessage = "Por favor, insira um código válido."
                        showErrorAlert = true
                    } else {
                        validarCodigoCompartilhamento(codigo: enteredCode) { sucesso in
                            DispatchQueue.main.async {
                                if sucesso {
                                    alertMessage = "Você entrou no grupo com sucesso!"
                                    showSuccessAlert = true
                                    showTextFieldAlert = false // 🔹 Fecha o alerta após sucesso
                                } else {
                                    alertMessage = "Código inválido ou erro ao entrar no grupo."
                                    showErrorAlert = true
                                }
                            }
                        }
                    }
                }
            } message: {
                Text("Digite o código compartilhado para ingressar no grupo.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            /*
            // Botão: Compartilhamento Ativo (Se usuário já estiver em um grupo)
            if let grupoId = grupoAtual {
                Divider()
                    .background(Color(hex: "#3e3e40"))

                Button(action: {
                    showAlert = true
                }) {
                    HStack {
                        Text("Compartilhamento Ativo")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Color(hex: "#252527"))
                    .cornerRadius(12)
                }
                .alert("Sair do Compartilhamento", isPresented: $showAlert) {
                    Button("Cancelar", role: .cancel) { }
                    Button("Manter Dados") {
                        sairDoCompartilhamento(manterDados: true)
                    }
                    Button("Excluir Dados", role: .destructive) {
                        sairDoCompartilhamento(manterDados: false)
                    }
                } message: {
                    Text("Ao sair do compartilhamento, você pode escolher manter ou excluir os dados compartilhados.")
                }
            }
             */

            // Botão: Compartilhamento Ativo
            Divider()
                .background(Color(hex: "#3e3e40"))

            Button(action: {
                if participantes.count == 2 {
                    showAlert = true // 🔹 Exibir alerta para saída do grupo
                } else {
                    alertMessage = "O compartilhamento ainda não foi ativado."
                    showErrorAlert = true
                }
            }) {
                HStack {
                    Text("Compartilhamento Ativo")
                        .font(.headline)
                        .foregroundColor(participantes.count == 2 ? .red : Color(hex: "#B3B3B3")) // 🔴 Vermelho se houver 2 participantes, ⚪️ cinza caso contrário
                    Spacer()
                }
                .padding()
                .background(Color(hex: "#252527"))
                .cornerRadius(12)
            }
            .onAppear {
                monitorarParticipantes() // 🔹 Garante que o botão sempre reflete o estado correto
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .alert("Sair do Compartilhamento", isPresented: $showAlert) {
                Button("Cancelar", role: .cancel) { }
                Button("Sair", role: .destructive) {
                    if let grupoId = grupoAtual {
                        CoreDataManager.shared.sairDoGrupoCompartilhado(grupoId: grupoId) { sucesso in
                            DispatchQueue.main.async {
                                if sucesso {
                                    grupoAtual = nil
                                    participantes.removeAll()
                                    alertMessage = "Você saiu do compartilhamento."
                                    showSuccessAlert = true
                                } else {
                                    alertMessage = "Erro ao sair do compartilhamento."
                                    showErrorAlert = true
                                }
                            }
                        }
                    }
                }
            } message: {
                Text("Deseja realmente sair do grupo de compartilhamento? Você perderá o acesso aos dados compartilhados.")
            }
            
        }
        .background(Color(hex: "#252527"))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private func sairDoCompartilhamento(manterDados: Bool) {
        guard let userId = Auth.auth().currentUser?.uid, let grupoId = grupoAtual else {
            print("Erro: Usuário ou grupo não encontrados.")
            return
        }

        let db = Firestore.firestore()
        let groupRef = db.collection("shared_groups").document(grupoId)

        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao buscar grupo: \(error.localizedDescription)")
                return
            }

            guard let data = document?.data(), var participantes = data["participants"] as? [String] else {
                print("Dados do grupo inválidos.")
                return
            }

            // Remove o usuário do grupo
            participantes.removeAll { $0 == userId }

            if participantes.isEmpty {
                // ✅ Se o grupo ficar vazio, exclui do Firestore
                groupRef.delete { error in
                    if let error = error {
                        print("Erro ao excluir grupo: \(error.localizedDescription)")
                    } else {
                        print("Grupo excluído com sucesso.")
                    }
                }
            } else {
                // ✅ Atualiza o grupo sem o usuário que saiu
                groupRef.updateData(["participants": participantes]) { error in
                    if let error = error {
                        print("Erro ao atualizar grupo: \(error.localizedDescription)")
                    }
                }
            }

            DispatchQueue.main.async {
                // ✅ Atualiza a UI para ambos os usuários
                self.grupoAtual = nil
                self.participantes.removeAll()

                if !manterDados {
                    CoreDataManager.shared.removerDadosDoGrupo(grupoId: grupoId)
                }

                self.alertMessage = "Você saiu do compartilhamento com sucesso."
                self.showSuccessAlert = true
            }
        }
    }
    
    private func gerarCodigoCompartilhamento() {
        guard let userId = Auth.auth().currentUser?.uid else {
            alertMessage = "Erro ao autenticar usuário."
            showErrorAlert = true
            return
        }

        let db = Firestore.firestore()
        let groupsRef = db.collection("shared_groups")

        // Verifica se o usuário já tem um código pendente
        groupsRef.whereField("participants", arrayContains: userId).getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao buscar grupos existentes: \(error.localizedDescription)")
                return
            }

            if let existingGroup = snapshot?.documents.first {
                // ✅ O usuário já gerou um código antes, mas ninguém aceitou. Reutiliza o código existente.
                if let participantes = existingGroup.data()["participants"] as? [String], participantes.count == 1 {
                    DispatchQueue.main.async {
                        self.generatedCode = existingGroup.documentID
                        self.activeActionSheet = .share
                    }
                    return
                }
            }

            // ✅ Nenhum código pendente encontrado, gera um novo
            let caracteres = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            let novoCodigo = String((0..<6).map { _ in caracteres.randomElement()! })

            groupsRef.document(novoCodigo).setData([
                "participants": [userId],
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.alertMessage = "Erro ao criar o grupo: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                } else {
                    DispatchQueue.main.async {
                        self.generatedCode = novoCodigo
                        self.activeActionSheet = .share
                    }
                }
            }
        }
    }

    private func entrarNoCompartilhamento() {
        if grupoAtual != nil {
            alertMessage = "Você já está em um grupo de compartilhamento. Saia primeiro para entrar em outro."
            showErrorAlert = true
            return
        }
        showTextFieldAlert = true
    }
    
}

// Define uma struct para os dados do perfil.
struct ProfileData: Equatable {
    let name: String
    let email: String
    let usingFaceID: Bool
    let imageURL: URL?
}

// Componente para selecionar imagem da galeria
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
                parent.selectedImage = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct EnterSharingCodeView: View {
    @Binding var enteredCode: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Insira o código compartilhado para participar do grupo.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                
                TextField("Digite o código", text: $enteredCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationBarTitle("Entrar no Compartilhamento", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancelar") {
                    onCancel()
                },
                trailing: Button("Confirmar") {
                    onConfirm()
                }
                .disabled(enteredCode.isEmpty)
            )
        }
    }
}

struct SharingView: View {
    @State private var participantes: [Usuario] = []
    @State private var grupoAtual: String? = nil

    var body: some View {
        NavigationView {
            VStack {
                if participantes.isEmpty {
                    Text("Nenhum participante encontrado.")
                        .foregroundColor(.gray)
                } else {
                    List(participantes, id: \.id) { usuario in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(usuario.nome)
                                    .font(.headline)
                                Text(usuario.email)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("Compartilhamento")
            .onAppear {
                carregarParticipantes()
            }
        }
    }

    private func carregarParticipantes() {
        CoreDataManager.shared.verificarGrupoCompartilhado { grupos in
            if let grupos = grupos, let primeiroGrupo = grupos.first {
                DispatchQueue.main.async {
                    self.grupoAtual = primeiroGrupo
                    CoreDataManager.shared.buscarParticipantesDoGrupo(grupoId: primeiroGrupo) { usuarios in
                        DispatchQueue.main.async {
                            self.participantes = usuarios
                        }
                    }
                }
            }
        }
    }
}

// Singleton para armazenar em cache os dados do perfil.
class ProfileCache: ObservableObject {
    static let shared = ProfileCache()
    @Published var profile: ProfileData? = nil
    private init() { }
    
    func loadProfile() {
        guard let user = Auth.auth().currentUser,
              let email = user.email else { return }
        
        if let usuario = CoreDataManager.shared.fetchUsuario(email: email) {
            let url: URL?
            if let customURLString = usuario.customProfileImageURL,
               let customURL = URL(string: customURLString),
               FileManager.default.fileExists(atPath: customURL.path) {
                url = customURL
            } else {
                url = user.photoURL
            }
            let newProfile = ProfileData(
                name: usuario.nome,
                email: usuario.email,
                usingFaceID: usuario.usarFaceID,
                imageURL: url
            )
            DispatchQueue.main.async {
                self.profile = newProfile
            }
        } else {
            let newProfile = ProfileData(
                name: user.displayName ?? "Usuário",
                email: email,
                usingFaceID: false,
                imageURL: user.photoURL
            )
            DispatchQueue.main.async {
                self.profile = newProfile
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(isLoggedIn: .constant(false))
            .environment(\.managedObjectContext, CoreDataManager.shared.context)
            .previewLayout(.device)
            .environment(\.colorScheme, .dark)
    }
}
