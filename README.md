# Equisim

Ferramenta de apoio à decisão de investimentos em ações da B3, com valuation por
Fluxo de Caixa Descontado (DCF) e CAPM, gestão de dupla carteira (Principal e
Reserva) e planejamento de metas patrimoniais.

Trabalho de Conclusão de Curso — aplicação Flutter/Dart.

---

## Estado atual: reconstrução concluída (Fases 0 a 5)

A transição de escopo está cumprida. O escopo anterior — simulação comparativa
de **uma ação contra um FII** com valuation binário — foi **descontinuado**, e o
motor correspondente foi removido.

| | |
|---|---|
| **Escopo atual** | Dupla carteira, DCF + CAPM, metas patrimoniais, backtest Principal × Reserva |
| **Fora de escopo** | FIIs, renda fixa, bandas de alocação, benchmarks de índice |
| **Legado congelado em** | tag git `legado-escopo-a` |

Documentos de referência:

- **[`PLANO_ARQUITETURA.md`](PLANO_ARQUITETURA.md)** — parecer de stack com benchmark
  medido, auditoria da API, arquitetura, modelo de domínio e roadmap por fases.
  **Congelado**: cumpriu o que planejava, e guarda as decisões 0 a 18.
- **[`docs/decisoes/`](docs/decisoes/)** — as decisões 19 em diante, uma por arquivo,
  imutáveis depois de aceitas. A
  [decisão 19](docs/decisoes/019-registro-por-arquivo.md) instituiu esse formato
  e aposentou o relatório de análise avulso que vivia na raiz.
- **[`docs/estado.md`](docs/estado.md)** — retrato do repositório: decisões, superfície
  medida e histórico. **Gerado** por `npm run estado`; não se edita à mão.

### O que funciona hoje

- **Autenticação, sessão, tema e perfil** — preservados do projeto anterior.
- **`packages/equisim_core`** — motor financeiro completo em Dart puro: DCF por
  FCFF descontado ao WACC, CAPM, cenários discretos e Monte Carlo, backtest sem
  rebalanceamento, TWR/XIRR, métricas de risco, meta patrimonial e concentração
  setorial. 207 testes, 83,9% de cobertura de linhas, zero rede.
- **`lib/data`** — camada de acesso a dados com Dio, cache Drift, proventos
  higienizados e portão de qualidade. Testes rodando offline sobre fixtures
  reais.
- **`lib/di` e `lib/presentation`** — grafo de dependências em Riverpod,
  estado da dupla carteira com edição síncrona, avaliação orquestrada e
  persistência dos estudos no Firestore.
- **Interface completa** em quatro frentes, uma por aba: dupla carteira com
  arrastar-e-soltar (*Estudo*), preço justo com cenários e sensibilidade
  (*Valuation*), planejamento patrimonial com semáforo de viabilidade (*Meta*),
  e comparação histórica com gráficos e exportação em CSV (*Simulação*).

- **`tool/validate.dart`** — executor de validação que reusa exatamente a mesma
  camada de dados e o mesmo motor do aplicativo, gerando os relatórios de
  evidência em [`docs/validacao/`](docs/validacao/).

Ao todo: **458 testes automatizados** — 251 do aplicativo e 207 do núcleo —,
todos offline, com 83,9% de cobertura de linhas no núcleo de domínio.

### Evidências de corretude

| Verificação | Resultado |
|---|---|
| [Invariantes do motor](docs/validacao/invariantes.md) | 15 aprovadas |
| [Conferência cruzada em Python](docs/validacao/conferencia_python.md) | 80/80 dentro de 1e-4 |
| [Qualidade dos proventos](docs/validacao/qualidade_proventos.md) | 11/11 consistentes |
| [Sensibilidade às premissas](docs/validacao/sensibilidade.md) | três eixos medidos |
| [Limitações](docs/validacao/limitacoes.md) | 20 catalogadas |

Para regerar:

```bash
dart run tool/validate.dart tudo
```

E a conferência independente em Python:

```bash
python docs/validacao/cross_validation.py
```

### Cadeia de QA por agente

Além das suítes, o repositório roda uma cadeia de revisão por modelo de
linguagem, registrada na
[decisão 20](docs/decisoes/020-cadeia-de-qa-por-agente.md). A regra que sustenta
o arranjo: **quem propõe não bloqueia; quem bloqueia não propõe.** Ampliar o
auditor para "proponha melhorias" destruiria a calibragem que o torna confiável.

| Camada | Comando | Papel | Bloqueia? |
|---|---|---|---|
| Portão local | `.githooks/pre-commit` | regras determinísticas, sem rede, em ~250–500 ms | sim, todo commit |
| **Auditor** | `npm run qa:gemini` | caça defeito de correção ancorado em arquivo e linha | sim, todo push |
| **Conselheiro** | `npm run conselho -- --lente <id>` | examina relação entre coisas em sete lentes — registro, núcleo, dados, método, risco, rumo, tela | não, nunca |

Os dois hooks não vêm ligados num clone novo; o git precisa ser apontado para
eles, uma vez:

```bash
git config core.hooksPath .githooks
```

O auditor libera o push quando a auditoria **não pôde ser executada** — sem rede
ou sem cota não é defeito do código, e um gate que trava nessas horas seria
arrancado na primeira ocorrência. O payload liberado vai para a fila, e
`npm run qa:pending` audita exatamente aquele instantâneo quando a cota volta.

O conselheiro nunca bloqueia: sai com código 0 mesmo em falha de rede, de cota
ou de JSON inválido, e nenhum hook o chama.

### Barramento de auditoria em tempo de execução

[`lib/audit/`](lib/audit/) liga o coletor do núcleo, o interceptador de rede e um
canal entre janelas a um painel de inspeção, aberto em `/#/logs`. É o que permite
mostrar, durante a defesa, que um número da tela veio de uma requisição
identificada e de um caminho de cálculo registrado — e não de um atalho.
Desligado fora do modo de depuração, com sobrescrita por
`--dart-define=EQUISIM_AUDIT=true`.

---

## Instalação numa máquina nova

Um clone recém-baixado **não compila direto**, e por um motivo simples: os
arquivos que guardam credencial não são versionados, e um deles — o `.env` — está
declarado como asset no `pubspec.yaml`. Sem ele a compilação para logo no início,
com `No file or variants found for asset: .env`.

O script de preparação resolve isso e o resto de uma vez só.

### Pré-requisitos

| | |
|---|---|
| **Flutter** | 3.44 ou mais recente (Dart 3.12+). O piso está declarado em `pubspec.yaml`, então um SDK antigo é recusado pelo próprio `pub get`. |
| **Windows** | **Modo de Desenvolvedor ligado** — `start ms-settings:developers`. O `pub get` cria links simbólicos para os plugins nativos; sem esse privilégio ele falha com *"Building with plugins requires symlink support"*. |
| **Alvo de execução** | Chrome (para o alvo web) **ou** Visual Studio com "Desenvolvimento para desktop com C++" (para o alvo Windows) **ou** Android SDK. Confira com `flutter doctor`. |
| **Node 20** | Só para quem for publicar a função de proxy. |
| **Credencial** | Token da API [brapi.dev](https://brapi.dev/dashboard) — gratuito. |

### Um comando

No Windows:

```bash
.\tool\setup.bat
```

No macOS ou Linux:

```bash
./tool/setup.sh
```

O script verifica o Flutter, confirma o suporte a links simbólicos, cria `.env` e
`config/local.json` a partir dos arquivos de exemplo e baixa as dependências do
aplicativo e do núcleo. É idempotente: rodar de novo não sobrescreve arquivo
nenhum que já exista.

| Opção | Efeito |
|---|---|
| `-Verificar` / `--verificar` | Roda análise estática e as duas suítes de teste ao final |
| `-ComFunctions` / `--com-functions` | Instala também as dependências Node de `functions/` |
| `-PularChecagens` | Ignora a verificação de links simbólicos (Windows) |

### Versões travadas

`pubspec.lock` **é versionado** — este repositório é uma aplicação, não uma
biblioteca. É o que garante que a outra máquina resolva exatamente as mesmas
versões de dependência, e não a resolução mais recente que o `pub` encontrar no
dia. Para atualizar de propósito: `flutter pub upgrade` e commite o lock novo.

---

## Configuração

O script acima já deixa o projeto compilável, mas **sem credencial**: o
aplicativo sobe e as telas que consultam a brapi ficam sem dados. Escolha uma
das três formas abaixo — o `ApiConfig` resolve nesta ordem de preferência e
avisa no console quando cai na última.

| Modo | Onde vive o token | Proteção |
|---|---|---|
| Cloud Function *(recomendado)* | só no servidor | **efetiva** |
| `--dart-define-from-file` | constante no binário | parcial — extraível com `strings` |
| `.env` como asset *(legado)* | dentro do bundle | nenhuma — público no alvo web |

**Modo `.env`** — o mais rápido para desenvolvimento e demonstração. Preencha o
token no `.env` que o script criou:

```
BRAPI_TOKEN=seu_token_aqui
```

E execute sem argumento nenhum: `flutter run`.

**Modo definição de compilação** — preencha `BRAPI_TOKEN` em `config/local.json`
(também criado pelo script) e execute passando o arquivo:

```bash
flutter run --dart-define-from-file=config/local.json
```

**Modo proxy** — preencha `BRAPI_PROXY_URL` em `config/local.json` com a URL da
Cloud Function e deixe o token vazio. Ver a seção *Proxy de custódia* adiante.

**Firebase** — as credenciais em `lib/firebase_options.dart` e
`android/app/google-services.json` já apontam para o projeto do TCC e são
versionadas; nada a fazer na máquina nova. Para usar outro projeto, regenere com
`flutterfire configure`.

## Execução

```bash
flutter run
```

## Testes e análise estática

Os testes do aplicativo rodam **offline**, sobre respostas reais capturadas em
`test/fixtures/`:

```bash
flutter test
```

O núcleo de domínio tem sua própria suíte, sem Flutter e sem rede:

```bash
dart test --directory packages/equisim_core
```

```bash
flutter analyze
```

## Geração de código

O schema do cache usa Drift, que depende de geração. Após alterar
`lib/data/datasources/local/cache_database.dart`:

```bash
dart run build_runner build
```

## Proxy de custódia da credencial (opcional)

Publica uma função que injeta o token no servidor, de modo que o aplicativo não
carregue credencial alguma — e que resolve o CORS no alvo web.

```bash
firebase functions:secrets:set BRAPI_TOKEN
```

```bash
firebase deploy --only functions
```

Depois, preencha `BRAPI_PROXY_URL` em `config/local.json` com a URL retornada.

---

## Fontes de dados

| Dado | Fonte | Observação |
|---|---|---|
| Cotações diárias | brapi `/v2/stocks/historical` | `close` já ajustado por split, **não** por proventos |
| Proventos | brapi `/v2/stocks/dividends` | campo `label` distingue JCP (IRRF 15%) de dividendo |
| Fundamentos históricos | brapi `statistics`, `income-statement`, `balance-sheet`, `cash-flow` (`mode=history`) | granularidade **anual**, 2010–2025 |
| Setor / indústria | brapi `/v2/stocks/profile` | taxonomia própria da brapi, não GICS nem B3 |
| Taxa livre de risco | Banco Central, série SGS 12 (CDI) | API aberta, sem chave |
| Índice de mercado | brapi `^BVSP` | para Rm e cálculo local de beta |

Limitações conhecidas dos dados estão catalogadas em
[`PLANO_ARQUITETURA.md`](PLANO_ARQUITETURA.md) §0.4 e §2.3.

## Estrutura

```
packages/equisim_core/     domínio puro — sem Flutter, sem rede, sem I/O
├── entities/              ativo, carteira, valuation, meta, fundamentos
├── value_objects/         ticker, dinheiro em centavos, peso, intervalo
├── services/              valuation, backtest, métricas, meta, carteira
├── repositories/          contratos (interfaces)
└── tax/ · time/ · failures/

lib/data/                  acesso a dados
├── config/                resolução de credencial (proxy · define · .env)
├── network/               Dio + interceptors
├── datasources/remote/    brapi · Banco Central
├── datasources/local/     cache Drift + políticas de validade
├── dtos/                  espelham o JSON; não vazam para o domínio
├── quality/               portão de qualidade dos proventos
└── repositories/          implementações dos contratos

lib/di/                    raiz de composição (Riverpod)
lib/presentation/          estado e telas por funcionalidade
├── shell/                 navegação principal
├── study/                 dupla carteira, arrastar-e-soltar, persistência
├── goals/                 plano patrimonial e semáforo de viabilidade
├── valuation/             preço justo, cenários e sensibilidade
├── backtest/              comparação histórica e métricas
├── export/                exportação em CSV
├── audit/                 painel de logs em janela paralela
├── theme/                 tokens de cor, tipografia e espaçamento
├── components/            número financeiro e cartão de saldo
└── shared/                formatadores, cartões, gráficos e ponte de tema

lib/audit/                 barramento de auditoria em tempo de execução
lib/                       legado preservado
├── controllers/           autenticação e tema em Provider
└── views/                 telas de login, cadastro e perfil

scripts/                   cadeia de QA — auditor, conselheiro e lentes
.githooks/                 pre-commit determinístico · pre-push com o auditor
docs/decisoes/             registro de decisões, uma por arquivo
docs/validacao/            evidências de corretude e o conferidor em Python
functions/                 proxy de custódia da credencial
test/fixtures/             respostas reais versionadas
```

A regra de dependência é `presentation → domain ← data`, e o domínio não conhece
ninguém. Isso não é convenção: `packages/equisim_core/test/purity_test.dart`
falha o build se `package:flutter`, `package:http`, `dart:js`, Firebase ou Drift
forem importados no núcleo.
