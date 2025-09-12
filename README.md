# WALL-ET Bitcoin Wallet

App nativo e moderno para iOS, escrito em Swift 6, para gerenciamento de carteiras Bitcoin. Utiliza a arquitetura MVVM-C e os princípios da Clean Architecture para garantir escalabilidade, testabilidade e uma clara separação de responsabilidades.

* * *

## Estrutura de Diretórios Detalhada

A estrutura de diretórios proposta é excelente e segue as melhores práticas da Clean Architecture. Aqui está um detalhamento do que cada diretório irá conter:

    WALL-ET/
    ├── App/                             # Ponto de entrada, ciclo de vida e configurações globais
    │   ├── AppMain.swift                # A struct principal com @main que define a WindowGroup
    │   ├── AppDelegate.swift            # Para integrações com serviços de terceiros (ex: Push Notifications)
    │   ├── Configuration/               # Arquivos .xcconfig para Debug/Release/Staging
    │   └── Privacy/                     # PrivacyInfo.xcprivacy
    │
    ├── Core/                            # Utilitários de baixo nível, agnósticos à aplicação
    │   ├── Concurrency/                 # Helpers para async/await, @MainActor, etc.
    │   ├── Constants/                   # Chaves de UserDefaults, margens de UI, URLs fixas
    │   ├── DI/                          # Contêiner de Injeção de Dependência (Swinject ou manual)
    │   ├── Extensions/                  # Extensões para tipos nativos (Date, String, etc.)
    │   └── Observability/               # Logging estruturado, métricas de performance (Firebase, etc.)
    │
    ├── Data/                            # Implementações concretas de protocolos do Domínio
    │   ├── DTOs/                        # Data Transfer Objects (respostas de API)
    │   ├── Mappers/                     # Conversores de DTO para Modelos de Domínio e vice-versa
    │   ├── Repositories/                # Implementações dos repositórios (ex: WalletRepositoryImpl)
    │   └── Services/                    # Serviços de infraestrutura (APIService, KeychainService, DatabaseService)
    │
    ├── DesignSystem/                    # Camada de design compartilhada e reutilizável
    │   ├── Colors/                      # Paleta de cores para light/dark mode
    │   ├── Components/                  # Componentes genéricos (PrimaryButton, AddressTextView, BalanceHeaderView)
    │   ├── Typography/                  # Estilos e fontes da aplicação (Font Tokens)
    │   └── Assets.xcassets              # Ícones, logos, imagens
    │
    ├── Domain/                          # Regras de negócio puras (independente de UI e Data)
    │   ├── Models/                      # Entidades centrais (Account, Wallet, Transaction, Blockchain)
    │   ├── Protocols/                   # Contratos/interfaces (ex: IWalletRepository, ISendHandler)
    │   └── UseCases/                    # Orquestração do domínio (ex: CreateWalletUseCase, SendBitcoinUseCase)
    │
    ├── Presentation/                    # Camada MVVM-C que conecta Domínio <-> UI
    │   ├── Coordinators/                # Controladores de fluxo de navegação (AppCoordinator, SendCoordinator)
    │   ├── ViewModels/                  # Estado e lógica das telas (BalanceViewModel, SendViewModel)
    │   └── Views/                       # Interface em SwiftUI
    │       ├── Screens/                 # Telas completas (BalanceView, SendView, SettingsView)
    │       └── Components/              # Componentes de UI específicos de uma feature
    │
    ├── Resources/                       # Recursos estáticos (arquivos de localização .strings)
    └── Tooling/                         # Scripts de build, CI/CD, linters
    

* * *

## Destaques Técnicos

*   **Clean Architecture**: Garante que a lógica de negócios seja independente de frameworks, tornando a aplicação mais robusta e fácil de testar.
    
*   **MVVM-C**: Separa a lógica de apresentação (ViewModel) da navegação (Coordinator), mantendo as Views (SwiftUI) limpas e declarativas.
    
*   **Protocol-Oriented Programming**: Uso intensivo de protocolos para inversão de dependência, facilitando a substituição de implementações e a criação de mocks para testes.
    
*   **Swift Concurrency**: Utilização de `async/await` para um código assíncrono mais limpo e seguro.
    
*   **Injeção de Dependência**: Elimina o uso de singletons, tornando as dependências explícitas e o código mais modular.
    

* * *

## Funcionalidades e Telas Principais

### Core Features

*   **Gerenciamento Multi-Conta**: Suporte para múltiplas contas (carteiras), permitindo ao usuário alternar entre elas.
    
*   **Criação e Restauração**:
    
    *   **Criação**: Geração de novas carteiras com seed phrase (mnemônico) de 12 ou 24 palavras.
        
    *   **Restauração**: Importação de carteiras existentes via Mnemonic (BIP39 e não-padrão), Chave Privada, ou Endereço Público (modo "Watch-Only").
        
*   **Segurança Avançada**:
    
    *   Proteção por senha e biometria (Face ID/Touch ID).
        
    *   **Modo Coação (Duress Mode)**: Uma senha secundária que, quando inserida, abre um conjunto diferente de carteiras, protegendo o usuário em situações de risco.
        
*   **Gerenciamento de Taxas (Bitcoin)**: Estimativa de taxas de transação e opções avançadas como Replace-by-Fee (RBF).
    

### 1\. Tela de Saldo (Balance)

A tela principal do aplicativo, onde o usuário visualiza seus ativos.

*   **Saldo Total**: Exibido na moeda fiduciária base selecionada pelo usuário, com a opção de ocultar valores.
    
*   **Lista de Carteiras**: Uma lista de todas as carteiras ativas, cada uma exibindo:
    
    *   Ícone e nome da criptomoeda (ex: Bitcoin).
        
    *   Saldo em criptomoeda e seu equivalente fiduciário.
        
    *   Variação de preço nas últimas 24h.
        
    *   Status de sincronização.
        
*   **Ações Rápidas**: Botões principais para **Enviar**, **Receber** e **Escanear QR Code**.
    
*   **Gerenciamento e Ordenação**:
    
    *   Botão para acessar a tela "Gerenciar Carteiras" (adicionar/remover moedas).
        
    *   Opções para ordenar a lista por saldo, nome ou variação de preço.
        
*   **Pull-to-Refresh**: Atualiza todos os saldos e preços.
    

### 2\. Tela de Transações

Um histórico completo de todas as transações, com opções avançadas de filtragem.

*   **Lista de Transações**: Agrupada por data ("Hoje", "Ontem", etc.). Cada item exibe:
    
    *   Tipo de transação (ícone de envio, recebimento, etc.).
        
    *   Destinatário/remetente.
        
    *   Valor principal (em cripto) e valor secundário (em fiat).
        
    *   Status (Pendente, Confirmada, Falhou).
        
*   **Filtros Avançados**: Um painel de filtros para refinar a lista por:
    
    *   **Blockchain**: Exibir transações de apenas uma rede (ex: Bitcoin).
        
    *   **Token**: Filtrar por uma criptomoeda específica.
        
    *   **Contato**: Mostrar transações de ou para um contato salvo.
        
    *   **Tipo**: Filtrar por Enviadas, Recebidas, Swap, Aprovações.
        
    *   **Ocultar Transações Suspeitas**: Filtro para remover possíveis transações de spam.
        
*   **Tela de Detalhes da Transação**:
    
    *   Informações completas: status, data, valor, taxa de rede, remetente, destinatário.
        
    *   Link para visualizar a transação em um explorador de blocos.
        
    *   Opções de **Acelerar (Speed Up)** ou **Cancelar (Cancel)** para transações Bitcoin com RBF habilitado.
        

### 3\. Tela de Configurações

Central de personalização e segurança do aplicativo.

*   **Gerenciar Carteiras**: Adicionar novas carteiras, criar, restaurar ou visualizar as *seed phrases* das existentes.
    
*   **Segurança**:
    
    *   **Senha**: Ativar/desativar, alterar senha.
        
    *   **Biometria**: Ativar Face ID/Touch ID.
        
    *   **Auto-Lock**: Definir tempo para bloqueio automático do app.
        
    *   **Modo Coação**: Configurar uma senha alternativa e selecionar as carteiras a serem exibidas.
        
*   **Aparência**:
    
    *   **Tema**: Claro, Escuro ou Automático (Sistema).
        
    *   **Moeda Base**: Selecionar a moeda fiduciária principal (USD, BRL, EUR, etc.).
        
    *   **Ícone do App**: Permitir que o usuário escolha entre diferentes ícones.
        
*   **Backup do App**: Funcionalidade para criar um backup criptografado de todas as carteiras, configurações e contatos, salvando em um arquivo local ou na nuvem (iCloud).
    
*   **Conexões dApp (WalletConnect)**: Visualizar e gerenciar sessões ativas com aplicações descentralizadas.
    
*   **Sobre**: Informações da versão do app, links para redes sociais, site oficial e termos de serviço.