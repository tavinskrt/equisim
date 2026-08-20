# Equisim

Ferramenta de apoio à decisão de investimentos em ações da B3, com valuation por
Fluxo de Caixa Descontado (DCF) e CAPM, gestão de dupla carteira (Principal e
Reserva) e planejamento de metas patrimoniais.

Trabalho de Conclusão de Curso — aplicação Flutter/Dart.

---

## ⚠ Estado atual: Fases 0, 1 e 2 concluídas (reconstrução em andamento)

O projeto está em transição. O escopo anterior — simulação comparativa de
**uma ação contra um FII** com valuation binário — foi **descontinuado**, e o
motor correspondente foi removido.

| | |
|---|---|
| **Escopo atual** | Dupla carteira, DCF + CAPM, metas patrimoniais, backtest Principal × Reserva |
| **Fora de escopo** | FIIs, renda fixa, bandas de alocação, benchmarks de índice |
| **Legado congelado em** | tag git `legado-escopo-a` |

Documentos de referência:

- **[`PLANO_ARQUITETURA.md`](PLANO_ARQUITETURA.md)** — parecer de stack com benchmark
  medido, auditoria da API, arquitetura, modelo de domínio e roadmap por fases.
- **[`RELATORIO_ANALISE.md`](RELATORIO_ANALISE.md)** — auditoria de defeitos do código legado.

### O que funciona hoje

- **Autenticação, sessão, tema e perfil** — preservados do projeto anterior.
- **`packages/equisim_core`** — motor financeiro completo em Dart puro: DCF por
  FCFF descontado ao WACC, CAPM, cenários discretos e Monte Carlo, backtest sem
  rebalanceamento, TWR/XIRR, métricas de risco, meta patrimonial e concentração
  setorial. 125 testes, 85% de cobertura, zero rede.
- **`lib/data`** — camada de acesso a dados com Dio, cache Drift, proventos
  higienizados e portão de qualidade. 42 testes rodando offline sobre fixtures
  reais.

Falta ligar as duas pontas na interface — Fases 3 e 4.

---

## Pré-requisitos

- Flutter **3.44+** (Dart 3.12+) — `flutter --version`
- Conta e token da API [brapi.dev](https://brapi.dev)
- Projeto Firebase configurado (Authentication + Cloud Firestore)
- Node 20, apenas se for publicar a função de proxy

## Configuração

**1. Dependências**

```bash
flutter pub get
```

**2. Credencial da brapi**

Escolha um dos modos abaixo. Os três são suportados; o `ApiConfig` resolve
nesta ordem de preferência e avisa no console quando cai no último.

| Modo | Onde vive o token | Proteção |
|---|---|---|
| Cloud Function *(recomendado)* | só no servidor | **efetiva** |
| `--dart-define-from-file` | constante no binário | parcial — extraível com `strings` |
| `.env` como asset *(legado)* | dentro do bundle | nenhuma — público no alvo web |

Para o modo por definição de compilação:

```bash
cp config/local.example.json config/local.json
```

E então execute passando o arquivo:

```bash
flutter run --dart-define-from-file=config/local.json
```

Para o modo legado, que continua funcionando sem argumentos extras:

```bash
cp .env.example .env
```

**3. Firebase**

As credenciais em `lib/firebase_options.dart` já apontam para o projeto do TCC.
Para usar outro projeto, regenere com `flutterfire configure`.

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

lib/                       aplicativo
├── controllers/           Provider — migra para Riverpod na Fase 3
├── utils/ · views/        design system e telas

functions/                 proxy de custódia da credencial
test/fixtures/             respostas reais versionadas
```

A regra de dependência é `presentation → domain ← data`, e o domínio não conhece
ninguém. Isso não é convenção: `packages/equisim_core/test/purity_test.dart`
falha o build se `package:flutter`, `package:http`, `dart:js`, Firebase ou Drift
forem importados no núcleo.
