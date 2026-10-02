# Equisim

O Equisim é um aplicativo de **estudo de carteira de ações brasileiras**. Ele
avalia cada ação por fluxo de caixa descontado (o "preço justo"), diz o quanto
essa avaliação é incerta, calcula a rentabilidade que uma meta patrimonial
exige e simula como a carteira teria se saído no passado com aportes mensais.

É um trabalho acadêmico, cujo resultado é um artigo. O motor de avaliação foi construído
para que **cada número possa ser seguido até a regra que o produziu e até a
teoria que a justifica**, e foi validado contra o que aconteceu no mercado
brasileiro de 2018 a 2025. O resultado da validação está declarado com
honestidade: a incerteza está calibrada, a habilidade de escolher ações foi
testada e **não** foi comprovada. É uma ferramenta de análise, e não um oráculo
([decisão 140](docs/decisoes/140-o-r3-e-habilidade-testada-com-o-poder-declarado.md)).

---

## Por onde começar a ler

| Você quer… | Leia |
|---|---|
| entender o que o motor faz, sem saber finanças | o [guia de estudo](docs/estudo/README.md) — do zero, com cinco empresas calculadas passo a passo |
| ver cada regra com código, fórmula, teoria e evidência | a [documentação do motor](docs/motor/README.md) |
| saber o que o motor **não** faz ou faz com limitação | as [limitações](docs/validacao/limitacoes.md) |
| entender o painel de logs do aplicativo | [AUDITORIA_DE_CALCULOS.md](docs/AUDITORIA_DE_CALCULOS.md) |
| saber o estado do projeto e o que falta | o [plano do motor de referência](docs/plano-motor-de-referencia.md) e o [estado](docs/estado.md) |
| saber por que cada coisa é como é | o [registro de decisões](docs/decisoes/README.md) |
| trabalhar no código (pessoa ou agente) | o [CLAUDE.md](CLAUDE.md) |

---

## O que o aplicativo faz

Quatro abas e um painel.

| Aba | Para quê |
|---|---|
| **Estudo** | montar a carteira **Principal** (até 15 ações, com pesos) e a **Reserva** (candidatas); ver o potencial de cada ação e o retorno esperado da carteira; salvar e reabrir estudos |
| **Valuation** | a avaliação de uma ação: preço justo, upside, faixa calibrada de 12 e 36 meses, cenários ou Monte Carlo, múltiplos de pares e ressalvas |
| **Meta** | a rentabilidade anual que um plano (aporte inicial, aporte mensal, valor desejado, prazo) exige, comparada ao CDI e ao Ibovespa da década, e à carteira |
| **Simulação** | a história das duas carteiras sob o mesmo plano de aportes, de 1 a 10 anos para trás: patrimônio, TWR, XIRR, volatilidade, drawdown, Sharpe, Sortino, Calmar |
| **Painel de logs** (menu do perfil) | cada passo de cada avaliação, com a fórmula, os números e o resultado |

### Como o preço justo é calculado, em cinco linhas

1. **Quem pode ser avaliado:** liquidez de pelo menos R$ 2 milhões por dia, oito
   anos de balanços e patrimônio positivo.
2. **Por qual caminho:** bancos e empresas de lucro operacional instável pelo
   lucro do acionista; as demais pelo fluxo da empresa, convertido ano a ano em
   fluxo do acionista.
3. **De onde parte e quanto cresce:** o lucro do último ano, ajustado pelo
   retorno típico do ciclo quando o ano destoa; o crescimento que a história da
   própria empresa sustenta.
4. **A que taxa:** o custo do capital próprio (CAPM) sobre a curva de juros do
   Tesouro, ano a ano, com o risco recalculado conforme a dívida projetada. O
   prêmio de risco do mercado é o que o próprio preço da bolsa embute: a média
   de dez anos do prêmio implícito, 1,21% em 14/09/2026 (decisão 142).
5. **Depois de dez anos:** o retorno do capital novo converge ao custo dele, a
   menos que a história mostre uma vantagem competitiva que persiste.

O [capítulo 4 do guia](docs/estudo/04-fluxo-de-caixa-descontado.md) explica cada
passo; o [caso WEGE3](docs/estudo/casos/wege3.md) mostra todas as contas.

### O que foi verificado, e o que ficou em aberto

| | Condição | Situação |
|---|---|---|
| **R1** | nenhum defeito conhecido | ver o [plano](docs/plano-motor-de-referencia.md): a rodada de 01/10/2026 fechou os dois defeitos de dado que a medição do prêmio achou (B43 e B44); o B38, o rótulo do cenário otimista, aguarda decisão |
| **R2** | incerteza calibrada | **atingida**: a faixa de 80% conteve 79,7% (12 meses) e 79,6% (36 meses) dos casos fora da amostra (remedida em 01/10/2026) |
| **R3** | habilidade testada, com o poder declarado | **atingida nessa definição**: o teste fixado antes não passou (0,032, `t` de 0,18 contra 2,70), e o registro diz que ele não teria poder para passar com a série brasileira disponível; nem o book-to-market sozinho passou |

Dois fatos que qualquer leitor deve ter em mente: o motor é **sistematicamente
mais pessimista que o mercado** (upside mediano de −37%, medido em 01/10/2026 sobre os dados de 14/09/2026), e **não
se comprovou** que comprar as ações de maior upside rende mais.

---

## Instalação numa máquina nova

### Pré-requisitos

| | |
|---|---|
| **Flutter** | 3.44 ou mais recente (Dart 3.11.5 ou mais recente); o piso está no `pubspec.yaml` |
| **Windows** | Modo de Desenvolvedor ligado (`start ms-settings:developers`): o `pub get` cria links simbólicos para os plugins |
| **Alvo** | Chrome (web), Visual Studio com C++ (Windows) ou Android SDK; confira com `flutter doctor` |
| **Node** | só para a cadeia de QA (`npm install`) e para o proxy opcional em `functions/` |
| **Python 3** | só para algumas ferramentas de medição em `tool/` |
| **Credencial** | token gratuito da [brapi.dev](https://brapi.dev/dashboard) |

### Preparação

Um clone novo não compila direto: o `.env` não é versionado e está declarado
como asset. O script de preparação cria os arquivos locais a partir dos
exemplos e baixa as dependências. É idempotente.

No Windows:

```bash
.\tool\setup.bat
```

No macOS ou Linux:

```bash
./tool/setup.sh
```

Opções: `-Verificar`/`--verificar` roda análise e testes ao final;
`-ComFunctions`/`--com-functions` instala as dependências de `functions/`.

Depois, uma vez por clone, ligue os hooks de QA:

```bash
git config core.hooksPath .githooks
```

`pubspec.lock` é versionado: a outra máquina resolve as mesmas versões.

### Credencial da brapi

O `ApiConfig` procura o token nesta ordem, e avisa no console quando cai na
última:

| Modo | Onde fica o token | Proteção |
|---|---|---|
| proxy (Cloud Function) | só no servidor | efetiva — exige o plano Blaze do Firebase, que o projeto não usa |
| `--dart-define-from-file=config/local.json` | constante no binário | parcial |
| `.env` (`BRAPI_TOKEN=...`) | dentro do bundle | **nenhuma** — público no build web |

> **Segurança:** o `.env` é asset público no build web. Nunca coloque nele
> segredo de ferramenta. A chave da auditoria (`GEMINI_API_KEY`) mora em
> `.env.qa`, que não é asset nem versionado. O hook de pre-commit barra `.env*`,
> `google-services.json`, `serviceAccount*.json` e material criptográfico.

O Firebase (login e estudos salvos no Firestore) já aponta para o projeto do
trabalho em `lib/firebase_options.dart`.

---

## Execução

```bash
flutter run
```

### Build web

Na web, a curva do Tesouro vem só do pacote do build e vale cerca de uma semana
([decisão 86](docs/decisoes/086-na-web-a-curva-vem-so-do-pacote.md)). Regere
antes de cada build:

```bash
python tool/tesouro_baixar.py
```

```bash
dart run tool/curva_empacotar.dart
```

```bash
flutter build web
```

Com o pacote vencido, a avaliação recua para duas pontas do CDI e diz isso num
aviso. O cache local na web depende de dois arquivos em `web/`
([web/ASSETS.md](web/ASSETS.md)).

---

## Testes e qualidade

```bash
flutter test
```

```bash
dart test --directory packages/equisim_core
```

```bash
flutter analyze
```

Os testes do aplicativo rodam offline, sobre respostas reais em
`test/fixtures/`. A cadeia de QA:

| Camada | Quando | O que faz |
|---|---|---|
| `.githooks/pre-commit` | todo commit | regras locais, sem rede, em menos de um segundo |
| `.githooks/pre-push` e `npm run qa:gemini` | todo push, e antes de concluir tarefa | auditor de defeitos de correção; **FAIL bloqueia** |
| `npm run conselho -- --lente <id>` | depois de mudanças | conselheiro por lentes; nunca bloqueia |
| `dart run tool/gabarito_cascata.dart --conferir` | mudança no motor | confere ao bit a saída de 376 ativos |

Detalhes no [CLAUDE.md](CLAUDE.md) e no
[capítulo 8 da documentação do motor](docs/motor/08-verificacao-e-validacao.md).

O cache usa Drift; depois de mudar `lib/data/datasources/local/cache_database.dart`:

```bash
dart run build_runner build
```

---

## Fontes de dados

| Dado | Fonte |
|---|---|
| Demonstrações anuais | CVM (dados abertos, pacote `assets/cvm/`) e brapi |
| Cotações e índice | brapi |
| Contagem de ações e setor | registro de emissores da B3 (`assets/b3/emissores.json`) |
| Proventos | B3 (`assets/b3/proventos.json`) — no retorno total do beta e da validação; somados na bolsa inteira, na série do prêmio implícito (decisão 142) |
| Eventos de capital, units, concessões | CVM, formulários cadastral e de referência (`assets/cvm/`) |
| Curva de juros | Tesouro Direto (`assets/tesouro/curva.json` na web) |
| CDI, IPCA, IBC-Br | Banco Central, SGS 12, 433 e 24364 |
| Prêmio de mercado, múltiplos de pares, prior do beta, faixa calibrada | pacotes medidos pelo próprio projeto (`assets/mercado/`, `assets/validacao/`) |

Detalhes e regras de cada fonte no
[capítulo 1 da documentação do motor](docs/motor/01-insumos-e-dados.md).

---

## Estrutura

```
packages/equisim_core/   o núcleo: Dart puro, sem dependência, sem rede, sem relógio
  lib/src/usecases/      a cascata de avaliação, a montagem dos insumos
  lib/src/services/      DCF, custo de capital, guardas, curva, cenários, faixa,
                         múltiplos, beta, métricas, meta, simulação
  lib/src/entities/      fundamentos, carteira, resultado da avaliação
  lib/src/audit/         o rastro de cálculo
  test/                  a suíte do núcleo, inclusive o teste de pureza
lib/                     o aplicativo Flutter
  data/                  fontes (brapi, Banco Central, Tesouro), cache, repositórios
  presentation/          as telas (study, valuation, goals, backtest, audit)
  audit/                 o barramento do painel de logs
tool/                    medições, backtest, gabarito, empacotadores, casos de estudo
scripts/                 a cadeia de QA (auditor, conselheiro, gate local, estado)
docs/estudo/             o guia de estudo
docs/motor/              a documentação do motor
docs/decisoes/           o registro de decisões, uma por arquivo
docs/validacao/          as medições e as limitações
assets/                  pacotes de dados versionados
functions/               proxy opcional da credencial
```

A regra de dependência é `presentation → domínio ← data`, e o domínio não
conhece ninguém:
[purity_test.dart](packages/equisim_core/test/purity_test.dart) falha se Flutter,
rede, Firebase, Drift ou `dart:js` entrarem no núcleo.
