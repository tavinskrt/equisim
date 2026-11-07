# CLAUDE.md — Equisim

Instruções para agentes de codificação (Claude Code, Antigravity, e afins)
trabalhando neste repositório.

---

## 1. Regra mandatória de QA

**Antes de considerar QUALQUER tarefa concluída, execute a auditoria:**

```bash
npm run qa:gemini
```

Se o resultado for **FAIL**, você não terminou. Leia os achados, corrija o
código, e rode de novo até obter **PASS**. Não relate a tarefa como concluída
com um FAIL pendente, e não desative o gate para passar.

Interpretação da saída:

| Código | Significado | O que fazer |
|---|---|---|
| `0` PASS | Nenhum achado bloqueante | Tarefa pode ser concluída |
| `1` FAIL | Defeito real no código novo | **Corrija e reaudite** |
| `2` — | Falha de infraestrutura (sem chave, sem cota, API fora) | Não é defeito do código. Relate ao usuário e siga; não finja que passou |

Achados **WARN** não bloqueiam. São dívida em código preexistente. Não os
corrija por conta própria dentro de uma tarefa não relacionada — mencione ao
usuário e siga.

### Quando usar cada comando

```bash
npm run qa:gemini            # diff contra HEAD~1 — o padrão
npm run qa:staged            # só o que está em staging
npm run qa:file -- <arquivo> # arquivo integral
npm run qa:pending           # audita o que ficou na fila por falta de cota
npm run qa:visual -- <img>   # auditoria visual de captura de tela
npm run qa:api               # mesma auditoria pela API key (reproduzível)
npm run qa:dry               # monta o payload sem chamar o modelo (custo zero)
npm run typecheck            # verificação estática dos scripts de QA
```

### Quando a cota acabar

Se a auditoria falhar por cota esgotada, o runner **não bloqueia o trabalho**:
ele grava o payload exato em `.qa-pending/` e sai com código `2`. Isso libera o
commit e o push.

Nesse caso, **relate ao usuário que a auditoria ficou pendente** — não trate
como aprovação. Quando a cota voltar:

```bash
npm run qa:pending
```

A fila guarda o **instantâneo** do que foi liberado, não o intervalo de
commits. Drenar três commits depois audita o mesmo código que passou, não o
`HEAD` atual.

Se estiver alterando **apenas** os scripts de QA em `scripts/`, `npm run
typecheck` basta — não gaste cota auditando a própria ferramenta.

---

## 2. Como o gate está montado

Duas camadas, com orçamentos de tempo diferentes. A separação é deliberada:
os commits deste projeto saem pelo **GitHub Desktop**, que congela a interface
enquanto um hook roda e não oferece `--no-verify` na tela.

| Camada | Quando | Custo | O que verifica |
|---|---|---|---|
| `.githooks/pre-commit` | todo commit | ~250–500 ms, **sem rede** | Regras determinísticas locais ([scripts/qa-local.mjs](scripts/qa-local.mjs)) |
| `.githooks/pre-push` | todo push | 30 s – 4 min | Auditoria completa com o Gemini |

Instalação dos hooks (uma vez por clone):

```bash
git config core.hooksPath .githooks
```

**Válvula de emergência:** criar o arquivo `.qa-skip` na raiz desativa as duas
camadas. Existe porque o GitHub Desktop não expõe `--no-verify`. Apague depois
de usar — ele está no `.gitignore` e não é versionado.

O `pre-push` **libera** o push quando a auditoria não pôde ser executada
(código 2). Ficar sem internet ou sem cota não é defeito do código, e um gate
que trava o push nessas horas seria arrancado na primeira ocorrência.

### Qual modelo audita

O padrão é o backend `agy` — a CLI do Antigravity, autenticada pela assinatura
**Google AI Pro**. Sem API key, sem billing, com acesso à família Pro.

Rodando em terminal, ele **pergunta qual modelo usar** e mostra o tamanho do
alvo antes: Flash ou Pro, em `low` ou `high`, sempre na versão mais recente
disponível — a lista vem de `agy models` a cada execução, nada é fixado por
nome. Em hook ou CI não há terminal, então ele usa o padrão sem perguntar.

O backend `api` (API key) continua disponível em `npm run qa:api`. Ele tem
schema forçado pelo servidor e `temperature: 0`, portanto é o mais reproduzível
— mas o tier gratuito dá **20 requisições/dia** e cota **zero** para modelos Pro.

---

## 3. Restrições de arquitetura que você não deve violar

### 3.1 `src/core` é TypeScript puro

**Zero dependências de runtime**, por decisão deliberada, travada pelo teste
`test/core/purity.test.ts`: todo import de `src/core` é relativo e fica dentro
dele. O núcleo foi Dart (`packages/equisim_core`) até a versão 2.0.0, que o
portou regra por regra; `test/parity/` confere que nenhum número mudou.

- **Não importe pacote algum** nesse módulo — nem `decimal.js`, nem `big.js`,
  nem utilitário "só dessa vez".
- Para precisão monetária, a solução aceita é **aritmética inteira em
  centavos** (`number` inteiro, exato até `Number.MAX_SAFE_INTEGER`, e `bigint`
  se houver risco de passar dele), convertendo para fração de real apenas na
  fronteira de apresentação.
- Sem rede, sem I/O, sem `node:*`, sem navegador (`window`, `document`,
  `fetch`, armazenamento), sem React, sem Firebase.
- `src/core/lang/` é o runtime do porte: `DateTime`, `round` (meio afastado de
  zero), `mod` (resto nunca negativo), `toStringAsFixed`, `Random` com a
  semântica do Dart de origem. Use-o no núcleo em vez do equivalente nativo
  quando a semântica difere — `Math.round(-2.5)` é `-2`, e `round(-2.5)` é
  `-3`.

### 3.2 O núcleo precisa ser determinístico

A mesma entrada tem de produzir a mesma saída hoje e daqui a um ano. Não
introduza `DateTime.now()` direto em caminho de cálculo — receba a data por
parâmetro, seguindo o padrão já usado no repositório:

```ts
const today = args.asOf ?? DateTime.now();
```

O hook de pre-commit bloqueia a forma direta — e `new Date()` e `Date.now()`,
que são o mesmo relógio — e permite a forma com `??`.

### 3.3 Credenciais

- O **Vite embarca no bundle toda variável `VITE_*`** do `.env`: ela fica
  pública no JavaScript servido por `npm run build`. Nunca coloque segredo de
  ferramenta numa `VITE_*`. Em produção, a brapi vai pelo proxy
  (`VITE_BRAPI_PROXY_URL`); `VITE_BRAPI_TOKEN` é só de desenvolvimento.
- As ferramentas de `tool/` leem `BRAPI_TOKEN`, sem prefixo, que o Vite ignora:
  só o Node a vê.
- A `GEMINI_API_KEY` mora em **`.env.qa`**, que é ignorado pelo git e não é
  lido pelo Vite.
- O hook de pre-commit bloqueia `.env*`, `google-services.json`,
  `serviceAccount*.json` e material criptográfico em staging.

---

## 4. Convenções de domínio

Moeda é BRL: 2 casas, arredondamento half-up. Quantidade de ação é **inteira**
(o escopo é de ações: o projeto não tem FII).

- Selic/CDI são publicados em % ao ano na **base 252 dias úteis**. Converta
  por composição — `(1+i)^(1/252)-1` —, **nunca** por `i/252`.
- Taxa real usa Fisher: `(1+nominal)/(1+inflação)-1`. A subtração simples erra
  quase meio ponto percentual com a inflação brasileira.
- **Provento é dado conferido da validação, e não crédito da simulação.** Os
  proventos da B3 entram em três lugares, e só neles: o **retorno total nas
  coortes de validação** e no beta; a **faixa calibrada** da tela de avaliação,
  que sai desse retorno total medido; e o **prêmio implícito**, que é o prêmio
  de mercado do CAPM e usa os proventos da bolsa inteira — provento agregado,
  nunca o de um ativo (ver [docs/motor/](docs/motor/README.md), capítulos 1, 4
  e 6). A simulação da carteira, o fluxo de cada ativo na cascata e o retorno
  esperado são de preço. Estender provento a qualquer um deles é mudança de
  método: só com pedido explícito do usuário, e com a documentação e o
  changelog atualizados (seção 7).
- A simulação compra **ação inteira**, e a sobra de cada aporte fica em caixa
  por ativo, acumula e entra no aporte seguinte. Fração de ação em caminho de
  cálculo é defeito.
- Toda divisão de dinheiro entre N destinos **distribui o resto**. Opere na
  magnitude em centavos inteiros e reaplique o sinal: o `%` do JavaScript tem o
  sinal do dividendo (`(-1) % 3 === -1`) e o `mod` de `src/core/lang` é sempre
  não-negativo (`mod(-1, 3) === 2`), e nos dois o algoritmo ingênuo erra um
  centavo em estornos.

Casos verificados, com valores executados em Dart 3.12, estão em
[test/qa_fixtures/financial_edge_cases.json](test/qa_fixtures/financial_edge_cases.json).
O `double` do Dart e o `number` do JavaScript são o mesmo IEEE-754 binário de
64 bits, então os valores valem para o TypeScript; onde o caso depende de
operador (`%`, `round`), vale a versão de `src/core/lang`. Consulte-o antes de
escrever cálculo financeiro novo.

---

## 5. Onde ficam as regras dos agentes

O comportamento do **auditor** é definido em
[scripts/qa/rules.ts](scripts/qa/rules.ts); o do **conselheiro**, em
[scripts/qa/advisor/rules.ts](scripts/qa/advisor/rules.ts) mais a disciplina de
cada lente em [scripts/qa/advisor/lentes.ts](scripts/qa/advisor/lentes.ts). Se
um achado veio errado, a correção é **nesses arquivos** — não no código do
runner, e nunca desativando a regra para o commit passar.

A calibragem de severidade do auditor vale a leitura antes de discordar de um
achado: `FAIL` exige que o defeito esteja em linha adicionada **e** seja erro de
correção real; código preexistente no máximo vira `WARN`.

---

## 6. O conselheiro

Segundo agente, de papel **oposto** ao do auditor. Aquele caça defeito de
correção ancorado em arquivo e linha, e **bloqueia**. Este examina relação entre
coisas — documentação contra código, rótulo contra tela, propósito contra
implementação — e **nunca bloqueia**: sai com código 0 mesmo em falha de rede,
cota ou JSON inválido, e nenhum hook o chama.

A regra que sustenta o arranjo: **quem propõe não bloqueia; quem bloqueia não
propõe.** Ampliar o auditor para "proponha melhorias" destruiria a calibragem
que o torna confiável.

```bash
npm run conselho                      # lista as lentes
npm run conselho -- --lente <id>      # executa uma
npm run conselho:dry -- --lente <id>  # monta o payload sem chamar o modelo
```

| Lente | Pergunta |
|---|---|
| `registro` | Onde a documentação e o changelog divergem da realidade do repositório? |
| `nucleo` | As entidades são coesas? Que regra de negócio vazou para a UI? |
| `dados` | O que acontece quando a API cai, estoura cota ou devolve série incompleta? |
| `metodo` | A metodologia de DCF e CAPM é defensável? Que premissa está implícita? |
| `risco` | Que caminho de cálculo ou de erro não tem teste? |
| `rumo` | Que limitação ou pendência declarada continua aberta? |
| `tela` | O que compete por atenção? O rótulo descreve o que a tela faz? |

Seis são texto puro e rodam pelo `agy`, na cota da assinatura. Só `tela` precisa
de imagem, e o `agy` não transmite imagem — ela força o backend `api` e avisa no
stderr quando troca.

### A lente `tela` exige capturas

```bash
npm run ui:capturar   # 48 PNGs em docs/telas/, ignorado pelo git
npm run conselho -- --lente tela --largura 1024 --tema escuro
```

O capturador é [scripts/capture-screens.ts](scripts/capture-screens.ts): sobe
o Vite em modo local, abre um Chromium sem janela pelo `playwright-core`,
responde a brapi e o Banco Central com um mercado sintético e fixa o relógio do
navegador. Fica fora de `test/` de propósito: não é teste de regressão, e uma
alteração intencional de UI não deixa a suíte vermelha. Sem Chromium do
Playwright, use `--navegador <caminho>` ou o Chrome instalado.

**Quatro limites do equipamento**, já registrados no prompt da lente. Não os
reintroduza ao mexer ali:

1. Inter e JetBrains Mono vêm do Google Fonts; sem rede, o texto cai na fonte
   do sistema. Símbolo fora das fontes instaladas na máquina de captura
   (U+26A0 e afins) pode sair como caixa vazia e renderiza bem no aparelho.
2. A janela é esticada até a altura do conteúdo antes da foto, e nunca encolhe
   abaixo de 844 px (celular) ou 900 px. Sobra vertical não é defeito da
   interface. O `fullPage` do Playwright foi descartado porque deixava o
   cabeçalho grudado e a barra fixa no meio da imagem.
3. O mercado é sintético: os números da tela não são os de mercado.
4. Material parcial produz ausência falsa. Onde a pergunta é "o que existe", a
   listagem tem de ser completa no escopo declarado — e dizer que é.

### No tier gratuito o limite diário é POR MODELO

Por isso o backend `api` cascateia quando o conselheiro o usa:
`3.7-flash` → `3.6-flash` → `3.5-flash` → `3.5-flash-lite` (este com 500/dia
contra 20 dos outros). O relatório avisa quando houve rebaixamento.

**O auditor NÃO cascateia**, e não deve passar a: ele existe para ser
reproduzível, e trocar de modelo em silêncio destruiria isso.

Lista vazia vinda do último degrau é mais provavelmente "não enxerguei" do que
"não há". Para direção visual, espere o topo liberar.

---

## 7. Histórico, versão e documentação

O projeto registra o que muda em **dois lugares, e só neles**: o **changelog**,
que diz o que mudou para quem usa o produto, e a **documentação técnica**, que
diz como o sistema funciona hoje. Não existe mais registro de decisões
numeradas: a pasta `docs/decisoes/` saiu do repositório na versão 2.5.0, e o
gate local bloqueia arquivo novo nela.

**Nunca crie arquivo numerado de decisão, nem documento que cite o pedido do
usuário** (`origem`, `citacao`, "você pediu"). O que o usuário pediu é contexto
da conversa, e não produto.

### O que fazer a cada mudança

Sempre que uma alteração impactar funcionalidade, cálculo, interface ou
experiência do usuário:

1. **Atualize a documentação técnica** correspondente — o capítulo de
   [docs/motor/](docs/motor/README.md) que descreve a regra, o
   [docs/estudo/](docs/estudo/README.md) se o guia a explica, o
   [README.md](README.md) se a mudança aparece nele. Escreva o estado atual,
   **sem mencionar que houve mudança** ("antes era X", "passou a", "desde a
   versão"): quem lê a documentação quer saber como é, e o como era mora no
   changelog.
2. **Acrescente a entrada no changelog**, em
   [src/data/changelog.ts](src/data/changelog.ts) — a fonte única, que a tela
   de novidades do aplicativo lê —, e regenere o markdown com
   `npm run changelog`. Nunca edite o [CHANGELOG.md](CHANGELOG.md) à mão.
3. **Atualize a versão** quando a mudança for publicada: o `version` do
   `package.json` e a versão nova no alto de `changelog`, com a data
   `AAAA-MM-DD`. Trabalho que ainda não fecha uma versão vai para `unreleased`,
   que aparece como "Não publicado".
4. Rode `npm run estado` para regenerar o [docs/estado.md](docs/estado.md).

`test/data/changelog.test.ts` reprova quando a versão do `package.json`, a do
aplicativo e a mais recente do changelog divergem, quando o `CHANGELOG.md` não é
o que `npm run changelog` gera, ou quando um item cita arquivo, código ou
registro interno.

### Como escrever o changelog

O formato é o [Keep a Changelog 1.1.0](https://keepachangelog.com/pt-BR/1.1.0/),
e a numeração, o [Versionamento Semântico 2.0.0](https://semver.org/lang/pt-BR/).

- **Quatro categorias**, nesta ordem: `added` (Adicionado), `changed`
  (Alterado), `removed` (Removido) e `fixed` (Corrigido).
- **Tom profissional, voltado a quem usa o produto ou analisa a avaliação.**
  Diga o que mudou na tela, no cálculo ou na simulação, e o efeito para o
  usuário. Nada de caminho de arquivo, nome de componente, tipo ou variável
  interna (`DetailMode`, `SideBySidePortfolios`), nem menção ao pedido.
- Cada item é uma frase completa, terminada em ponto.

| Mudança | Versão |
|---|---|
| A plataforma ou o método de avaliação é reconstruído de ponta a ponta, ou o que o usuário gravou deixa de ser lido como antes | **MAJOR** |
| Funcionalidade que entra, muda ou sai, ou regra de cálculo que muda, mantendo legível o que o usuário gravou | **MINOR** |
| Só correção de defeito, sem funcionalidade nova | **PATCH** |

A política completa está em `versioningPolicy`, no mesmo arquivo, e aparece no
alto do `CHANGELOG.md`.

### Onde mora cada coisa

| Onde | O quê |
|---|---|
| `src/data/changelog.ts` | Histórico de versões, fonte única. A tela Changelog e o `CHANGELOG.md` saem dele |
| `CHANGELOG.md` | **Gerado** por `npm run changelog`. Nunca edite à mão |
| `docs/estado.md` | **Gerado** por `npm run estado`. Nunca edite à mão |
| `docs/motor/` | O que o código faz, regra por regra, com código, fórmula, teoria e evidência. Mudou uma regra, mude o capítulo |
| `docs/estudo/` | Guia para quem não sabe finanças: capítulos e casos com os números de `tool/study-cases.ts`. Mudou o motor, refaça os dados e releia os casos |
| `docs/validacao/` | Relatórios de medição, **datados**: o número vale para a data e o motor de quando foi medido |

### Postura: como tratar o que já existe

A **preservação** é o padrão: divergência é dívida a inventariar, e só regressão
vira tarefa. Mudança de método — na cascata de avaliação inclusive — só acontece
quando o usuário a pede explicitamente, e vem com a medição que a sustenta, o
capítulo de `docs/motor/` reescrito e a entrada no changelog. Se a mudança move
um número da paridade (`test/parity/`), diga isso ao usuário antes de regravar
qualquer gabarito.
