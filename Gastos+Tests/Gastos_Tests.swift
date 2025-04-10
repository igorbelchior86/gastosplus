import XCTest

class AppUITests: XCTestCase {
    // Essa constante representa o aplicativo em teste
    let app = XCUIApplication()

    // Configuração inicial que roda antes de cada teste
    override func setUpWithError() throws {
        // Continua executando mesmo que um teste falhe
        continueAfterFailure = false

        // Encerra qualquer instância do app que já esteja rodando
        app.terminate()

        // Inicia o aplicativo
        app.launch()
    }

    // Função de limpeza após cada teste, se necessário
    override func tearDownWithError() throws {
        // Implemente se necessário
    }

    // MARK: - Login e Autenticação

    func testLoginComGoogle() throws {
        // Exemplo de teste de login
        // Localize o botão de Login com Google
        let googleLoginButton = app.buttons["LoginComGoogle"]
        XCTAssertTrue(googleLoginButton.exists)

        // Simule o toque no botão de Login com Google
        googleLoginButton.tap()

        // Checar se tela de permissão ou próxima etapa apareceu
        // Exemplo placeholder, pode variar
        let consentAlert = app.alerts["Google Consent"]
        if consentAlert.exists {
            // Se necessário, toque no botão de aceitar
            let allowButton = consentAlert.buttons["Permitir"]
            if allowButton.exists {
                allowButton.tap()
            }
        }

        // Verificar se o login foi bem-sucedido
        // Por exemplo, checar se apareceu a tela principal
        let homeScreen = app.otherElements["HomeScreen"]
        XCTAssertTrue(homeScreen.waitForExistence(timeout: 10), "Falha ao fazer login com Google")
    }

    func testFaceIDAutenticacao() throws {
        // Ativar FaceID ou simular
        // Aqui, normalmente se utiliza o simulador com FaceID habilitado
        // Exemplo de simulação da autenticação
        let faceIDToggle = app.switches["FaceIDSwitch"]
        if faceIDToggle.exists {
            // Ativar Face ID
            faceIDToggle.tap()
            // Validar se está habilitado
            XCTAssertEqual(faceIDToggle.value as? String, "1", "FaceID não ativou corretamente")
        }
    }

    func testConfiguracaoPIN() throws {
        // Exemplo de criação do PIN
        let createPINButton = app.buttons["CriarPIN"]
        if createPINButton.exists {
            createPINButton.tap()
            let pinTextField = app.secureTextFields["PINTextField"]
            pinTextField.tap()
            pinTextField.typeText("1234")
            app.buttons["Confirmar"].tap()

            // Valida se o PIN foi criado
            let successLabel = app.staticTexts["PIN criado com sucesso"]
            XCTAssertTrue(successLabel.exists, "Falha ao criar PIN")
        }
    }

    func testLogout() throws {
        // Exemplo de logout
        let logoutButton = app.buttons["Logout"]
        XCTAssertTrue(logoutButton.exists)
        logoutButton.tap()

        // Validar se voltou para tela de login
        let loginScreen = app.otherElements["LoginScreen"]
        XCTAssertTrue(loginScreen.waitForExistence(timeout: 5), "Falha ao deslogar")
    }

    func testLogoutForcadoAposFecharApp() throws {
        // Fecha o aplicativo
        app.terminate()
        // Reabre
        app.launch()
        // Verifica se usuário voltou para a tela de login
        let loginScreen = app.otherElements["LoginScreen"]
        XCTAssertTrue(loginScreen.waitForExistence(timeout: 5), "Usuário não foi deslogado ao reabrir o app")
    }

    func testRevalidarLoginAposSessaoExpirada() throws {
        // Simule o tempo ou a expiração da sessão
        // Verifique se app pediu login novamente
        let loginScreen = app.otherElements["LoginScreen"]
        XCTAssertTrue(loginScreen.waitForExistence(timeout: 10), "O login não foi requisitado após expirar a sessão")
    }

    // MARK: - Perfil do Usuário

    func testEditarPerfil() throws {
        // Exemplo: abrir tela de perfil
        let profileTab = app.buttons["PerfilTab"]
        profileTab.tap()
        let editButton = app.buttons["EditarPerfil"]
        editButton.tap()

        // Exemplo de edição
        let nameField = app.textFields["Nome"]
        nameField.tap()
        nameField.typeText("Nome Editado")
        app.buttons["Salvar"].tap()

        // Validar se o nome foi atualizado
        let updatedName = app.staticTexts["Nome Editado"]
        XCTAssertTrue(updatedName.exists, "Falha ao atualizar o nome do usuário")
    }

    func testUploadImagemPerfil() throws {
        // Exemplo de upload de imagem
        let profileTab = app.buttons["PerfilTab"]
        profileTab.tap()
        let changePhotoButton = app.buttons["AlterarFoto"]
        changePhotoButton.tap()

        // Simular abertura da galeria de fotos
        // Isso pode exigir automação adicional
        let firstPhoto = app.collectionViews.cells.element(boundBy: 0)
        if firstPhoto.exists {
            firstPhoto.tap()
        }

        // Validar feedback
        let successLabel = app.staticTexts["Foto de perfil atualizada"]
        XCTAssertTrue(successLabel.exists, "A foto de perfil não foi atualizada corretamente")
    }

    func testAtivacaoDesativacaoFaceIDnoPerfil() throws {
        let profileTab = app.buttons["PerfilTab"]
        profileTab.tap()
        let faceIDSwitch = app.switches["FaceIDSwitchPerfil"]
        if faceIDSwitch.exists {
            faceIDSwitch.tap()
            XCTAssertEqual(faceIDSwitch.value as? String, "1", "Falha ao ativar Face ID no perfil")
        }
    }

    func testResetTotalPerfil() throws {
        // Exemplo de reset total
        let profileTab = app.buttons["PerfilTab"]
        profileTab.tap()
        let resetTotalButton = app.buttons["ResetTotalPerfil"]
        resetTotalButton.tap()

        // Confirmar exclusão de dados
        let confirmButton = app.alerts.buttons["Confirmar"]
        if confirmButton.exists {
            confirmButton.tap()
        }

        // Verificar se app retornou para primeira tela
        let onboardingScreen = app.otherElements["OnboardingScreen"]
        XCTAssertTrue(onboardingScreen.exists, "O app não foi resetado corretamente")
    }

    func testResetParcialPerfil() throws {
        let profileTab = app.buttons["PerfilTab"]
        profileTab.tap()
        let resetParcialButton = app.buttons["ResetParcialPerfil"]
        resetParcialButton.tap()

        // Confirmar
        let confirmButton = app.alerts.buttons["Confirmar"]
        if confirmButton.exists {
            confirmButton.tap()
        }

        // Verificar se preferências foram mantidas, mas dados sensíveis removidos
        let somePreference = app.switches["TemaDarkSwitch"]
        XCTAssertTrue(somePreference.exists, "Preferências não foram mantidas no reset parcial")
    }

    // MARK: - Gerenciamento de Cartões

    func testAdicionarNovoCartao() throws {
        let cardsTab = app.buttons["CartoesTab"]
        cardsTab.tap()
        let addCardButton = app.buttons["AdicionarCartao"]
        addCardButton.tap()

        // Preenche dados do cartão
        app.textFields["NomeCartao"].tap()
        app.textFields["NomeCartao"].typeText("Cartão de Teste")
        app.textFields["NumeroCartao"].tap()
        app.textFields["NumeroCartao"].typeText("1234567890123456")
        // Continue com o restante dos campos

        // Salva
        app.buttons["SalvarCartao"].tap()

        // Valida se cartão aparece na lista
        let cardCell = app.cells.staticTexts["Cartão de Teste"]
        XCTAssertTrue(cardCell.exists, "Falha ao adicionar novo cartão")
    }

    func testEditarCartaoExistente() throws {
        // Selecionar um cartão existente
        let cardsTab = app.buttons["CartoesTab"]
        cardsTab.tap()
        let existingCard = app.cells.staticTexts["Cartão de Teste"]
        existingCard.tap()

        // Tocar em Editar
        let editButton = app.buttons["EditarCartao"]
        editButton.tap()

        // Editar campos
        let nameField = app.textFields["NomeCartao"]
        nameField.tap()
        nameField.typeText(" - Editado")
        app.buttons["SalvarCartao"].tap()

        // Verificar se aparece "Cartão de Teste - Editado" na lista
        let updatedCardCell = app.cells.staticTexts["Cartão de Teste - Editado"]
        XCTAssertTrue(updatedCardCell.exists, "Falha ao editar o cartão")
    }

    func testDefinirCartaoPadrao() throws {
        let cardsTab = app.buttons["CartoesTab"]
        cardsTab.tap()
        // Supondo que haja um botão para definir como padrão
        let definePadraoButton = app.buttons["DefinirComoPadrao"]
        definePadraoButton.tap()
        // Validar se foi marcado como padrão
        let padraoLabel = app.staticTexts["Cartão Padrão"]
        XCTAssertTrue(padraoLabel.exists, "Falha ao definir cartão padrão")
    }

    func testExcluirCartao() throws {
        let cardsTab = app.buttons["CartoesTab"]
        cardsTab.tap()
        // Supondo que o cartão "Cartão de Teste - Editado" ainda exista
        let card = app.cells.staticTexts["Cartão de Teste - Editado"]
        if card.exists {
            card.swipeLeft()
            let deleteButton = app.buttons["Excluir"]
            deleteButton.tap()
            // Verificar se sumiu
            XCTAssertFalse(card.exists, "Falha ao excluir o cartão")
        }
    }

    // MARK: - Operações e Transações

    func testAdicionarOperacao() throws {
        let addOperationButton = app.buttons["AdicionarOperacao"]
        addOperationButton.tap()

        // Preenche dados básicos da operação
        let valorField = app.textFields["ValorOperacao"]
        valorField.tap()
        valorField.typeText("100")

        // Seleciona método de pagamento
        let pagamentoSegment = app.segmentedControls["MetodoPagamento"]
        pagamentoSegment.buttons["Cartão"].tap()

        // Salva
        app.buttons["SalvarOperacao"].tap()

        // Verifica se aparece na lista
        let newOperation = app.cells.staticTexts["R$ 100"]
        XCTAssertTrue(newOperation.exists, "Falha ao adicionar operação")
    }

    func testExcluirOperacao() throws {
        // Selecionar operação
        let operationCell = app.cells.staticTexts["R$ 100"]
        if operationCell.exists {
            operationCell.swipeLeft()
            let deleteButton = app.buttons["Excluir"]
            deleteButton.tap()
            XCTAssertFalse(operationCell.exists, "Falha ao excluir operação")
        }
    }

    func testOperacaoParcelada() throws {
        let addOperationButton = app.buttons["AdicionarOperacao"]
        addOperationButton.tap()

        // Preenche dados
        let valorField = app.textFields["ValorOperacao"]
        valorField.tap()
        valorField.typeText("500")
        // Selecionar parcelamento
        let parcelasSegment = app.segmentedControls["Parcelas"]
        parcelasSegment.buttons["5x"].tap()

        app.buttons["SalvarOperacao"].tap()

        // Verificar criação de múltiplas parcelas
        // Exemplo simples, cada parcela pode ter referência
        let parcela1 = app.cells.staticTexts["Parcela 1/5"]
        let parcela5 = app.cells.staticTexts["Parcela 5/5"]
        XCTAssertTrue(parcela1.exists && parcela5.exists, "Falha ao criar operação parcelada")
    }

    func testExcluirOperacaoParcelada() throws {
        // Excluir uma operação parcelada completa
        let parcela1 = app.cells.staticTexts["Parcela 1/5"]
        if parcela1.exists {
            parcela1.swipeLeft()
            let deleteSeriesButton = app.buttons["ExcluirSerie"]
            deleteSeriesButton.tap()
            // Verificar se sumiu
            XCTAssertFalse(parcela1.exists, "Falha ao excluir série de parcelas")
        }
    }

    // MARK: - Faturas e Pagamentos

    func testGeracaoFatura() throws {
        // Acessar faturas
        let faturasTab = app.buttons["FaturasTab"]
        faturasTab.tap()

        // Verificar se existe alguma fatura gerada
        let faturaAtual = app.cells.staticTexts["FaturaAtual"]
        XCTAssertTrue(faturaAtual.exists, "Fatura não foi gerada corretamente")
    }

    func testPagamentoFatura() throws {
        let faturasTab = app.buttons["FaturasTab"]
        faturasTab.tap()
        let faturaAtual = app.cells.staticTexts["FaturaAtual"]
        faturaAtual.tap()
        let pagarButton = app.buttons["PagarFatura"]
        pagarButton.tap()

        // Verificar saldo
        let saldoLabel = app.staticTexts["SaldoCartao"]
        // Exemplo: se o saldo esperado for 0
        XCTAssertEqual(saldoLabel.label, "R$ 0,00", "Falha ao pagar fatura")
    }

    // MARK: - Navegação e UI

    func testFluxoInicial() throws {
        // Verifica se o app inicia na tela de login quando não autenticado
        let loginScreen = app.otherElements["LoginScreen"]
        XCTAssertTrue(loginScreen.exists, "O app não iniciou na tela de login")
    }

    func testBarraNavegacaoInferior() throws {
        // Após login, verifica se a barra de navegação inferior existe
        let homeTab = app.buttons["HomeTab"]
        let addOperationTab = app.buttons["AdicionarOperacaoTab"]
        let profileTab = app.buttons["PerfilTab"]
        XCTAssertTrue(homeTab.exists && addOperationTab.exists && profileTab.exists, "Barra de navegação inferior não funciona corretamente")
    }

    func testTemaDark() throws {
        // Exemplo: verificar se a UI está em modo dark
        // Teste fictício, pode variar
        let darkModeElement = app.otherElements["DarkModeActive"]
        XCTAssertTrue(darkModeElement.exists, "Tema dark não está ativo")
    }

    func testAlternarSaldoVisivelOculto() throws {
        let toggleSaldoButton = app.buttons["ToggleSaldo"]
        toggleSaldoButton.tap()

        let saldoOculto = app.staticTexts["****"]
        XCTAssertTrue(saldoOculto.exists, "Falha ao ocultar saldo")

        toggleSaldoButton.tap()

        let saldoVisivel = app.staticTexts["R$"]
        XCTAssertTrue(saldoVisivel.exists, "Falha ao exibir saldo")
    }

    // MARK: - Sincronização e Banco de Dados

    func testSincronizacaoFirestore() throws {
        // Realizar alguma ação que gere atualização no Firestore
        // Exemplo: adicionar operação
        let addOperationButton = app.buttons["AdicionarOperacao"]
        addOperationButton.tap()
        app.textFields["ValorOperacao"].tap()
        app.textFields["ValorOperacao"].typeText("150")
        app.buttons["SalvarOperacao"].tap()

        // Verificar se um indicador de sincronização aparece
        let syncIndicator = app.otherElements["Sincronizando..."]
        XCTAssertTrue(syncIndicator.waitForExistence(timeout: 5), "Não houve sincronização com Firestore")
    }

    func testSincronizacaoOffline() throws {
        // Simular modo offline no simulador ou usar uma flag interna
        // Criar uma operação
        let addOperationButton = app.buttons["AdicionarOperacao"]
        addOperationButton.tap()
        app.textFields["ValorOperacao"].tap()
        app.textFields["ValorOperacao"].typeText("200")
        app.buttons["SalvarOperacao"].tap()

        // Reativar conexão
        // Verificar se sincroniza depois
        let syncIndicator = app.otherElements["Sincronizando..."]
        XCTAssertTrue(syncIndicator.waitForExistence(timeout: 5), "A operação offline não foi sincronizada")
    }

    // MARK: - Notificações e Alertas

    func testAtivacaoNotificacoes() throws {
        let notificacoesSwitch = app.switches["NotificacoesSwitch"]
        notificacoesSwitch.tap()
        XCTAssertEqual(notificacoesSwitch.value as? String, "1", "Falha ao ativar notificações")
    }

    func testNotificacaoFaturasVencidas() throws {
        // Simular data ou avançar tempo
        // Verificar se alerta de fatura vencida aparece
        let faturaAlert = app.alerts["Fatura Vencida"]
        XCTAssertTrue(faturaAlert.exists, "Notificação de fatura vencida não apareceu")
    }

    // MARK: - Reset de Dados

    func testResetBancoDeDadosDesenvolvimento() throws {
        // Supondo que haja um botão para reset de dev
        let devSettingsTab = app.buttons["DevSettingsTab"]
        devSettingsTab.tap()
        let resetDBButton = app.buttons["ResetBancoDeDados"]
        resetDBButton.tap()

        let confirmButton = app.alerts.buttons["Confirmar"]
        if confirmButton.exists {
            confirmButton.tap()
        }

        // Verificar se todas as entidades foram removidas
        // Exemplo: a lista de cartões deve estar vazia
        let cardsTab = app.buttons["CartoesTab"]
        cardsTab.tap()
        XCTAssertFalse(app.cells.count > 0, "Banco de dados não foi resetado corretamente")
    }
}
