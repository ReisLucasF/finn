<div align="center">

# Finn

**Gestão financeira pessoal: offline, local e com regras financeiras de verdade.**

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)
![Plataformas](https://img.shields.io/badge/plataformas-Windows%20%7C%20Android%20%7C%20iOS-0F5C45)
![Banco](https://img.shields.io/badge/dados-SQLite%20local-3D8F72)

</div>

---

O Finn organiza contas, cartões, investimentos, metas e orçamentos em um só lugar. Os dados ficam em um banco SQLite no próprio dispositivo: não há conta, servidor nem nuvem obrigatória.

A ideia central é que **um app financeiro não é um CRUD**. Uma transferência não é receita nem despesa, uma aplicação não é gasto e o pagamento da fatura não é uma compra nova. Essas regras vivem no domínio e valem para todo o app, inclusive para os indicadores.

## Sumário

- [Funcionalidades](#funcionalidades)
- [Instalação](#instalação)
- [Desenvolvimento](#desenvolvimento)
- [Arquitetura](#arquitetura)
- [Dados e privacidade](#dados-e-privacidade)
- [Publicando uma versão](#publicando-uma-versão)
- [Roadmap](#roadmap)
- [Licença](#licença)

## Funcionalidades

### Visão geral
- **Dashboard** com patrimônio líquido, receitas, despesas, economia e taxa de aporte, com comparação ao mês anterior e filtros de período (mês atual, mês passado, 3 meses, 6 meses, ano ou personalizado).
- **Saúde financeira**: nota de 0 a 100 composta por economia, reserva, aportes e endividamento do cartão.
- **Insights automáticos**, como período no vermelho, despesas em alta e concentração de gastos em uma categoria.
- **Gráficos interativos** de patrimônio, fluxo de caixa, tendência de economia, despesas e receitas por categoria e evolução dos investimentos.
- **Modo privacidade**: um toque esconde todos os valores da tela.

### Dia a dia
- **Contas** bancárias, carteira, poupança e dinheiro em espécie, com saldo calculado pelos lançamentos.
- **Lançamentos**: receitas, despesas e transferências, com status (confirmado ou pendente) e categorias com ícone e cor.
- **Extrato** com busca, filtros e saldo de fechamento do dia.
- **Cartões de crédito** com limite, fechamento, vencimento, compras e pagamento de fatura.
- **Importação OFX** com detecção de duplicidades, sugestão de categoria e detecção de transferências entre contas.

### Planejamento
- **Orçamentos por categoria**: limite mensal, alerta aos 80% ou quando o ritmo projeta estourar, saldo disponível por dia e sugestão de limite pela média dos últimos 3 meses.
- **Metas** com progresso e projeção de prazo, tanto no ritmo real de economia quanto no aporte planejado.
- **Reserva de emergência**: meses de autonomia calculados a partir das despesas essenciais.
- **Recorrências e provisões**, com os próximos vencimentos e as contas atrasadas na dashboard.
- **Investimentos**: aportes, resgates e rendimentos, separando o capital investido do valor atual.
- **Renda fixa indexada**: % do CDI, CDI + taxa ou prefixado, com rendimento por dia útil (CDI diário do Banco Central e feriados nacionais), IR e IOF regressivos por aporte e valor líquido estimado refletido no patrimônio.

### Sistema
- **Backup e restauração** em um único arquivo `.zip`.
- **Atualização automática** no Windows pelas releases do GitHub.
- **Tema claro, escuro ou do sistema**, layout responsivo (barra lateral no desktop, abas no celular) e animações que respeitam a opção de reduzir movimento.

## Instalação

### Windows
Baixe o instalador `Finn-Setup-x.y.z.exe` na página de [Releases](https://github.com/ReisLucasF/finan/releases) e execute. O app avisa quando sai uma versão nova, em **Mais → Verificar atualização**.

> O repositório é privado, então a verificação de atualização precisa de um token do GitHub com permissão de leitura nas releases. Veja [Atualização automática](#atualização-automática).

### Android e iOS
Ainda não há distribuição nas lojas. Gere o build a partir do código (veja abaixo).

## Desenvolvimento

### Requisitos
- Flutter **3.47** ou mais recente (Dart **3.13**)
- Windows: Visual Studio com a carga de trabalho "Desenvolvimento para desktop com C++"
- Android: Android SDK; iOS: Xcode

### Rodando

```bash
flutter pub get
flutter run -d windows        # ou: -d android, -d ios
```

### Qualidade

```bash
flutter analyze               # lint (flutter_lints)
flutter test                  # testes de unidade e integração
```

Os testes de integração usam um SQLite real em arquivo temporário, via `sqflite_common_ffi`, criado por `test/support/test_graph.dart`. Eles cobrem fluxos completos: lançamentos, OFX, planejamento, orçamentos e recategorização.

## Arquitetura

O código segue camadas desacopladas. A interface conhece a aplicação, a aplicação conhece o domínio e a infraestrutura implementa as interfaces do domínio.

```text
Presentation   Flutter: telas, widgets, formatação
     │
Application    Casos de uso (CreateTransaction, GetDashboardSummary, SaveBudget…)
     │
Domain         Entidades, regras e serviços puros (sem Flutter e sem SQL)
     │
Infrastructure SQLite, OFX, backup, atualização, gateways externos
```

```text
lib/
├── app/             # bootstrap, injeção de dependências (AppGraph), sessão, rotas
├── core/            # Money, LocalDate, período financeiro, tema, erros
├── domain/          # entidades, enums, interfaces de repositório, serviços de regra
├── application/     # casos de uso, agrupados por assunto
├── infrastructure/  # SQLite (migrações e repositórios), OFX, backup, update
└── presentation/    # telas por funcionalidade e componentes em shared/
```

### Convenções
- **Dinheiro em centavos.** `Money` guarda um `int`; `double` só aparece para exibição.
- **Datas sem fuso.** `LocalDate` representa dias do calendário, e o mês financeiro pode começar em qualquer dia (`FinancialPeriod`).
- **Regras no domínio.** Cálculos como saldo, patrimônio, projeção de metas, saúde financeira e orçamento ficam em `domain/services` e são testados sem banco.
- **Injeção de dependências** feita à mão em `lib/app/dependency_injection.dart` (`AppGraph`), acessível na interface por `AppScope.of(context)`.
- **Componentes visuais compartilhados** em `presentation/shared/`: `FinanPage`, `FinanCard`, `SectionHeader` e as animações de `motion.dart`.

### Nome interno
O app se chama **Finn**, mas os identificadores internos continuam `finan` _(nome antigo desta aplicação)_ (pacote Dart, `finan.exe`, `finan.db`, pasta de instalação `Finan`, AppId do instalador e repositório). Trocar esses nomes faria o app abrir sem os dados ou instalar um segundo app em vez de atualizar.

### Migrações de banco
O esquema é versionado em `lib/infrastructure/database/sqlite/migrations/`. Para alterar o banco:

1. Crie `migration_0NN_<nome>.dart` com um método `up`.
2. Registre a migração em `apply_migrations.dart`.
3. Incremente `databaseVersion` em `lib/app/app_config.dart`.
4. Se a tabela guarda dados do usuário, inclua-a em `backupTables` (`sqlite_backup_store.dart`).

Migrações rodam uma única vez e nunca devem ser editadas depois de publicadas.

## Dados e privacidade

- Tudo fica em um arquivo `finan.db` local, no diretório de dados do app de cada plataforma.
- O backup (**Mais → Backup**) exporta todas as tabelas para um `.zip` e a restauração substitui os dados atuais.
- Nenhum dado financeiro sai do dispositivo. O app usa a internet só para verificar e baixar atualizações, consultar o CDI na API pública do Banco Central (séries SGS 12, 4389 e 4391, guardadas em cache para uso offline) e, na primeira execução, baixar as fontes (Sora e Source Sans 3, via `google_fonts`).


### Atualizações
O `UpdateService` consulta a última release de `ReisLucasF/finn`. Basta acessar na sidebar "mais" no App instalado e buscar por atualizações.


## Licença

Este projeto está licenciado sob a licença MIT. Consulte o arquivo [`LICENSE`](LICENSE) para mais detalhes.
