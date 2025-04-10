import CoreData
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import UserNotifications

// MARK: - Notifications
extension Notification.Name {
    static let didUpdateData = Notification.Name("didUpdateData")
}

// ======================================================
// MARK: - CoreDataManager (Singleton)
// ======================================================
final class CoreDataManager {
    
    // MARK: Singleton
    static let shared = CoreDataManager()
    
    // Armazena os listeners para cada grupo (a chave pode ser o grupoId)
    private var groupListeners: [String: [ListenerRegistration]] = [:]
    
    // MARK: Container e Contexto
    let persistentContainer: NSPersistentContainer
    var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    // MARK: - Inicialização Privada
    private init() {
        // (1) Criar o ManagedObjectModel programaticamente
        let model = CoreDataManager.createManagedObjectModel()
        
        // (2) Inicializar o NSPersistentContainer
        persistentContainer = NSPersistentContainer(name: "Gastos+", managedObjectModel: model)
        
        // (3) Configurar armazenamento em memória para previews (opcional/desativado)
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            /*
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            persistentContainer.persistentStoreDescriptions = [description]
            */
        } else {
            // (4) Ativar migração leve
            if let description = persistentContainer.persistentStoreDescriptions.first {
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
            }
        }
        
        // (5) Carregar as Persistent Stores e corrigir dados inválidos
        persistentContainer.loadPersistentStores { [weak self] _, error in
            if let error = error as NSError? {
                fatalError("Erro ao carregar Core Data: \(error), \(error.userInfo)")
            } else {
                print("Store carregada com sucesso.")
                self?.corrigirDadosInvalidos()
            }
        }
        
        // (6) Configurar políticas de mesclagem
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // MARK: - Correção de Dados Inválidos
    private func corrigirDadosInvalidos() {
        let context = persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Operacao")
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "data == nil"),
            NSPredicate(format: "id == nil")
        ])
        fetchRequest.predicate = predicate
        
        do {
            let results = try context.fetch(fetchRequest)
            print("Encontradas \(results.count) operações com dados inválidos.")
            for operacao in results {
                if operacao.value(forKey: "data") == nil {
                    operacao.setValue(Date(), forKey: "data")
                    print("Corrigido 'data' para Operacao ID: \(operacao.value(forKey: "id") ?? "Sem ID")")
                }
                if operacao.value(forKey: "id") == nil {
                    operacao.setValue(UUID(), forKey: "id")
                    print("Corrigido 'id' para Operacao.")
                }
            }
            try context.save()
            print("Dados inválidos corrigidos com sucesso.")
        } catch {
            print("Erro ao corrigir dados inválidos: \(error)")
        }
    }
    
    func resetPersistentStore() {
        let coordinator = persistentContainer.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            if let storeURL = store.url {
                do {
                    // Remove a store do coordinator.
                    try coordinator.remove(store)
                    // Remove o arquivo físico.
                    try FileManager.default.removeItem(at: storeURL)
                    print("Persistent store removida e arquivo deletado: \(storeURL)")
                } catch {
                    print("Erro ao resetar a persistent store: \(error.localizedDescription)")
                }
            }
        }
        // Recarrega a persistent store.
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Erro ao recarregar persistent store: \(error.localizedDescription)")
            } else {
                print("Persistent store recarregada com sucesso: \(description)")
            }
        }
    }
    
    // MARK: - Criação do Modelo (Estático)
    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // (A) Declarar todas as entidades
        // ------------------------------------------------------
        // Entidade Cartao
        let cartaoEntity = NSEntityDescription()
        cartaoEntity.name = "Cartao"
        cartaoEntity.managedObjectClassName = NSStringFromClass(Cartao.self)
        
        // Entidade Operacao
        let operacaoEntity = NSEntityDescription()
        operacaoEntity.name = "Operacao"
        operacaoEntity.managedObjectClassName = NSStringFromClass(Operacao.self)
        
        // Entidade Recorrencia
        let recorrenciaEntity = NSEntityDescription()
        recorrenciaEntity.name = "Recorrencia"
        recorrenciaEntity.managedObjectClassName = NSStringFromClass(Recorrencia.self)
        
        // Entidade Fatura
        let faturaEntity = NSEntityDescription()
        faturaEntity.name = "Fatura"
        faturaEntity.managedObjectClassName = NSStringFromClass(Fatura.self)
        
        // Entidade Usuario
        let usuarioEntity = NSEntityDescription()
        usuarioEntity.name = "Usuario"
        usuarioEntity.managedObjectClassName = NSStringFromClass(Usuario.self)
        
        // (B) Configurar as propriedades de cada entidade
        // ------------------------------------------------------
        // Propriedades Cartao
        let cartaoId = NSAttributeDescription()
        cartaoId.name = "id"
        cartaoId.attributeType = .UUIDAttributeType
        cartaoId.isOptional = false
        
        let cartaoNumero = NSAttributeDescription()
        cartaoNumero.name = "numero"
        cartaoNumero.attributeType = .stringAttributeType
        cartaoNumero.isOptional = true
        
        let cartaoDataFechamento = NSAttributeDescription()
        cartaoDataFechamento.name = "dataFechamento"
        cartaoDataFechamento.attributeType = .dateAttributeType
        cartaoDataFechamento.isOptional = false
        
        let cartaoDataVencimento = NSAttributeDescription()
        cartaoDataVencimento.name = "dataVencimento"
        cartaoDataVencimento.attributeType = .dateAttributeType
        cartaoDataVencimento.isOptional = false
        
        let cartaoLimite = NSAttributeDescription()
        cartaoLimite.name = "limite"
        cartaoLimite.attributeType = .doubleAttributeType
        cartaoLimite.isOptional = false
        
        let cartaoTaxaJuros = NSAttributeDescription()
        cartaoTaxaJuros.name = "taxaJuros"
        cartaoTaxaJuros.attributeType = .doubleAttributeType
        cartaoTaxaJuros.isOptional = true
        
        let cartaoApelido = NSAttributeDescription()
        cartaoApelido.name = "apelido"
        cartaoApelido.attributeType = .stringAttributeType
        cartaoApelido.isOptional = true
        
        let cartaoIsDefault = NSAttributeDescription()
        cartaoIsDefault.name = "isDefault"
        cartaoIsDefault.attributeType = .booleanAttributeType
        cartaoIsDefault.isOptional = false
        
        let cartaoAtivo = NSAttributeDescription()
        cartaoAtivo.name = "ativo"
        cartaoAtivo.attributeType = .booleanAttributeType
        cartaoAtivo.isOptional = false
        cartaoAtivo.defaultValue = true
        
        let cartaoBandeira = NSAttributeDescription()
        cartaoBandeira.name = "bandeira"
        cartaoBandeira.attributeType = .stringAttributeType
        cartaoBandeira.isOptional = true
        
        let cartaoNome = NSAttributeDescription()
        cartaoNome.name = "nome"
        cartaoNome.attributeType = .stringAttributeType
        cartaoNome.isOptional = true
        
        // Propriedades Operacao
        let operacaoId = NSAttributeDescription()
        operacaoId.name = "id"
        operacaoId.attributeType = .UUIDAttributeType
        operacaoId.isOptional = false
        
        let operacaoNome = NSAttributeDescription()
        operacaoNome.name = "nome"
        operacaoNome.attributeType = .stringAttributeType
        operacaoNome.isOptional = false
        
        let operacaoValor = NSAttributeDescription()
        operacaoValor.name = "valor"
        operacaoValor.attributeType = .doubleAttributeType
        operacaoValor.isOptional = false
        
        let operacaoData = NSAttributeDescription()
        operacaoData.name = "data"
        operacaoData.attributeType = .dateAttributeType
        operacaoData.isOptional = false
        
        let operacaoMetodoPagamento = NSAttributeDescription()
        operacaoMetodoPagamento.name = "metodoPagamento"
        operacaoMetodoPagamento.attributeType = .stringAttributeType
        operacaoMetodoPagamento.isOptional = false
        
        let operacaoRecorrente = NSAttributeDescription()
        operacaoRecorrente.name = "recorrente"
        operacaoRecorrente.attributeType = .booleanAttributeType
        operacaoRecorrente.isOptional = false
        
        let operacaoCategoria = NSAttributeDescription()
        operacaoCategoria.name = "categoria"
        operacaoCategoria.attributeType = .stringAttributeType
        operacaoCategoria.isOptional = true
        
        let operacaoNota = NSAttributeDescription()
        operacaoNota.name = "nota"
        operacaoNota.attributeType = .stringAttributeType
        operacaoNota.isOptional = true
        
        let tipoAttribute = NSAttributeDescription()
        tipoAttribute.name = "tipoString"
        tipoAttribute.attributeType = .stringAttributeType
        tipoAttribute.isOptional = true
        
        let operacaoIdRecorrencia = NSAttributeDescription()
        operacaoIdRecorrencia.name = "idRecorrencia"
        operacaoIdRecorrencia.attributeType = .UUIDAttributeType
        operacaoIdRecorrencia.isOptional = true
        
        let operacaoNumeroParcelas = NSAttributeDescription()
        operacaoNumeroParcelas.name = "numeroParcelas"
        operacaoNumeroParcelas.attributeType = .integer16AttributeType
        operacaoNumeroParcelas.isOptional = false
        operacaoNumeroParcelas.defaultValue = 1
        
        // Propriedades Recorrencia
        let recorrenciaId = NSAttributeDescription()
        recorrenciaId.name = "id"
        recorrenciaId.attributeType = .UUIDAttributeType
        recorrenciaId.isOptional = false
        
        let recorrenciaTipo = NSAttributeDescription()
        recorrenciaTipo.name = "tipo"
        recorrenciaTipo.attributeType = .stringAttributeType
        recorrenciaTipo.isOptional = false
        
        let recorrenciaIntervalo = NSAttributeDescription()
        recorrenciaIntervalo.name = "intervalo"
        recorrenciaIntervalo.attributeType = .integer32AttributeType
        recorrenciaIntervalo.isOptional = false
        
        let recorrenciaProximaData = NSAttributeDescription()
        recorrenciaProximaData.name = "proximaData"
        recorrenciaProximaData.attributeType = .dateAttributeType
        recorrenciaProximaData.isOptional = false
        
        // Propriedades Fatura
        let faturaId = NSAttributeDescription()
        faturaId.name = "id"
        faturaId.attributeType = .UUIDAttributeType
        faturaId.isOptional = false
        
        let faturaDataInicio = NSAttributeDescription()
        faturaDataInicio.name = "dataInicio"
        faturaDataInicio.attributeType = .dateAttributeType
        faturaDataInicio.isOptional = false
        
        let faturaDataFechamento = NSAttributeDescription()
        faturaDataFechamento.name = "dataFechamento"
        faturaDataFechamento.attributeType = .dateAttributeType
        faturaDataFechamento.isOptional = false
        
        let faturaDataVencimento = NSAttributeDescription()
        faturaDataVencimento.name = "dataVencimento"
        faturaDataVencimento.attributeType = .dateAttributeType
        faturaDataVencimento.isOptional = false
        
        let faturaValorTotal = NSAttributeDescription()
        faturaValorTotal.name = "valorTotal"
        faturaValorTotal.attributeType = .doubleAttributeType
        faturaValorTotal.isOptional = false
        
        let faturaPaga = NSAttributeDescription()
        faturaPaga.name = "paga"
        faturaPaga.attributeType = .booleanAttributeType
        faturaPaga.isOptional = false
        faturaPaga.defaultValue = false
        
        // Propriedades Usuario
        let usuarioId = NSAttributeDescription()
        usuarioId.name = "id"
        usuarioId.attributeType = .UUIDAttributeType
        usuarioId.isOptional = false
        
        let usuarioEmail = NSAttributeDescription()
        usuarioEmail.name = "email"
        usuarioEmail.attributeType = .stringAttributeType
        usuarioEmail.isOptional = false
        
        let usuarioNome = NSAttributeDescription()
        usuarioNome.name = "nome"
        usuarioNome.attributeType = .stringAttributeType
        usuarioNome.isOptional = false
        
        let usuarioCustomProfileImageURL = NSAttributeDescription()
        usuarioCustomProfileImageURL.name = "customProfileImageURL"
        usuarioCustomProfileImageURL.attributeType = .stringAttributeType
        usuarioCustomProfileImageURL.isOptional = true
        
        let usuarioUsarFaceID = NSAttributeDescription()
        usuarioUsarFaceID.name = "usarFaceID"
        usuarioUsarFaceID.attributeType = .booleanAttributeType
        usuarioUsarFaceID.isOptional = false
        usuarioUsarFaceID.defaultValue = false
        
        let usuarioPin = NSAttributeDescription()
        usuarioPin.name = "pin"
        usuarioPin.attributeType = .stringAttributeType
        usuarioPin.isOptional = true
        
        let usuarioHasCustomProfilePhoto = NSAttributeDescription()
        usuarioHasCustomProfilePhoto.name = "hasCustomProfilePhoto"
        usuarioHasCustomProfilePhoto.attributeType = .booleanAttributeType
        usuarioHasCustomProfilePhoto.isOptional = false
        usuarioHasCustomProfilePhoto.defaultValue = false
        
        // (C) Relacionamentos
        // ------------------------------------------------------
        // Relacionamento Cartao -> Fatura (To-Many)
        let cartaoFaturasRel = NSRelationshipDescription()
        cartaoFaturasRel.name = "faturas"
        cartaoFaturasRel.destinationEntity = faturaEntity
        cartaoFaturasRel.isOptional = true
        cartaoFaturasRel.minCount = 0
        cartaoFaturasRel.maxCount = 0
        cartaoFaturasRel.deleteRule = .nullifyDeleteRule
        
        // Relacionamento Cartao -> Operacoes (To-Many)
        let cartaoOperacoesRel = NSRelationshipDescription()
        cartaoOperacoesRel.name = "operacoes"
        cartaoOperacoesRel.destinationEntity = operacaoEntity
        cartaoOperacoesRel.isOptional = true
        cartaoOperacoesRel.minCount = 0
        cartaoOperacoesRel.maxCount = 0
        cartaoOperacoesRel.deleteRule = .cascadeDeleteRule
        
        // Relacionamento Operacao -> Cartao (To-One)
        let operacaoCartaoRel = NSRelationshipDescription()
        operacaoCartaoRel.name = "cartao"
        operacaoCartaoRel.destinationEntity = cartaoEntity
        operacaoCartaoRel.isOptional = true
        operacaoCartaoRel.minCount = 0
        operacaoCartaoRel.maxCount = 1
        operacaoCartaoRel.deleteRule = .nullifyDeleteRule
        
        // Relacionamento Operacao -> Recorrencia (To-One)
        let operacaoRecorrenciaRel = NSRelationshipDescription()
        operacaoRecorrenciaRel.name = "recorrencia"
        operacaoRecorrenciaRel.destinationEntity = recorrenciaEntity
        operacaoRecorrenciaRel.isOptional = true
        operacaoRecorrenciaRel.maxCount = 1
        operacaoRecorrenciaRel.deleteRule = .cascadeDeleteRule
        
        // Relacionamento Recorrencia -> Operacao (To-One)
        let recorrenciaOperacaoRel = NSRelationshipDescription()
        recorrenciaOperacaoRel.name = "operacao"
        recorrenciaOperacaoRel.destinationEntity = operacaoEntity
        recorrenciaOperacaoRel.isOptional = true
        recorrenciaOperacaoRel.maxCount = 1
        recorrenciaOperacaoRel.deleteRule = .nullifyDeleteRule
        
        // Relacionamento Operacao -> Fatura (To-One)
        let operacaoFaturaRel = NSRelationshipDescription()
        operacaoFaturaRel.name = "fatura"
        operacaoFaturaRel.destinationEntity = faturaEntity
        operacaoFaturaRel.isOptional = true
        operacaoFaturaRel.minCount = 0
        operacaoFaturaRel.maxCount = 1
        operacaoFaturaRel.deleteRule = .nullifyDeleteRule
        
        // Relacionamento Fatura -> Operacoes (To-Many)
        let faturaOperacoesRel = NSRelationshipDescription()
        faturaOperacoesRel.name = "operacoes"
        faturaOperacoesRel.destinationEntity = operacaoEntity
        faturaOperacoesRel.isOptional = true
        faturaOperacoesRel.minCount = 0
        faturaOperacoesRel.maxCount = 0
        faturaOperacoesRel.deleteRule = .cascadeDeleteRule
        
        // Relacionamento Fatura -> Cartao (To-One)
        let faturaCartaoRel = NSRelationshipDescription()
        faturaCartaoRel.name = "cartao"
        faturaCartaoRel.destinationEntity = cartaoEntity
        faturaCartaoRel.isOptional = true
        faturaCartaoRel.minCount = 0
        faturaCartaoRel.maxCount = 1
        faturaCartaoRel.deleteRule = .nullifyDeleteRule
        
        // (D) Inversos
        // ------------------------------------------------------
        operacaoCartaoRel.inverseRelationship = cartaoOperacoesRel
        cartaoOperacoesRel.inverseRelationship = operacaoCartaoRel
        
        operacaoRecorrenciaRel.inverseRelationship = recorrenciaOperacaoRel
        recorrenciaOperacaoRel.inverseRelationship = operacaoRecorrenciaRel
        
        operacaoFaturaRel.inverseRelationship = faturaOperacoesRel
        faturaOperacoesRel.inverseRelationship = operacaoFaturaRel
        
        cartaoFaturasRel.inverseRelationship = faturaCartaoRel
        faturaCartaoRel.inverseRelationship = cartaoFaturasRel
        
        // (E) Atribuição de Propriedades às Entidades
        // ------------------------------------------------------
        cartaoEntity.properties = [
            cartaoId, cartaoNumero, cartaoDataVencimento, cartaoDataFechamento,
            cartaoLimite, cartaoTaxaJuros, cartaoApelido, cartaoIsDefault,
            cartaoAtivo, cartaoBandeira, cartaoNome, cartaoOperacoesRel, cartaoFaturasRel
        ]
        
        operacaoEntity.properties = [
            operacaoId, operacaoNome, operacaoValor, operacaoData,
            operacaoMetodoPagamento, operacaoRecorrente, operacaoCategoria,
            operacaoNota, operacaoCartaoRel, operacaoRecorrenciaRel,
            operacaoFaturaRel, tipoAttribute, operacaoIdRecorrencia, operacaoNumeroParcelas
        ]
        
        recorrenciaEntity.properties = [
            recorrenciaId, recorrenciaTipo, recorrenciaIntervalo,
            recorrenciaProximaData, recorrenciaOperacaoRel
        ]
        
        faturaEntity.properties = [
            faturaId, faturaDataInicio, faturaDataFechamento,
            faturaDataVencimento, faturaValorTotal, faturaPaga,
            faturaOperacoesRel, faturaCartaoRel
        ]
        
        usuarioEntity.properties = [
            usuarioId, usuarioEmail, usuarioNome,
            usuarioUsarFaceID, usuarioCustomProfileImageURL, usuarioPin, usuarioHasCustomProfilePhoto
        ]
        
        // (F) Adicionar todas as entidades ao modelo
        model.entities = [
            cartaoEntity, operacaoEntity, recorrenciaEntity,
            faturaEntity, usuarioEntity
        ]
        
        return model
    }
}

// ======================================================
// MARK: - Métodos Genéricos de Fetch, Salvar e Deletar
// ======================================================
extension CoreDataManager {
    
    // MARK: Fetch Genérico
    @MainActor
    func fetch<T: NSManagedObject>(
        _ entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) async -> [T] {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        
        do {
            return try await context.perform {
                try self.context.fetch(request)
            }
        } catch {
            print("Erro ao buscar \(entityName): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Salvar Contexto
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Contexto salvo com sucesso no Core Data.")
            } catch let error as NSError {
                print("Erro ao salvar contexto: \(error), \(error.userInfo)")
            }
        } else {
            print("Nenhuma alteração para salvar no Core Data.")
        }
    }
    
    // MARK: Deletar Objeto
    func delete(_ object: NSManagedObject) {
        if object is Usuario {
            print("Não é permitido deletar o objeto Usuario através do método delete(_:).")
            return
        }
        
        if let operacao = object as? Operacao, let fatura = operacao.fatura {
            fatura.removerOperacao(operacao) // Remove a operação da fatura
        }
        context.delete(object)
        saveContext()
    }
}

// ======================================================
// MARK: - Fetch Específicos (Cartões, Faturas, Recorrências, etc.)
// ======================================================
extension CoreDataManager {
    
    // MARK: Fetch de Recorrências (Exemplo)
    func fetchRecorrencias() async -> [Recorrencia] {
        let fetchRequest: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
        do {
            let recorrencias = try await context.perform {
                try self.context.fetch(fetchRequest)
            }
            return recorrencias
        } catch {
            print("Erro ao buscar recorrências: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Fetch Cartões Ordenados por Apelido
    @MainActor
    func fetchCartoesOrdenadosPorApelido() async -> [Cartao] {
        return await fetchCartoes(
            predicate: nil,
            sortDescriptors: [NSSortDescriptor(key: "apelido", ascending: true)]
        )
    }
    
    // MARK: Fetch Auxiliar de Cartões
    @MainActor
    private func fetchCartoes(predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?) async -> [Cartao] {
        let fetchedObjects: [Cartao] = await fetch(
            "Cartao",
            predicate: predicate,
            sortDescriptors: sortDescriptors
        ) as? [Cartao] ?? []
        return fetchedObjects
    }
    
    // MARK: Buscar a Primeira Data de Operação
    func fetchFirstOperationDate() async -> Date? {
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "data", ascending: true)]
        fetchRequest.fetchLimit = 1
        
        do {
            let operacao = try await context.perform {
                try self.context.fetch(fetchRequest).first
            }
            return operacao?.data
        } catch {
            print("Erro ao buscar a primeira data de operação: \(error)")
            return nil
        }
    }
    
    // MARK: Fetch Faturas Ordenadas
    func fetchFaturasFiltradas() async -> [Fatura] {
        let sortDescriptor = NSSortDescriptor(key: "dataVencimento", ascending: true)
        let todasFaturas = await fetchFaturas(predicate: nil, sortDescriptors: [sortDescriptor])

        return todasFaturas.filter { fatura in
            guard let cartao = fatura.cartao else { return false }
            
            // Se o cartão está ativo, mantemos a fatura
            if cartao.ativo { return true }
            
            // Se o cartão está arquivado, verificamos se a fatura tem operações
            return fatura.operacoes?.isEmpty == false
        }
    }
    
    @MainActor
    private func fetchFaturas(predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?) async -> [Fatura] {
        let fetchedObjects: [Fatura] = await fetch(
            "Fatura",
            predicate: predicate,
            sortDescriptors: sortDescriptors
        ) as? [Fatura] ?? []
        return fetchedObjects
    }
}

// ======================================================
// MARK: - Operações sobre Faturas (atualizarValorTotalFatura, etc.)
// ======================================================
extension CoreDataManager {
    func atualizarValorTotalFatura(_ fatura: Fatura) {
        let total = fatura.operacoes?.reduce(0.0) { $0 + $1.valor } ?? 0.0
        fatura.valorTotal = total
        saveContext()
    }
}

// ======================================================
// MARK: - Métodos Relacionados a Usuario (Fetch, Criar, Atualizar, etc.)
// ======================================================
extension CoreDataManager {
    
    // MARK: Fetch Usuário por E-mail
    func fetchUsuario(email: String) -> Usuario? {
        let request: NSFetchRequest<Usuario> = Usuario.fetchRequest()
        request.predicate = NSPredicate(format: "email == %@", email)
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Erro ao buscar usuário: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: Criar Usuário
    func criarUsuario(email: String, nome: String) -> Usuario {
        let usuario = Usuario(context: self.context)
        usuario.id = UUID()
        usuario.email = email
        usuario.nome = nome
        usuario.usarFaceID = false
        usuario.customProfileImageURL = nil
        salvarContexto()
        return usuario
    }
    
    // MARK: Salvar Contexto (nome diferente do saveContext para compatibilidade)
    func salvarContexto() {
        if context.hasChanges {
            do {
                try context.save()
                print("Contexto salvo com sucesso.")
            } catch {
                print("Erro ao salvar contexto: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Atualizar Preferência FaceID
    func atualizarPreferenciaFaceID(usuario: Usuario, usarFaceID: Bool) {
        usuario.usarFaceID = usarFaceID
        salvarContexto()
        print("Preferência de FaceID atualizada para \(usarFaceID) no Core Data para o usuário \(usuario.email).")
    }
    
    // MARK: Buscar Usuário Atual
    func fetchUsuarioAtual() -> Usuario? {
        guard let email = Auth.auth().currentUser?.email else { return nil }
        let fetchRequest: NSFetchRequest<Usuario> = Usuario.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "email == %@", email)
        fetchRequest.fetchLimit = 1
        do {
            let usuario = try context.fetch(fetchRequest).first
            if usuario == nil {
                print("fetchUsuarioAtual(): Usuário com email \(email) NÃO encontrado!")
            } else {
                print("fetchUsuarioAtual(): Usuário encontrado: \(usuario!.email)")
            }
            return usuario
        } catch {
            print("Erro ao buscar usuário atual: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: Resetar Dados do Usuário
    func resetarDadosUsuario() {
        let fetchRequest: NSFetchRequest<Usuario> = Usuario.fetchRequest()
        do {
            let usuarios = try context.fetch(fetchRequest)
            for usuario in usuarios {
                context.delete(usuario)
            }
            saveContext()
            print("Dados do usuário resetados com sucesso.")
        } catch {
            print("Erro ao resetar dados do usuário: \(error.localizedDescription)")
        }
    }
    
    // MARK: Atualizar PIN
    func atualizarPin(usuario: Usuario, pin: String) {
        usuario.pin = pin
        salvarContexto()
        print("PIN atualizado no Core Data para o usuário: \(usuario.email).")
    }
    
    // MARK: Atualizar URL da Imagem de Perfil
    func atualizarCustomProfileImageURL(usuario: Usuario, urlString: String) {
        usuario.customProfileImageURL = urlString
        salvarContexto()
        print("URL da imagem de perfil atualizada para: \(urlString)")
    }
}

// ======================================================
// MARK: - Métodos de Criação de Operações e Faturas
// ======================================================
extension CoreDataManager {
    
    // MARK: Criar Operacao (Exemplo de método usado antes)
    func criarOperacao(
        nome: String,
        valor: Double,
        data: Date,
        metodoPagamento: String,
        recorrente: Bool,
        cartao: Cartao? = nil,
        fatura: Fatura? = nil
    ) {
        let novaOperacao = Operacao(context: context)
        novaOperacao.id = UUID()
        novaOperacao.nome = nome
        novaOperacao.valor = valor
        novaOperacao.data = data
        novaOperacao.metodoPagamento = metodoPagamento
        novaOperacao.recorrente = recorrente
        novaOperacao.cartao = cartao
        novaOperacao.fatura = fatura
        
        if recorrente {
            let novaRecorrencia = Recorrencia(context: context)
            novaRecorrencia.id = UUID()
            novaRecorrencia.tipo = "Semanal"
            novaRecorrencia.intervalo = 7
            novaRecorrencia.operacao = novaOperacao
            
            // Próxima data
            if let proximaDataCalculada = Calendar.current.date(byAdding: .day, value: Int(novaRecorrencia.intervalo), to: data) {
                novaRecorrencia.proximaData = proximaDataCalculada
            } else {
                novaRecorrencia.proximaData = Date()
            }
            if novaRecorrencia.proximaData == nil {
                fatalError("Erro crítico: `proximaData` está nula mesmo após os cálculos.")
            }
        }
        
        saveContext()
    }
    
    // MARK: Criar Fatura
    func criarFatura(
        para cartao: Cartao,
        dataInicio: Date,
        dataFechamento: Date,
        dataVencimento: Date
    ) async {
        let novaFatura = Fatura(context: context)
        novaFatura.id = UUID()
        novaFatura.dataInicio = dataInicio
        novaFatura.dataFechamento = dataFechamento
        novaFatura.dataVencimento = dataVencimento
        novaFatura.valorTotal = 0.0
        novaFatura.paga = false
        novaFatura.cartao = cartao
        
        let propsObrigatorias: [String: Any?] = [
            "id": novaFatura.id,
            "dataInicio": novaFatura.dataInicio,
            "dataFechamento": novaFatura.dataFechamento,
            "dataVencimento": novaFatura.dataVencimento,
            "cartao": novaFatura.cartao,
            "valorTotal": novaFatura.valorTotal,
            "paga": novaFatura.paga
        ]
        
        for (prop, val) in propsObrigatorias {
            if val == nil || (val as? String)?.isEmpty == true {
                fatalError("Erro: Propriedade obrigatória '\(prop)' ausente ao criar Fatura.")
            }
        }
        
        saveContext()
        
        // Verifica grupos compartilhados e sincroniza no Firestore
        await MoneyManager.shared.verificarGruposCompartilhados { grupos in
            if let grupos = grupos, !grupos.isEmpty {
                for _ in grupos {
                    Task {
                        await MoneyManager.shared.salvarFaturaNoFirestore(novaFatura) // ✅ Agora chamando corretamente no MoneyManager
                    }
                }
            } else {
                Task {
                    await MoneyManager.shared.salvarFaturaNoFirestore(novaFatura)
                }
            }
        }
    }
}

// MARK: - Administração de Grupos Compartilhados
extension CoreDataManager {
    
    /// Remove um participante do grupo compartilhado
    func removerParticipanteDoGrupo(grupoId: String, participanteId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let groupRef = db.collection("shared_groups").document(grupoId)

        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao buscar grupo compartilhado: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let document = document, document.exists else {
                print("Erro: Grupo não encontrado.")
                completion(false)
                return
            }

            // Remover o participante da lista
            groupRef.updateData([
                "participants": FieldValue.arrayRemove([participanteId])  // ❌ Removendo, não adicionando
            ]) { error in
                if let error = error {
                    print("Erro ao remover participante do grupo: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Participante removido do grupo com sucesso.")

                    // Atualizar a UI apenas se ainda houver participantes no grupo
                    groupRef.getDocument { updatedDocument, error in
                        if let updatedData = updatedDocument?.data(),
                           let participantes = updatedData["participants"] as? [String],
                           !participantes.isEmpty {  // ✅ Só notifica se ainda houver participantes

                            NotificationCenter.default.post(name: .didUpdateData, object: nil)
                        }
                    }

                    completion(true)
                }
            }
        }
    }

    /// Exclui completamente um grupo compartilhado (apenas para o criador)
    func encerrarCompartilhamento(grupoId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let groupRef = db.collection("shared_groups").document(grupoId)

        groupRef.delete { error in
            if let error = error {
                print("Erro ao excluir o grupo: \(error.localizedDescription)")
                completion(false)
            } else {
                print("Grupo \(grupoId) excluído com sucesso.")
                completion(true)
            }
        }
    }
}

// ======================================================
// MARK: - Entidades (Operacao, Recorrencia, Cartao, Fatura, Usuario)
// ======================================================

@objcMembers
class Operacao: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var nome: String
    @NSManaged public var valor: Double
    @NSManaged public var data: Date
    @NSManaged public var metodoPagamento: String
    @NSManaged public var recorrente: Bool
    @NSManaged public var categoria: String?
    @NSManaged public var nota: String?
    @NSManaged public var recorrencia: Recorrencia?
    @NSManaged public var cartao: Cartao?
    @NSManaged public var fatura: Fatura?
    @NSManaged public var ehRecorrente: Bool
    @NSManaged public var tipoString: String?
    @NSManaged public var idRecorrencia: UUID?
    @NSManaged public var numeroParcelas: Int16
    
    var tipoOperacao: TipoOperacao {
        get { TipoOperacao(rawValue: tipoString ?? "") ?? .desconhecido }
        set { tipoString = newValue.rawValue }
    }
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
    }
    
    convenience init(
        context: NSManagedObjectContext,
        nome: String,
        valor: Double,
        data: Date,
        metodoPagamento: String,
        recorrente: Bool,
        cartao: Cartao?
    ) {
        self.init(context: context)
        self.id = UUID()
        self.nome = nome
        self.valor = valor
        self.data = data
        self.metodoPagamento = metodoPagamento
        self.recorrente = recorrente
        self.cartao = cartao
        self.atualizarFaturaRelacionada()
    }
    
    convenience init() {
        self.init(context: CoreDataManager.shared.context)
        self.id = UUID()
        self.nome = ""
        self.valor = 0
        self.data = Date()
        self.metodoPagamento = "Dinheiro"
        self.recorrente = false
    }
}

extension Operacao {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Operacao> {
        return NSFetchRequest<Operacao>(entityName: "Operacao")
    }
    
    func atualizarFaturaRelacionada() {
        guard let fatura = self.fatura else { return }
        fatura.associarOperacao(self)
    }
}

// ------------------------------------------------------

@objc(Recorrencia)
class Recorrencia: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var tipo: String
    @NSManaged public var intervalo: Int32
    @NSManaged public var operacao: Operacao?
    @NSManaged public var proximaData: Date
    
    /// Construtor principal de Recorrencia,
    /// já definindo a próximaData corretamente.
    convenience init(
        context: NSManagedObjectContext,
        tipo: String,
        intervalo: Int32,
        dataInicial: Date,
        operacao: Operacao?
    ) {
        self.init(context: context)
        self.id = UUID()
        self.tipo = tipo
        self.intervalo = intervalo
        self.operacao = operacao
        
        // Define a 'proximaData' de acordo com o tipo
        switch tipo.lowercased() {
        case "diária":
            self.proximaData = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: dataInicial
            ) ?? dataInicial
            
        case "semanal":
            // Soma de 7 dias exatos
            self.proximaData = Calendar.current.date(
                byAdding: .day,
                value: 7,
                to: dataInicial
            ) ?? dataInicial
            
        case "quinzenal":
            // Soma de 14 dias
            self.proximaData = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: dataInicial
            ) ?? dataInicial
            
        case "mensal":
            // Soma de 1 mês exato
            self.proximaData = Calendar.current.date(
                byAdding: .month,
                value: 1,
                to: dataInicial
            ) ?? dataInicial
            
        // Caso queira "anual", "bimestral", etc., vá adicionando...
        
        default:
            // Fallback: se não bater em nenhum case acima,
            // some 'intervalo' dias
            self.proximaData = Calendar.current.date(
                byAdding: .day,
                value: Int(intervalo),
                to: dataInicial
            ) ?? dataInicial
        }
        
        print("Recorrência criada com próxima data: \(self.proximaData)")
    }
}

extension Recorrencia {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Recorrencia> {
        return NSFetchRequest<Recorrencia>(entityName: "Recorrencia")
    }
}

// ------------------------------------------------------

@objc(Cartao)
class Cartao: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var nome: String
    @NSManaged public var limite: Double
    @NSManaged public var dataFechamento: Date
    @NSManaged public var dataVencimento: Date
    @NSManaged public var isDefault: Bool
    @NSManaged public var bandeira: String?
    @NSManaged public var numero: String?
    @NSManaged public var operacoes: Set<Operacao>?
    @NSManaged public var faturas: Set<Fatura>?
    @NSManaged public var taxaJuros: Double
    @NSManaged public var apelido: String?
    @NSManaged public var ativo: Bool
    
    convenience init(
        context: NSManagedObjectContext,
        nome: String,
        limite: Double,
        dataFechamento: Date,
        dataVencimento: Date,
        isDefault: Bool,
        bandeira: String?,
        numero: String?,
        taxaJuros: Double,
        apelido: String?,
        ativo: Bool = true
    ) {
        self.init(context: context)
        self.id = UUID()
        self.nome = nome
        self.limite = limite
        self.dataFechamento = dataFechamento
        self.dataVencimento = dataVencimento
        self.isDefault = isDefault
        self.bandeira = bandeira
        self.numero = numero
        self.taxaJuros = taxaJuros
        self.apelido = apelido
        self.ativo = ativo
    }
}

extension Cartao {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Cartao> {
        return NSFetchRequest<Cartao>(entityName: "Cartao")
    }
    
    @objc(addFaturasObject:)
    @NSManaged public func addToFaturas(_ value: Fatura)
    
    @objc(removeFaturasObject:)
    @NSManaged public func removeFromFaturas(_ value: Fatura)
    
    @objc(addFaturas:)
    @NSManaged public func addToFaturas(_ values: NSSet)
    
    @objc(removeFaturas:)
    @NSManaged public func removeFromFaturas(_ values: NSSet)
    
    func addOperacao(_ operacao: Operacao) {
        let current = self.operacoes ?? []
        self.operacoes = current.union([operacao])
    }
    
    func removeOperacao(_ operacao: Operacao) {
        // Remove da fatura, se houver
        if let fatura = operacao.fatura {
            fatura.removerOperacao(operacao)
        }
        // Remove do set
        let currentOperacoes = self.operacoes ?? []
        self.operacoes = currentOperacoes.subtracting([operacao])
        // Remove do Core Data
        CoreDataManager.shared.context.delete(operacao)
        // Salva
        CoreDataManager.shared.saveContext()
    }
    
    func calcularSaldoDisponível() -> Double {
        let totalGasto = operacoes?.reduce(0) { $0 + $1.valor } ?? 0.0
        return limite - totalGasto
    }
}

// ------------------------------------------------------

@objc(Fatura)
class Fatura: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var dataInicio: Date
    @NSManaged public var dataFechamento: Date
    @NSManaged public var dataVencimento: Date
    @NSManaged public var valorTotal: Double
    @NSManaged public var paga: Bool
    @NSManaged public var cartao: Cartao?
    @NSManaged public var operacoes: Set<Operacao>?
    
    convenience init(
        context: NSManagedObjectContext,
        dataInicio: Date,
        dataFechamento: Date,
        dataVencimento: Date,
        valorTotal: Double,
        paga: Bool,
        cartao: Cartao?
    ) {
        self.init(context: context)
        self.id = UUID()
        self.dataInicio = dataInicio
        self.dataFechamento = dataFechamento
        self.dataVencimento = dataVencimento
        self.valorTotal = valorTotal
        self.paga = paga
        self.cartao = cartao
    }
}

extension Fatura {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Fatura> {
        return NSFetchRequest<Fatura>(entityName: "Fatura")
    }
    
    func associarOperacao(_ operacao: Operacao) {
        guard let cartao = operacao.cartao else { return }
        if cartao != self.cartao { return }
        guard operacao.data >= self.dataInicio && operacao.data <= self.dataFechamento else {
            print("Erro: A operação está fora do intervalo da fatura.")
            return
        }
        self.mutableSetValue(forKey: "operacoes").add(operacao)
        calcularValorTotal()
        CoreDataManager.shared.saveContext()
    }
    
    func removerOperacao(_ operacao: Operacao) {
        guard operacoes?.contains(operacao) == true else { return }
        self.mutableSetValue(forKey: "operacoes").remove(operacao)
        calcularValorTotal()
        CoreDataManager.shared.saveContext()
    }
    
    func calcularValorTotal() {
        guard let ops = self.operacoes else {
            self.valorTotal = 0.0
            return
        }
        self.valorTotal = ops.reduce(0.0) { $0 + abs($1.valor) }
    }
    
    func atualizarOperacoesRelacionadas() async {
        guard let cartao = self.cartao else { return }
        let predicate = NSPredicate(
            format: "cartao == %@ AND data >= %@ AND data <= %@",
            cartao, dataInicio as NSDate, dataFechamento as NSDate
        )
        let ops: [Operacao] = await CoreDataManager.shared.fetch("Operacao", predicate: predicate)
        self.mutableSetValue(forKey: "operacoes").addObjects(from: ops)
        calcularValorTotal()
    }
    
    static func calcularImpactoNoSaldo(data: Date) async -> Double {
        let faturasDoDia: [Fatura] = await CoreDataManager.shared.fetch(
            "Fatura",
            predicate: NSPredicate(format: "dataVencimento == %@", data as NSDate)
        )
        return faturasDoDia.reduce(0.0) { $0 + $1.valorTotal }
    }
    
    static func criarFaturaParaCartao(
        cartao: Cartao,
        dataInicio: Date,
        dataVencimento: Date
    ) async {
        let jaExiste = cartao.faturas?.contains(where: {
            Calendar.current.isDate($0.dataVencimento, inSameDayAs: dataVencimento)
        }) ?? false
        if jaExiste {
            print("Fatura já existe para este período.")
            return
        }
        
        let novaFatura = Fatura(
            context: CoreDataManager.shared.context,
            dataInicio: dataInicio,
            dataFechamento: dataVencimento,
            dataVencimento: dataVencimento,
            valorTotal: 0.0,
            paga: false,
            cartao: cartao
        )
        cartao.addToFaturas(novaFatura)
        CoreDataManager.shared.saveContext()
    }
}

// ------------------------------------------------------

@objc(Usuario)
class Usuario: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var email: String
    @NSManaged public var nome: String
    @NSManaged public var usarFaceID: Bool
    @NSManaged public var customProfileImageURL: String?
    @NSManaged public var pin: String?
    @NSManaged public var hasCustomProfilePhoto: Bool
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.usarFaceID = false
    }
    
    convenience init(context: NSManagedObjectContext, email: String, nome: String) {
        self.init(context: context)
        self.email = email
        self.nome = nome
        self.usarFaceID = false
    }
}

extension Usuario {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Usuario> {
        return NSFetchRequest<Usuario>(entityName: "Usuario")
    }
}

// ======================================================
// MARK: - Enum Auxiliar (TipoOperacao)
// ======================================================
enum TipoOperacao: String, CaseIterable {
    case despesa = "despesa"
    case receita = "receita"
    case recorrente = "recorrente"
    case parcelada = "parcelada"
    case unica = "unica"
    case desconhecido = "desconhecido"
}

// ======================================================
// MARK: - Novos Métodos vindos do CardManager (criarCartao, etc.)
// ======================================================
extension CoreDataManager {
    
    // MARK: Buscar Cartões (Apenas Ativos ou Todos)
    @MainActor
    func fetchCartoes(apenasAtivos: Bool = true) async -> [Cartao] {
        let predicate: NSPredicate? = apenasAtivos ? NSPredicate(format: "ativo == true") : nil
        let sortDescriptors = [NSSortDescriptor(key: "apelido", ascending: true)]
        let fetchedCartoes: [Cartao] = await fetch("Cartao", predicate: predicate, sortDescriptors: sortDescriptors)
        return fetchedCartoes
    }
    
    // MARK: Atualizar Cartão
    @MainActor
    func atualizarCartao(_ cartao: Cartao) async {
        do {
            try context.save()
            NotificationCenter.default.post(name: .didUpdateData, object: nil)
            Task {
                await MoneyManager.shared.carregarDados()
            }
        } catch {
            print("Erro ao atualizar o cartão: \(error.localizedDescription)")
        }
    }
    
    // MARK: Criar Cartão
    @MainActor
    func criarCartao(
        nome: String,
        numero: String,
        bandeira: String?,
        dataVencimento: Date,
        dataFechamento: Date,
        limite: Double,
        taxaJuros: Double,
        apelido: String?,
        isDefault: Bool
    ) async -> Cartao? {
        guard !numero.isEmpty, limite > 0 else {
            print("Erro: Número do cartão ou limite inválidos.")
            return nil
        }
        
        let primeiroCartao = await verificarSePrimeiroCartao()
        
        let novoCartao = Cartao(
            context: context,
            nome: nome,
            limite: limite,
            dataFechamento: dataFechamento,
            dataVencimento: dataVencimento,
            isDefault: primeiroCartao ? true : isDefault,
            bandeira: bandeira,
            numero: numero,
            taxaJuros: taxaJuros,
            apelido: apelido
        )
        novoCartao.ativo = true
        
        if primeiroCartao || isDefault {
            await definirCartaoPadrao(novoCartao)
        }
        
//        await criarFaturasBaseadoNoFechamento(novoCartao)
        saveContext()
        
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        Task {
            await MoneyManager.shared.carregarDados()
        }
        Task {
            await CardManager.shared.salvarCartaoNoFirestore(novoCartao)
        }
        
        return novoCartao
    }
    
    // MARK: Arquivar (Inativar) Cartão
    @MainActor
    func arquivarCartao(_ cartao: Cartao) async {
        // Salve se o cartão arquivado era o padrão
        let wasDefault = cartao.isDefault

        // Arquiva o cartão
        cartao.ativo = false
        saveContext()
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        
        // Se o cartão arquivado era o padrão, defina outro cartão ativo como padrão
        if wasDefault {
            // Busca apenas os cartões ativos (não arquivados)
            let activeCards: [Cartao] = await fetchCartoes(apenasAtivos: true)
            // Se houver algum cartão ativo, escolha o primeiro (ou a lógica que preferir)
            if let newDefault = activeCards.first {
                await definirCartaoPadrao(newDefault)
            }
        }
        
        Task {
            await MoneyManager.shared.carregarDados()
        }
        
        // Notificação local
        let content = UNMutableNotificationContent()
        content.title = "Atualização de Dados"
        content.body = "Os dados do aplicativo foram atualizados."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao enviar notificação local: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Definir Cartão Padrão
    @MainActor
    func definirCartaoPadrao(_ cartao: Cartao) async {
        let todosCartoes: [Cartao] = await fetch("Cartao")
        for c in todosCartoes {
            c.isDefault = (c == cartao)
        }
        saveContext()
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        Task {
            await MoneyManager.shared.carregarDados()
        }
        
        // Disparar notificação local
        let content = UNMutableNotificationContent()
        content.title = "Atualização de Dados"
        content.body = "Os dados do aplicativo foram atualizados."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao enviar notificação local: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Verificar se é o Primeiro Cartão
    @MainActor
    func verificarSePrimeiroCartao() async -> Bool {
        // Filtra apenas os cartões ativos (não arquivados)
        let predicate = NSPredicate(format: "ativo == true")
        let todosCartoes: [Cartao] = await fetch("Cartao", predicate: predicate, sortDescriptors: nil) as? [Cartao] ?? []
        return todosCartoes.isEmpty
    }
    
    // MARK: Desativar Cartão
    @MainActor
    func desativarCartao(_ cartao: Cartao) async {
        cartao.ativo = false
        saveContext()
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        Task {
            await MoneyManager.shared.carregarDados()
        }
        
        // Notificação local
        let content = UNMutableNotificationContent()
        content.title = "Atualização de Dados"
        content.body = "Os dados do aplicativo foram atualizados."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao enviar notificação local: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Atualizar Faturas (Recriar se necessário)
    @MainActor
    func atualizarFaturas() async {
        let todosCartoes: [Cartao] = await fetch("Cartao")
        for cartao in todosCartoes {
            await criarFaturasBaseadoNoFechamento(cartao)
        }
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        Task {
            await MoneyManager.shared.carregarDados()
        }
        
        // Notificação local
        let content = UNMutableNotificationContent()
        content.title = "Atualização de Dados"
        content.body = "Os dados do aplicativo foram atualizados."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erro ao enviar notificação local: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Adicionar Operação (possivelmente parcelada)
    @MainActor
    func adicionarOperacao(
        valor: Double,
        descricao: String,
        cartao: Cartao,
        parcelas: Int = 1,
        dataOperacao: Date
    ) async {
        guard cartao.ativo else {
            print("Erro: Cartão desativado.")
            return
        }
        
        let dataBase = dataOperacao
        let valorPorParcela = (valor / Double(parcelas)).rounded(to: 2)
        var restante = valor
        let idRecorrencia = UUID()
        
        for parcela in 1...parcelas {
            let operacaoData = Calendar.current.date(byAdding: .month, value: parcela - 1, to: dataBase) ?? dataBase
            let operacaoValor = (parcela == parcelas) ? restante : valorPorParcela
            let operacaoValorNegativo = -abs(operacaoValor)
            
            let novaOperacao = Operacao(
                context: context,
                nome: (parcelas == 1)
                    ? descricao
                    : "\(descricao) - Parcela \(parcela)",
                valor: operacaoValorNegativo,
                data: operacaoData,
                metodoPagamento: "Cartão",
                recorrente: false,
                cartao: cartao
            )
            
            novaOperacao.tipoOperacao = .parcelada
            
            novaOperacao.idRecorrencia = idRecorrencia
            await vincularOperacaoAFatura(novaOperacao)
            
            restante -= valorPorParcela
        }
        
        saveContext()
        print("Parcelamento criado: \(descricao), ID Recorrência: \(idRecorrencia.uuidString)")
        NotificationCenter.default.post(name: .didUpdateData, object: nil)
        Task {
            await MoneyManager.shared.carregarDados()
        }
    }
    
    // MARK: Vincular Operação à Fatura
    @MainActor
    func vincularOperacaoAFatura(_ operacao: Operacao) async {
        guard let cartao = operacao.cartao else {
            print("Operação \(operacao.nome) não possui cartão associado.")
            return
        }
        let faturas = cartao.faturas?.filter { fatura in
            fatura.dataInicio <= operacao.data && operacao.data <= fatura.dataFechamento
        }
        if let faturaRelacionada = faturas?.first {
            operacao.fatura = faturaRelacionada
            await recalcularValorFatura(faturaRelacionada)
            print("Operação \(operacao.nome) vinculada à fatura: \(faturaRelacionada.id)")
        } else {
            print("Nenhuma fatura encontrada para a operação \(operacao.nome) no período.")
        }
    }
    
    // MARK: Recalcular Valor Fatura
    @MainActor
    func recalcularValorFatura(_ fatura: Fatura) async {
        let ops = fatura.operacoes ?? []
        fatura.valorTotal = ops.reduce(0.0) { $0 + abs($1.valor) }
        saveContext()
        print("Fatura \(fatura.id) recalculada com valor total: \(fatura.valorTotal)")
    }
    
    // MARK: Buscar Operações do Dia
    @MainActor
    func buscarOperacoesDoDia(data: Date) async -> [Operacao] {
        let predicate = NSPredicate(
            format: "metodoPagamento == %@ AND data == %@",
            "Cartão", data as NSDate
        )
        let ops: [Operacao] = await fetch("Operacao", predicate: predicate)
        return ops
    }
    
    // MARK: Buscar Faturas do Dia (dataVencimento)
    @MainActor
    func buscarFaturasDoDia(data: Date) async -> [Fatura] {
        let predicate = NSPredicate(format: "dataVencimento == %@", data as NSDate)
        let faturas: [Fatura] = await fetch("Fatura", predicate: predicate)
        return faturas
    }
    
    // MARK: Criar 12 Faturas Futuras
    @MainActor
    fileprivate func criarFaturasBaseadoNoFechamento(_ cartao: Cartao) async {
        let calendar = Calendar.current
        let hoje = Date()
        
        let fechamentoDay = calendar.component(.day, from: cartao.dataFechamento)
        let vencimentoDay = calendar.component(.day, from: cartao.dataVencimento)
        
        var currentFechamento = ajustarDia(baseDate: hoje, diaDoMes: fechamentoDay, endOfDay: true)
        
        if currentFechamento < hoje {
            if let mesSeguinte = calendar.date(byAdding: .month, value: 1, to: currentFechamento) {
                currentFechamento = ajustarDia(baseDate: mesSeguinte, diaDoMes: fechamentoDay, endOfDay: true)
            }
        }
        
        for _ in 0..<12 {
            let dataFechamento = currentFechamento
            let dataInicio = calendar.date(byAdding: .month, value: -1, to: dataFechamento)
                .flatMap {
                    calendar.date(byAdding: .day, value: 1, to: $0.startOfDay())
                } ?? dataFechamento.startOfDay()
            
            let dataVencimento = ajustarDia(baseDate: dataFechamento, diaDoMes: vencimentoDay, endOfDay: true)
            
            let novaFatura = Fatura(
                context: context,
                dataInicio: dataInicio,
                dataFechamento: dataFechamento,
                dataVencimento: dataVencimento,
                valorTotal: 0.0,
                paga: false,
                cartao: cartao
            )
            cartao.addToFaturas(novaFatura)
            
            if let plusOneMonth = calendar.date(byAdding: .month, value: 1, to: dataFechamento) {
                currentFechamento = ajustarDia(baseDate: plusOneMonth, diaDoMes: fechamentoDay, endOfDay: true)
            }
        }
        saveContext()
        
    }
    
    // MARK: Ajustar Dia do Mês
    private func ajustarDia(baseDate: Date, diaDoMes: Int, endOfDay: Bool) -> Date {
        let cal = Calendar.current
        var comp = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: baseDate)
        comp.day = diaDoMes
        
        if endOfDay {
            comp.hour = 23
            comp.minute = 59
            comp.second = 59
        } else {
            comp.hour = 0
            comp.minute = 0
            comp.second = 0
        }
        
        return cal.date(from: comp) ?? baseDate
    }
}

// ======================================================
// MARK: - Criação de Operações e Recorrências (Async/await)
// ======================================================
@MainActor
extension CoreDataManager {
    func criarOperacao(
        id: UUID? = nil,
        nome: String,
        valor: Double,
        data: Date,
        metodoPagamento: String,
        recorrente: Bool,
        categoria: String? = nil,
        nota: String? = nil,
        tipo: String? = nil,
        idRecorrencia: UUID? = nil,
        numeroParcelas: Int = 1,
        cartao: Cartao? = nil
    ) async -> Operacao? {
        let novaOperacao = Operacao(context: context)
        // Use o id passado, se houver; caso contrário, gere um novo.
        novaOperacao.id = id ?? UUID()
        
        novaOperacao.nome = nome
        novaOperacao.valor = valor
        novaOperacao.data = data
        novaOperacao.metodoPagamento = metodoPagamento
        novaOperacao.recorrente = recorrente
        novaOperacao.categoria = categoria
        novaOperacao.nota = nota
        novaOperacao.tipoString = tipo
        novaOperacao.idRecorrencia = idRecorrencia
        novaOperacao.numeroParcelas = Int16(numeroParcelas)
        novaOperacao.cartao = cartao
        
        saveContext()
        
        MoneyManager.shared.verificarGruposCompartilhados { grupos in
            if let grupos = grupos, !grupos.isEmpty {
                for grupoId in grupos {
                    Task {
                        await MoneyManager.shared.salvarOperacaoNoFirestore(novaOperacao)
                    }
                }
            } else {
                Task {
                    await MoneyManager.shared.salvarOperacaoNoFirestore(novaOperacao)
                }
            }
        }
        
        return novaOperacao
    }
}

extension CoreDataManager {
    @MainActor
    func criarRecorrencia(
        tipo: String,
        intervalo: Int,
        dataInicial: Date,
        operacao: Operacao
    ) async -> Recorrencia? {
        guard let context = persistentContainer.viewContext as? NSManagedObjectContext else {
            print("Erro: Contexto do Core Data indisponível.")
            return nil
        }
        
        let novaRecorrencia = Recorrencia(context: context)
        novaRecorrencia.id = UUID()
        novaRecorrencia.tipo = tipo
        novaRecorrencia.intervalo = Int32(intervalo)
        novaRecorrencia.proximaData = Calendar.current.date(byAdding: .day, value: intervalo, to: dataInicial) ?? dataInicial
        novaRecorrencia.operacao = operacao
        
        do {
            try context.save()
            print("Recorrência \(novaRecorrencia.tipo) criada com sucesso.")
            return novaRecorrencia
        } catch {
            print("Erro ao salvar a recorrência: \(error.localizedDescription)")
            return nil
        }
    }
}

// ======================================================
// MARK: - Métodos de Sincronização com Firestore
// ======================================================
extension CoreDataManager {
    
    // ======================================================
    // MARK: Upload (Exportar) Dados para Firestore
    // ======================================================
    @MainActor
    func uploadDataToFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ Erro: Usuário não autenticado.")
            return
        }
        
        let db = Firestore.firestore()
        
        // 1️⃣ **Usuário**
        if let usuario = fetchUsuarioAtual() {
            let userData: [String: Any] = [
                "id": usuario.id.uuidString,
                "email": usuario.email,
                "nome": usuario.nome,
                "usarFaceID": usuario.usarFaceID,
                "customProfileImageURL": usuario.customProfileImageURL ?? "",
                "pin": usuario.pin ?? ""
            ]
            do {
                try await db.collection("users").document(userId).setData(userData)
                print("✅ Usuário sincronizado.")
            } catch {
                print("❌ Erro ao sincronizar usuário: \(error.localizedDescription)")
            }
        }
        
        // 2️⃣ **Cartões**
        let cartoes = await fetchCartoes(apenasAtivos: false)
        for cartao in cartoes {
            let cartaoData: [String: Any] = [
                "id": cartao.id.uuidString,
                "nome": cartao.nome,
                "limite": cartao.limite,
                "dataFechamento": cartao.dataFechamento,
                "dataVencimento": cartao.dataVencimento,
                "isDefault": cartao.isDefault,
                "bandeira": cartao.bandeira ?? "",
                "numero": cartao.numero ?? "",
                "taxaJuros": cartao.taxaJuros,
                "apelido": cartao.apelido ?? "",
                "ativo": cartao.ativo
            ]
            
            do {
                try await db.collection("users").document(userId).collection("cards")
                    .document(cartao.id.uuidString)
                    .setData(cartaoData)
                print("✅ Cartão \(cartao.nome) sincronizado.")
            } catch {
                print("❌ Erro ao sincronizar cartão \(cartao.nome): \(error.localizedDescription)")
            }
            
            // 🔄 **Sincronizar faturas do cartão**
            if let faturas = cartao.faturas {
                for fatura in faturas {
                    let faturaData: [String: Any] = [
                        "id": fatura.id.uuidString,
                        "dataInicio": fatura.dataInicio,
                        "dataFechamento": fatura.dataFechamento,
                        "dataVencimento": fatura.dataVencimento,
                        "valorTotal": fatura.valorTotal,
                        "paga": fatura.paga
                    ]
                    do {
                        try await db.collection("users").document(userId)
                            .collection("cards").document(cartao.id.uuidString)
                            .collection("invoices").document(fatura.id.uuidString)
                            .setData(faturaData)
                        print("✅ Fatura \(fatura.id.uuidString) sincronizada.")
                    } catch {
                        print("❌ Erro ao sincronizar fatura \(fatura.id.uuidString): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // 3️⃣ **Operações**
        let operacoes = await fetch("Operacao") as? [Operacao] ?? []
        for operacao in operacoes {
            let operacaoData: [String: Any] = [
                "id": operacao.id.uuidString,
                "nome": operacao.nome,
                "valor": operacao.valor,
                "data": operacao.data,
                "metodoPagamento": operacao.metodoPagamento,
                "recorrente": operacao.recorrente,
                "categoria": operacao.categoria ?? "",
                "nota": operacao.nota ?? "",
                "tipo": operacao.tipoString ?? "",
                "idRecorrencia": operacao.idRecorrencia?.uuidString ?? "",
                "numeroParcelas": operacao.numeroParcelas
            ]
            
            do {
                try await db.collection("users").document(userId).collection("operations")
                    .document(operacao.id.uuidString)
                    .setData(operacaoData)
                print("✅ Operação \(operacao.nome) sincronizada.")
            } catch {
                print("❌ Erro ao sincronizar operação \(operacao.nome): \(error.localizedDescription)")
            }
        }
        
        // 4️⃣ **Recorrências**
        let recorrencias = await fetch("Recorrencia") as? [Recorrencia] ?? []
        for recorrencia in recorrencias {
            let recorrenciaData: [String: Any] = [
                "id": recorrencia.id.uuidString,
                "tipo": recorrencia.tipo,
                "intervalo": recorrencia.intervalo,
                "proximaData": recorrencia.proximaData
            ]
            do {
                try await db.collection("users").document(userId).collection("recurrences")
                    .document(recorrencia.id.uuidString)
                    .setData(recorrenciaData)
                print("✅ Recorrência \(recorrencia.tipo) sincronizada.")
            } catch {
                print("❌ Erro ao sincronizar recorrência \(recorrencia.id.uuidString): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Fetch (Importar) Dados do Firestore
    @MainActor
    func fetchDataFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let db = Firestore.firestore()
        
        // 1. Usuário
        do {
            let userSnapshot = try await db.collection("users").document(userId).getDocument()
            if let userData = userSnapshot.data() {
                if let usuario = fetchUsuarioAtual() {
                    usuario.nome = userData["nome"] as? String ?? usuario.nome
                    // NÃO sobrescreva usarFaceID – deixe-o inalterado
                    usuario.customProfileImageURL = userData["customProfileImageURL"] as? String ?? usuario.customProfileImageURL
                    usuario.pin = userData["pin"] as? String ?? usuario.pin
                } else {
                    // NÃO crie um novo usuário aqui para evitar resetar o usarFaceID.
                    print("Usuário não encontrado no Core Data – verifique a persistência do usuário.")
                }
            }
            print("Usuário atualizado no Core Data.")
        } catch {
            print("Erro ao buscar dados do usuário no Firestore: \(error.localizedDescription)")
        }
        
        // 2. Cartões
        do {
            let cardsSnapshot = try await db.collection("users").document(userId).collection("cards").getDocuments()
            for document in cardsSnapshot.documents {
                let cardData = document.data()
                guard let id = UUID(uuidString: cardData["id"] as? String ?? "") else { continue }
                
                let fetchRequest: NSFetchRequest<Cartao> = Cartao.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                
                let existingCartao = try context.fetch(fetchRequest).first
                
                if let cartao = existingCartao {
                    cartao.nome = cardData["nome"] as? String ?? cartao.nome
                    cartao.limite = cardData["limite"] as? Double ?? cartao.limite
                    cartao.dataFechamento = (cardData["dataFechamento"] as? Timestamp)?.dateValue() ?? cartao.dataFechamento
                    cartao.dataVencimento = (cardData["dataVencimento"] as? Timestamp)?.dateValue() ?? cartao.dataVencimento
                    cartao.isDefault = cardData["isDefault"] as? Bool ?? cartao.isDefault
                    cartao.bandeira = cardData["bandeira"] as? String ?? cartao.bandeira
                    cartao.numero = cardData["numero"] as? String ?? cartao.numero
                    cartao.taxaJuros = cardData["taxaJuros"] as? Double ?? cartao.taxaJuros
                    cartao.apelido = cardData["apelido"] as? String ?? cartao.apelido
                    cartao.ativo = cardData["ativo"] as? Bool ?? cartao.ativo
                } else {
                    let novoCartao = Cartao(
                        context: context,
                        nome: cardData["nome"] as? String ?? "Sem nome",
                        limite: cardData["limite"] as? Double ?? 0.0,
                        dataFechamento: (cardData["dataFechamento"] as? Timestamp)?.dateValue() ?? Date(),
                        dataVencimento: (cardData["dataVencimento"] as? Timestamp)?.dateValue() ?? Date(),
                        isDefault: cardData["isDefault"] as? Bool ?? false,
                        bandeira: cardData["bandeira"] as? String,
                        numero: cardData["numero"] as? String,
                        taxaJuros: cardData["taxaJuros"] as? Double ?? 0.0,
                        apelido: cardData["apelido"] as? String
                    )
                    novoCartao.ativo = cardData["ativo"] as? Bool ?? true
                }
                
                // 2.1 Faturas
                let invoicesSnapshot = try await db.collection("users").document(userId)
                    .collection("cards").document(document.documentID)
                    .collection("invoices").getDocuments()
                
                for invoiceDocument in invoicesSnapshot.documents {
                    let invoiceData = invoiceDocument.data()
                    guard let invoiceId = UUID(uuidString: invoiceData["id"] as? String ?? "") else { continue }
                    
                    let fetchInvoiceRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
                    fetchInvoiceRequest.predicate = NSPredicate(format: "id == %@", invoiceId as CVarArg)
                    
                    let existingFatura = try context.fetch(fetchInvoiceRequest).first
                    
                    if let fatura = existingFatura {
                        fatura.dataInicio = (invoiceData["dataInicio"] as? Timestamp)?.dateValue() ?? fatura.dataInicio
                        fatura.dataFechamento = (invoiceData["dataFechamento"] as? Timestamp)?.dateValue() ?? fatura.dataFechamento
                        fatura.dataVencimento = (invoiceData["dataVencimento"] as? Timestamp)?.dateValue() ?? fatura.dataVencimento
                        fatura.valorTotal = invoiceData["valorTotal"] as? Double ?? fatura.valorTotal
                        fatura.paga = invoiceData["paga"] as? Bool ?? fatura.paga
                    } else {
                        let novaFatura = Fatura(
                            context: context,
                            dataInicio: (invoiceData["dataInicio"] as? Timestamp)?.dateValue() ?? Date(),
                            dataFechamento: (invoiceData["dataFechamento"] as? Timestamp)?.dateValue() ?? Date(),
                            dataVencimento: (invoiceData["dataVencimento"] as? Timestamp)?.dateValue() ?? Date(),
                            valorTotal: invoiceData["valorTotal"] as? Double ?? 0.0,
                            paga: invoiceData["paga"] as? Bool ?? false,
                            cartao: existingCartao
                        )
                        existingCartao?.addToFaturas(novaFatura)
                    }
                }
            }
            print("Cartões e faturas atualizados no Core Data.")
        } catch {
            print("Erro ao buscar cartões/faturas no Firestore: \(error.localizedDescription)")
        }
        
        // 3. Operações
        do {
            let operationsSnapshot = try await db.collection("users").document(userId).collection("operations").getDocuments()
            for document in operationsSnapshot.documents {
                let operationData = document.data()
                guard let id = UUID(uuidString: operationData["id"] as? String ?? "") else { continue }
                
                let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                fetchRequest.fetchLimit = 1
                
                let existingOperacao = try context.fetch(fetchRequest).first
                
                if let operacao = existingOperacao {
                    operacao.nome = operationData["nome"] as? String ?? operacao.nome
                    operacao.valor = operationData["valor"] as? Double ?? operacao.valor
                    operacao.data = (operationData["data"] as? Timestamp)?.dateValue() ?? operacao.data
                    operacao.metodoPagamento = operationData["metodoPagamento"] as? String ?? operacao.metodoPagamento
                    operacao.recorrente = operationData["recorrente"] as? Bool ?? operacao.recorrente
                    operacao.categoria = operationData["categoria"] as? String ?? operacao.categoria
                    operacao.nota = operationData["nota"] as? String ?? operacao.nota
                    operacao.tipoString = operationData["tipo"] as? String ?? operacao.tipoString
                } else {
                    _ = Operacao(
                        context: context,
                        nome: operationData["nome"] as? String ?? "Sem nome",
                        valor: operationData["valor"] as? Double ?? 0.0,
                        data: (operationData["data"] as? Timestamp)?.dateValue() ?? Date(),
                        metodoPagamento: operationData["metodoPagamento"] as? String ?? "Outro",
                        recorrente: operationData["recorrente"] as? Bool ?? false,
                        cartao: nil
                    )
                }
            }
            print("Operações atualizadas no Core Data.")
        } catch {
            print("Erro ao buscar operações no Firestore: \(error.localizedDescription)")
        }
        
        saveContext()
    }
}

// ======================================================
// MARK: - Sincronização de Faturas com Firestore
// ======================================================
/*
extension CoreDataManager {
    
    @MainActor
    func salvarFaturaNoFirestore(_ fatura: Fatura) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        let faturaData: [String: Any] = [
            "id": fatura.id.uuidString,
            "cartaoId": fatura.cartao?.id.uuidString ?? "",
            "valorTotal": fatura.valorTotal,
            "dataVencimento": fatura.dataVencimento
        ]
        
        let db = Firestore.firestore()
        
        // Obtenha os grupos compartilhados de forma assíncrona:
        let grupos = await withCheckedContinuation { continuation in
            verificarGruposCompartilhados { groupCodes in
                continuation.resume(returning: groupCodes)
            }
        }
        
        // 1. Salve sempre na coleção do usuário:
        let userCollectionPath = "users/\(userId)/bills"
        do {
            try await db.collection(userCollectionPath).document(fatura.id.uuidString).setData(faturaData)
            print("Fatura \(fatura.id.uuidString) salva no Firestore do usuário.")
        } catch {
            print("Erro ao salvar fatura no Firestore do usuário: \(error.localizedDescription)")
        }

        // 2. Se houver grupos, salve também na coleção de cada grupo:
        if let grupos = grupos, !grupos.isEmpty {
            for groupCode in grupos {
                let groupCollectionPath = "shared_groups/\(groupCode)/bills"
                do {
                    try await db.collection(groupCollectionPath).document(fatura.id.uuidString).setData(faturaData)
                    print("Fatura \(fatura.id.uuidString) sincronizada com o grupo \(groupCode).")
                } catch {
                    print("Erro ao salvar fatura no grupo \(groupCode): \(error.localizedDescription)")
                }
            }
        }
    }
}
 */

// ======================================================
// MARK: - Observadores Firestore (ex: configurarObservadoresFirestore)
// ======================================================
extension CoreDataManager {
    func configurarObservadoresFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        let db = Firestore.firestore()
        db.collection("shared_groups")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Erro ao observar grupos compartilhados: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("Nenhum grupo compartilhado encontrado (observador).")
                    return
                }
                // Para cada grupo, configura o listener específico
                for document in documents {
                    let groupId = document.documentID
                    print("Configurando observador para o grupo \(groupId)")
                    self.configurarObservadorDoGrupo(grupoId: groupId)
                }
            }
    }
    
    // MARK: Atualizar Cartão Firestore
    private func atualizarCartaoFirestore(document: DocumentSnapshot) {
        guard let data = document.data() else { return }
        Task {
            if let cartao = await fetchCartaoPorId(UUID(uuidString: data["id"] as? String ?? "") ?? UUID()) {
                cartao.nome = data["nome"] as? String ?? cartao.nome
                cartao.limite = data["limite"] as? Double ?? cartao.limite
                cartao.dataFechamento = (data["dataFechamento"] as? Timestamp)?.dateValue() ?? cartao.dataFechamento
                cartao.dataVencimento = (data["dataVencimento"] as? Timestamp)?.dateValue() ?? cartao.dataVencimento
                cartao.isDefault = data["isDefault"] as? Bool ?? cartao.isDefault
                cartao.bandeira = data["bandeira"] as? String ?? cartao.bandeira
                cartao.numero = data["numero"] as? String ?? cartao.numero
                cartao.taxaJuros = data["taxaJuros"] as? Double ?? cartao.taxaJuros
                cartao.apelido = data["apelido"] as? String ?? cartao.apelido
                cartao.ativo = data["ativo"] as? Bool ?? cartao.ativo
                saveContext()
                print("Cartão \(cartao.nome) atualizado no Core Data.")
            } else {
                let _ = Cartao(
                    context: context,
                    nome: data["nome"] as? String ?? "Sem Nome",
                    limite: data["limite"] as? Double ?? 0.0,
                    dataFechamento: (data["dataFechamento"] as? Timestamp)?.dateValue() ?? Date(),
                    dataVencimento: (data["dataVencimento"] as? Timestamp)?.dateValue() ?? Date(),
                    isDefault: data["isDefault"] as? Bool ?? false,
                    bandeira: data["bandeira"] as? String,
                    numero: data["numero"] as? String,
                    taxaJuros: data["taxaJuros"] as? Double ?? 0.0,
                    apelido: data["apelido"] as? String,
                    ativo: data["ativo"] as? Bool ?? true
                )
                saveContext()
                print("Novo cartão adicionado ao Core Data.")
            }
        }
    }
    
    private func removerCartaoFirestore(documentId: String) {
        Task {
            guard let cartao = await fetchCartaoPorId(UUID(uuidString: documentId) ?? UUID()) else { return }
            context.delete(cartao)
            saveContext()
            print("Cartão \(cartao.nome) removido do Core Data.")
        }
    }
    
    // MARK: Atualizar Operação Firestore
    private func atualizarOperacaoFirestore(document: DocumentSnapshot) {
        guard let data = document.data() else { return }
        Task {
            if let operacao = await fetchOperacaoPorId(UUID(uuidString: data["id"] as? String ?? "") ?? UUID()) {
                operacao.nome = data["nome"] as? String ?? operacao.nome
                operacao.valor = data["valor"] as? Double ?? operacao.valor
                operacao.data = (data["data"] as? Timestamp)?.dateValue() ?? operacao.data
                operacao.metodoPagamento = data["metodoPagamento"] as? String ?? operacao.metodoPagamento
                operacao.recorrente = data["recorrente"] as? Bool ?? operacao.recorrente
                operacao.categoria = data["categoria"] as? String ?? operacao.categoria
                operacao.nota = data["nota"] as? String ?? operacao.nota
                
                if let rawTipo = data["tipo"] as? String {
                    if let enumValue = TipoOperacao(rawValue: rawTipo) {
                        operacao.tipoOperacao = enumValue
                    } else {
                        operacao.tipoString = rawTipo
                    }
                }
                
                saveContext()
                print("Operação \(operacao.nome) atualizada no Core Data.")
            } else {
                let _ = Operacao(
                    context: context,
                    nome: data["nome"] as? String ?? "Sem Nome",
                    valor: data["valor"] as? Double ?? 0.0,
                    data: (data["data"] as? Timestamp)?.dateValue() ?? Date(),
                    metodoPagamento: data["metodoPagamento"] as? String ?? "Outro",
                    recorrente: data["recorrente"] as? Bool ?? false,
                    cartao: nil
                )
                saveContext()
                print("Nova operação adicionada ao Core Data.")
            }
        }
    }
    
    private func removerOperacaoFirestore(documentId: String) {
        Task {
            guard let operacao = await fetchOperacaoPorId(UUID(uuidString: documentId) ?? UUID()) else { return }
            context.delete(operacao)
            saveContext()
            print("Operação \(operacao.nome) removida do Core Data.")
        }
    }
    
    // MARK: Atualizar Recorrência Firestore
    private func atualizarRecorrenciaFirestore(document: DocumentSnapshot) {
        guard let data = document.data() else { return }
        Task {
            if let recorrencia = await fetchRecorrencias().first(where: { $0.id.uuidString == document.documentID }) {
                if let tipoString = data["tipo"] as? String {
                    recorrencia.tipo = TipoOperacao(rawValue: tipoString)?.rawValue ?? "Desconhecido"
                }
                recorrencia.intervalo = data["intervalo"] as? Int32 ?? recorrencia.intervalo
                recorrencia.proximaData = (data["proximaData"] as? Timestamp)?.dateValue() ?? recorrencia.proximaData
                saveContext()
                print("Recorrência \(recorrencia.tipo) atualizada no Core Data.")
            } else {
                let novaRecorrencia = Recorrencia(
                    context: context,
                    tipo: data["tipo"] as? String ?? "Mensal",
                    intervalo: data["intervalo"] as? Int32 ?? 30,
                    dataInicial: Date(),
                    operacao: nil
                )
                novaRecorrencia.proximaData = (data["proximaData"] as? Timestamp)?.dateValue() ?? Date()
                saveContext()
                print("Nova recorrência adicionada ao Core Data.")
            }
        }
    }
    
    private func removerRecorrenciaFirestore(documentId: String) {
        Task {
            let recorrencias = await fetchRecorrencias()
            if let recorrencia = recorrencias.first(where: { $0.id.uuidString == documentId }) {
                context.delete(recorrencia)
                saveContext()
                print("Recorrência \(recorrencia.tipo) removida do Core Data.")
            }
        }
    }
}

// ======================================================
// MARK: - Métodos para Buscar Objetos por ID
// ======================================================
extension CoreDataManager {
    
    func fetchCartaoPorId(_ id: UUID) async -> Cartao? {
        let fetchRequest: NSFetchRequest<Cartao> = Cartao.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            return try await context.perform {
                try self.context.fetch(fetchRequest).first
            }
        } catch {
            print("Erro ao buscar cartão por ID \(id): \(error.localizedDescription)")
            return nil
        }
    }
    
    func fetchOperacaoPorId(_ id: UUID) async -> Operacao? {
        let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            return try await context.perform {
                try self.context.fetch(fetchRequest).first
            }
        } catch {
            print("Erro ao buscar operação por ID \(id): \(error.localizedDescription)")
            return nil
        }
    }
    
    func fetchFaturaPorId(_ id: UUID) async -> Fatura? {
        let fetchRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            return try await context.perform {
                try self.context.fetch(fetchRequest).first
            }
        } catch {
            print("Erro ao buscar fatura por ID \(id): \(error.localizedDescription)")
            return nil
        }
    }
}

// ======================================================
// MARK: - Compartilhamento (Grupos) no Firestore
// ======================================================
/*
func criarCodigoCompartilhamento(completion: @escaping (String?) -> Void) {
    let db = Firestore.firestore()
    let groupRef = db.collection("shared_groups")
    
    func gerarCodigoAleatorio() -> String {
        let caracteres = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in caracteres.randomElement()! })
    }

    func verificarEInserirCodigo(_ codigo: String) {
        groupRef.document(codigo).getDocument { document, error in
            if let error = error {
                print("Erro ao verificar código: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if document?.exists == true {
                // 🔹 Código já existe, geramos outro
                print("Código \(codigo) já existe. Gerando outro...")
                verificarEInserirCodigo(gerarCodigoAleatorio())
            } else {
                // 🔹 Código é único, podemos criar o grupo
                groupRef.document(codigo).setData([
                    "participants": [],
                    "createdAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("Erro ao criar grupo: \(error.localizedDescription)")
                        completion(nil)
                    } else {
                        print("Código \(codigo) criado com sucesso!")
                        completion(codigo)
                    }
                }
            }
        }
    }

    // Inicia a geração e verificação do código
    verificarEInserirCodigo(gerarCodigoAleatorio())
}
 */

extension CoreDataManager {
    func removerDadosDoGrupo(grupoId: String) {
        let context = self.context // Certifique-se de usar o contexto correto associado ao CoreDataManager
        
        let fetchRequestCartoes: NSFetchRequest<Cartao> = Cartao.fetchRequest()
        fetchRequestCartoes.predicate = NSPredicate(format: "grupoId == %@", grupoId)
        
        let fetchRequestOperacoes: NSFetchRequest<Operacao> = Operacao.fetchRequest()
        fetchRequestOperacoes.predicate = NSPredicate(format: "grupoId == %@", grupoId)
        
        do {
            // Remove os cartões associados ao grupo
            let cartoes = try context.fetch(fetchRequestCartoes)
            for cartao in cartoes {
                context.delete(cartao)
            }
            
            // Remove as operações associadas ao grupo
            let operacoes = try context.fetch(fetchRequestOperacoes)
            for operacao in operacoes {
                context.delete(operacao)
            }
            
            try context.save()
            print("Dados do grupo \(grupoId) removidos com sucesso.")
        } catch let error as NSError {
            print("Erro ao remover dados do grupo \(grupoId): \(error), \(error.userInfo)")
        }
    }
}

extension CoreDataManager {
    func entrarNoGrupoCompartilhado(codigo: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(false)
            return
        }
        
        let groupRef = db.collection("shared_groups").document(codigo.uppercased())
        
        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao buscar grupo compartilhado: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists else {
                print("Erro: Código de compartilhamento não encontrado.")
                completion(false)
                return
            }
            
            groupRef.updateData([
                "participants": FieldValue.arrayUnion([userId])
            ]) { error in
                if let error = error {
                    print("Erro ao entrar no grupo compartilhado: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Usuário adicionado ao grupo compartilhado com sucesso.")

                    // Buscar o grupo atualizado (opcional, só p/ contagem de participantes)
                    groupRef.getDocument { updatedDocument, error in
                        if let updatedData = updatedDocument?.data(),
                           let participantes = updatedData["participants"] as? [String],
                           participantes.count > 1 {
                            
                            NotificationCenter.default.post(name: .didUpdateData, object: nil)
                        }
                    }

                    // [MODIFICAÇÃO] CHAMAR IMPORTAÇÃO DE DADOS ASSIM QUE ENTRAR
                    self.importarDadosDoGrupo(grupoId: codigo.uppercased()) {
                        // [MODIFICAÇÃO] CHAMAR O LISTENER EM TEMPO REAL
                        self.configurarObservadorDoGrupo(grupoId: codigo.uppercased())

                        completion(true)
                    }
                }
            }
        }
    }
}

// ==============================
// [NOVO MÉTODO] Importar dados do grupo
// ==============================
extension CoreDataManager {
    
    /// Faz uma leitura única de *cards*, *operations* e *bills* em `shared_groups/<groupId>`
    /// e salva (ou atualiza) tudo no Core Data local.
    func importarDadosDoGrupo(grupoId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        let groupDoc = db.collection("shared_groups").document(grupoId)
        
        // Precisamos buscar 3 subcoleções: cards, operations, bills.
        // Vamos usar DispatchGroup pra saber quando todas terminaram.
        
        let dispatchGroup = DispatchGroup()
        
        // =====================
        // 1) Importar Cartões
        // =====================
        dispatchGroup.enter()
        groupDoc.collection("cards").getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao buscar 'cards' do grupo \(grupoId): \(error.localizedDescription)")
                dispatchGroup.leave()
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("Nenhum card encontrado em shared_groups/\(grupoId)/cards")
                dispatchGroup.leave()
                return
            }
            
            Task {
                for doc in documents {
                    await self.atualizarOuCriarCartaoDeGrupo(doc: doc)
                }
                dispatchGroup.leave()
            }
        }
        
        // ======================
        // 2) Importar Faturas
        // ======================
        dispatchGroup.enter()
        groupDoc.collection("bills").getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao buscar 'bills' do grupo \(grupoId): \(error.localizedDescription)")
                dispatchGroup.leave()
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("Nenhuma bill encontrada em shared_groups/\(grupoId)/bills")
                dispatchGroup.leave()
                return
            }
            
            Task {
                for doc in documents {
                    await self.atualizarOuCriarFaturaDeGrupo(doc: doc)
                }
                dispatchGroup.leave()
            }
        }
        
        // ======================
        // 3) Importar Operações
        // ======================
        dispatchGroup.enter()
        groupDoc.collection("operations").getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao buscar 'operations' do grupo \(grupoId): \(error.localizedDescription)")
                dispatchGroup.leave()
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("Nenhuma operation encontrada em shared_groups/\(grupoId)/operations")
                dispatchGroup.leave()
                return
            }
            
            Task {
                for doc in documents {
                    await self.atualizarOuCriarOperacaoDeGrupo(doc: doc)
                }
                dispatchGroup.leave()
            }
        }
        
        // Quando tudo terminar, chamamos o `completion`
        dispatchGroup.notify(queue: .main) {
            print(">>> Importação inicial de dados do grupo \(grupoId) concluída.")
            completion()
        }
    }
    
    @MainActor
    private func atualizarOuCriarRecorrenciaDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        
        guard let idString = data["id"] as? String,
              let recorrenciaId = UUID(uuidString: idString)
        else {
            print("❌ Recorrência com ID inválido no grupo: \(doc.documentID)")
            return
        }
        
        let fetchReq: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
        fetchReq.predicate = NSPredicate(format: "id == %@", recorrenciaId as CVarArg)
        
        do {
            if let existente = try context.fetch(fetchReq).first {
                // Atualiza os dados da recorrência existente
                existente.tipo = data["tipo"] as? String ?? existente.tipo
                existente.intervalo = data["intervalo"] as? Int32 ?? existente.intervalo
                existente.proximaData = (data["proximaData"] as? Timestamp)?.dateValue() ?? existente.proximaData
                saveContext()
                print("✅ Recorrência [\(existente.tipo)] atualizada no Core Data (grupo).")
            } else {
                // Cria nova recorrência
                let novaRecorrencia = Recorrencia(context: context)
                novaRecorrencia.id = recorrenciaId
                novaRecorrencia.tipo = data["tipo"] as? String ?? "Mensal"
                novaRecorrencia.intervalo = data["intervalo"] as? Int32 ?? 30
                novaRecorrencia.proximaData = (data["proximaData"] as? Timestamp)?.dateValue() ?? Date()
                saveContext()
                print("✅ Nova recorrência [\(novaRecorrencia.tipo)] criada no Core Data (grupo).")
            }
        } catch {
            print("❌ Erro ao buscar/criar recorrência do grupo: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func removerRecorrenciaDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        
        guard let idString = data["id"] as? String,
              let recorrenciaId = UUID(uuidString: idString) else {
            print("Erro: Recorrência removida do Firestore, mas ID inválido.")
            return
        }
        
        let fetchRequest: NSFetchRequest<Recorrencia> = Recorrencia.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", recorrenciaId as CVarArg)

        do {
            if let recorrencia = try context.fetch(fetchRequest).first {
                context.delete(recorrencia)
                saveContext()
                print("Recorrência [\(recorrencia.tipo)] removida do Core Data (grupo).")
            } else {
                print("Recorrência com ID [\(recorrenciaId)] não encontrada no Core Data.")
            }
        } catch {
            print("Erro ao remover recorrência do Core Data: \(error.localizedDescription)")
        }
    }
    
    func fetchTodosOsCartoes() async -> [Cartao] {
        let fetchRequest: NSFetchRequest<Cartao> = Cartao.fetchRequest()
        
        do {
            let cartoes = try context.fetch(fetchRequest)
            return cartoes
        } catch {
            print("❌ Erro ao buscar todos os cartões no Core Data: \(error.localizedDescription)")
            return []
        }
    }
    
    // ---------------------------------------------------
    // A seguir, os métodos auxiliares para cada tipo:
    // ---------------------------------------------------
    
    @MainActor
    func atualizarOuCriarCartaoDeGrupo(doc: QueryDocumentSnapshot) async {
        print("📥 RECEBENDO do Firestore para atualizar/criar cartão: \(doc.data())")
        let data = doc.data()

        guard let idString = data["id"] as? String,
              let cartaoId = UUID(uuidString: idString) else {
            print("❌ Cartão com ID inválido no grupo: \(doc.documentID)")
            return
        }
        
        // ✅ 🔍 Verificação Extra: Buscar TODOS os cartões antes de verificar
        let todosCartoes = await fetchTodosOsCartoes()
        print("🔍 Core Data contém \(todosCartoes.count) cartões antes da verificação.")

        // ✅ 🔄 Verifica se já existe no Core Data
        if let existente = await fetchCartaoPorId(cartaoId) {
            print("🔄 Cartão já existe no Core Data! Atualizando dados...")
            
            existente.nome = data["nome"] as? String ?? existente.nome
            existente.limite = data["limite"] as? Double ?? existente.limite
            existente.dataFechamento = (data["fechamento"] as? Timestamp)?.dateValue() ?? existente.dataFechamento
            existente.dataVencimento = (data["vencimento"] as? Timestamp)?.dateValue() ?? existente.dataVencimento
            existente.isDefault = data["isDefault"] as? Bool ?? existente.isDefault
            existente.bandeira = data["bandeira"] as? String ?? existente.bandeira
            existente.numero = data["numero"] as? String ?? existente.numero
            existente.taxaJuros = data["taxaJuros"] as? Double ?? existente.taxaJuros
            existente.apelido = data["apelido"] as? String ?? existente.apelido
            existente.ativo = data["ativo"] as? Bool ?? existente.ativo

            saveContext()
            print("✅ Cartão [\(existente.nome)] atualizado no Core Data.")
        } else {
            print("🆕 Criando novo cartão no Core Data.")
            let novoCartao = Cartao(
                context: context,
                nome: data["nome"] as? String ?? "Sem nome",
                limite: data["limite"] as? Double ?? 0.0,
                dataFechamento: (data["fechamento"] as? Timestamp)?.dateValue() ?? Date(),
                dataVencimento: (data["vencimento"] as? Timestamp)?.dateValue() ?? Date(),
                isDefault: data["isDefault"] as? Bool ?? false,
                bandeira: data["bandeira"] as? String,
                numero: data["numero"] as? String,
                taxaJuros: data["taxaJuros"] as? Double ?? 0.0,
                apelido: data["apelido"] as? String
            )
            novoCartao.id = cartaoId  // 🔹 IMPORTANTE: Garante que o UUID está sendo salvo corretamente
            novoCartao.ativo = data["ativo"] as? Bool ?? true

            saveContext()
            print("✅ Novo Cartão [\(novoCartao.nome)] criado no Core Data.")
        }

        // ✅ 🔍 Verificação Extra: Buscar TODOS os cartões após salvar
        let totalCartoesDepois = await fetchTodosOsCartoes()
        print("📊 ✅ Total de cartões no Core Data após sincronização: \(totalCartoesDepois.count)")
    }
    
    @MainActor
    func atualizarOuCriarFaturaDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        
        guard let idString = data["id"] as? String,
              let faturaId = UUID(uuidString: idString)
        else {
            print("Fatura com ID inválido no grupo: \(doc.documentID)")
            return
        }
        
        // Tenta ler o cartaoId e buscar o Cartao correspondente
        var cartaoAssociado: Cartao? = nil
        if let cartaoIdStr = data["cartaoId"] as? String,
           let cartaoId = UUID(uuidString: cartaoIdStr) {
            cartaoAssociado = await fetchCartaoPorId(cartaoId)
            
            // Se não encontrou, aguarde 2 segundos e tente novamente
            if cartaoAssociado == nil {
                print("Cartão não encontrado de imediato para ID: \(cartaoIdStr). Tentando novamente em 2 segundos...")
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 segundos
                cartaoAssociado = await fetchCartaoPorId(cartaoId)
            }
        }
        
        let fetchReq: NSFetchRequest<Fatura> = Fatura.fetchRequest()
        fetchReq.predicate = NSPredicate(format: "id == %@", faturaId as CVarArg)
        
        do {
            if let existente = try context.fetch(fetchReq).first {
                existente.dataVencimento = (data["dataVencimento"] as? Timestamp)?.dateValue() ?? existente.dataVencimento
                existente.valorTotal = data["valorTotal"] as? Double ?? existente.valorTotal
                // Se disponível, associa o cartão
                if let cartao = cartaoAssociado {
                    existente.cartao = cartao
                }
                saveContext()
                print("Fatura [\(existente.id)] atualizada no Core Data (grupo).")
            } else {
                let novaFatura = Fatura(context: context)
                novaFatura.id = faturaId
                novaFatura.dataVencimento = (data["dataVencimento"] as? Timestamp)?.dateValue() ?? Date()
                novaFatura.valorTotal = data["valorTotal"] as? Double ?? 0.0
                novaFatura.paga = data["paga"] as? Bool ?? false
                // Associa o cartão se possível
                if let cartao = cartaoAssociado {
                    novaFatura.cartao = cartao
                }
                saveContext()
                print("Nova Fatura [\(novaFatura.id)] criada no Core Data (grupo).")
            }
        } catch {
            print("Erro ao buscar/criar fatura do grupo: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func atualizarOuCriarOperacaoDeGrupo(doc: QueryDocumentSnapshot) async {
        // Execute a operação de forma síncrona no contexto para evitar condições de corrida
        await context.perform {
            let data = doc.data()
            
            // Verifica se o campo "id" está presente e é um UUID válido
            guard let idString = data["id"] as? String,
                  let opId = UUID(uuidString: idString) else {
                print("Operação com ID inválido no grupo: \(doc.documentID)")
                return
            }
            
            // Cria um fetch request para buscar a operação com o mesmo ID
            let fetchRequest: NSFetchRequest<Operacao> = Operacao.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", opId as CVarArg)
            fetchRequest.fetchLimit = 1
            
            do {
                let results = try self.context.fetch(fetchRequest)
                if let existente = results.first {
                    // Atualiza os campos da operação existente
                    existente.nome = data["nome"] as? String ?? existente.nome
                    existente.valor = data["valor"] as? Double ?? existente.valor
                    existente.data = (data["data"] as? Timestamp)?.dateValue() ?? existente.data
                    existente.metodoPagamento = data["metodoPagamento"] as? String ?? existente.metodoPagamento
                    existente.recorrente = data["recorrente"] as? Bool ?? existente.recorrente
                    existente.categoria = data["categoria"] as? String ?? existente.categoria
                    existente.nota = data["nota"] as? String ?? existente.nota
                    if let tipo = data["tipo"] as? String {
                        existente.tipoString = tipo
                    }
                    if let recIdStr = data["idRecorrencia"] as? String {
                        existente.idRecorrencia = UUID(uuidString: recIdStr)
                    }
                    existente.numeroParcelas = Int16(data["numeroParcelas"] as? Int ?? 1)
                    
                    print("Operação [\(existente.nome)] atualizada no Core Data (grupo).")
                } else {
                    // Se não encontrou, cria uma nova operação com o mesmo ID
                    let novaOperacao = Operacao(context: self.context)
                    novaOperacao.id = opId
                    novaOperacao.nome = data["nome"] as? String ?? "Sem nome"
                    novaOperacao.valor = data["valor"] as? Double ?? 0.0
                    novaOperacao.data = (data["data"] as? Timestamp)?.dateValue() ?? Date()
                    novaOperacao.metodoPagamento = data["metodoPagamento"] as? String ?? "Outro"
                    novaOperacao.recorrente = data["recorrente"] as? Bool ?? false
                    novaOperacao.categoria = data["categoria"] as? String
                    novaOperacao.nota = data["nota"] as? String
                    novaOperacao.tipoString = data["tipo"] as? String
                    if let recIdStr = data["idRecorrencia"] as? String {
                        novaOperacao.idRecorrencia = UUID(uuidString: recIdStr)
                    }
                    novaOperacao.numeroParcelas = Int16(data["numeroParcelas"] as? Int ?? 1)
                    
                    print("Nova operação criada no Core Data (grupo).")
                }
                try self.context.save()
            } catch {
                print("Erro ao atualizar/criar operação (grupo): \(error.localizedDescription)")
            }
        }
    }
}

// ==============================
// [NOVO MÉTODO] Observador em tempo real do grupo
// ==============================
extension CoreDataManager {

    func configurarObservadorDoGrupo(grupoId: String) {
        print("📡 Configurando listener para o grupo: \(grupoId)")
        let db = Firestore.firestore()
        let groupDoc = db.collection("shared_groups").document(grupoId)
        
        var listeners: [ListenerRegistration] = []
        
        // 🔄 **Escutar mudanças em `cards`**
        let listenerCards = groupDoc.collection("cards").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Erro no listener de cards (grupo \(grupoId)): \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else { return }
            
            for change in snapshot.documentChanges {
                let doc = change.document
                switch change.type {
                case .added, .modified:
                    Task { await self.atualizarOuCriarCartaoDeGrupo(doc: doc) }
                case .removed:
                    Task { await self.removerCartaoDeGrupo(doc: doc) }
                }
            }
        }
        listeners.append(listenerCards)
        
        // 🔄 **Escutar mudanças em `bills`**
        let listenerBills = groupDoc.collection("bills").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Erro no listener de bills (grupo \(grupoId)): \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else { return }
            
            for change in snapshot.documentChanges {
                let doc = change.document
                switch change.type {
                case .added, .modified:
                    Task { await self.atualizarOuCriarFaturaDeGrupo(doc: doc) }
                case .removed:
                    Task { await self.removerFaturaDeGrupo(doc: doc) }
                }
            }
        }
        listeners.append(listenerBills)
        
        // 🔄 **Escutar mudanças em `operations`**
        let listenerOperations = groupDoc.collection("operations").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Erro no listener de operations (grupo \(grupoId)): \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else { return }
            print("📡 Listener de operations do grupo \(grupoId) disparado com \(snapshot.documentChanges.count) mudança(s).")
            
            for change in snapshot.documentChanges {
                let doc = change.document
                switch change.type {
                case .added, .modified:
                    Task { await self.atualizarOuCriarOperacaoDeGrupo(doc: doc) }
                case .removed:
                    Task { await self.removerOperacaoDeGrupo(doc: doc) }
                }
            }
        }
        listeners.append(listenerOperations)
        
        // 🔄 **Escutar mudanças em `recurrences`**
        let listenerRecurrences = groupDoc.collection("recurrences").addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Erro no listener de recurrences (grupo \(grupoId)): \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else { return }
            
            for change in snapshot.documentChanges {
                let doc = change.document
                switch change.type {
                case .added, .modified:
                    Task { await self.atualizarOuCriarRecorrenciaDeGrupo(doc: doc) }
                case .removed:
                    Task { await self.removerRecorrenciaDeGrupo(doc: doc) }
                }
            }
        }
        listeners.append(listenerRecurrences)
        
        // **🔐 Salvando listeners ativos**
        groupListeners[grupoId] = listeners
    }

    // ==========================================
    // Métodos de REMOÇÃO local, se o doc é removido
    // ==========================================

    @MainActor
    private func removerCartaoDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        guard let idString = data["id"] as? String,
              let cartaoId = UUID(uuidString: idString) else {
            print("Erro: Cartão removido do Firestore mas ID inválido.")
            return
        }
        if let cartao = await fetchCartaoPorId(cartaoId) {
            context.delete(cartao)
            saveContext()
            print("Cartão [\(cartao.nome)] removido do Core Data (grupo).")
        }
    }

    @MainActor
    private func removerFaturaDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        guard let idString = data["id"] as? String,
              let faturaId = UUID(uuidString: idString) else {
            print("Erro: Fatura removida do Firestore mas ID inválido.")
            return
        }
        let fetchRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", faturaId as CVarArg)

        do {
            if let fatura = try context.fetch(fetchRequest).first {
                context.delete(fatura)
                saveContext()
                print("Fatura [\(fatura.id)] removida do Core Data (grupo).")
            }
        } catch {
            print("Erro ao remover fatura [\(faturaId)] do Core Data: \(error.localizedDescription)")
        }
    }

    @MainActor
     func removerOperacaoDeGrupo(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        guard let idString = data["id"] as? String,
              let opId = UUID(uuidString: idString) else {
            print("Erro: Operação removida do Firestore mas ID inválido.")
            return
        }
        if let operacao = await fetchOperacaoPorId(opId) {
            context.delete(operacao)
            saveContext()
            print("Operação [\(operacao.nome)] removida do Core Data (grupo).")
        }
    }
    
    @MainActor
    func removerOperacaoDoUsuario(doc: QueryDocumentSnapshot) async {
        let data = doc.data()
        guard let idString = data["id"] as? String,
              let opId = UUID(uuidString: idString) else {
             print("Erro: Operação removida do Firestore (usuário) mas ID inválido.")
             return
        }
        if let operacao = await fetchOperacaoPorId(opId) {
             context.delete(operacao)
             saveContext()
             print("Operação '\(operacao.nome)' removida do Core Data (usuário).")
        } else {
             print("Operação com ID \(opId.uuidString) não encontrada no Core Data.")
        }
    }
}

extension CoreDataManager {
    func criarGrupoCompartilhado(completion: @escaping (String?) -> Void) {
        let db = Firestore.firestore()
        let sharedCode = UUID().uuidString.prefix(8).uppercased()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(nil)
            return
        }
        
        let groupData: [String: Any] = [
            "sharedCode": sharedCode,
            "participants": [userId],
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("shared_groups").document(String(sharedCode)).setData(groupData) { error in
            if let error = error {
                print("Erro ao criar grupo compartilhado: \(error.localizedDescription)")
                completion(nil)
            } else {
                print("Grupo compartilhado criado com sucesso com o código: \(sharedCode)")
                completion(String(sharedCode))
            }
        }
    }
}

extension CoreDataManager {
    func verificarGrupoCompartilhado(completion: @escaping ([String]?) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(nil)
            return
        }
        
        db.collection("shared_groups").whereField("participants", arrayContains: userId).getDocuments { snapshot, error in
            if let error = error {
                print("Erro ao verificar grupo compartilhado: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                print("Nenhum grupo compartilhado encontrado.")
                completion(nil)
                return
            }
            
            let groupCodes = documents.map { $0.documentID }
            completion(groupCodes)
        }
    }
}

extension CoreDataManager {
    func observarGruposCompartilhados(completion: @escaping ([String]?) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(nil)
            return
        }
        
        db.collection("shared_groups")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Erro ao observar grupos compartilhados: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    // Caso não haja nenhum grupo, chamamos completion(nil) pra limpar o estado
                    print("Nenhum grupo compartilhado encontrado (snapshotListener).")
                    completion(nil)
                    return
                }
                
                // Se houver documentos, criamos a lista de IDs
                let groupCodes = documents.map { $0.documentID }
                completion(groupCodes)
            }
    }
}

extension CoreDataManager {
    func sincronizarOperacoesCompartilhadas() async {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            return
        }
        
        db.collection("shared_groups").whereField("participants", arrayContains: userId).getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                print("Erro ao buscar grupos compartilhados: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                print("Nenhum grupo compartilhado encontrado.")
                return
            }
            let groupCodes = documents.map { $0.documentID }
            for groupCode in groupCodes {
                Task {
                    await self.sincronizarOperacoesDoGrupo(grupoCode: groupCode)
                }
            }
        }
    }
    
    func sincronizarOperacoesDoGrupo(grupoCode: String) async {
        let db = Firestore.firestore()
        db.collection("shared_groups").document(grupoCode).collection("operations").getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                print("Erro ao sincronizar operações do grupo \(grupoCode): \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                print("Nenhuma operação encontrada para o grupo \(grupoCode).")
                return
            }
            for document in documents {
                let data = document.data()
                let id = UUID(uuidString: data["id"] as? String ?? "")
                let nome = data["nome"] as? String ?? "Sem Nome"
                let valor = data["valor"] as? Double ?? 0.0
                let dataOperacao = (data["data"] as? Timestamp)?.dateValue() ?? Date()
                let metodoPagamento = data["metodoPagamento"] as? String ?? "Outro"
                let recorrente = data["recorrente"] as? Bool ?? false
                
                Task {
                    if let id = id, await self.fetchOperacaoPorId(id) == nil {
                        await self.criarOperacao(
                            id: id, // passa o ID vindo do Firestore
                            nome: nome,
                            valor: valor,
                            data: dataOperacao,
                            metodoPagamento: metodoPagamento,
                            recorrente: recorrente
                        )
                        print("Operação \(nome) sincronizada do grupo \(grupoCode).")
                    }
                }
            }
        }
    }
}

extension MoneyManager {
    private func sincronizarTudoAoIniciar() async {
        await CoreDataManager.shared.sincronizarOperacoesCompartilhadas()
    }
}

// MARK: - Controle de Permissões para Grupos Compartilhados
extension CoreDataManager {
    func verificarPermissaoNoGrupo(grupoId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else {
            print("Erro: Usuário não autenticado.")
            completion(false)
            return
        }

        let groupRef = db.collection("shared_groups").document(grupoId)

        groupRef.getDocument { document, error in
            if let error = error {
                print("Erro ao verificar permissão no grupo: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let document = document, document.exists,
                  let data = document.data(),
                  let participantes = data["participants"] as? [String] else {
                print("Grupo não encontrado ou sem participantes.")
                completion(false)
                return
            }

            if participantes.contains(userId) {
                print("Usuário tem permissão para acessar o grupo \(grupoId).")
                completion(true)
            } else {
                print("Usuário NÃO tem permissão para acessar o grupo \(grupoId).")
                completion(false)
            }
        }
    }
}

// MARK: - Logs de Auditoria para Grupos Compartilhados
extension CoreDataManager {
    func registrarLogNoGrupo(grupoId: String, acao: String, detalhes: String) {
        let db = Firestore.firestore()
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let logData: [String: Any] = [
            "usuarioId": userId,
            "acao": acao,
            "detalhes": detalhes,
            "timestamp": FieldValue.serverTimestamp()
        ]

        db.collection("shared_groups").document(grupoId).collection("logs").addDocument(data: logData) { error in
            if let error = error {
                print("Erro ao registrar log no grupo: \(error.localizedDescription)")
            } else {
                print("Log registrado no grupo \(grupoId): \(acao) - \(detalhes)")
            }
        }
    }
}

// ======================================================
// MARK: - Extensões Úteis (Date, Double, etc.)
// ======================================================
extension Date {
    func startOfDay(_ calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }
    func endOfDay(_ calendar: Calendar = .current) -> Date {
        let start = self.startOfDay(calendar)
        return calendar.date(byAdding: .second, value: 86399, to: start) ?? self
    }
}

extension Double {
    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension Calendar.Component {
    static func from(_ tipo: String) -> Calendar.Component? {
        switch tipo.lowercased() {
        case "diária":  return .day
        case "semanal": return .weekOfYear
        case "mensal":  return .month
        case "anual":   return .year
        default:        return nil
        }
    }
}

// MARK: - Buscar Participantes de um Grupo (Exemplo adicional)
func buscarParticipantesDoGrupo(grupoId: String, completion: @escaping ([Usuario]) -> Void) {
    let db = Firestore.firestore()
    db.collection("shared_groups").document(grupoId).getDocument { snapshot, error in
        if let error = error {
            print("Erro ao buscar participantes do grupo: \(error.localizedDescription)")
            completion([])
            return
        }
        
        guard let data = snapshot?.data(), let participants = data["participants"] as? [String] else {
            print("Nenhum participante encontrado.")
            completion([])
            return
        }
        
        var usuarios: [Usuario] = []
        let dispatchGroup = DispatchGroup()
        
        for userId in participants {
            dispatchGroup.enter()
            db.collection("users").document(userId).getDocument { userSnapshot, userError in
                if let userError = userError {
                    print("Erro ao buscar usuário: \(userError.localizedDescription)")
                } else if let userData = userSnapshot?.data() {
                    DispatchQueue.main.async {
                        let usuario = Usuario(context: CoreDataManager.shared.context)
                        usuario.id = UUID(uuidString: userId) ?? UUID()
                        usuario.nome = userData["nome"] as? String ?? "Nome Desconhecido"
                        usuario.email = userData["email"] as? String ?? "Email não disponível"
                        usuarios.append(usuario)
                    }
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(usuarios)
        }
    }
}

@MainActor
extension CoreDataManager {
    func atualizarFaturaFirestore(document: DocumentSnapshot) async {
        guard let data = document.data() else { return }
        guard let id = UUID(uuidString: data["id"] as? String ?? "") else {
            print("Erro: ID inválido para a fatura.")
            return
        }
        
        let fetchRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let existingFatura = try self.context.fetch(fetchRequest).first
            
            if let fatura = existingFatura {
                fatura.dataInicio = (data["dataInicio"] as? Timestamp)?.dateValue() ?? fatura.dataInicio
                fatura.dataFechamento = (data["dataFechamento"] as? Timestamp)?.dateValue() ?? fatura.dataFechamento
                fatura.dataVencimento = (data["dataVencimento"] as? Timestamp)?.dateValue() ?? fatura.dataVencimento
                fatura.valorTotal = data["valorTotal"] as? Double ?? fatura.valorTotal
                fatura.paga = data["paga"] as? Bool ?? fatura.paga
                self.saveContext()
                print("Fatura \(fatura.id) atualizada no Core Data.")
            } else {
                let novaFatura = Fatura(context: self.context)
                novaFatura.id = id
                novaFatura.dataInicio = (data["dataInicio"] as? Timestamp)?.dateValue() ?? Date()
                novaFatura.dataFechamento = (data["dataFechamento"] as? Timestamp)?.dateValue() ?? Date()
                novaFatura.dataVencimento = (data["dataVencimento"] as? Timestamp)?.dateValue() ?? Date()
                novaFatura.valorTotal = data["valorTotal"] as? Double ?? 0.0
                novaFatura.paga = data["paga"] as? Bool ?? false
                self.saveContext()
                print("Nova fatura \(novaFatura.id) adicionada ao Core Data.")
            }
        } catch {
            print("Erro ao buscar ou atualizar fatura no Core Data: \(error.localizedDescription)")
        }
    }
    
    func removerFaturaFirestore(documentId: String) async {
        guard let id = UUID(uuidString: documentId) else { return }
        
        let fetchRequest: NSFetchRequest<Fatura> = Fatura.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            if let fatura = try self.context.fetch(fetchRequest).first {
                self.context.delete(fatura)
                self.saveContext()
                print("Fatura \(fatura.id) removida do Core Data.")
            } else {
                print("Fatura com ID \(id) não encontrada no Core Data.")
            }
        } catch {
            print("Erro ao remover fatura do Core Data: \(error.localizedDescription)")
        }
    }
}

extension CoreDataManager {
    func buscarParticipantesDoGrupo(grupoId: String, completion: @escaping ([Usuario]) -> Void) {
        let db = Firestore.firestore()
        var usuarios: [Usuario] = []
        let dispatchGroup = DispatchGroup()
        
        db.collection("shared_groups").document(grupoId).getDocument { snapshot, error in
            guard let data = snapshot?.data(), error == nil else {
                print("Erro ao buscar participantes do grupo \(grupoId): \(error?.localizedDescription ?? "Desconhecido")")
                completion([])
                return
            }
            
            let participants = data["participants"] as? [String] ?? []
            for userId in participants {
                dispatchGroup.enter()
                db.collection("users").document(userId).getDocument { userSnapshot, userError in
                    if let userError = userError {
                        print("Erro ao buscar usuário: \(userError.localizedDescription)")
                    } else if let userData = userSnapshot?.data() {
                        DispatchQueue.main.async {
                            let usuario = Usuario(context: CoreDataManager.shared.context)
                            usuario.id = UUID(uuidString: userId) ?? UUID()
                            usuario.nome = userData["nome"] as? String ?? "Nome Desconhecido"
                            usuario.email = userData["email"] as? String ?? "Email não disponível"
                            usuarios.append(usuario)
                        }
                    }
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                completion(usuarios)
            }
        }
    }
}

// Fim do arquivo refatorado
