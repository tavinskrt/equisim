# Equisim

Ferramenta de apoio à decisão de investimentos em ações da B3, com valuation por
Fluxo de Caixa Descontado (DCF) e CAPM, gestão de dupla carteira (Principal e
Reserva) e planejamento de metas patrimoniais.

Trabalho de Conclusão de Curso — aplicação Flutter/Dart.

---

## ⚠ Estado atual: Fase 0 concluída (reconstrução em andamento)

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

Autenticação, sessão, tema claro/escuro, perfil e uma tela inicial que verifica
a conectividade com a brapi. O motor financeiro está sendo reconstruído a partir
da Fase 1.

---

## Pré-requisitos

- Flutter **3.44+** (Dart 3.12+) — `flutter --version`
- Conta e token da API [brapi.dev](https://brapi.dev)
- Projeto Firebase configurado (Authentication + Cloud Firestore)

## Configuração

**1. Dependências**

```bash
flutter pub get
```

**2. Variáveis de ambiente**

O arquivo `.env` é obrigatório — está declarado como asset e a build falha sem
ele. Copie o modelo e preencha seu token:

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

```bash
flutter analyze
```

```bash
flutter test
```

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
lib/
├── controllers/   gerenciamento de estado (Provider — migra para Riverpod na Fase 3)
├── models/        modelos de dados
├── services/      acesso à API (transitório — vira camada data/ na Fase 2)
├── utils/         design system
└── views/         telas
```

A arquitetura em camadas (`equisim_core` como pacote Dart puro + `data/` +
`presentation/`) entra a partir da Fase 1.
