# Equisim

O Equisim é um aplicativo web de **estudo de carteira de ações brasileiras**. Ele
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

Quatro áreas, a página de Raio-X de cada ação e um painel. Tudo em
TypeScript, no navegador ([decisão 152](docs/decisoes/152-o-equisim-passa-a-typescript-e-o-dart-sai-do-repositorio.md)).

| Área | Para quê |
|---|---|
| **Estudo** | montar a carteira **Principal** (até 15 ações, com pesos) e a **Reserva** (candidatas), arrastando entre as duas; ver o potencial de cada ação — o do motor, ou o seu, quando você confirmou um valuation que discorda dele — e o retorno esperado da carteira; salvar e reabrir estudos |
| **Raio-X** (página `/ativo/<AÇÃO>`; busca por Ctrl/⌘ + K) | a avaliação de uma ação: preço justo, potencial, régua de preço, faixa calibrada de 12 e 36 meses, sensibilidade ou Monte Carlo, múltiplos de pares e ressalvas, em dois modos — **Essencial**, para quem está começando, e **Completo**; e o botão **Simular minhas premissas**, que abre a conta do motor para você trocar lucro, crescimento, taxa e perpetuidade e ver o preço mudar na hora (decisão 147) |
| **Meta** | a rentabilidade anual que um plano (aporte inicial, aporte mensal, valor desejado, prazo) exige, comparada ao CDI e ao Ibovespa da década, e à carteira |
| **Backtest** | a história das duas carteiras sob o mesmo plano de aportes, de 1 a 10 anos para trás: patrimônio, TWR, XIRR, volatilidade, drawdown, Sharpe, Sortino, Calmar |
| **Meus valuations** | os valuations que você confirmou, gravados com as premissas e o resultado do dia (decisão 150) |
| **Painel de logs** (menu da conta, em janela própria) | cada passo de cada avaliação, com a fórmula, os números e o resultado |

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
| **Node** | 22.13 ou mais recente (LTS). O aplicativo compila a partir do 20.19, o piso do Vite; as ferramentas de `tool/` leem o cache da validação pelo `node:sqlite`, que pede o 22.13 |
| **Python 3** | só para baixar as bases públicas (`tool/*_baixar.py`) e para as conferências em Python de `tool/` |
| **Credencial** | token gratuito da [brapi.dev](https://brapi.dev/dashboard) |
| **Flutter** | só para rodar o motor **pré-registrado** da réplica selada (C7), que é o núcleo Dart do commit selado (decisão 152) |

### Preparação

O script de preparação confere o Node, cria o `.env` a partir do
`.env.example`, instala as dependências travadas no `package-lock.json`
(`npm ci`) e liga os hooks de QA. É idempotente.

No Windows:

```bash
.\tool\setup.bat
```

No macOS ou Linux:

```bash
./tool/setup.sh
```

Opções: `-Verificar`/`--verificar` roda a verificação de tipos e os testes ao
final; `-ComFunctions`/`--com-functions` instala as dependências de
`functions/`.

### Configuração

O `.env` tem dois leitores, que não veem as mesmas variáveis:

| Variável | Quem lê | O que é |
|---|---|---|
| `VITE_BRAPI_PROXY_URL` | aplicativo | o proxy de custódia (`functions/index.js`): o token fica no servidor |
| `VITE_BRAPI_TOKEN` | aplicativo | **só desenvolvimento**: o token direto, embarcado no bundle |
| `VITE_EQUISIM_LOCAL` | aplicativo | `true` força o modo local, sem Firebase: estudos e valuations ficam no IndexedDB do navegador |
| `VITE_EQUISIM_AUDIT` | aplicativo | `true` liga o painel de logs num build de produção (em desenvolvimento ele já vem ligado) |
| `BRAPI_TOKEN` | ferramentas de `tool/` | o token, lido só pelo Node |

> **Segurança:** o Vite **embarca** no JavaScript servido toda variável com
> prefixo `VITE_`. Um `VITE_BRAPI_TOKEN` num build que vai ao ar é público; em
> produção use o proxy. A chave da auditoria (`GEMINI_API_KEY`) mora em
> `.env.qa`, que não é lido pelo Vite nem versionado. O hook de pre-commit barra
> `.env*`, `google-services.json`, `serviceAccount*.json` e material
> criptográfico.

O Firebase (login, estudos e valuations no Firestore) já aponta para o projeto
do trabalho em `src/app/firebase-options.ts`; esses valores são identificadores
públicos do cliente, e quem protege os dados são as regras do
[firestore.rules](firestore.rules).

---

## Execução

```bash
npm run dev            # http://localhost:5173
```

```bash
npm run build          # verificação de tipos e build de produção em dist/
npm run preview        # serve o dist/ em http://localhost:4173
firebase deploy --only hosting
```

**Antes de publicar, regere a curva de juros** (seção seguinte): o navegador
não lê o arquivo do Tesouro, então a avaliação usa a curva empacotada no build,
que só vale por **sete dias** ([decisão 86](docs/decisoes/086-na-web-a-curva-vem-so-do-pacote.md)).
Um clone do GitHub traz o pacote do dia em que foi gerado, e passada uma semana
o aplicativo **funciona, mas sem a curva**, com preços que não são os do motor.

---

## Pacotes de dados

O aplicativo não baixa as bases nem varre o mercado inteiro: ele lê **pacotes
versionados em `public/assets/`**, que as ferramentas de `tool/` geram a partir
de bases públicas (CVM, B3, Tesouro, Banco Central) e que o build copia para
`dist/assets/`. Um clone traz todos os pacotes prontos. Quase todos são da
mesma data, a **entrada congelada de 14/09/2026**, de propósito: o mesmo código
com os mesmos pacotes dá o mesmo preço justo, e é isso que o gabarito confere.
A data de cada pacote está no campo `geradoEm` do próprio arquivo.

As ferramentas rodam por `npm run tool -- <nome>`; `npm run tool`, sem nome,
lista todas, e o [tool/README.md](tool/README.md) tem o mapa de cada uma ao
script Dart que ela substituiu.

### Os três pacotes que envelhecem

| Pacote | O que o aplicativo faz quando ele envelhece | Quando acontece |
|---|---|---|
| `public/assets/tesouro/curva.json` — a curva dos títulos prefixados | **com mais de 7 dias, a curva é recusada** e a taxa livre de risco recua para os dois pontos do CDI: o de hoje no ano 1 e a média de dez anos (cerca de 9,4%) na perpetuidade. Medido no gabarito (montagens com e sem a curva, prêmio de 5,5%), isso sobe o preço justo em 16% na mediana | uma semana depois de gerado: **regere antes de publicar** |
| `public/assets/mercado/premio_implicito.json` — o prêmio de mercado ([decisão 142](docs/decisoes/142-o-premio-de-mercado-e-a-media-de-dez-anos-do-premio-implicito.md)) | com mais de 183 dias, continua valendo, com uma ressalva da data; sem o pacote, o prêmio volta aos 5,5% e a avaliação diz isso | a partir de 17/03/2027 |
| `public/assets/cvm/documentos.json` — as demonstrações da CVM | com mais de 100 dias, a avaliação avisa que demonstrações entregues depois não entraram | a partir de 24/12/2026 |

### Antes de publicar: a curva

Qualquer desenvolvedor faz isto, sem base local: o primeiro comando baixa o
arquivo público de taxas do Tesouro Direto (cerca de 14 MB, sem cadastro), e o
segundo grava o pacote com as dez datas-base mais recentes.

```bash
python tool/tesouro_baixar.py
```

```bash
npm run tool -- curve-package
```

Depois, `npm run build`.

### Como conferir que a avaliação está íntegra

Abra o Raio-X de uma ação e o painel de logs:

| Passo do painel | Íntegro | Sem o pacote |
|---|---|---|
| Estrutura a termo da taxa de desconto | "a taxa livre de risco de cada ano é o forward de um ano da curva dos prefixados de DD/MM/AAAA" | "**sem curva de juros**, o custo de capital do ano 1 usa a taxa livre de risco corrente" |
| Custo do capital próprio (CAPM), Passo 0 | "a média de dez anos do prêmio implícito no preço da bolsa" | "5.5%, o prêmio parametrizado: a série do prêmio implícito não chegou a esta avaliação" |

Nos dois casos a avaliação também traz uma ressalva dizendo o que faltou.
**Preço justo calculado sem a curva não é comparável** com os da documentação e
dos casos de estudo.

### Todos os pacotes

Todos em `public/assets/`, salvo o último.

| Pacote | O que leva | Gerado por (`npm run tool -- …`, ou `python tool/…`) | Precisa de |
|---|---|---|---|
| `tesouro/curva.json` | curva dos prefixados | `tesouro_baixar.py` → `curve-package` | só internet |
| `mercado/premio_implicito.json` | série trimestral do prêmio implícito | `implied-premium --so-serie` | entrada congelada e bases da B3 e do Tesouro |
| `cvm/documentos.json` | demonstrações anuais e trimestrais | `cvm_baixar.py` → `cvm-ingest data/cvm` → `cvm-package` | base da CVM (cerca de 7 GB) |
| `cvm/capital.json` | emissões e eventos de ações | `cvm_baixar.py --docs FRE` e `b3_baixar.py` → `capital-package` | FRE e COTAHIST |
| `cvm/outorgas.json` | prazo das concessões | `cvm_baixar.py --docs FRE` → `fre-grants` | FRE |
| `cvm/units.json` | composição das units | `cvm_baixar.py --docs FCA` → `unit-package` | FCA |
| `cvm/controle.json` | espécie do controle acionário, para a ressalva de controle estatal | `cvm_baixar.py --docs FCA` → `control-package` | FCA |
| `b3/emissores.json` | contagem oficial de ações e setor | `b3_companhias_baixar.py` e `b3_complemento_baixar.py` → `b3-package` | internet |
| `b3/proventos.json` | proventos, para o beta de retorno total | `b3_complemento_baixar.py` → `b3-dividends-package` | internet |
| `mercado/beta_prior.json` | prior do beta por setor | `beta-prior-package` | entrada congelada |
| `mercado/multiplos_setoriais.json` | medianas de múltiplos dos pares | `multiples-package` | entrada congelada |
| `validacao/banda_calibrada.json` | a faixa calibrada | backtest → `cobertura_banda.py` | backtest |
| `validacao/habilidade.json` | a habilidade medida | backtest → `conditional-regression --trimestral` | backtest |
| `public/config/distressed_tickers.json` | companhias em recuperação judicial | editado à mão | — |

As bases brutas ficam em `data/`, que **não é versionada** (só a da CVM tem
cerca de 7 GB). Por isso só quem tem as bases regera a maior parte dos pacotes;
os outros desenvolvedores só precisam da curva.

### Depois de mudar o motor

Sem mexer na entrada congelada:

| Passo | Comando |
|---|---|
| 1. Regravar o gabarito | `npm run tool -- cascade-golden --regravar` |
| 2. Refazer os casos de estudo e as figuras | `npm run tool -- study-cases`, depois `python tool/figuras_estudo.py`, e reler os casos em `docs/estudo/casos/` |
| 3. Se a mudança afeta a validação: o backtest (cerca de 1 hora) | `npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas --trimestral` |
| 4. A faixa calibrada | `python tool/cobertura_banda.py` |
| 5. A habilidade e o poder | `npm run tool -- conditional-regression --trimestral`, depois `npm run tool -- r3-power` |
| 6. Conferir | `npm test`, `npm run typecheck` e `npm run qa:gemini` |
| 7. O cálculo do usuário continua reproduzindo o motor | `npm run tool -- manual-calculation-check` |
| 8. O porquê das normalizações, ativo a ativo | `npm run tool -- normalizations` (grava `docs/validacao/normalizacoes.md`) |

O gabarito gravado pelo Dart **não serve de comparação ao TypeScript** sem ser
regravado uma vez: o JSON do JavaScript escreve `1` onde o do Dart escrevia
`1.0`, e a impressão muda sem que número algum mude. A igualdade dos números
entre os dois motores é conferida por `npm run test:parity` (decisão 152).

### Atualizar o conjunto inteiro (avançar a entrada congelada)

É uma rodada própria, com registro: todos os números da documentação, do
gabarito e dos casos mudam. **Hoje não é só rodar comandos.** A data 14/09/2026
está fixa no código de `tool/validation/frozen.ts`, `tool/cascade-golden.ts`,
`tool/beta-prior-package.ts`, `tool/unit-package.ts`,
`tool/control-package.ts`, `tool/b3-delisted-count.ts` e
`tool/backtest-valuation.ts`, e `tool/implied-premium.ts` mede os trimestres
até 30/06/2026. Avançá-la é mudança de código. Depois disso, a ordem segue as
dependências declaradas no cabeçalho de cada ferramenta (os nomes abaixo são
os de `npm run tool -- …`):

| Etapa | Comandos |
|---|---|
| 1. Bases brutas, em `data/` | `python tool/cvm_baixar.py`; `python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre`; `python tool/cvm_baixar.py --docs FCA`; `python tool/b3_baixar.py`; `python tool/b3_companhias_baixar.py`; `python tool/b3_complemento_baixar.py`; `python tool/b3_complemento_baixar.py --deslistadas`; `python tool/b3_ponte.py`; `python tool/tesouro_baixar.py` |
| 2. Ingestão e contagens por data | `cvm-ingest data/cvm`; `b3-delisted-count` |
| 3. Pacotes de dado | `cvm-package`, `b3-package`, `b3-dividends-package`, `capital-package --agora`, `fre-grants`, `unit-package --agora`, `control-package --agora` e `curve-package` |
| 4. Congelar a entrada nova | `cascade-golden`, sem `--regravar`: copia o cache do dia para `data/gabarito/` |
| 5. Pacotes medidos sobre ela | `beta-prior-package`, `multiples-package` e `implied-premium --so-serie` — que recusa regravar trimestre já gravado que tenha mudado; confira a causa antes de usar `--aceitar-mudanca-do-passado` (item B48) |
| 6. O gabarito com os pacotes novos | `cascade-golden --regravar` |
| 7. Validação, casos e conferência | os passos 2 a 6 de "Depois de mudar o motor" |

---

## Testes e qualidade

```bash
npm test               # a suíte inteira (Vitest): núcleo, paridade, dados, aplicativo, telas e ferramentas
npm run test:core      # só o núcleo
npm run test:parity    # o núcleo TypeScript contra o gabarito do núcleo Dart original
npm run typecheck      # aplicativo, testes, scripts de QA e ferramentas
```

Os testes rodam offline, sobre respostas reais em `test/fixtures/` e os pacotes
de `public/assets/`; o [test/README.md](test/README.md) diz o que cada pasta
cobre. A cadeia de QA:

| Camada | Quando | O que faz |
|---|---|---|
| `.githooks/pre-commit` | todo commit | regras locais, sem rede, em menos de um segundo |
| `.githooks/pre-push` e `npm run qa:gemini` | todo push, e antes de concluir tarefa | auditor de defeitos de correção; **FAIL bloqueia** |
| `npm run conselho -- --lente <id>` | depois de mudanças | conselheiro por lentes; nunca bloqueia |
| `npm run ui:capturar` | antes da lente `tela` | as capturas das sete telas, em três larguras e dois temas, com mercado sintético |
| `npm run tool -- cascade-golden --conferir` | mudança no motor | confere ao bit a saída de 376 ativos |
| `npm run tool -- manual-calculation-check` | mudança no motor ou na tela Simular minhas premissas | confere que, sem troca, o cálculo do usuário dá o preço do motor em cada avaliado |

Detalhes no [CLAUDE.md](CLAUDE.md) e no
[capítulo 8 da documentação do motor](docs/motor/08-verificacao-e-validacao.md).

---

## Fontes de dados

| Dado | Fonte |
|---|---|
| Demonstrações anuais | CVM (dados abertos, pacote `public/assets/cvm/`) e brapi |
| Cotações e índice | brapi |
| Contagem de ações e setor | registro de emissores da B3 (`public/assets/b3/emissores.json`) |
| Proventos | B3 (`public/assets/b3/proventos.json`) — no retorno total do beta e da validação; somados na bolsa inteira, na série do prêmio implícito (decisão 142) |
| Eventos de capital, units, concessões | CVM, formulários cadastral e de referência (`public/assets/cvm/`) |
| Curva de juros | Tesouro Direto (`public/assets/tesouro/curva.json`) |
| CDI, IPCA, IBC-Br | Banco Central, SGS 12, 433 e 24364 |
| Prêmio de mercado, múltiplos de pares, prior do beta, faixa calibrada | pacotes medidos pelo próprio projeto (`public/assets/mercado/`, `public/assets/validacao/`) |

Detalhes e regras de cada fonte no
[capítulo 1 da documentação do motor](docs/motor/01-insumos-e-dados.md).

---

## Estrutura

```
src/
  core/                o núcleo: TypeScript puro, sem dependência, sem rede, sem relógio
    usecases/          a cascata de avaliação, a montagem dos insumos
    services/          DCF, custo de capital, guardas, curva, cenários, faixa,
                       múltiplos, beta, métricas, meta, simulação
    entities/          fundamentos, carteira, resultado da avaliação
    audit/             o rastro de cálculo
    lang/              o runtime do porte: data, arredondamento e sorteio com a semântica do Dart
  data/                fontes (brapi, Banco Central, Tesouro), rede, cache, persistência, worker
  app/                 a raiz de dependências, o estado (Zustand) e as consultas
  audit/               o barramento do painel de logs (BroadcastChannel)
  copy/                os textos de tela e a formatação brasileira
  features/            as telas: study, asset (Raio-X), manual, goal, backtest, valuations, logs, shell
  ui/                  componentes (Radix UI e Tailwind) e gráficos (Recharts)
  styles.css           os tokens de cor, tipo e espaço dos dois temas
public/assets/         pacotes de dados versionados
tool/                  medições, backtest, gabarito, empacotadores, casos de estudo
test/                  toda a suíte de testes, separada pelo que ela testa
  core/                o núcleo, inclusive o teste de pureza
  parity/              o núcleo TypeScript contra o gabarito do núcleo Dart
  data/, app/, audit/  dados, aplicativo e barramento
  ui/                  telas e contraste
  tool/                os scripts de tool/
  fixtures/            respostas reais das fontes, para os testes rodarem offline
  qa_fixtures/         casos financeiros conferidos, consultados pelo auditor
scripts/               a cadeia de QA (auditor, conselheiro, gate local, estado, capturas)
docs/estudo/           o guia de estudo
docs/motor/            a documentação do motor
docs/decisoes/         o registro de decisões, uma por arquivo
docs/validacao/        as medições e as limitações
functions/             proxy opcional da credencial
```

A regra de dependência é uma só: telas, aplicativo, dados e ferramentas
dependem do núcleo, e o núcleo não conhece ninguém.
[purity.test.ts](test/core/purity.test.ts) falha se React, rede, navegador,
Firebase ou módulo do Node entrarem nele.
