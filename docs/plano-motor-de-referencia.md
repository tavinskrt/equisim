# Plano para o motor de referência

Análise completa do motor em 11/09/2026, e o que falta para dois objetivos
distintos: **valuation exemplar** (o preço justo de um ativo é defensável) e
**motor de referência** (nenhum defeito conhecido + incerteza calibrada +
habilidade comprovada).

Este documento substitui as listas parciais das rodadas anteriores. Ele é
reordenado por uma medição feita hoje, que muda a prioridade de tudo.

> **Última atualização: 14/09/2026, à tarde**, na rodada de A1.10 a A3 — que
> **fecha o eixo A da Fase 1** até A3, com A4 a A6 fora do escopo autorizado.
> A rodada da manhã (A1.8 a A3, viabilidade do D1) segue registrada abaixo. O
> estado de cada item está na §6; o efeito somado da Fase 1 sobre o motor, em
> [fase1_padrao.md](validacao/fase1_padrao.md).

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

**Estado em 14/09/2026: entregue como capacidade, não ligado.** A ANBIMA não
tem arquivo histórico aberto; o Tesouro Direto tem, desde 2002, no portal de
dados abertos. A curva sai dos prefixados — LTN, cupom zero, e NTN-F —, com
interpolação *flat-forward* e um termo por ano de projeção
([decisão 74](decisoes/074-a-taxa-livre-de-risco-segue-a-curva-observada.md)).
A previsão acima se confirmou nas duas metades: a ordenação quase não se move
(postos 0,9325; **0,9174** na remedição), e o nível se move muito — potencial
mediano de −37,6% para **−48,6%** —, porque a perpetuidade da curva fica 2,9 a
4,5 p.p. acima da média decenal do CDI em todas as coortes de 2021 a 2025. A
auditoria do gate recusou o prazo em dias corridos, e ele passou a dias úteis
da liquidação ([decisão 79](decisoes/079-o-prazo-da-curva-conta-dias-uteis.md)):
conferido contra o PU de 19.171 LTN, 99,13% ao dia, com efeito de até 4,7 bp nos
forwards. Ver
[curva_de_juros.md](validacao/curva_de_juros.md).

### A3. Ações societárias e contagem de papéis — B3

Resolveria §1.7 (as duas contagens, 27 ativos com divisor contestado por até
4.852×), a razão de unidade da decisão 61 e a cegueira do backtest da §3.5.
Onze ativos hoje têm divisor contestado, e **três deles estão entre os oito
primeiros da ordenação**.

**Estado em 14/09/2026: a metade que o preço consegue dar está feita.** O
COTAHIST traz o fechamento **bruto** de todo papel, deslistado inclusive, e o
`DISMES`. `CorporateEvents` infere desdobramento, grupamento e bonificação da
razão entre pregões e ajusta a série
([decisão 75](decisoes/075-eventos-de-acoes-inferidos-do-cotahist.md)); os
retornos ajustados batem com a fonte de mercado em **99,96%** de 118.871 pares.
O que o preço não dá — bonificação pequena, evento com o mercado andando junto
— e as duas outras metades viraram A3.1 a A3.3 na §6. Ver
[b3_cotahist.md](validacao/b3_cotahist.md).

**Estado à tarde: o eixo fechou, e com um achado maior que o item.** O
registro de empresas listadas da B3 dá contagem oficial de ações e eventos com
fator declarado, para 297 de 297 emissores
([decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md)). Ele
mostrou que a regra do maior do divisor errava nos dois sentidos — e que em
**dez ativos a "contagem do exercício" da fonte é o capital autorizado**
(GGBR4 com 4,5 bilhões contra 1,98 emitidas; CSAN3 com 8 contra 3,97; B3SA3 com
7,5 contra 5,05). A contagem oficial passou a arbitrar o divisor, líquida de
tesouraria. O COTAHIST de 2010 a 2026 está baixado, e 164 companhias
deslistadas têm ponte para o preço. Ver
[b3_registro.md](validacao/b3_registro.md) e
[b3_deslistadas.md](validacao/b3_deslistadas.md).

### A4. Proventos por fonte independente — CVM ou B3

Permitiria reabrir a [decisão 23](decisoes/023-remocao-de-proventos.md) com
dado conferido, resolver §1.2 (o `adjustedClose` que erra 9,1%), §2.7 (retorno
de preço) e a não sincronia da decisão 57.

**Reabrir a decisão 23 é decisão do orientador, não minha** — ela foi tomada
por ausência de conferência documental, e a conferência passa a ser possível.

**A fonte existe desde 14/09/2026.** O registro da B3 do item A3.1 traz, por
emissor, os proventos em dinheiro com data-com, rótulo — dividendo, JCP,
rendimento — e valor por ação. Não foi usado: está fora do escopo autorizado, e
a decisão continua sendo do orientador.

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

### D1. `_evaluateLane` tem 1.104 linhas

`compute_valuation.dart` tem **3.163 linhas — 20% do núcleo inteiro** — e um
único método privado, `_evaluateLane`, ocupa as linhas 984 a 2087. Cresceu 17
linhas nesta rodada, com a curva de juros.

Isto não é estética. O padrão que se repetiu em todas as rodadas deste ciclo é
que **o motor erra nas costuras, não nas peças** — e as costuras estão dentro
de um método que não pode ser testado em pedaços. Cada defeito das decisões
45–66 esteve na composição, não no endpoint.

Quebrar em passos nomeados e testáveis é o item que mais reduz a chance do
**próximo** defeito.

#### Viabilidade, analisada em 14/09/2026

**É viável agora, e não era antes.** A objeção da rodada do A1.3 era de ordem:
refatorar a cascata enquanto a ingestão mudava o que entra nela misturaria duas
mudanças que se escondem uma na outra. Com o A1.7 validado — 127 avaliados
antes e depois —, o que entra na cascata está estável, e a condição que falta
é poder provar que a refatoração **não mudou nenhum número**.

**Essa prova existe.** O núcleo é determinístico por regra, então a igualdade
é verificável ao bit. `tool/gabarito_cascata.dart` grava a saída completa do
universo — valor justo em centavos, potencial e taxas pela representação que
volta ao mesmo `double`, cenários, avisos e o diagnóstico inteiro — em duas
montagens por ativo, a dos dois pontos e a da curva, e o modo `--conferir`
refaz e compara. Cobre **127 avaliados × 2 montagens**, as duas vias (FCFF e
lucro), a migração de via, e **9 caminhos de recusa distintos**.

**Resultado: idêntico.** Gravado e conferido em 14/09/2026 em duas execuções
seguidas, sobre o código de hoje: **375 ativos, duas montagens cada, saída
completa bit a bit**. E a igualdade é informativa, não vazia — as duas
montagens do mesmo ativo diferem entre si em **127 de 127** avaliados, e o
valor justo em centavos em 125: o gabarito enxerga uma mudança na taxa livre
de risco, e portanto enxergaria a de uma refatoração que errasse.

**A ressalva, que muda o procedimento.** O gabarito congela a **saída**, e não
a entrada. A entrada vem do cache da validação, que expira, e do Ibovespa, que
`ValidationContext` busca **sem cache** a cada execução. A igualdade acima
prova estabilidade no intervalo entre as duas execuções, não entre dias. Por
isso o arquivo não é versionado, e o D1 segue três regras: **gravar
imediatamente antes** da série de passos; **conferir primeiro o código
intacto**, como controle — divergência ali é dado, não refatoração; e, se a
série durar dias, gravar de novo no começo de cada uma.

**Os nove estágios, e o estado que atravessa as fronteiras.** A contagem é por
variável local declarada num estágio e lida num posterior — limite inferior,
porque `local` e `warnings` são listas mutadas por todos.

| estágio | linhas | locais que atravessam |
|---|---:|---:|
| Saída 1 — a base | 166 | 7 |
| Saída 2 — a taxa | 42 | 2 |
| Premissas | 184 | 9 |
| Fluxo-base | 75 | 2 |
| Custo realavancado (dec. 41) | 21 | 4 |
| Quem resolve o Ke (dec. 46) | 206 | 1 |
| Rota do capital próprio (dec. 43) | 29 | 3 |
| Estrutura recusada (dec. 45) | 108 | 1 |
| Pós-condição — a ponte | 239 | 0 |

**29 locais atravessam fronteira**, mais duas listas mutáveis e **uma
recursão**: a estrutura recusada chama `_evaluateLane` de novo, na outra via.
Quebrar não é recortar texto: cada estágio vira função com entrada e saída
declaradas, e as 29 variáveis viram quatro ou cinco *records*.

**A ordem recomendada** é das pontas para o meio, onde o acoplamento é menor:

1. **A ponte** — não entrega nada adiante.
2. **A taxa** — dois valores de saída.
3. **O fluxo-base** — dois valores de saída.
4. **A estrutura recusada** — um valor de saída, mas contém a recursão; ela
   passa a ser uma decisão devolvida ao chamador, e não uma chamada interna.
5. **A base e as premissas**, que são os dois maiores exportadores.
6. **O custo realavancado e o Ke** por último: quatro saídas num estágio de 21
   linhas é o sinal de que a fronteira atual está no lugar errado.

**Cada passo é um commit que passa no gabarito.** Um passo que muda um bit
não entra, por menor que seja — é o que separa refatoração de mudança de
método, e a regra de preservação exige decisão para a segunda.

**O que o gabarito não cobre.** O modo Monte Carlo, que fica em
`scenario_engine`, fora do método; a série da CVM e a ancorada, que exercitam
as guardas com outros dados; e o que não está no universo de hoje. Os 220
testes de `usecases_test`, `valuation_guards_test` e `audit_test` cobrem casos
sintéticos e continuam obrigatórios. Antes de começar, vale acrescentar ao
gabarito a montagem com a CVM — é uma terceira chamada, e amplia a cobertura
das guardas com dado real.

**Recomendação: fazer o D1 como o primeiro item da Fase 2**, antes do C2. A
validação vai instrumentar a cascata — a cobertura da banda precisa dos
cenários, a coorte trimestral precisa rodar o motor milhares de vezes —, e
instrumentar um método de 1.104 linhas é o jeito mais barato de criar o
próximo defeito de costura.

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
> [cvm_ingestao.md](validacao/cvm_ingestao.md). **A1.7 a A3 executados em
> 14/09/2026 de manhã**, com a análise de viabilidade do D1. **A1.10 a A3
> executados à tarde**: o eixo A está estável até A3. Entraram A2.2, A3.4, B9 e
> B10.

| # | item | estado |
|---|---|---|
| A1.0 | Conferência de campos | ✅ [cvm_conferencia.md](validacao/cvm_conferencia.md) |
| A1.1 | Ponte ticker↔CNPJ | ✅ **371/375 = 98,9%**, zero ambíguo, zero conflito de raiz |
| A1.2 | Leitor do plano de contas | ✅ `CvmChart`, 19 testes; **0 faltas em 5.838 exercícios** |
| A1.3 | Ingestão DFP + ITR, `con` com recuo | ✅ 2.107 recuos, **0 sem DRE** |
| A1.4 | *Point-in-time* por `DT_RECEB` | ✅ `PointInTimeView` prefere a data observada |
| A1.5 | Contagem líquida de tesouraria | ✅ **ligada ao divisor** pela contagem oficial da B3, pela fração — [decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md) |
| A1.6 | Todos os anos, com deslistadas | ✅ baixador; **60,6% dos exercícios fora do universo vivo** |
| A1.7 | Ligar a ingestão ao motor | ✅ **mescla com procedência**; refeito nesta rodada sem os artefatos de exercício fora do calendário: 127 → 128 avaliados, mediana do Δ em 0,0% |
| A1.8 | Série trimestral no motor | ✅ **capacidade** — doze meses ancorados no trimestre, 16 testes; **não é o padrão** (postos **0,683** contra a anual, remedido pela [decisão 78](decisoes/078-a-mescla-nao-empresta-fluxo-de-outra-janela.md)) — [decisão 73](decisoes/073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md) |
| A1.9 | Levar a ligação ao aplicativo | ✅ pacote de 371 tickers (8,9 MB; 1,5 MB comprimido) e repositório decorador — [decisão 76](decisoes/076-a-cvm-chega-ao-aplicativo-por-pacote.md) |
| A1.10 | O pacote no processo de build | ✅ **pacote versionado**, por decisão sua; teste que reprova a suíte sem ele; a ausência vira ressalva na avaliação — [decisão 80](decisoes/080-o-pacote-da-cvm-e-versionado-e-a-ausencia-aparece.md) |
| A1.11 | A cascata lê o patrimônio da CVM | ✅ VPA derivado do PL da CVM; a base de mercado **já era** o PL consolidado em 99,4%, e o que muda é o ponto de junho (postos anual × ancorada 0,683 → 0,737) e cinco ativos — [decisão 81](decisoes/081-a-base-de-patrimonio-e-o-pl-da-cvm.md). Revelou a ponte errada da MBRF3 — [decisão 82](decisoes/082-a-ponte-comeca-pelo-registro-oficial-da-b3.md) |
| A2 | Curva de juros observada | ✅ **capacidade** — Tesouro prefixado, *flat-forward*, 13 testes; **o padrão é decisão sua** — [decisão 74](decisoes/074-a-taxa-livre-de-risco-segue-a-curva-observada.md) |
| A2.1 | Curva no aplicativo, e a decisão do padrão | ✅ **a curva é o padrão**, por decisão sua; nativo lê só o começo do arquivo do Tesouro, web pela função `tesouro`, recuo para o pacote e depois para os dois pontos, declarado — [decisão 84](decisoes/084-a-curva-e-o-padrao-do-aplicativo.md) |
| **A2.2** | **Publicar a função `tesouro`** | ⬜ **novo, ação sua** — `firebase deploy --only functions` e o `TESOURO_PROXY_URL` no build web. Até lá, a web usa a curva do pacote, que vale uma semana |
| A3 | Eventos de ações e contagem de papéis | ✅ inferência pelo preço ([decisão 75](decisoes/075-eventos-de-acoes-inferidos-do-cotahist.md)) e registro oficial — com o teto da inferência **medido contra o registro**: 41,5% dos eventos oficiais encontrados, 63,8% dos inferidos confirmados |
| A3.1 | Registro oficial de eventos da B3 | ✅ 297 de 297 emissores; convenção do fator medida, eventos da mesma data compostos, **93,4% de 243 batem com o preço a 15%** — [b3_registro.md](validacao/b3_registro.md) |
| A3.2 | COTAHIST inteiro e ponte das deslistadas | ✅ 2010 a 2026, 1,63 milhão de pregões; **164 de 290** companhias deslistadas com ação em bolsa ligadas ao preço, 1.272 exercícios — [b3_deslistadas.md](validacao/b3_deslistadas.md) |
| A3.3 | Eventos no divisor por papel | ✅ **a contagem oficial arbitra o divisor**, líquida de tesouraria, e o WACC estático pondera por ela; potencial mediano −37,6% → −28,7% com postos 0,982 — [decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md) |
| **A3.4** | **Evento e contagem por data para as deslistadas** | ⬜ **novo** — a ponte do A3.2 dá preço bruto; a coorte precisa do ajuste por evento, que para deslistada só a inferência dá (com o teto acima), e da contagem de ações na data, que a CVM dá sem escala. **É o que falta ao C1b** |
| A4 | Proventos por fonte independente | ⬜ §1.2, §2.7; reabrir a decisão 23 é **decisão do orientador** |
| A5 | Taxonomia setorial B3 | ⬜ §1.5, §2.14 |
| A6 | Prazo das outorgas — FRE | ⬜ §2.16 |
| D1 | Quebrar `_evaluateLane` | 🟨 **viável** — gabarito ao bit construído; **recomendado como primeiro item da Fase 2** (§5). O gabarito da manhã ficou velho com as decisões 81, 83 e 84: gravar de novo antes de começar, como o procedimento já manda |
| D2 | Camada multi-fonte com procedência | ✅ `FundamentalsProvenance`, campo a campo |

#### O que a rodada de A1.10 a A3 encontrou

> Registro completo em [b3_registro.md](validacao/b3_registro.md),
> [b3_deslistadas.md](validacao/b3_deslistadas.md) e
> [fase1_padrao.md](validacao/fase1_padrao.md).

**Três decisões eram suas, e foram tomadas no início da rodada:** a curva é o
padrão do aplicativo, o pacote da CVM é versionado, e a web busca a curva por
função de nuvem.

**O divisor por papel estava errado em dez ativos grandes, e no sentido
contrário ao que o registro supunha.** A contagem oficial da B3 mostrou que a
"contagem do exercício" da fonte é, nesses dez, o capital autorizado — número
redondo, até 2,28x as ações emitidas. A regra do maior o adotava, e o árbitro
`lucro ÷ LPA` o confirmava porque a fonte calcula o LPA com a mesma contagem.
GGBR4, CSAN3, B3SA3, RENT3, COGN3 estavam todos com o preço justo deprimido.
**E MILS3 e MEAL3, os casos-símbolo da §1.7 das limitações, não eram
grupamento**: a B3 não registra evento nenhum, e a contagem "corrente" da fonte
simplesmente está errada.

**A ponte do A1.1 tinha duas ligações erradas**, nas fusões de 2025: MBRF3 na
BRF em vez da Marfrig, AUAU3 na Petz em vez da União Pet. Apareceu quando o
A1.11 passou a ler o PL da CVM: a MBRF3 foi de −27% a −82% por uma diferença de
5% na base, e a razão era a CVM de uma empresa sobre o mercado de outra. O
registro da B3 dá código CVM por emissor, e a ponte agora começa por ele.

**A validação da decisão 75 media a coisa errada.** Os 99,96% de retornos
diários batendo não diziam quantos eventos a inferência acha, porque evento é
raro no dia. Contra o registro: **41,5%**, e só 63,8% do que ela acha é evento
de fato — parte do resto é cisão (ITUB3 em 2021).

**A1.11 achou menos do que o item supunha.** A base de patrimônio de mercado já
era o PL consolidado da CVM em 99,4% dos exercícios; a CVM muda cinco ativos no
anual, e o ponto de junho da série ancorada.

**A FCA não tem código de negociação de 2010 a 2017**, em nenhuma linha. A
ponte das deslistadas desse período teve de ser por nome, com o nome anterior
que a FCA guarda — revisada à mão, 42 ligações.

**A Fase 1 inteira move a ordenação o bastante para que a §0 precise ser
refeita.** Na mesma execução, da montagem de antes ao padrão do aplicativo:
potencial mediano de −37,5% a −48,2%, correlação de postos de **0,884**, 76
ativos movendo mais de 10 p.p. Nada disso é habilidade: é o motor sobre o qual
o C1 tem de rodar.

**E uma descontinuidade do método.** Na PRIO3, a curva — mais alta que os dois
pontos em quase todo ano — **sobe** o potencial de −80,6% para −18,3%: a
perpetuidade maior leva o capital próprio a 14,4% do valor da firma, e a
cascata migra para a via do acionista, que vale mais. Taxa maior não deveria dar
preço justo maior. Virou o **B10**.

#### O que as lentes disseram na rodada de A1.10 a A3

Cinco lentes, sobre o staging da rodada. **Um estrutural da `metodo` aceito e
corrigido**, um da `dados` e dois da `risco` aceitos e corrigidos, um da
`registro` aceito na forma do precedente e outro recusado por verificação.

| lente | achados | o que foi feito |
|---|---|---|
| `metodo` | 1 estrutural, 1 local | estrutural **corrigido** — o WACC estático readquiria o `marketCap` da fonte depois de a ponte arbitrar a contagem (decisão 83); local vira o **B9** |
| `dados` | 1 local | **corrigido** — snapshot corrente vazio deixava o valor de mercado da linha anual no lugar |
| `risco` | 3 locais | **2 corrigidos** com teste — falha do mercado no repositório da CVM, cache vencido de fundamentos —, 1 de tela vai para o **D3** |
| `nucleo` | 2 estruturais, 2 locais | inventariado — construtor de `Portfolio`, listas paralelas no diagnóstico, nomes; código anterior à rodada |
| `registro` | 2 estruturais | **1 aceito** pela decisão 85, no caminho da 26; **1 recusado** — `refinamento-do-valuation.md` existe, com 120 KB |

**Aceito e corrigido — o peso do capital próprio no WACC.** `_wacc` usava
`latest.marketCap` sempre que existia. Com a fonte errando a contagem, o valor
de mercado erra junto, e o WACC readquiria o erro que a ponte acabava de
arbitrar. O teste reproduz 1,07 p.p. de WACC com valor de mercado 2,6x errado.

**Aceito — a substituição que a decisão 23 não pôde declarar.** A 23 derrubou as
decisões 12, 16, 17 e 18 no corpo, sem o campo `substitui`, porque o gate não o
aceitava na época. A decisão 26 tirou o impedimento e fez o mesmo pela 14. A
[decisão 85](decisoes/085-a-substituicao-das-decisoes-12-16-17-e-18-pela-23-e-declarada.md)
faz pela 23, sem editá-la.

**Recusado por verificação.** A `registro` disse que a decisão 25 cita um
documento que não existe. `docs/refinamento-do-valuation.md` existe, tem 120 KB e
a tabela P1 a P13. A lente não o recebeu no material.

#### O que a auditoria do gate disse na rodada de A1.10 a A3

**O staging das duas rodadas passou do teto do auditor.** Com 60 arquivos, o
material bateu nos 180 mil caracteres, foi truncado, e o `agy` respondeu vazio
duas vezes — código 2, falha de infraestrutura. Sem poder fazer commit, a
auditoria foi feita em grupos pelo índice: núcleo com seus testes, e aplicativo
com ferramentas, função e scripts.

- **Núcleo: aprovado, 0 FAIL / 0 WARN / 0 INFO.**
- **Aplicativo, ferramentas e função: reprovado na primeira passada com 3 FAIL**,
  todos nas ferramentas de medição — empate de postos comparado com `==`,
  variância comparada com `== 0`, correlação sem guarda de denominador. Corrigidos,
  **aprovado com 2 WARN e 1 INFO**: diferença de dias em hora local, sujeita ao
  horário de verão, no COTAHIST e na conferência de eventos. Eram código desta
  sessão, e foram corrigidos também — no detector do núcleo inclusive.

**E o gate local tinha um defeito de leitura.** O leitor da tabela congelada do
`PLANO_ARQUITETURA.md` só reconhecia linha que começa em `|` com número sem
negrito. As decisões 0 a 8 estão dentro de uma citação (`> |`) e a 0 e a 18 em
negrito: dez das dezenove ficavam de fora, e a decisão 85 foi bloqueada por citar
a 18. A expressão passou a aceitar os dois formatos, e lê exatamente 0 a 18.

#### O que a rodada de A1.8 a A3 encontrou

> Registro completo em [cvm_trimestral.md](validacao/cvm_trimestral.md),
> [curva_de_juros.md](validacao/curva_de_juros.md) e
> [b3_cotahist.md](validacao/b3_cotahist.md).

**Um defeito da rodada anterior, achado ao construir a de agora.** O ITR traz,
no segundo e no terceiro trimestres, **duas linhas por conta** na DRE — o
trimestre e o acumulado do ano — com o mesmo `ORDEM_EXERC`. A ingestão ficava
com a primeira que aparecesse. **19.237 dos 29.218 ITRs** tinham a duplicação.
No A1.7 ela só entrava pelo defeito seguinte; a série de doze meses teria
somado trimestre com acumulado em todo o universo
([decisão 72](decisoes/072-a-ingestao-le-o-periodo-e-o-tipo-do-documento.md)).

**Uma atribuição da rodada anterior, corrigida.** O A1.7 classificava como
anual o exercício que termina em dezembro. Companhia de exercício fora do
calendário — AGRO3 em junho, SMTO3, JALL3 e RAIZ4 em março, CAML3 em
fevereiro — tinha o ITR de dezembro lido como ano cheio. **O SMTO3 (−45,2 p.p.)
e o AGRO3 (−5,6 p.p.) da tabela do A1.7 eram artefato disso**, e não efeito da
CVM; refeita a medição, o SMTO3 move −0,9 p.p. A ingestão passou a ler o tipo do documento, e não o mês.

**O lucro por ação da CVM sai da mescla.** A conta 3.99 vem **zerada em 14.684
dos 15.206** exercícios que a trazem, e zero sobrescrevia o LPA da fonte de
mercado — que é o árbitro da contagem de ações da §1.7. Passou a ser campo só
de mercado.

**A fonte tem buraco.** A CVM não publica o ITR de 2025 (404). A primeira
versão da série ancorada leu 2024 → 2026 como um ano, e a QUAL3 foi de −22% a
**+908%**. A série agora recua para DFP quando há buraco, e o baixador lista o
que falta. Hoje, **toda série recua** — o que é o comportamento certo, e quer
dizer que o A1.8 não tem efeito até a CVM publicar o arquivo. Ver limitações
§1.10.

**O motor é sensível à janela do exercício** — correlação de postos de
**0,683** entre a ordenação anual e a ancorada no trimestre, depois da
decisão 78 (0,816 na medição com o defeito da mescla). Não é defeito da soma,
conferido no caso extremo (CSNA3); é consistente com a §0. Ver limitações §3.8,
e é por isso que a série ancorada não é padrão.

**A conferência do COTAHIST mediu a coisa errada primeiro.** Comparado nível
contra nível, o ajuste batia em 68%, com papéis discordando em todos os pregões
e sem evento algum — a fonte de mercado ajusta até **hoje**, e com anos
parciais um evento fora da janela vira deslocamento constante. Por retorno
diário, que é invariante a isso, bate em **99,96%**.

**Três itens novos no A3, e um no A2.** A inferência pelo preço tem teto
medido (limitações §3.9) — é o **A3.1**. As deslistadas têm demonstrativo e
preço, mas não a ponte entre ISIN e CNPJ — é o **A3.2**, e é o que o C1b
espera. O fator detectado não entra no divisor — é o **A3.3**. E a curva existe
só na ferramenta de validação — é o **A2.1**, junto com a decisão do padrão.

#### O que as lentes disseram na rodada de A1.8 a A3

Cinco lentes, sobre o código em staging. **Dois estruturais da `dados`
conferidos e corrigidos**, um local da `metodo` aceito como limite declarado, e
**dois defeitos achados por revisão própria** enquanto elas rodavam — um deles
no código desta rodada.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 2 estruturais | **os dois corrigidos** ([decisão 77](decisoes/077-o-snapshot-corrente-e-o-ativo-omitido-seguem-a-regra-da-falha.md)); o cache negativo, metade do segundo, fica de fora com razão |
| `metodo` | 1 estrutural, 3 locais | estrutural **já decidido** (62); `CorporateEvents` **aceito** como limite de uso; escudo fiscal **recusado** (37); RONIC = ROIC inventariado no eixo B |
| `nucleo` | 3 estruturais | inventariado — código anterior à rodada, e o `label` dos enums já foi recusado duas vezes |
| `risco` | 4 locais | cobertura de caminho de erro em código anterior — **D3** |
| `registro` | 0 tensões | **o inventário parou de novo na decisão 30** — conferência feita à mão, ver abaixo |

**Aceito e corrigido — o snapshot corrente.** A `dados` apontou que a regra da
decisão 68 parou nos quatro demonstrativos: a busca do snapshot corrente falhava
em silêncio. A conferência achou efeito pior que o descrito — sem o corrente,
cada linha anual fica com o **próprio** `marketCap`, que é o inflado pelo fator
da unit (SAPR11 com R$ 59,9 bi contra R$ 10,1 bi), e isso ia para o cache. E
esses são exatamente os campos que a CVM delega ao mercado no aplicativo.

**Aceito e corrigido — o ativo omitido.** A lente descreveu custo de cota; o
teste reproduziu **perda de dado**: um lote que responde e deixa um ativo de
fora fazia o ativo sumir, com o histórico dele em disco.

**Aceito como limite — `CorporateEvents`.** A lente diz que bonificação pequena
vira prejuízo falso na carteira. Hoje nada no aplicativo lê a série ajustada, e
o prejuízo não acontece; mas aconteceria no dia em que alguém a ligasse a
retorno. A documentação do serviço passou a dizer que ela **não é série de
retorno** até o A3.1.

**Recusado — o escudo fiscal.** A lente quer o escudo do WACC na alíquota
estrutural. A [decisão 37](decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md)
tratou disso: a dedutibilidade do juro vale na margem, e a margem é a alíquota
cheia.

**Já decidido — retorno total contra simulação de preço.** A
[decisão 62](decisoes/062-o-esperado-e-retorno-total-e-nao-pede-yield.md)
declarou o esperado como retorno total e removeu o *yield* que o duplicava. O
*backtest* histórico de preço é outra régua, e a reabertura dos proventos é o A4.

**O alcance da `registro`, de novo.** Recebeu 66 blocos, incluídas as decisões
72 a 76, e inventariou até a 30. **Duas rodadas seguidas**: o "sem tensões"
dela nunca cobre as decisões deste ciclo. Conferido à mão: todo identificador
citado nas decisões 72 a 76 existe no código, e as constantes citadas batem
(`minDesvio` 0,19, `maxDiasEntrePregoes` 7, `diasDeRecuo` 7). O conserto da
lente é trabalho à parte, nos arquivos de regra dela.

**Achado por revisão própria — a mescla misturava janelas.** A série ancorada
completava um ponto de doze meses até junho com o exercício de mercado de
dezembro: a despesa de juros de outra janela ia para o custo da dívida, o NOPAT
publicado de outra janela vencia o derivado do EBIT, e o LPA de outro lucro
entrava no árbitro da contagem. **A medição do A1.8 foi feita com esse
defeito** — ver [decisão 78](decisoes/078-a-mescla-nao-empresta-fluxo-de-outra-janela.md)
e a remedição.

**Achado ao investigar a remedição — documento do futuro apagava o ano.** A
USIM3 foi de "ancorada = anual" para "ancorada = só mercado" com a correção, o
que ela não explicava. A DFP de 2023 foi reapresentada, e a versão ingerida tem
recebimento em 16/01/2025; em 04/09/2024 o caminho anual a mesclava mesmo
assim, descartava o exercício de mercado de 2023 — publicado de fato — e a
cascata removia o ponto mesclado por ser do futuro. **O ano sumia.** USIM3
(−47 p.p.) e USIM5 (−42 p.p.) da lista de movimentos do A1.7 em 2024 eram isso.
Corrigido na decisão 78; a correção certa do dado é o B8.

**Achado por revisão própria — o pacote era decodificado por chamada.** O
repositório da CVM guardava o resultado, e não a leitura em curso: avaliações
simultâneas decodificavam os 9 MB cada uma. Corrigido na decisão 77.

**Achado ao corrigir o anterior — a cascata não lê o patrimônio da CVM.** A
primeira versão da regra da mescla também recusava emprestar o VPA e a contagem
do exercício, e **106 de 113 avaliados** da série ancorada foram recusados como
insolventes, com R$ 20 bi de PL na própria linha. A base de patrimônio da
cascata é `VPA × contagem do exercício`, sempre; o `totalStockholderEquity` que
a CVM traz não é lido. Virou o **A1.11**.

#### O que a auditoria do gate disse

**Reprovado na primeira passada, com 4 FAIL**, todos conferidos e corrigidos
([decisão 79](decisoes/079-o-prazo-da-curva-conta-dias-uteis.md)):

- **Prazo da curva em dias corridos para taxa na base 252** (R9). Estava
  declarado como aproximação de "fração de ponto base", sem medição. Medido
  contra o PU do próprio Tesouro, a convenção certa é **dias úteis da
  liquidação, pelo calendário conhecido na data-base** — o 20 de novembro só
  entra para quem já conhecia a lei de 2023 —, e bate ao dia em 99,13% de 19.171
  LTN. O efeito na taxa é de até 4,7 bp; a declaração subestimava o erro, e o
  motor ganhou um calendário de dias úteis que não tinha.
- **`double` como chave de mapa, elemento de conjunto e operando de `==`**
  (R6), na curva, nos fatores de evento e no codec do pacote. Nenhum produzia
  número errado hoje.

**O gabarito do D1 gravado nesta rodada fica velho** na montagem da curva, que
mudou em até 4,7 bp. Não altera a análise de viabilidade: o procedimento já
manda gravar de novo imediatamente antes de começar.

#### O que as lentes disseram na rodada do A1.7

Cinco lentes. **Um estrutural aceito e corrigido**, um recusado por
conferência, o resto inventariado para a Fase 3.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 1 estrutural, 1 local | **corrigido** ([decisão 71](decisoes/071-a-validade-do-cache-macro-nao-cobre-a-janela.md)) |
| `nucleo` | 2 estruturais, 1 local | inventariado — são B/D, e um deles já foi recusado antes |
| `metodo` | 1 estrutural, 1 local | é o **B1** |
| `risco` | 1 estrutural, 1 local | cobertura — **D3** |
| `registro` | 0 tensões | **mas leu só as decisões 0 a 30** — ver abaixo |

**A ressalva do `registro`.** Ele voltou com "nenhuma tensão", e o relatório
declara ter examinado *"as decisões 0 a 30"*. **São 71 hoje.** O aval dele
cobre o terço mais antigo do registro, e não as decisões 31 a 71 — que são
justamente as deste ciclo. Não é achado nem contra-indicação; é um limite de
alcance que o quadro esconderia se ficasse só em "sem tensões".

**Aceito.** A validade do cache macro é por **série** e o recorte é por
**janela**, e as duas não conversavam: um gráfico de três meses de CDI marcava
a série como fresca, e a simulação de dez anos recebia os três meses **achando
que recebeu dez anos**. O CAGR decenal, a taxa de equilíbrio da estrutura a
termo e o Sharpe sairiam apurados sobre um trimestre, sem aviso. O caminho
normal passa a exigir cobertura do início; o degradado continua aceitando o que
houver.

**Recusado.** A `nucleo` voltou a pedir a remoção do `label` dos enums do
domínio. Os avisos da cascata são narrativa econômica em português **por
construção** — é o que a tela mostra e o que a auditoria registra —, e a
proposta trataria isso como vazamento de apresentação. Já inventariado.

#### O que as lentes disseram na rodada anterior

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
| D1 | Quebrar `_evaluateLane`, passo a passo contra o gabarito — **antes de a validação instrumentar a cascata** |
| C2 | Cobertura da banda fora da amostra — **incerteza calibrada** |
| C0 | O que as recusas custam |
| C1a | Erro-padrão para janelas sobrepostas |
| C1b | Amostra com deslistadas — preço e ponte prontos (A3.2); **exige o A3.4** |
| C1c | Coortes **trimestrais** (vem do A1.8) — **decide se a série ancorada vira padrão** |
| C1 | Reexecutar a habilidade — **o alvo**, sobre o motor da Fase 1, que moveu a ordenação (postos 0,884 contra o de antes) |

### Fase 3 — método e nível

> **Detalhada em 11/09/2026**, a pedido: a lista faseada trazia o eixo B só por
> sigla. Os itens estão descritos na §3; aqui está a ordem e o estado.

| # | item | por que, e o que decide |
|---|---|---|
| **B1** | **O que o potencial serve** | É **decisão sua**, não trabalho meu, e destrava o resto. A §0 mostrou que a ordenação do motor não acrescenta ao book-to-market; a `metodo` propõe reverter ao IRR implícito. Três saídas: o DCF é o produto e a ordenação sai de outro modelo; o DCF tem de ganhar; ou os dois medidos lado a lado. **Recomendo o terceiro**, com o primeiro implantado enquanto o segundo é perseguido |
| **B2** | Potencial ortogonalizado como produto | Transforma a §0 de acusação em **métrica de acompanhamento**: o resíduo do potencial contra o B/M é o que o DCF sabe que o valor patrimonial não sabe. Hoje vale +0,0394 em 36 meses |
| **B6** | Horizonte de projeção | Fixo em dez anos para todo mundo, sem medição. É o item **mais barato** do eixo: uma varredura de 5 a 20 anos sobre o universo, sem dado novo |
| **B3** | Prêmio de risco deixa de ser parâmetro | 5,5% fixo (§2.2). Move o **nível** de todos juntos, e quase nada na ordenação — é "exemplar", não "referência" |
| **B4** | Risco-país e o que falta no custo de capital | Não há prêmio de risco-país nem ajuste por tamanho. CAPM de fator único é defensável numa monografia e fraco num motor de referência |
| **B5** | Triangulação por múltiplos | Nenhuma avaliação profissional entrega DCF sozinho. Dá a segunda leitura e o teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa |
| **B7** | **Consistência real × nominal** | **Novo.** O motor desconta fluxo nominal a taxa nominal e usa o IPCA só no teto da perpetuidade. Nunca foi conferido que as duas pontas usam a mesma convenção de inflação |
| **B9** | **WACC estático com dívida bruta, e o resolvido com líquida** | **Novo, da lente `metodo`.** O custo de capital realavancado da decisão 41 pondera pela dívida líquida; o WACC estático de recuo, pela bruta, e a ponte desconta a líquida. As duas vias de taxa não usam a mesma convenção, e a diferença cai sobre ativo com muito caixa |
| **B10** | **A migração de via é descontínua** | **Novo.** Na PRIO3, uma curva mais alta levou o capital próprio a 14,4% do valor da firma, a cascata migrou para a via do acionista, e o potencial **subiu** de −80,6% para −18,3%. Taxa maior dando preço justo maior é resposta que um motor de referência não pode ter. Ver [fase1_padrao.md](validacao/fase1_padrao.md) |
| **B8** | **Reapresentação no *point-in-time*** | **Novo.** A ingestão adota a **última versão** de cada documento, e **24,8% dos anuais têm mais de uma**. A data de cada versão está gravada; usá-la é o que torna a coorte honesta. **Evidência de 14/09/2026:** a DFP de 2023 da USIM3 foi reapresentada e a versão ingerida tem recebimento em 16/01/2025 — em 04/09/2024 o ano ficava sem CVM, e a decisão 78 o devolveu ao mercado em vez da versão original |

Fecham a fase os itens de higiene: **C4** (custos de transação) e **D3**
(cobertura apontada pela lente `risco`).

**A ordem tem uma razão.** B1 primeiro porque é decisão e porque o defeito que
ela resolve está **em produção**. B2 e B6 depois porque não precisam de dado
novo. B3 a B5 por último dentro da fase, porque movem nível e não ordenação —
e é a ordenação que a §0 mostrou estar em dívida.

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
