# Plano para o motor de referência

Análise completa do motor em 11/09/2026, e o que falta para dois objetivos
distintos: **valuation exemplar** (o preço justo de um ativo é defensável) e
**motor de referência** (nenhum defeito conhecido + incerteza calibrada +
habilidade comprovada).

Este documento substitui as listas parciais das rodadas anteriores. Ele é
reordenado por uma medição feita hoje, que muda a prioridade de tudo.

---

## 0. O fato que reorganiza a lista

O cabeçalho de `tool/backtest_valuation.dart` declara, desde que foi escrito, o
critério pelo qual a cascata se justifica:

> Sozinho, um coeficiente de correlação não diz se a sofisticação se paga. O
> potencial é medido lado a lado com dois fatores ingênuos que usam os mesmos
> dados e nenhuma modelagem: o valor patrimonial sobre o preço e o lucro sobre
> o preço. **Se o motor não os supera, a cascata inteira está cobrando um custo
> de complexidade que não entrega.**

O teste nunca tinha sido executado. Executado hoje, sobre 8 coortes
*point-in-time* (2018–2025) e o motor **atual** — depois das 66 decisões:

| horizonte | n | motor | book-to-market | earnings yield |
|---|---:|---:|---:|---:|
| 12 meses | 685 | +0,0696 | **+0,1394** | +0,0571 |
| 36 meses | 470 | +0,1559 | **+0,2403** | +0,1383 |

**O motor perde para `patrimônio líquido ÷ valor de mercado` nos dois
horizontes, por um fator de aproximadamente dois.**

E na leitura que decide carteira — quintil superior contra inferior, na mesma
amostra comum:

| horizonte | motor | book-to-market | earnings yield |
|---|---:|---:|---:|
| 12 meses | +3,0 p.p. | **+10,3 p.p.** | +3,3 p.p. |
| 36 meses | +19,3 p.p. | **+39,6 p.p.** | +17,5 p.p. |

**E um achado que não estava na pergunta.** Nas 1.218 observações em que o
motor **recusou avaliar**, o book-to-market entrega o maior spread de todos —
**+23,8 p.p.** em 12 meses e **+77,3 p.p.** em 36. O motor está recusando
justamente onde o sinal de valor é mais forte. Parte disso é cauda: ativo
recusado é pequeno, ilíquido ou em dificuldade, e o retorno dele é extremo nos
dois sentidos. Mas o tamanho pede investigação própria — as recusas podem estar
custando mais sinal do que protegem.

### 0.1 O teste decisivo: o motor acrescenta algo ao B/M?

Regressão transversal empilhada, tudo em posto normalizado dentro de cada
coorte:

| horizonte | preditor | coeficiente | t |
|---|---|---:|---:|
| **12m** | motor | +0,0131 | **+0,24** |
| | book-to-market | +0,1300 | +2,72 |
| | earnings yield | −0,0151 | −0,26 |
| **36m** | motor | +0,0835 | **+1,16** |
| | book-to-market | +0,2209 | +3,73 |
| | earnings yield | −0,0661 | −0,85 |

Sozinho o motor tem sinal — t = +1,85 em 12 meses e **+3,42** em 36. **Condicionado
ao book-to-market, ele não tem.** O IC do potencial ortogonalizado contra B/M é
de **+0,0066** em 12 meses e **+0,0394** em 36.

**Estado honesto da perna "habilidade comprovada": não demonstrada.**

### 0.2 Por que — quatro diagnósticos

**O potencial já é um fator de valor, com ruído por cima.** A correlação de
postos entre o potencial e os ingênuos é alta e estável nas oito coortes:

| | Spearman com o potencial |
|---|---:|
| book-to-market | **+0,5404** |
| earnings yield | **+0,6865** |

Por coorte, o B/M fica entre +0,442 e +0,621. A cascata de 3.128 linhas está
produzindo uma versão embaralhada do que uma divisão de dois campos produz.

**O sinal é lento porque o dado é anual.** A autocorrelação de posto do
potencial entre coortes consecutivas tem mediana de **+0,666** — dois terços da
ordenação sobrevivem de um ano para o outro. Entre duas divulgações o potencial
só se move com o preço, o que é precisamente a definição de um fator de valor
defasado.

**Não é o provento.** Sob retorno ajustado — que inclui distribuição, e cuja
série erra 9,1% na mediana (§1.2) — o motor sobe para +0,0896 e +0,1777, mas o
B/M sobe junto, para +0,1552 e +0,2608. A distância persiste.

**Não são as ressalvas.** Restringir aos casos sem ressalva alguma **piora** o
motor em 36 meses (+0,072 contra +0,180 nos casos com ressalva). Os avisos não
estão marcando as avaliações ruins.

### 0.3 O que isso não significa

**Não significa que o DCF esteja errado.** Significa que a *ordenação* que ele
produz não acrescenta à ordenação de um fator de uma linha, nesta amostra e
neste horizonte. Um DCF pode ter valor como afirmação sobre **um** ativo — o
preço justo defensável, com premissas auditáveis — sem ser o melhor ordenador
de uma seção transversal. O projeto, porém, usa a ordenação: ela alimenta o
retorno esperado, a meta e a recomendação de troca. Para esse uso, o teste é o
certo.

**As ressalvas da amostra, declaradas:** as janelas de 36 meses de coortes
vizinhas se sobrepõem, de modo que o `n` efetivo é bem menor que 470 e os
erros-padrão estão subestimados nos dois lados; o universo tem viés de
sobrevivência; os fundamentos vêm como a fonte os publica **hoje**, e
reapresentação entra como conhecimento futuro. Nada disso favorece o motor
seletivamente — e o t = +0,24 é fraco demais para que qualquer uma delas o
resgate.

---

## 1. Como a lista se reordena

Antes desta medição, a lista era um inventário de costuras a costurar. Depois
dela, há um critério único de prioridade:

> **Um item entra na frente se houver argumento plausível de que ele fecha a
> distância para o book-to-market. Todo o resto é higiene.**

Higiene continua importando — é o que sustenta "valuation exemplar" e é
pré-requisito de credibilidade. Mas não é o que falta para "motor de
referência".

Os quatro eixos abaixo estão ordenados por essa régua.

---

## 2. Eixo A — Dados: a Fase B, finalmente especificada

"Fase B" é citada cinco vezes no registro e **nunca foi definida**. É a fase da
segunda fonte, e ela está agora autorizada. Este é o eixo com maior chance de
mover a agulha, porque três dos quatro diagnósticos da §0.2 são de dado.

### A1. CVM Dados Abertos — **conferido em 11/09/2026**

> Conferência completa em [cvm_conferencia.md](validacao/cvm_conferencia.md).
> Esta seção passa a registrar o que foi **medido**, não o que se supunha.

Acesso confirmado: sem cadastro, sem token, sem limite observado, com
profundidade até 2010 — cobre as oito coortes do backtest. Cada zip anual traz
19 CSVs (BPA, BPP, DRE, DFC direto e indireto, DMPL, DVA, `composicao_capital`,
`parecer`), em versão consolidada e individual.

**O que ficou confirmado:**

| resolve | limitação | estado |
|---|---|---|
| **Trimestralidade** | §1.1 e o sinal lento da §0.2 | **286/286** companhias com ITR, 3 trimestres cada — 4 observações/ano contra 1 |
| **`DT_RECEB`** | §2.3 | *point-in-time* vira dado: mediana de **78 dias** no anual e **40** no trimestral |
| **Lucro de banco** | §2.12 | **resolvido** — Itaú tem R$ 42,1 bi em 2024 |
| **Ativo total** | §2.17 | **resolvido** — `1 = Ativo Total` existe em 100% |
| **Exercício com DRE zerada** | §1.9 | resolvido onde a CVM tem o documento |
| **Reapresentação** | ressalva da §0.3 | `VERSAO` e data por documento — e ela atinge **24,8%** dos anuais |
| **Minoritário** | §2.14 | `2.03.09`, da fonte primária (segue contábil) |
| **CapEx** | §2.1 | **parcial** — 86% têm linha em `6.02.*`, com descrição em texto livre |

**Cobertura de contas: 100% dos 286 CNPJs**, com o recuo
`consolidado → individual` (Sanepar, Comgás, Coelba e afins só arquivam
individual) e o mapa de layout abaixo.

#### O que a conferência corrigiu

**A ponte publicada não serve sozinha.** `Codigo_Negociacao` do FCA é texto
livre: **44% em branco**, e o resto traz código CVM (`25585` na CSN Mineração),
zeros (`000000` no BTG) ou a string `ADR` (Marfrig). Filtrando por formato de
ticker sobre sete anos de FCA: **359 de 375 = 95,7%**, com **zero
ambiguidade**. Os 16 restantes são quase todos classes secundárias de
companhias já resolvidas.

Casamento **aproximado** de nome é proibido, e a razão está medida: `CSNA3`
casa com **COSAN** a 0,75 de similaridade — confiante e errado. Só igualdade
após normalização.

**O plano de contas tem quatro layouts, não um**, e o lucro líquido mora em
código diferente em cada:

| layout | consolidado | individual |
|---|---|---|
| Não financeira (513) | 3.11 | 3.11 |
| Banco "**de** Intermediação" (18) | 3.11 | 3.11 |
| Banco "**da** Intermediação" (7) | **3.09** | **3.13** |
| Seguradora (4) | 3.13 | 3.13 |

Os dois de banco se distinguem por **uma preposição** num rótulo em português.
Isso invalidou uma medição intermediária minha: eu ia registrar cobertura de
100% por casar o código `3.11`, e no individual do Itaú `3.11` é *"Reversão dos
Juros sobre Capital Próprio"*. O mesmo vale para o EBIT — `3.05` é EBIT na não
financeira e "Antes dos Tributos" no banco, R$ 47,6 bi contra R$ 42,1 bi de
lucro no Itaú.

**Consequência de projeto:** o integrador detecta o layout e resolve conta por
`(código, padrão de descrição)`, recusando quando ambíguo. Tabela fixa de
códigos está errada.

#### Achado novo: 62% do universo tem ação em tesouraria

`composicao_capital` publica a contagem integralizada **e** a em tesouraria.
**178 de 286 companhias têm tesouraria > 0**, e o motor não a trata em lugar
nenhum — ação em tesouraria não tem direito a fluxo e deveria sair do divisor.
Não estava em lista alguma porque a fonte atual não publica o campo. Tamanho
por medir.

#### O que a CVM não resolve

Preço, valor de mercado e volume (ficam com A3); proventos (A4); prazo de
outorga, que está no FRE (A6); setor, que a CVM não classifica (A5). E as
deslistadas exigem baixar **todos** os anos, não confiar no universo de hoje.

### A2. Curva de juros observada — ANBIMA ou Tesouro

Hoje a estrutura a termo é **interpolação linear entre dois pontos do CDI**
(§2.9), e o registro já diz que "não é uma curva de juros". A ETTJ da ANBIMA e
os preços do Tesouro Direto são públicos e diários.

Move o nível do valor terminal, que é onde metade do valor mora (peso terminal
mediano de 0,513, p90 de 1,287). **Não há razão para esperar que mova a
ordenação** — e por isso não está antes de A1. É item de "valuation exemplar",
não de "motor de referência".

### A3. Ações societárias e contagem de papéis — B3

Resolveria §1.7 (as duas contagens, 27 ativos com divisor contestado por até
4.852×), a razão de unidade da decisão 61 e a cegueira do backtest da §3.5.
Onze ativos hoje têm divisor contestado, e **três deles estão entre os oito
primeiros da ordenação**.

### A4. Proventos por fonte independente — CVM ou B3

Permitiria reabrir a [decisão 23](decisoes/023-remocao-de-proventos.md) com
dado conferido, resolver §1.2 (o `adjustedClose` que erra 9,1%), §2.7 (retorno
de preço) e a não sincronia da decisão 57.

**Reabrir a decisão 23 é decisão do orientador, não minha** — ela foi tomada
por ausência de conferência documental, e a conferência passa a ser possível.

### A5. Taxonomia setorial oficial — B3 ou GICS

§1.5 e §2.14 (BRSR6, PINE4 e SANB4 chegam sem setor e escapam da Porta 1).
Item pequeno, efeito medido em terceira casa decimal.

### A6. Prazo das outorgas — FRE da CVM

§2.16: quinze ativos sob concessão com horizonte infinito. O tamanho está
medido — preço justo mediano em 0,80 do publicado se o contrato acabasse em dez
anos. Exige modelar junto a indenização do investimento não amortizado.

---

## 3. Eixo B — Método: o que fazer com a §0

Este é o eixo que responde à medição da §0, e é onde está o trabalho
intelectualmente difícil.

### B1. Decidir o que o potencial é para servir

A escolha é de projeto, e precisa ser explícita:

**(a) O DCF é o produto, e a ordenação sai de outra coisa.** O preço justo
continua sendo a entrega da tela de avaliação; o retorno esperado e a
recomendação de carteira passam a sair de um modelo transversal declarado, com
o potencial como **um** insumo entre outros. Honesto e imediato.

**(b) O DCF tem de ganhar.** Mantém-se o potencial como ordenador e ataca-se a
causa — trimestralidade (A1), ruído dos insumos, e o que a §0.2 mostrar depois
dela. Mais ambicioso e sem garantia.

**(c) Ambos, medidos lado a lado, e o registro diz qual venceu.** É o que o
método deste projeto já faz com tudo.

**Recomendo (c)**, com (a) implantado enquanto (b) é perseguido — porque hoje a
tela de metas usa uma ordenação que não bate um fator de uma linha, e isso é
defeito em produção, não pesquisa em aberto.

### B2. Medir o potencial ortogonalizado como produto

Se o motor tem `IC = +0,0394` ortogonalizado ao B/M em 36 meses, esse resíduo é
exatamente "o que o DCF sabe que o valor patrimonial não sabe". Publicá-lo como
grandeza própria — e medi-lo a cada rodada — transforma a §0 de acusação em
métrica de acompanhamento.

### B3. Prêmio de risco de mercado deixa de ser parâmetro

§2.2: hoje é 5,5% fixo. Alternativas: prêmio implícito (Damodaran), histórico
com encolhimento, ou implícito da própria seção. **Move o nível de todo mundo
junto, e portanto quase nada na ordenação** — item de "exemplar".

### B4. Risco-país e o que mais falta no custo de capital

Não há prêmio de risco-país, nem ajuste por tamanho, nem qualquer fator além do
beta. Um CAPM de fator único é defensável numa monografia e é fraco como motor
de referência.

### B5. Triangulação por múltiplos

Nenhuma avaliação profissional entrega DCF sozinho. Um múltiplo de pares —
EV/EBITDA, P/L, P/VP setorial — dá uma segunda leitura e, principalmente, um
teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa.

### B6. O horizonte de projeção é fixo em dez anos

Para todo mundo, independentemente de ciclo, setor ou maturidade. Nunca foi
medido se dez é melhor que sete ou quinze.

---

## 4. Eixo C — Validação: as duas pernas

### C0. O que as recusas custam

Novo, e não estava em lista nenhuma: nas 1.218 observações recusadas, o B/M dá
spread de quintil de +23,8 p.p. (12m) e +77,3 p.p. (36m), acima de qualquer
outro recorte medido. Antes de tratar isso como sinal perdido é preciso separar
a cauda — recusado costuma ser pequeno e ilíquido — do que a Porta 0 e as
guardas estão descartando por excesso de zelo.

Medição: repetir o quintil dentro dos recusados, por **motivo** de recusa, e
confrontar com a liquidez. Executável já, sem dado novo.

### C1. Habilidade comprovada — **medida hoje, e reprovada**

Deixa de ser tarefa a fazer e vira **métrica de acompanhamento**. O alvo é
explícito: `t` do motor condicionado ao B/M acima de 2, em 36 meses, com a
amostra ampliada por A1.

Sub-itens que a tornam confiável:
- **C1a.** Corrigir o erro-padrão para janelas sobrepostas (Newey-West sobre
  coortes, ou coortes não sobrepostas). O núcleo já tem HAC conferido contra o
  `statsmodels`.
- **C1b.** Ampliar a amostra com as deslistadas de A1 — hoje há viés de
  sobrevivência nos dois lados.
- **C1c.** Coortes trimestrais em vez de anuais, depois de A1.

### C2. Incerteza calibrada — **não iniciada**

`ScenarioEngine` existe e produz banda; **a frequência de cobertura fora da
amostra nunca foi medida**. Uma banda de 80% que cobre 40% dos casos é pior que
não ter banda.

Medição: para cada coorte, a fração de ativos cujo preço realizado em 12 e 36
meses caiu dentro da banda declarada, contra a frequência nominal. Não depende
de nenhum dado novo — **é executável já**, e é o item de melhor razão
esforço/resultado do plano inteiro.

### C3. A validação não exercita a ponte por papel

§3.5: 351 de 351 ativos colapsam para `u = 1` sob a reescala do backtest. Três
peças do motor não têm evidência preditiva. Resolve-se com A3.

### C4. Custos de transação

§2.5. O backtest é otimista. Baixo por não rebalancear, mas não medido.

---

## 5. Eixo D — Engenharia

### D1. `_evaluateLane` tem 1.087 linhas

`compute_valuation.dart` tem **3.128 linhas — 23% do núcleo inteiro** — e um
único método privado, `_evaluateLane`, ocupa as linhas 966 a 2053.

Isto não é estética. O padrão que se repetiu em todas as rodadas deste ciclo é
que **o motor erra nas costuras, não nas peças** — e as costuras estão dentro
de um método que não pode ser testado em pedaços. Cada defeito das decisões
45–66 esteve na composição, não no endpoint.

Quebrar em passos nomeados e testáveis é o item que mais reduz a chance do
**próximo** defeito.

### D2. Camada de dados com múltiplas fontes e procedência

Hoje: uma fonte (brapi) mais o BCB. A Fase B exige conflito de fontes resolvido
com regra explícita, e **cada número carregando de onde veio** — sem isso, o
inventário de limitações vira ficção na primeira divergência.

### D3. Cobertura de teste apontada pela lente `risco`

Telas renderizadas vazias na suíte de estouro; conversor de fundamentos sem
teste de payload corrompido.

---

## 6. Ordem sugerida

> **Reordenado em 11/09/2026**, depois da conferência do A1. O usuário fixou a
> sequência: **o eixo A inteiro e estável primeiro**, e só depois as pernas de
> validação — porque a habilidade só é comprovável quando o dado necessário
> estiver acessível, e a incerteza só é calibrável contra o que o dado não
> conclui. A ordem abaixo obedece a isso.

### Fase 1 — o eixo A, até estar estável

> **A1.1 a A1.6 concluídos em 11/09/2026.** Registro em
> [cvm_ingestao.md](validacao/cvm_ingestao.md).

| # | item | estado |
|---|---|---|
| A1.0 | Conferência de campos | ✅ [cvm_conferencia.md](validacao/cvm_conferencia.md) |
| A1.1 | Ponte ticker↔CNPJ | ✅ **371/375 = 98,9%**, zero ambíguo, zero conflito de raiz |
| A1.2 | Leitor do plano de contas | ✅ `CvmChart`, 19 testes; **0 faltas em 5.838 exercícios** |
| A1.3 | Ingestão DFP + ITR, `con` com recuo | ✅ 2.107 recuos, **0 sem DRE** |
| A1.4 | *Point-in-time* por `DT_RECEB` | ✅ `PointInTimeView` prefere a data observada |
| A1.5 | Contagem líquida de tesouraria | ✅ `sharesNetOfTreasury`; falta **ligar ao divisor** (depende de A3) |
| A1.6 | Todos os anos, com deslistadas | ✅ baixador; **60,6% dos exercícios fora do universo vivo** |
| **A1.7** | **Ligar a ingestão ao motor** | ⬜ **novo** — hoje a saída é um JSON paralelo |
| A2 | Curva ANBIMA/Tesouro | ⬜ §2.9 |
| A3 | Ações societárias e preço histórico de deslistada — B3 | ⬜ §1.7, §3.5; **virou pré-requisito da validação** |
| A4 | Proventos por fonte independente | ⬜ §1.2, §2.7; reabrir a decisão 23 é **decisão do orientador** |
| A5 | Taxonomia setorial B3 | ⬜ §1.5, §2.14 |
| A6 | Prazo das outorgas — FRE | ⬜ §2.16 |
| D1 | Quebrar `_evaluateLane` | ⬜ **não feito nesta rodada** — ver abaixo |
| D2 | Camada multi-fonte com procedência | ⬜ é o que o A1.7 exige |

#### O que as lentes disseram, ao final da rodada

Cinco lentes rodadas. **Um achado estrutural aceito, um recusado por
conferência**, o resto inventariado.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 2 estruturais, 1 local | **1 corrigido** ([decisão 68](decisoes/068-falha-de-um-demonstrativo-reprova-a-busca.md)), 1 **recusado** |
| `risco` | 1 estrutural, 2 locais | reforça o mesmo defeito; teste acrescentado |
| `nucleo` | 0 estruturais, 2 locais, 1 polimento | inventariado — Fase 3 |
| `metodo` | 2 estruturais | é o B1, e depende de medição — Fase 3 |
| `registro` | — | sem tensões |

**Aceito.** `fundamentalsHistory` devolvia `Ok` quando **algum** dos quatro
endpoints respondia. Falha na DRE produzia série com balanço preenchido e
resultado ausente — a forma que a decisão 52 trata como "ausência não é zero"
—, e o repositório **grava isso no cache**, de modo que a corrupção sobrevivia
à falha de rede. Pior: o filtro downstream a transformava em "histórico
curto", e um 503 aparecia como ativo inelegível.

**Recusado por conferência.** A mesma lente pediu inverter a ordem dos
interceptors, para que a espera da repetição ficasse fora do slot do
limitador. `ThrottleInterceptor` libera o slot no `onError` e está registrado
**antes** do `RetryInterceptor`: a liberação já acontece primeiro, e a
inversão proposta **criaria** o defeito descrito.

**Adiado com razão.** A `metodo` quer reintroduzir `impliedIrr` e reverter o
estimador transversal da decisão 58. Isso é o **B1** — a pergunta de o que o
potencial serve —, e a §0 mostrou que ela é real. Mas reverter para o IRR
implícito não é obviamente a resposta, e a régua desta rodada é medir antes.

#### Itens que entraram durante a execução

**A1.7 — ligar a ingestão ao motor.** A ingestão produz
`data/cvm_exercicios.json` e o motor continua lendo a brapi. Ligar as duas
exige o D2 (procedência por campo), e é o que transforma todo o trabalho
acima em mudança de resultado. **É o próximo item de maior alavancagem.**

**A3 mudou de posição.** Os 3.537 exercícios de companhias deslistadas não têm
ticker nem série de preço, e sem preço não há retorno a confrontar. O A3
deixou de ser item de higiene e virou **pré-requisito** de C1b — a amostra sem
viés de sobrevivência só existe com preço histórico das deslistadas.

**D1 não foi feito, e a razão é honesta.** O plano dizia "D1 antes de A1.3,
porque a ingestão vai acrescentar caminhos a `_evaluateLane`". Executando, o
acoplamento revelou-se mais fraco do que eu supus: a ingestão acrescenta
**campos** a `FundamentalsSnapshot`, e não caminhos à cascata. `_evaluateLane`
segue com 1.087 linhas e segue sendo o maior risco estrutural — mas misturar
a refatoração dele com a ingestão teria piorado as duas. Fica na Fase 1, antes
do A1.7, que é quando os caminhos de fato mudam.

### Fase 2 — validação, sobre a base completa

| # | item |
|---|---|
| C2 | Cobertura da banda fora da amostra — **incerteza calibrada** |
| C0 | O que as recusas custam |
| C1a | Erro-padrão para janelas sobrepostas |
| C1b | Amostra com deslistadas (vem do A1.6) |
| C1c | Coortes **trimestrais** (vem do A1.3) |
| C1 | Reexecutar a habilidade — **o alvo** |

### Fase 3 — método e nível

B1 (o que o potencial serve), B2, B3, B4, B5, B6, C4, D3.

**A exceção à sequência:** o defeito que a §0 expõe está **em produção** — a
tela de metas ordena por um potencial que não bate um fator de uma linha.
Isso não precisa esperar o eixo A. Recomendo declarar a ressalva na tela agora
e decidir o B1 quando a habilidade for remedida sobre a base nova.

---

## 7. Critério de parada

**Valuation exemplar** — o preço justo de um ativo é defensável linha a linha:

- [ ] Nenhum defeito conhecido em aberto *(a tesouraria do A1.5 tem tratamento; falta **ligá-la ao divisor**, que depende do A3)*
- [ ] Insumos de fonte primária, com procedência declarada *(A1 **construído**; falta A1.7 ligar, mais A3 e A4)*
- [ ] Curva de desconto observada, não interpolada *(A2)*
- [ ] Horizonte compatível com o contrato onde há contrato *(A6)*
- [ ] Segunda leitura por múltiplos *(B5)*

**Motor de referência** — as três condições combinadas:

- [x] **Nenhum defeito conhecido** — atingido em 11/09/2026, 66 decisões
- [ ] **Incerteza calibrada** — não medida *(C2)*
- [ ] **Habilidade comprovada** — **medida e reprovada** *(C1: t = +0,24 em 12m, +1,16 em 36m, condicionado ao B/M)*

A primeira condição estava certa, e as outras duas não estavam medidas. Agora
uma delas está, e o resultado é negativo. **Isso é progresso**: um alvo que não
se sabia estar longe passou a ter distância conhecida.

---

## 8. O que pode dar errado

**A distância pode não fechar.** É possível que um DCF sobre fundamento anual
brasileiro simplesmente não bata um fator de valor, e que a resposta certa seja
a opção (a) da B1 — o DCF como produto de análise individual, e a ordenação
saindo de um modelo declarado. Se for isso, o registro deve dizê-lo, e a
monografia fica mais forte por dizê-lo do que por escondê-lo.

**A CVM pode custar muito mais do que parece.** O casamento CNPJ↔ticker,
reapresentações, mudanças de layout entre anos e a diferença entre consolidado
e individual são trabalho real. O item 3 da ordem pode ser mais longo que os
outros sete somados.

**A amostra pode continuar pequena demais para decidir.** Com coortes anuais
sobrepostas, o `n` efetivo é pequeno. Coortes trimestrais e as deslistadas
ajudam, mas o mercado brasileiro tem o tamanho que tem.
