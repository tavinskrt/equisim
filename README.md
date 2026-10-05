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
| **R1** | nenhum defeito conhecido | ver o [plano](docs/plano-motor-de-referencia.md): a rodada de 02/10/2026 achou e fechou mais um — companhias com patrimônio positivo recusadas como insolventes (B47); o B38, o rótulo do cenário otimista, aguarda decisão |
| **R2** | incerteza calibrada | **atingida**: a faixa de 80% conteve 79,7% (12 meses) e 78,7% (36 meses) dos casos fora da amostra (remedida em 02/10/2026) |
| **R3** | habilidade testada, com o poder declarado | **atingida nessa definição**: o teste fixado antes não passou (0,010, `t` de 0,05 contra 2,70), e o registro diz que ele não teria poder para passar com a série brasileira disponível; nem o book-to-market sozinho passou |

Dois fatos que qualquer leitor deve ter em mente: o motor é **sistematicamente
mais pessimista que o mercado** (upside mediano de −37%, remedido em 02/10/2026 sobre os dados de 14/09/2026), e **não
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
| **Python 3** | para baixar a curva do Tesouro antes de rodar na web (seção [Pacotes de dados](#pacotes-de-dados)) e para as ferramentas de medição em `tool/` |
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

**Antes de rodar na web, leia a seção seguinte.** No Windows, o aplicativo
baixa sozinho a curva de juros do dia; se a busca falhar, ele recorre ao pacote, com a
mesma regra de idade. Na web — `flutter run -d chrome` ou
`flutter build web` — ele não baixa: usa a curva empacotada no build, que só
vale por **sete dias** ([decisão 86](docs/decisoes/086-na-web-a-curva-vem-so-do-pacote.md)).
Um clone do GitHub traz o pacote do dia em que foi gerado, e passada uma semana
o aplicativo **funciona, mas sem a curva**, com preços que não são os do motor.

No Windows:

```bash
flutter run
```

Na web, depois de regerar a curva (seção seguinte):

```bash
flutter run -d chrome
```

O cache local na web depende de dois arquivos em `web/`
([web/ASSETS.md](web/ASSETS.md)).

---

## Pacotes de dados

O aplicativo não baixa as bases nem varre o mercado inteiro: ele lê **pacotes
versionados em `assets/`**, que as ferramentas de `tool/` geram a partir de
bases públicas (CVM, B3, Tesouro, Banco Central). Um clone traz todos os
pacotes prontos. Quase todos são da mesma data, a **entrada congelada de
14/09/2026**, de propósito: o mesmo código com os mesmos pacotes dá o mesmo
preço justo, e é isso que o gabarito confere. A data de cada pacote está no
campo `geradoEm` do próprio arquivo.

### Os três pacotes que envelhecem

| Pacote | O que o aplicativo faz quando ele envelhece | Quando acontece |
|---|---|---|
| `assets/tesouro/curva.json` — a curva dos títulos prefixados | **com mais de 7 dias, a curva é recusada** e a taxa livre de risco recua para os dois pontos do CDI: o de hoje no ano 1 e a média de dez anos (cerca de 9,4%) na perpetuidade. Medido no gabarito (montagens com e sem a curva, prêmio de 5,5%), isso sobe o preço justo em 16% na mediana | uma semana depois de gerado: **regere antes de rodar ou publicar na web** |
| `assets/mercado/premio_implicito.json` — o prêmio de mercado ([decisão 142](docs/decisoes/142-o-premio-de-mercado-e-a-media-de-dez-anos-do-premio-implicito.md)) | com mais de 183 dias, continua valendo, com uma ressalva da data; sem o pacote, o prêmio volta aos 5,5% e a avaliação diz isso | a partir de 17/03/2027 |
| `assets/cvm/documentos.json` — as demonstrações da CVM | com mais de 100 dias, a avaliação avisa que demonstrações entregues depois não entraram | a partir de 24/12/2026 |

### Antes de rodar ou publicar na web: a curva

Qualquer desenvolvedor faz isto, sem base local: o primeiro comando baixa o
arquivo público de taxas do Tesouro Direto (cerca de 14 MB, sem cadastro), e o
segundo grava o pacote com as dez datas-base mais recentes.

```bash
python tool/tesouro_baixar.py
```

```bash
dart run tool/curva_empacotar.dart
```

Depois, `flutter run -d chrome` ou `flutter build web`.

### Como conferir que a avaliação está íntegra

Abra uma avaliação e o painel de logs:

| Passo do painel | Íntegro | Sem o pacote |
|---|---|---|
| Estrutura a termo da taxa de desconto | "a taxa livre de risco de cada ano é o forward de um ano da curva dos prefixados de DD/MM/AAAA" | "**sem curva de juros**, o custo de capital do ano 1 usa a taxa livre de risco corrente" |
| Custo do capital próprio (CAPM), Passo 0 | "a média de dez anos do prêmio implícito no preço da bolsa" | "5.5%, o prêmio parametrizado: a série do prêmio implícito não chegou a esta avaliação" |

Nos dois casos a avaliação também traz uma ressalva dizendo o que faltou.
**Preço justo calculado sem a curva não é comparável** com os da documentação e
dos casos de estudo.

### Todos os pacotes

| Pacote | O que leva | Gerado por | Precisa de |
|---|---|---|---|
| `tesouro/curva.json` | curva dos prefixados | `tesouro_baixar.py` → `curva_empacotar.dart` | só internet |
| `mercado/premio_implicito.json` | série trimestral do prêmio implícito | `premio_implicito.dart --so-serie` | entrada congelada e bases da B3 e do Tesouro |
| `cvm/documentos.json` | demonstrações anuais e trimestrais | `cvm_baixar.py` → `cvm_ingerir.dart data/cvm` → `cvm_empacotar.dart` | base da CVM (cerca de 7 GB) |
| `cvm/capital.json` | emissões e eventos de ações | `cvm_baixar.py --docs FRE` e `b3_baixar.py` → `capital_empacotar.dart` | FRE e COTAHIST |
| `cvm/outorgas.json` | prazo das concessões | `cvm_baixar.py --docs FRE` → `fre_outorgas.dart` | FRE |
| `cvm/units.json` | composição das units | `cvm_baixar.py --docs FCA` → `unit_empacotar.dart` | FCA |
| `cvm/controle.json` | espécie do controle acionário, para a ressalva de controle estatal | `cvm_baixar.py --docs FCA` → `controle_empacotar.dart` | FCA |
| `b3/emissores.json` | contagem oficial de ações e setor | `b3_companhias_baixar.py` e `b3_complemento_baixar.py` → `b3_empacotar.dart` | internet |
| `b3/proventos.json` | proventos, para o beta de retorno total | `b3_complemento_baixar.py` → `b3_proventos_empacotar.dart` | internet |
| `mercado/beta_prior.json` | prior do beta por setor | `beta_prior_empacotar.dart` | entrada congelada |
| `mercado/multiplos_setoriais.json` | medianas de múltiplos dos pares | `multiplos_empacotar.dart` | entrada congelada |
| `validacao/banda_calibrada.json` | a faixa calibrada | backtest → `cobertura_banda.py` | backtest |
| `validacao/habilidade.json` | a habilidade medida | backtest → `regressao_condicional.dart --trimestral` | backtest |
| `config/distressed_tickers.json` | companhias em recuperação judicial | editado à mão | — |

As bases brutas ficam em `data/`, que **não é versionada** (só a da CVM tem
cerca de 7 GB). Por isso só quem tem as bases regera a maior parte dos pacotes;
os outros desenvolvedores só precisam da curva.

### Depois de mudar o motor

Sem mexer na entrada congelada:

| Passo | Comando |
|---|---|
| 1. Regravar o gabarito | `dart run tool/gabarito_cascata.dart --regravar` |
| 2. Refazer os casos de estudo e as figuras | `dart run tool/casos_de_estudo.dart`, depois `python tool/figuras_estudo.py`, e reler os casos em `docs/estudo/casos/` |
| 3. Se a mudança afeta a validação: o backtest (cerca de 1 hora) | `dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas --trimestral` |
| 4. A faixa calibrada | `python tool/cobertura_banda.py` |
| 5. A habilidade e o poder | `dart run tool/regressao_condicional.dart --trimestral`, depois `dart run tool/poder_r3.dart` |
| 6. Conferir | `flutter test`, `dart test --directory packages/equisim_core` e `npm run qa:gemini` |

### Atualizar o conjunto inteiro (avançar a entrada congelada)

É uma rodada própria, com registro: todos os números da documentação, do
gabarito e dos casos mudam. **Hoje não é só rodar comandos.** A data 14/09/2026
está fixa no código de `tool/validation/congelado.dart`,
`tool/gabarito_cascata.dart`, `tool/beta_prior_empacotar.dart`,
`tool/unit_empacotar.dart`, `tool/controle_empacotar.dart`,
`tool/b3_deslistadas_contagem.dart` e
`tool/backtest_valuation.dart`, e `tool/premio_implicito.dart` mede os
trimestres até 30/06/2026. Avançá-la é mudança de código. Depois disso, a ordem
segue as dependências declaradas no cabeçalho de cada ferramenta:

| Etapa | Comandos |
|---|---|
| 1. Bases brutas, em `data/` | `python tool/cvm_baixar.py`; `python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre`; `python tool/cvm_baixar.py --docs FCA`; `python tool/b3_baixar.py`; `python tool/b3_companhias_baixar.py`; `python tool/b3_complemento_baixar.py`; `python tool/b3_complemento_baixar.py --deslistadas`; `python tool/b3_ponte.py`; `python tool/tesouro_baixar.py` |
| 2. Ingestão e contagens por data | `dart run tool/cvm_ingerir.dart data/cvm`; `dart run tool/b3_deslistadas_contagem.dart` |
| 3. Pacotes de dado | `cvm_empacotar.dart`, `b3_empacotar.dart`, `b3_proventos_empacotar.dart`, `capital_empacotar.dart --agora`, `fre_outorgas.dart`, `unit_empacotar.dart --agora`, `controle_empacotar.dart --agora` e `curva_empacotar.dart` |
| 4. Congelar a entrada nova | `dart run tool/gabarito_cascata.dart`, sem `--regravar`: copia o cache do dia para `data/gabarito/` |
| 5. Pacotes medidos sobre ela | `beta_prior_empacotar.dart`, `multiplos_empacotar.dart` e `premio_implicito.dart --so-serie` — que recusa regravar trimestre já gravado que tenha mudado; confira a causa antes de usar `--aceitar-mudanca-do-passado` (item B48) |
| 6. O gabarito com os pacotes novos | `dart run tool/gabarito_cascata.dart --regravar` |
| 7. Validação, casos e conferência | os passos 2 a 6 de "Depois de mudar o motor" |

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
