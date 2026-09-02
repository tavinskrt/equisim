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

### 3.1 `packages/equisim_core` é Dart puro

**Zero dependências de runtime**, por decisão deliberada, travada pelo teste
`packages/equisim_core/test/purity_test.dart`.

- **Não adicione pacote algum** ao `pubspec.yaml` desse módulo — nem
  `decimal`, nem `rational`, nem utilitário "só dessa vez".
- Para precisão monetária, a solução aceita é **aritmética inteira em
  centavos** (`int`, e `BigInt` se houver risco de estouro), convertendo para
  `double` apenas na fronteira de apresentação.
- Sem rede, sem I/O, sem `dart:io`, sem Flutter.

### 3.2 O núcleo precisa ser determinístico

A mesma entrada tem de produzir a mesma saída hoje e daqui a um ano. Não
introduza `DateTime.now()` direto em caminho de cálculo — receba a data por
parâmetro, seguindo o padrão já usado no repositório:

```dart
final today = asOf ?? DateTime.now();
```

O hook de pre-commit bloqueia a forma direta e permite a forma com `??`.

### 3.3 Credenciais

- `.env` **é declarado como asset no `pubspec.yaml`**. Tudo que estiver nele é
  embarcado no bundle e fica público em `flutter build web`. Nunca coloque
  segredo de ferramenta ali.
- A `GEMINI_API_KEY` mora em **`.env.qa`**, que é ignorado pelo git e não é
  asset.
- O hook de pre-commit bloqueia `.env*`, `google-services.json`,
  `serviceAccount*.json` e material criptográfico em staging.

---

## 4. Convenções de domínio

Moeda é BRL: 2 casas, arredondamento half-up. Quantidade de ação e cota de FII
é **inteira**.

- Selic/CDI são publicados em % ao ano na **base 252 dias úteis**. Converta
  por composição — `(1+i)^(1/252)-1` —, **nunca** por `i/252`.
- Taxa real usa Fisher: `(1+nominal)/(1+inflação)-1`. A subtração simples erra
  quase meio ponto percentual com a inflação brasileira.
- **O projeto não modela provento.** Dividendo, JCP e a tributação deles saíram
  pela [decisão 23](docs/decisoes/023-remocao-de-proventos.md); o retorno
  apurado é de preço. Não reintroduza crédito de provento sem uma decisão nova
  que substitua aquela.
- A simulação compra **ação inteira**, e a sobra de cada aporte fica em caixa
  por ativo, acumula e entra no aporte seguinte. Fração de ação em caminho de
  cálculo é defeito.
- Toda divisão de dinheiro entre N destinos **distribui o resto**. Opere na
  magnitude em centavos inteiros e reaplique o sinal: o operador `%` do Dart é
  sempre não-negativo (`(-1) % 3 == 2`), e o algoritmo ingênuo inventa um
  centavo em estornos.

Casos verificados, com valores executados em Dart, estão em
[test/qa_fixtures/financial_edge_cases.json](test/qa_fixtures/financial_edge_cases.json).
Consulte-o antes de escrever cálculo financeiro novo.

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
coisas — decisão contra código, rótulo contra tela, propósito contra
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
| `registro` | Onde o registro diverge da realidade do repositório? |
| `nucleo` | As entidades são coesas? Que regra de negócio vazou para a UI? |
| `dados` | O que acontece quando a API cai, estoura cota ou devolve série incompleta? |
| `metodo` | A metodologia de DCF e CAPM é defensável? Que premissa está implícita? |
| `risco` | Que caminho de cálculo ou de erro não tem teste? |
| `rumo` | O que foi decidido e não foi entregue? |
| `tela` | O que compete por atenção? O rótulo descreve o que a tela faz? |

Seis são texto puro e rodam pelo `agy`, na cota da assinatura. Só `tela` precisa
de imagem, e o `agy` não transmite imagem — ela força o backend `api` e avisa no
stderr quando troca.

### A lente `tela` exige capturas

```bash
npm run ui:capturar   # 30 PNGs em docs/telas/, ignorado pelo git
npm run conselho -- --lente tela --largura 1024 --tema escuro
```

O arquivo de captura é [test/presentation/golden_capture.dart](test/presentation/golden_capture.dart)
— **sem** sufixo `_test`, de propósito: assim ele fica fora do `flutter test` e
uma alteração intencional de UI não deixa a suíte vermelha.

**Três limites do equipamento**, já registrados no prompt da lente. Não os
reintroduza ao mexer ali:

1. Só Roboto e MaterialIcons são carregados. Símbolo fora do Roboto (U+26A0 e
   afins) sai como caixa vazia na captura e renderiza bem no aplicativo real.
2. A captura tem 1600 px de altura para pegar a tela inteira. Sobra vertical
   não é defeito da interface.
3. Material parcial produz ausência falsa. Onde a pergunta é "o que existe", a
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

## 7. O registro de decisões

**Decisão mora em arquivo próprio**, em [docs/decisoes/](docs/decisoes/), e não
se edita depois de aceita — substitui-se por outra, que a cita. O formato está
no [README de lá](docs/decisoes/README.md).

| Onde | O quê |
|---|---|
| `docs/decisoes/` | Decisões 19+. Imutáveis, com `origem`, `data` e `afeta` |
| `docs/apontamentos/` | O que orientador e devs apontam fora do git |
| `docs/estado.md` | **Gerado** por `npm run estado`. Nunca edite à mão |
| `docs/eap/` | Pacotes da reconstrução da UI em curso |
| `PLANO_ARQUITETURA.md` | **Congelado.** Plano de transição já cumprido; decisões 0–18 estão nele |

O gate local bloqueia **referência quebrada** — `afeta` apontando para caminho
inexistente, `substitui` citando decisão que não existe. **Defasagem nunca
bloqueia**: um gate que trava o push porque um documento envelheceu é um gate
arrancado na primeira semana. Defasagem é assunto da lente `registro`.

### Postura: como tratar o que já existe

A **preservação** é o padrão: divergência é dívida a inventariar, e só regressão
vira tarefa. A **reconstrução** é declarada por uma decisão com
`postura: reconstrucao` e `status: aceita` — dentro do `afeta` dela, tudo é
acionável.

A fronteira não é configuração, é o próprio registro:
[scripts/qa/advisor/postura.ts](scripts/qa/advisor/postura.ts) lê
`docs/decisoes/` a cada execução. Cumprida a EAP, a decisão vira
`status: cumprida` e a superfície volta à preservação.

**Não há reconstrução aberta hoje.** A [decisão 22](docs/decisoes/022-reconstrucao-da-ui.md),
sobre as telas de operação, está `cumprida`: a EAP dela foi entregue e a
superfície voltou à preservação. Enquanto nenhuma decisão nova declarar
`postura: reconstrucao` com `status: aceita`, divergência na interface é dívida
a inventariar — não tarefa.

Confira antes de agir, em vez de confiar nesta frase: quem responde é
`docs/decisoes/`, e este parágrafo é cópia que envelhece.
