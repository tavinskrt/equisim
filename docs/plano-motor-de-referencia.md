# Plano para o motor de referência

O que falta para dois objetivos distintos, item a item, com o critério que diz
quando cada um está pronto. **Este documento é mantido atualizado a cada
rodada**: a §6 traz o estado e o *pronto se* de cada item, e a §7 diz, com a
mesma régua, onde cada objetivo está. O que cada rodada encontrou, o que as
lentes disseram e o que a auditoria reprovou ficam no
[histórico](plano-motor-de-referencia-historico.md).

> **Última atualização: 14/09/2026, fim da Fase 1.** O eixo A fechou: A3.4, A4,
> A5 e A6 conferidos no código e medidos na mesma execução
> ([fase1_padrao.md](validacao/fase1_padrao.md)). O orientador reabriu a decisão
> 23, e provento voltou como dado conferido da B3 no beta e nas coortes
> ([decisão 89](decisoes/089-proventos-voltam-como-dado-conferido.md)). A lente
> `metodo` achou um erro no A6 antes do commit — o terminal neutro perpetua o
> excedente do capital existente —, corrigido. Dois itens entraram: **B11**, o
> aplicativo não resolve o prior do beta, e **B12**, o excedente perpétuo fora
> das concessões, e **B13**, a discordância das vias que a decisão 39 declarou
> defeito e a revisão anterior não listou. A5 saiu dos defeitos abertos; B11 e
> B13 entraram.

## Os dois objetivos

**Valuation exemplar** — o que também chamamos de *valuation perfeito*: o preço
justo de **um** ativo é defensável linha a linha. Cada insumo tem fonte primária
e procedência, cada premissa é observada ou declarada, e o número responde ao
que muda no mundo no sentido que a teoria diz.

**Motor de referência** — a **ordenação** do universo é confiável, e o motor
sabe o quanto não sabe. Três condições, todas necessárias:

| | condição | como se mede |
|---|---|---|
| **R1** | Nenhum defeito conhecido | zero itens abertos com `R1` na coluna *serve a* da §6 — os marcados `R1 prevenção` reduzem a chance do próximo defeito e não contam |
| **R2** | Incerteza calibrada | cobertura fora da amostra da banda de cenários a até 5 p.p. da frequência nominal, em 12 e 36 meses (C2) |
| **R3** | Habilidade comprovada | `t` do potencial condicionado ao book-to-market acima de 2 em 36 meses, com erro-padrão para janelas sobrepostas e amostra sem viés de sobrevivência, sobre a montagem padrão do aplicativo (C1) |

**Os dois não são o mesmo.** Um DCF pode ser exemplar sobre um ativo e ainda
assim ordenar mal a seção — a §0 mostra que era o caso. Item de nível (prêmio de
risco, curva) serve ao exemplar e quase não mexe na ordenação; item de amostra
(deslistadas, coortes) serve à referência e não muda preço justo nenhum.

**Na coluna *serve a* da §6**, `E` é valuation exemplar e `R1`, `R2` e `R3` são as
condições do motor de referência. Item que não serve a nenhum dos dois não entra
na lista — ver o fim da §6.

---

## 0. O fato que reorganiza a lista

> **Medido em 11/09/2026, sobre o motor daquele dia.** A Fase 1 moveu a
> ordenação — correlação de postos de 0,849 entre o motor de antes e o padrão
> atual do aplicativo ([fase1_padrao.md](validacao/fase1_padrao.md)) —, e a
> medição tem de ser refeita: é o C1. Os números abaixo são o ponto de partida,
> não o estado.

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

**Estado: tratado desde 14/09/2026.** O divisor oficial desconta a fração em
tesouraria — 62 emissores com mais de 1%, mediana de 2,45%, máximo de 53,1%
([decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md)).

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

**Estado: é o padrão do aplicativo** desde 14/09/2026, por decisão do usuário
([decisão 84](decisoes/084-a-curva-e-o-padrao-do-aplicativo.md)); na web, vem só
do pacote do build, que serve por cerca de uma semana
([decisão 86](decisoes/086-na-web-a-curva-vem-so-do-pacote.md)). A medição que sustentou a decisão: a
ANBIMA não tem arquivo histórico aberto; o Tesouro Direto tem, desde 2002, no portal de
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

**Estado ao fim da Fase 1: o A3.4 fechou.** A contagem de ações por data das
deslistadas vem do Formulário de Referência, em três camadas — aprovação de
capital, evento declarado e formulário que a série não explica —, com os eventos
localizados no preço e os proventos pelo nome de pregão. A escala é conferida
contra a contagem oficial nas listadas (281 de 291 a 1%), contra a composição do
capital nas deslistadas (1.619 de 1.848 a 2%) e pelo P/VPA (860 de 867 na faixa):
160 das 164 companhias têm contagem por data
([decisão 90](decisoes/090-a-contagem-por-data-vem-do-formulario-de-referencia.md),
[b3_contagem_por_data.md](validacao/b3_contagem_por_data.md)).

### A4. Proventos por fonte independente — CVM ou B3

Permitia reabrir a [decisão 23](decisoes/023-remocao-de-proventos.md) com dado
conferido, resolver §1.2 (o `adjustedClose`), §2.7 (retorno de preço) e o
bloqueio de dado da decisão 57.

**Estado: feito, por reabertura do orientador.** A fonte que este item dava como
existente não servia — o registro do A3.1 só traz doze meses de proventos. O
histórico está em outra consulta da B3: 18.651 proventos dos 297 emissores, com o
fechamento com direito, que bate com o COTAHIST em 9.241 de 9.243. O
`adjustedClose` desvia 3,3% na mediana contra ela e continua fora de cálculo.
Provento entra no **retorno total das coortes** e no **beta**, que passa a sair do
retorno total dos dois lados; a simulação, a cascata e o retorno esperado
continuam de preço. Nas coortes do motor de 11/09, o retorno total não muda a
conclusão sobre a habilidade
([decisão 89](decisoes/089-proventos-voltam-como-dado-conferido.md),
[proventos.md](validacao/proventos.md)).

### A5. Taxonomia setorial oficial — B3 ou GICS

§1.5 e §2.14 (BRSR6, PINE4 e SANB4 chegam sem setor e escapam da Porta 1).

**Estado: feito.** O setor de todo ativo é o da classificação oficial da B3, por
emissor — 297 de 297 —, e a Porta 1 entra por subsetor. 51 tickers do universo
mudam de porta, quase todos por chegarem sem setor da fonte
([decisão 87](decisoes/087-o-setor-e-o-da-b3-por-emissor.md),
[b3_classificacao.md](validacao/b3_classificacao.md)).

### A6. Prazo das outorgas — FRE da CVM

§2.16: concessões com horizonte infinito.

**Estado: feito, e com a medição de antes corrigida.** O terminal neutro mantém
para sempre o excedente de retorno do capital existente, e é esse excedente que o
contrato corta: o terminal da concessão com prazo é o capital mais o excedente
até o fim do contrato, e a projeção termina nele quando ele acaba antes. O prazo
é a mediana das outorgas vigentes no Formulário de Referência
([decisão 88](decisoes/088-o-prazo-da-concessao-corta-o-excedente.md),
[outorgas.md](validacao/outorgas.md)).

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

### B1.0. A ressalva na tela de metas

A §0 chamou de **defeito em produção**: a tela de metas ordena a carteira por um
potencial que não bate um fator de uma linha. A recomendação era declarar a
ressalva na tela já, sem esperar o eixo A. **Conferido em 14/09/2026: não foi
feito** — nada em `lib/presentation/goals` diz isso ao usuário.

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
beta. Um CAPM de fator único é defensável num artigo e é fraco como motor
de referência.

### B5. Triangulação por múltiplos

Nenhuma avaliação profissional entrega DCF sozinho. Um múltiplo de pares —
EV/EBITDA, P/L, P/VP setorial — dá uma segunda leitura e, principalmente, um
teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa.

### B6. O horizonte de projeção é fixo em dez anos

Para todo mundo, independentemente de ciclo, setor ou maturidade. Nunca foi
medido se dez é melhor que sete ou quinze.

### B7. Consistência real × nominal

O motor desconta fluxo nominal a taxa nominal e usa o IPCA só no teto da
perpetuidade. Nunca foi conferido que as duas pontas usam a mesma convenção de
inflação em todo o caminho.

### B8. Reapresentação no *point-in-time*

A ingestão adota a **última versão** de cada documento, e 24,8% dos anuais têm
mais de uma. A data de cada versão está gravada; usá-la é o que torna a coorte
honesta. Evidência: a DFP de 2023 da USIM3 foi reapresentada, e a versão
ingerida tem recebimento em 16/01/2025 — em 04/09/2024 o ano ficava sem CVM, e
a decisão 78 o devolve ao mercado em vez da versão original.

### B9. WACC estático e WACC resolvido com convenções de dívida diferentes

Da lente `metodo`, em 14/09/2026. O custo de capital realavancado da decisão 41
pondera pela **dívida líquida**; o WACC estático, que é o recuo, pela **bruta**; a
ponte desconta a líquida. As duas vias de taxa não usam a mesma convenção, e a
diferença cai sobre ativo com muito caixa.

### B10. A migração de via é descontínua na taxa

Na PRIO3, uma curva mais alta levou o capital próprio a 14,4% do valor da firma,
a cascata migrou para a via do acionista, e o potencial **subiu** de −80,6% para
−18,3% ([fase1_padrao.md](validacao/fase1_padrao.md)). Taxa maior dando preço
justo maior é resposta que nem um valuation exemplar nem um motor de referência
podem ter: a migração precisa de transição, e não de degrau.

### B11. O aplicativo não resolve o prior do beta

Achado na rodada do A5, em 14/09/2026. `ResolveBetaPrior` só é chamado pelas
ferramentas de diagnóstico: `valuation_providers.dart` não passa prior a
`PrepareValuationInputs`, e sem ele não há beta desalavancado. **O aplicativo
avalia com o beta cru e o WACC estático** — o recuo das decisões 40 e 41 —, e o
encolhimento do beta, o custo de capital resolvido e a isenção de realavancagem
da Porta 1 não agem em produção. A montagem padrão da validação
(`padrao_ligar.dart`, `backtest_valuation.dart`) também não passa prior, então
ela mede o mesmo motor do aplicativo; o que diverge são as decisões, que
descrevem um motor que só roda em diagnóstico.

**E há uma tensão a resolver antes de ligar**, da lente `metodo`: na via do
acionista, o `Ke` resolvido cai com a desalavancagem do modelo, e o fluxo — o LPA
crescendo — não cobra a amortização da dívida que produziu essa queda.

### B12. O excedente do capital existente na perpetuidade

Da lente `metodo`, em 14/09/2026, conferido na álgebra do DCF. O terminal neutro
`lucro_{N+1}/r` recusa o valor do capital novo, e mantém para sempre o retorno
acima do custo do capital que já existe no ano N: é `capital_N + EVA_{N+1}/r`.
Nas concessões o A6 corta esse excedente no fim do contrato. **Fora delas é
premissa não declarada** — o comentário de `DcfAssumptions` dizia que o terminal
neutro era a afirmação de que "não há lucro econômico em perpetuidade", e não é.
Declarar, medir o peso dele no preço justo e decidir se decai.

### B13. As duas vias discordam, e a discordância é defeito declarado

Da lente `rumo`, em 14/09/2026, conferido no registro. A
[decisão 39](decisoes/039-as-duas-vias-sao-modelos-independentes.md) mediu a via
da firma e a via do acionista sobre LPA discordando por até 28× no mesmo ativo, e
declarou: **enquanto não for fechada ou substituída por caminho único, o motor não
pode ser descrito como sem defeito conhecido**. A rota derivada da
[decisão 43](decisoes/043-capital-proprio-pela-rota-derivada.md) tirou a
discordância de quem migra da firma, e deixou com ela quem cai na via do
acionista pela Porta 3 — que as decisões 42, 43 e 64 mantiveram. A revisão de
14/09 não a pôs entre os defeitos abertos. É a raiz do B10: a migração é
descontínua porque os dois modelos não concordam.

---

## 4. Eixo C — Validação: as duas pernas

### C0. O que as recusas custam

Novo, e não estava em lista nenhuma: nas 1.218 observações recusadas, o B/M dá
spread de quintil de +23,8 p.p. (12m) e +77,3 p.p. (36m), acima de qualquer
outro recorte medido. Antes de tratar isso como sinal perdido é preciso separar
a cauda — recusado costuma ser pequeno e ilíquido — do que a Porta 0 e as
guardas estão descartando por excesso de zelo.

Medição: repetir o quintil dentro dos recusados, por **motivo** de recusa, e
confrontar com a liquidez. Executável já, sem dado novo. **Conferido em
14/09/2026: não iniciado** — `tool/backtest_valuation.dart` separa avaliado de
recusado, e nada mede por motivo.

### C1. Habilidade comprovada — **medida em 11/09/2026, e reprovada**

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

**Conferido em 14/09/2026: a reprovação é do motor de 11/09, e a ferramenta ainda
mede aquele motor.** `tool/backtest_valuation.dart` monta as coortes só com a
fonte de mercado — sem CVM, sem curva do Tesouro —, e o motor que o aplicativo
usa desde a Fase 1 não é mais esse. A contagem oficial da B3 não entra em coorte
por construção: ela é de hoje. O estimador de Newey-West existe no núcleo
(`inference.dart`, conferido contra o `statsmodels`) e não é usado no teste de
habilidade.

### C2. Incerteza calibrada — **não iniciada**

`ScenarioEngine` existe e produz banda; **a frequência de cobertura fora da
amostra nunca foi medida**. Uma banda de 80% que cobre 40% dos casos é pior que
não ter banda.

Medição: para cada coorte, a fração de ativos cujo preço realizado em 12 e 36
meses caiu dentro da banda declarada, contra a frequência nominal. Não depende
de nenhum dado novo — **é executável já**, e é o item de melhor razão
esforço/resultado do plano inteiro. **Conferido em 14/09/2026:** nenhuma
ferramenta mede a cobertura.

### C3. A validação não exercita a ponte por papel

§3.5: 351 de 351 ativos colapsam para `u = 1` sob a reescala do backtest. Três
peças do motor não têm evidência preditiva. **A contagem oficial da B3 não
resolve isto** (A3.3): ela é de hoje, e coorte não a usa. Resolve-se com a
contagem de ações por data (A3.4), que existe desde 14/09/2026 para as 164
deslistadas da ponte; ligá-la às coortes é o C1.

### C4. Custos de transação

§2.5. O backtest é otimista. Baixo por não rebalancear, mas não medido.

---

## 5. Eixo D — Engenharia

### D1. `_evaluateLane` tem 1.104 linhas

`compute_valuation.dart` tem **3.358 linhas — 20% do núcleo inteiro** — e um
único método privado, `_evaluateLane`, ocupa as linhas 1164 a 2268 (conferido em
14/09/2026). O arquivo cresceu com a contagem oficial da B3 e a curva; o método,
não.

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

**Feito.** São seis fontes — brapi, BCB, CVM, registro da B3, COTAHIST e
Tesouro —, e cada conflito tem regra explícita: brapi contra CVM campo a campo,
com procedência (`FundamentalsProvenance`, decisão 69); a contagem de ações pelo
registro oficial (decisão 83); a ponte ticker↔CNPJ pelo código CVM da B3
(decisão 82).

### D3. Cobertura de teste apontada pela lente `risco`

Pendências conferidas em 14/09/2026: as telas de estudo, metas e avaliação
entram no teste de estouro só vazias; o cache macroeconômico não tem teste de
recurso offline.

---

## 6. Itens, estado e critério de pronto

> **A sequência foi fixada pelo usuário em 11/09/2026:** o eixo A inteiro e
> estável primeiro, e só depois as pernas de validação — porque a habilidade só
> é comprovável quando o dado necessário estiver acessível, e a incerteza só é
> calibrável contra o que o dado não conclui. **A Fase 1 fechou em 14/09/2026**:
> todo item do eixo A está pronto pelo critério dele, com o A2.2 por outro
> caminho (decisão 86).
>
> **Como ler.** *Serve a* diz a qual objetivo o item responde. *Pronto se* é o
> critério verificável que fecha o item: para o que está feito, é o critério
> que foi atingido e onde conferir; para o que está aberto, é o que precisa ser
> verdade para marcar ✅. Item só muda de estado com o critério atingido.

Legenda: ✅ pronto · 🟨 em curso ou parcial · ⬜ aberto · 👤 depende de decisão
ou ação do usuário ou do orientador.

### Fase 1 — o eixo A, até estar estável

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| A1.0 | Conferência de campos da CVM | E | ✅ | todo campo que o motor lê tem conta localizada ou ausência declarada nos CNPJs do universo — atingido em 100% dos 286 ([cvm_conferencia.md](validacao/cvm_conferencia.md)) |
| A1.1 | Ponte ticker↔CNPJ | E, R3 | ✅ | ≥ 95% do universo ligado, sem ambiguidade, e cada ligação conferida contra o código CVM do registro da B3 — atingido: 371/375, 369 iguais ao registro e 2 corrigidas ([decisão 82](decisoes/082-a-ponte-comeca-pelo-registro-oficial-da-b3.md)) |
| A1.2 | Leitor do plano de contas | E | ✅ | lucro, EBIT e balanço resolvidos nos quatro layouts sem tabela fixa de código, e nenhum exercício sem DRE onde a CVM tem o documento — atingido: `CvmChart`, 0 faltas em 5.838 exercícios, 2.107 recuos para o individual |
| A1.3 | Ingestão DFP + ITR | E, R3 | ✅ | ativo = passivo em ≥ 99,9% dos documentos, e trimestre separado do acumulado — atingido: 39.947 de 39.953 ([decisão 72](decisoes/072-a-ingestao-le-o-periodo-e-o-tipo-do-documento.md)) |
| A1.4 | *Point-in-time* por `DT_RECEB` | R1, R3 | ✅ | nenhum exercício entra numa avaliação antes do recebimento na CVM, com teste — atingido (`PointInTimeView`) |
| A1.5 | Tesouraria no divisor | E, R1 | ✅ | o divisor oficial desconta a fração em tesouraria, com teste — atingido ([decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md)) |
| A1.6 | Todos os anos, com deslistadas | R3 | ✅ | 2010 até o ano corrente baixados, e ano ausente na fonte listado — atingido; 60,6% dos exercícios são de companhia fora do universo, e o ITR de 2025 não é publicado pela CVM |
| A1.7 | Ingestão ligada ao motor | E | ✅ | a montagem com a CVM avalia ao menos os mesmos ativos da montagem de mercado, com procedência por campo — atingido: 127 → 128 |
| A1.8 | Série de doze meses no trimestre | R3 | ✅ | a série ancorada existe, testada, fora do padrão — atingido, com correlação de postos de 0,737 contra a anual ([decisão 73](decisoes/073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md)); **vira padrão só se** o C1c mostrar que ela ordena melhor que a anual |
| A1.9 | CVM no aplicativo | E | ✅ | o aplicativo avalia com a CVM mesclada — atingido ([decisão 76](decisoes/076-a-cvm-chega-ao-aplicativo-por-pacote.md)) |
| A1.10 | Pacote da CVM no build | E, R1 | ✅ | pacote ausente reprova a suíte, e avaliação sem a CVM traz ressalva — atingido, pacote versionado ([decisão 80](decisoes/080-o-pacote-da-cvm-e-versionado-e-a-ausencia-aparece.md)) |
| A1.11 | Patrimônio da CVM na cascata | E | ✅ | a base de patrimônio é o PL da CVM na data do ponto, com teste — atingido; a base de mercado já era o PL consolidado em 99,4% dos exercícios ([decisão 81](decisoes/081-a-base-de-patrimonio-e-o-pl-da-cvm.md)) |
| A2 | Curva de juros observada | E | ✅ | curva do Tesouro no núcleo, com prazo em dias úteis conferido contra o PU em ≥ 99% das LTN — atingido: 99,13% ([decisão 79](decisoes/079-o-prazo-da-curva-conta-dias-uteis.md)) |
| A2.1 | Curva no aplicativo | E | ✅ | o aplicativo nativo avalia pela curva do dia e recua declarando — atingido ([decisão 84](decisoes/084-a-curva-e-o-padrao-do-aplicativo.md)) |
| A2.2 | Curva na web | E | ✅ | na web a avaliação usa o pacote sem buscar o Tesouro, o README regera o pacote antes do build web, e sem curva a avaliação diz por quê — atingido, com teste do repositório e `flutter build web` compilando ([decisão 86](decisoes/086-na-web-a-curva-vem-so-do-pacote.md)); a função `tesouro` saiu, porque o deploy exige o plano Blaze |
| A3 | Eventos de ações e contagem | E, R1 | ✅ | todo emissor listado do universo tem contagem oficial e eventos declarados, e o teto da inferência pelo preço está medido contra o registro — atingido: 41,5% de cobertura, 63,8% de precisão |
| A3.1 | Registro oficial da B3 | E, R1 | ✅ | registro para ≥ 95% dos emissores, com a convenção do fator conferida contra o preço em ≥ 90% dos eventos a 15% — atingido: 297/297 e 93,4% ([b3_registro.md](validacao/b3_registro.md)) |
| A3.2 | COTAHIST inteiro e ponte das deslistadas | R3 | ✅ | COTAHIST de 2010 até hoje, e ponte para as deslistadas que tinham ação em bolsa, com as ligações por nome revisadas à mão — atingido: 164 de 290 ([b3_deslistadas.md](validacao/b3_deslistadas.md)) |
| A3.3 | Contagem oficial no divisor | E, R1 | ✅ | a contagem oficial arbitra o divisor e o WACC estático pondera por ela, e os dez ativos com capital autorizado saem com o divisor oficial — atingido; potencial mediano de −37,6% a −28,7%, postos 0,982 ([decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md)) |
| A3.4 | Evento e contagem por data das deslistadas | R3 | ✅ | para cada companhia da ponte, eventos localizados no preço e contagem de ações por data, com a escala conferida e a cobertura declarada — atingido: 160 de 164 com contagem; escala contra a B3 nas listadas (281 de 291 a 1%), contra a composição do capital (1.619 de 1.848 a 2%) e pelo P/VPA (860 de 867); 69 eventos localizados e 22 marcados. **O critério mudou**: deslistada não tem valor de mercado de data conhecida, e a escala é conferida pelos três caminhos ([decisão 90](decisoes/090-a-contagem-por-data-vem-do-formulario-de-referencia.md)) |
| A4 | Proventos por fonte independente | E | ✅ | o orientador reabriu a decisão 23; proventos da B3 conferidos contra o COTAHIST e o `adjustedClose`, retorno total nas coortes e beta de retorno total no aplicativo — atingido: 9.241 de 9.243 preços com direito a 1%, `adjustedClose` a 3,3% na mediana ([decisão 89](decisoes/089-proventos-voltam-como-dado-conferido.md)) |
| A5 | Taxonomia setorial oficial | R1 | ✅ | todo ativo do universo tem setor de fonte oficial, e os que escapavam da Porta 1 sem setor (BRSR6, PINE4, SANB4) passam por ela — atingido: 297 de 297 emissores classificados pela B3, teste de integração da Porta 1 ([decisão 87](decisoes/087-o-setor-e-o-da-b3-por-emissor.md)) |
| A6 | Prazo das outorgas | E | ✅ | ativo sob concessão tem horizonte finito no contrato, com a indenização do investimento não amortizado, teste e efeito medido — atingido: terminal do contrato com o capital devolvido e o excedente até o fim, projeção encurtada quando o contrato acaba antes, 35 tickers com prazo do FRE ([decisão 88](decisoes/088-o-prazo-da-concessao-corta-o-excedente.md)) |
| D2 | Camada multi-fonte com procedência | E | ✅ | todo campo mesclado diz de que fonte veio, e todo conflito entre fontes tem regra — atingido |

### Fase 2 — validação, sobre a base completa

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| D1 | Quebrar `_evaluateLane` | R1 prevenção | 🟨 viável | o método vira funções de estágio com entrada e saída declaradas, a recursão da estrutura recusada vira decisão devolvida, e o gabarito **regravado antes** fica idêntico ao bit depois de cada passo — procedimento na §5 |
| C2 | Cobertura da banda fora da amostra | R2 | ⬜ | a fração de ativos cujo preço realizado cai na banda declarada é medida por coorte em 12 e 36 meses e fica a até 5 p.p. da nominal — ou a banda é recalibrada até ficar |
| C0 | O que as recusas custam | R3 | ⬜ | o spread do B/M dentro dos recusados é medido por motivo de recusa e por liquidez, e para cada motivo há decisão registrada: manter a recusa ou soltá-la |
| C1a | Erro-padrão para janelas sobrepostas | R3 | ⬜ | o teste de habilidade reporta `t` com Newey-West ou com coortes não sobrepostas |
| C1b | Amostra com deslistadas | R3 | ⬜ | as coortes incluem as companhias da ponte do A3.2, com a contagem por data, os eventos e o retorno total do A3.4, excluída a janela que atravessa evento não localizado, e o resultado é reportado com e sem elas |
| C1c | Coortes trimestrais | R3 | ⬜ | as coortes são trimestrais sobre a série ancorada, e há decisão registrada sobre ela virar padrão |
| C1 | Habilidade, sobre o motor de agora | R3 | ⬜ | `tool/backtest_valuation.dart` monta as coortes com a montagem padrão do aplicativo por data — CVM, curva do Tesouro, setor da B3, prazo das outorgas e beta de retorno total —, mede sobre o retorno total, com C1a a C1c aplicados, e o `t` condicionado ao B/M em 36 meses passa de 2 — **ou** o registro declara que não passa, e o B1 decide |
| C3 | Validação da ponte por papel | R3 | ⬜ | as coortes usam a contagem de ações da data do A3.4, e a razão de unidade e a regra do divisor deixam de colapsar para `u = 1` por construção |

**Por que o D1 abre a fase.** A validação vai instrumentar a cascata — a
cobertura da banda precisa dos cenários, as coortes trimestrais rodam o motor
milhares de vezes —, e instrumentar um método de 1.104 linhas é o jeito mais
barato de criar o próximo defeito de costura.

### Fase 3 — método e nível

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| B1.0 | Ressalva na tela de metas | R1 | ⬜ | a tela de metas diz ao usuário que a ordenação por potencial não supera o book-to-market, enquanto o C1 não aprovar — **defeito em produção desde a §0, e não depende de fase nenhuma** |
| B1 | O que o potencial serve | R3 | ⬜ 👤 | decisão registrada entre as três saídas da §3 (recomendada: medir DCF e modelo transversal lado a lado), e retorno esperado e tela de metas coerentes com ela |
| B10 | Migração de via descontínua | R1, E | ⬜ | um teste varia a taxa em torno do limiar de migração e o preço justo não sobe com a taxa, e a PRIO3 é remedida |
| B9 | Convenção de dívida no WACC | R1, E | ⬜ | o WACC estático e o realavancado usam a mesma convenção de dívida, declarada, com teste |
| B11 | Prior do beta no aplicativo | R1, E | ⬜ | o aplicativo e a montagem padrão da validação avaliam com o prior do beta e o custo de capital resolvido das decisões 40 e 41, com a tensão da via do acionista resolvida e o efeito medido na mesma execução — **ou** uma decisão declara que o aplicativo fica com o beta cru, e as decisões que dependem do prior ficam marcadas como de diagnóstico |
| B13 | As duas vias discordam | R1, E | ⬜ | a via do acionista sobre LPA fica só para instituição financeira, ou as duas vias concordam dentro de tolerância declarada e medida no universo, ou uma decisão nova substitui a 39 e diz por que a discordância deixa de ser defeito — resolver junto com o B10 |
| B12 | Excedente do capital existente na perpetuidade | E | ⬜ | o peso de `EVA_{N+1}/r` no preço justo está medido no universo, declarado no aviso, e uma decisão diz se ele fica, decai ou acaba num horizonte |
| B8 | Reapresentação no *point-in-time* | R3, R1 | ⬜ | a ingestão guarda cada versão com a data de recebimento dela, e a coorte usa a versão recebida até a data da avaliação |
| B2 | Potencial ortogonalizado | R3 | ⬜ | o IC do potencial ortogonalizado ao B/M sai do `backtest_valuation` em toda execução e fica registrado |
| B6 | Horizonte de projeção | E, R3 | ⬜ | a varredura de 5 a 20 anos está medida sobre o universo e sobre a habilidade, e o horizonte é escolhido por decisão |
| B7 | Consistência real × nominal | E, R1 | ⬜ | um teste confere que fluxo, taxa e perpetuidade usam a mesma convenção de inflação em todo o caminho |
| B3 | Prêmio de risco de mercado | E | ⬜ | o prêmio é estimado — implícito ou histórico com encolhimento —, por decisão e com efeito medido; hoje é 5,5% fixo |
| B4 | Risco-país e tamanho | E | ⬜ | decisão registrada sobre prêmio de risco-país e ajuste por tamanho, implementados ou recusados com medição |
| B5 | Triangulação por múltiplos | E | ⬜ | cada avaliação traz o preço justo por múltiplos de pares ao lado do DCF, com a divergência declarada — hoje não há modelo por múltiplos |
| C4 | Custos de transação | R3 | ⬜ | o custo de transação entra no backtest, e o efeito sobre o retorno medido é reportado |
| D3 | Cobertura de caminhos de erro | R1 prevenção | ⬜ | as telas carregadas entram no teste de estouro, e o cache macroeconômico tem teste de recurso offline |

**A ordem tem uma razão.** O B1.0 primeiro porque é defeito em produção e custa
pouco. Depois os defeitos de método (B10 com B13, B9, B11, B8), porque R1 não
fecha com eles abertos — e o B11 depois do B9, porque ligar o custo de capital resolvido
com convenções de dívida diferentes ligaria o defeito junto. B1 é decisão e destrava o sentido da ordenação. B2 e B6 não precisam de
dado novo. B3 a B5 movem nível e não ordenação — servem ao exemplar, e é a
ordenação que a §0 mostrou estar em dívida.

### Fora dos dois objetivos

Conferidos em 14/09/2026 e **deixados fora da lista**, porque não mudam preço
justo, ordenação, incerteza nem a correção do motor:

- os achados da lente `nucleo` sobre o domínio de carteira — invariantes do
  construtor de `Portfolio`, listas paralelas no diagnóstico, nome de
  `sharesOutstandingAsOf`, `label` dos enums, `field` em `InvalidInput`;
- o alcance da lente `registro`, que só inventaria as decisões até a 30 — é
  ferramenta de QA, e está em tarefa própria.

Se um deles passar a afetar número, entra na tabela com *serve a* `R1`.

---

## 7. Critério de parada

Conferido contra o código e as medições em 14/09/2026. Cada condição cita os
itens da §6 que a fecham.

**Valuation exemplar** — o preço justo de um ativo é defensável linha a linha:

- [x] **Insumos de fonte primária, com procedência** — demonstrações (CVM),
  contagem de ações e setor (B3), curva (Tesouro), proventos (B3) e prazo das
  outorgas (FRE) — A1 a A6
- [x] **Curva de desconto observada** — padrão do aplicativo (A2, A2.1); na web,
  do pacote do build, que serve por cerca de uma semana (A2.2)
- [ ] **Divisor por papel correto** — contagem oficial e tesouraria no divisor
  (A1.5, A3.3) feitos; falta o WACC com a mesma convenção de dívida (B9)
- [ ] **Resposta coerente à taxa** — a migração de via é descontínua (B10)
- [ ] **Custo de capital completo e consistente** — prêmio de risco, risco-país,
  inflação e o prior do beta que o aplicativo não resolve (B3, B4, B7, B11)
- [x] **Horizonte compatível com o contrato onde há contrato** — o terminal da
  concessão corta o excedente no fim do contrato (A6); fora de contrato, o
  excedente perpétuo é premissa a declarar (B12)
- [ ] **Segunda leitura por múltiplos** (B5)

**Motor de referência** — as três condições combinadas:

- [ ] **R1. Nenhum defeito conhecido** — desmarcado em 14/09/2026. **Defeitos
  abertos hoje:** B1.0 (tela de metas), B10 (migração de via), B13 (as duas vias
  discordam — declarado na decisão 39 e fora da lista até 14/09), B9 (convenção
  de dívida), B11 (prior do beta fora do aplicativo), B8 (reapresentação nas
  coortes) e B7 (inflação — a conferir; pode não ser defeito). O A5 fechou.
  Prevenção em aberto, que não conta: D1 e D3.
- [ ] **R2. Incerteza calibrada** — não medida (C2)
- [ ] **R3. Habilidade comprovada** — **reprovada no motor de 11/09** (t = +0,24
  em 12 meses e +1,16 em 36, condicionado ao B/M; o retorno total não muda a
  conclusão), e **não medida no motor de agora**: a Fase 1 moveu a ordenação, e
  a ferramenta ainda monta as coortes sem a montagem do aplicativo (C1, com C1a a
  C1c). O dado que a medição pedia está pronto: deslistadas com contagem,
  eventos e proventos (A3.4), e retorno total (A4)

**A leitura honesta.** A Fase 1 fechou: todo insumo do preço justo tem fonte
primária e procedência, e a curva, o divisor, o setor, o prazo e o beta saem
dela. Não mediu nada sobre o motor de referência — as três condições dependem da
Fase 2 —, e deixou duas dívidas de método que só apareceram quando o dado ficou
limpo: o motor das decisões 40 e 41 não é o do aplicativo (B11), e o terminal
neutro não é tão neutro quanto se dizia (B12). A distância, agora, está na
validação e no custo de capital.

---

## 8. O que pode dar errado

**A distância pode não fechar.** É possível que um DCF sobre fundamento anual
brasileiro simplesmente não bata um fator de valor, e que a resposta certa seja
a opção (a) da B1 — o DCF como produto de análise individual, e a ordenação
saindo de um modelo declarado. Se for isso, o registro deve dizê-lo, e a
o artigo fica mais forte por dizê-lo do que por escondê-lo.

**O dado de mercado deriva entre execuções.** O cache da validação vence e o
Ibovespa vem sem cache: em meia hora, 26 ativos mudaram de valor sem mudança de
código. Toda comparação que decide item — gabarito do D1, coortes do C1,
cobertura do C2 — tem de ser feita **dentro da mesma execução**, ou sobre
entrada congelada. Comparar números de execuções diferentes mistura o efeito do
código com o do dado.

**A CVM custou o que se temia, e ainda cobra.** Casamento CNPJ↔ticker,
reapresentação, layout, consolidado e individual levaram as rodadas de 11 a
14/09/2026 e produziram defeitos que só apareceram depois (decisões 72, 78, 82).
A reapresentação (B8) e a série trimestral sem o ITR de 2025 continuam abertas.

**A amostra pode continuar pequena demais para decidir.** Com coortes anuais
sobrepostas, o `n` efetivo é pequeno. Coortes trimestrais e as deslistadas
ajudam, mas o mercado brasileiro tem o tamanho que tem.
