# Plano para o motor de referência

O que falta para dois objetivos distintos, item a item, com o critério que diz
quando cada um está pronto. **Este documento é mantido atualizado a cada
rodada**: a §6 traz o estado e o *pronto se* de cada item, e a §7 diz, com a
mesma régua, onde cada objetivo está. O que cada rodada encontrou, o que as
lentes disseram e o que a auditoria reprovou ficam no
[histórico](plano-motor-de-referencia-historico.md).

> **Última atualização: 15/09/2026, quarta rodada — C2b e B1.0.** A Fase 2
> fechou, e a Fase 3 começou. **A faixa calibrada voltou a cobrir, por uma forma
> fixada por escrito antes de medir**: o centro é o quanto o preço de fato
> converge ao preço justo, e a largura é a volatilidade do papel. Fora da
> amostra, 87,9/79,0/50,3% em 12 meses e 88,2/80,4/51,2% em 36 — 2,1 e 1,8 p.p.
> da nominal, contra 5,4 e 7,2 da forma anterior nas mesmas observações
> ([decisão 100](decisoes/100-a-faixa-calibrada-sai-da-volatilidade-do-papel-e-o-justo-entra-com-o-peso-medido.md)).
> **O R2 está atingido de novo, e o que ele declara é outra coisa**: com
> `b = 0,03` em 12 meses e `0,08` em 36, dobrar o preço justo move a faixa 2% e
> 6% — a incerteza que o motor declara é, sobretudo, o preço de hoje mais a
> volatilidade do papel. **E a tela de metas passou a dizer que o prêmio tirado
> do potencial não está comprovado** (B1.0,
> [decisão 99](decisoes/099-a-tela-de-metas-diz-que-o-premio-do-potencial-nao-esta-comprovado.md)),
> com a medição empacotada: a ressalva some sozinha quando o C1 aprovar. O
> defeito em produção que a §0 apontou está fechado.

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
| **R2** | Incerteza calibrada | cobertura fora da amostra da faixa de incerteza que o motor declara a até 5 p.p. da frequência nominal, em 12 e 36 meses, em amostra sem viés de sobrevivência (C2, C2b) |
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
>
> **Refeita em 15/09/2026, sobre o motor de hoje** — montagem do aplicativo por
> data, retorno total, deslistadas e erro-padrão das janelas sobrepostas: o
> coeficiente do potencial condicionado ao B/M em 36 meses é de 0,070, com `t` de
> **1,24**. A conclusão desta seção não mudou
> ([habilidade_aplicativo.md](validacao/habilidade_aplicativo.md)).
>
> **E os números desta seção carregam um defeito de base, achado no C3.** O preço
> das coortes estava na base de ações de hoje, e a companhia que desdobrou depois
> entrava barata. Corrigido, e com 31 coortes trimestrais, o IC do B/M em 36 meses
> é de 0,181 e o do potencial, de 0,091; o potencial dado o B/M, de 0,030. **O B/M
> ordena menos do que esta seção diz, e o motor continua não acrescentando a ele**
> ([habilidade_trimestral.md](validacao/habilidade_trimestral.md)).

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

**Dois fatos da Fase 2 entram nesta decisão.** O preço converge ao preço justo
**um quarto do caminho em 36 meses** — `b = 0,24` nas coortes de 2018 a 2022,
onde a decisão 26 supõe `b = 1` ([cobertura_banda.md](validacao/cobertura_banda.md)).
E onde o motor recusa, o book-to-market ordena mais do que onde ele avalia: um
modelo transversal enxergaria as recusadas que o potencial não enxerga
([recusas_custo.md](validacao/recusas_custo.md)).

**E um terceiro, da segunda rodada.** O retorno esperado da tela de metas soma
ao `Ke` de cada ativo `z · prêmio`, com `z` tirado do potencial — e o potencial,
condicionado ao B/M, tem `t` de 1,24 sobre o motor de hoje
([habilidade_aplicativo.md](validacao/habilidade_aplicativo.md)). A lente
`metodo` apontou em 15/09/2026 que isso trata desconto relativo como prêmio
perene; a medição diz que é prêmio sem habilidade demonstrada.

**E um quarto, da terceira rodada.** A lente `metodo` apontou em 15/09/2026, e o
código confirma, que o retorno esperado da meta ancora no `Ke`, que é retorno
**total** pelo CAPM (decisão 62), enquanto a simulação da carteira é de **preço**
(decisão 23): a meta é julgada contra um número que embute o provento que a
simulação não credita. O comentário de `expectedReturn` dizia "não há parcela de
provento", e foi corrigido para dizer isso. Decidir o que o retorno esperado é —
e com que retorno a meta é julgada — é deste item.

### B1.0. A ressalva na tela de metas

A §0 chamou de **defeito em produção**: a tela de metas ordena a carteira por um
potencial que não bate um fator de uma linha. A recomendação era declarar a
ressalva na tela já, sem esperar o eixo A. **Conferido em 14/09/2026: não foi
feito** — nada em `lib/presentation/goals` diz isso ao usuário.

**Estado: feito em 15/09/2026, na primeira rodada da Fase 3**
([decisão 99](decisoes/099-a-tela-de-metas-diz-que-o-premio-do-potencial-nao-esta-comprovado.md)).
O cartão do confronto com a meta diz que o prêmio acima do `Ke` sai do potencial,
que o potencial não comprovou saber ordenar ações — correlação de postos de 0,09
contra 0,18 do book-to-market, e `t` corrigido de 0,24 contra 2,70 dado o B/M — e
que essa parte do esperado não está comprovada. **A frase sai da medição
empacotada** (`assets/validacao/habilidade.json`, gravado por
`tool/regressao_condicional.dart`), e o critério da decisão 96 mora no núcleo
(`SkillReading.demonstrated`): quando o C1 aprovar, a ressalva some sem mudar
código; sem pacote, ela diz que a habilidade não foi medida. O número não muda —
o que o prêmio deve ser é o B1.

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

**O caso geral já estava medido**, e a lente `rumo` o trouxe de volta em
15/09/2026: deslocando o nível da curva inteira, o preço justo não era monótono
em **46 de 122** ativos ([dcf_reverso.md](validacao/dcf_reverso.md) §2.6) —
deslocar as duas taxas juntas move também a participação estrutural que decide a
via, e a decisão 34 só resolvia o deslocamento da taxa corrente. A medição é
anterior às decisões 38 e 43, e tem de ser refeita.

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

**E um defeito latente, achado ao quebrar o `_evaluateLane` (D1).** Com as taxas
resolvidas, o preço justo sai das premissas finais — caminho de taxas e retorno
terminal do último passe —, mas os cenários, a taxa de desconto exibida e o rastro
do DCF saem das premissas **interpoladas**, de antes do ponto fixo. No aplicativo
de hoje as duas coincidem, porque ele não resolve o prior; ligar o prior sem
corrigir isso descasaria a banda de sensibilidade do preço que ela cerca.

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

### B14. O beta de papel pouco negociado

Da medição do C0b, em 15/09/2026 ([decisão 95](decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)).
Nos recusados só por liquidez, o potencial solto do corte ordena o retorno além do
book-to-market — e continua ordenando com as deslistadas —, mas o nível dele sai
27 p.p. acima do das avaliadas: beta de papel com pouco negócio sai baixo por
negociação não sincrônica, reduz o custo de capital e infla o preço justo. **É a
razão que sobrou para a recusa.** Um beta corrigido — Dimson, com defasagens e
avanços do índice, ou Scholes-Williams — tiraria essa razão, e aí a Porta 0 teria
de decidir de novo se o corte de liquidez fica.

### B15. A perpetuidade é descontada com o beta e a estrutura de capital de hoje

Da lente `metodo`, em 15/09/2026, conferido no código. A taxa de equilíbrio da
perpetuidade troca só a taxa livre de risco: `capm.withRiskFree(terminal)`, com o
mesmo beta, e, na via da firma, o WACC estático com o peso do capital próprio e a
dívida bruta de hoje (`_premissas` em `compute_valuation.dart`). O caminho
resolvido das decisões 41 a 44 realavanca ano a ano, mas o aplicativo não o usa
(B11). **Um estado estacionário com o beta e a alavancagem do ano da avaliação é
premissa não declarada** — e ela pesa onde metade do valor mora. Alternativas
com dado que o projeto tem: o beta ajustado em direção a 1 (Blume) e a
alavancagem da mediana do setor da B3 na perpetuidade.

### B16. A razão de unidade é inferida do valor de mercado, e erra com ágio entre espécies

Do C3, em 15/09/2026 ([ponte_por_papel.md](validacao/ponte_por_papel.md) §3,
limitações §3.13). `quotedUnitRatio` mede `contagem × preço da unit ÷ valor de
mercado`, e só acerta o número de ações da unit quando ordinária e preferencial
valem o mesmo. Nas coortes, contra a composição que a FCA declara, ela erra 79 de
220 observações de unit: em 49 cai em 1 e a unit é avaliada como ação; em 12 cai
no inteiro errado dentro da folga — a ENGI11 com 4 em vez de 5 —, sem aviso. **No
aplicativo as nove units passaram em 04/09/2026** (decisão 61), e a convenção do
valor de mercado da fonte, que não é conhecida, é o que decide se o erro aparece.
A composição declarada existe, por ano, na FCA.

### B17. A série de preços das coortes tem no máximo dez anos

**Achado em 15/09/2026**, ao conferir um apontamento da lente `dados`. A fonte de
cotações devolve uma janela fixa de dez anos, e o cache da validação guarda o que
ela devolve: a série de qualquer listada começa em setembro de 2016. A janela do
beta é de cinco anos (`PrepareValuationInputs.betaWindowYears`), e o mínimo do
estimador é de 30 pares — então **a coorte de 31/03/2018 estima beta com 383
pregões em vez de 1.240**, e passa sem ressalva.

O efeito é ruído no `Ke` das coortes de 2018 a 2021, que entra no preço justo
delas e, por ele, na medição da habilidade e na da faixa calibrada. **As
deslistadas não têm o problema**: a série delas vem do COTAHIST, que o projeto
tem desde 2010 — as duas metades da amostra não são estimadas na mesma janela.

O COTAHIST resolve também para as listadas: a montagem na base da data já o lê,
papel a papel, para medir o fator e refazer o volume (decisão 97).

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

**Estado: feito, e nenhuma recusa foi solta** ([decisão 91](decisoes/091-as-recusas-ficam-e-a-liquidez-e-remedida-com-as-deslistadas.md),
[recusas_custo.md](validacao/recusas_custo.md)). Na montagem do aplicativo por
data, 1.788 das 2.633 observações são recusadas, e o B/M ordena nelas o dobro do
que ordena nas avaliadas — IC de 0,27 contra 0,13 em 12 meses. O sinal é de dois
grupos: as ilíquidas e as que nenhuma via avalia. **Soltando o corte de
liquidez, o potencial ordena além do B/M** — IC condicionado de 0,12, `t` 2,75
entre sete coortes, onde nas avaliadas não passa de 0,04 —, e sobrevive a começar
o retorno um mês depois. Fica mesmo assim: o viés de sobrevivência é máximo nesse
grupo, o potencial mediano de −24% contra −50% confirma o beta enviesado que a
Porta 0 declara, e R$ 37 mil por dia não é investível. **Remedir com as
deslistadas é o C0b.**

**C0b, em 15/09/2026: o viés de sobrevivência não explica a ordenação**
([decisão 95](decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md),
[recusas_custo.md](validacao/recusas_custo.md) §6). Com as deslistadas, os soltos
passam de 848 para 1.003, e o potencial dado o B/M ordena com IC de 0,116 em 12
meses (`t` 2,73) e 0,189 em 36 (`t` 3,08). O viés pesa no nível do retorno — a
média de 36 meses cai de 73% para 68% —, e o nível do preço justo continua 27 p.p.
acima do das avaliadas. **A recusa fica pelo nível**; a razão da
investibilidade saiu, e o caminho para soltar é o B14.

**Remedido na base da data, trimestral** ([recusas_custo.md](validacao/recusas_custo.md)
§7). Os soltos do corte de liquidez dados o B/M ficam em 0,084 em 12 meses e 0,148
em 36 — quatro a seis vezes o das avaliadas —, e o `t` corrigido pela sobreposição
é de 1,67 e 1,16 contra os críticos de 2,24 e 2,70. **A ordenação dos soltos é
direção, e não prova**; o nível continua fora, com o potencial mediano de −25,4%
contra −51,5%, e a recusa fica.

### C1. Habilidade comprovada — **o instrumento está pronto, e a medição fica para o fim**

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

**Conferido em 14/09/2026: a montagem do motor de agora existe.**
`tool/backtest_valuation.dart --montagem aplicativo` monta cada coorte como o
aplicativo naquela data — curva do Tesouro do dia, CVM recebida até ali, setor
da B3, prazo das outorgas do Formulário de Referência recebido até ali
(`tool/cvm/outorgas_por_data.dart`, que reproduz o pacote do aplicativo em 35 de
35) e beta de retorno total. A contagem oficial da B3 não entra por construção:
ela é de hoje.

**C1a e C1b, em 15/09/2026: feitos, e a reprovação ficou**
([decisão 93](decisoes/093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md),
[habilidade_aplicativo.md](validacao/habilidade_aplicativo.md)). As deslistadas
entram com `--com-deslistadas`: CVM pelo CNPJ, COTAHIST ajustado pelos eventos até
a data, contagem do FRE, proventos, prazo e setor — o da B3, que responde para 62
dos 231 papéis, ou o representante do setor de atividade da CVM, que acerta as
três portas em 258 de 284 listadas sem a própria companhia. Sai a janela que
atravessa evento não localizado ou salto de mais de três vezes na série
ajustada. O `t` do segundo passo sai também com Newey-West, e vale o **menor**:
com cinco coortes, a autocovariância dos coeficientes saiu negativa e estreitou o
erro. **Em 36 meses, o potencial dado o B/M tem coeficiente de 0,070 e `t` de
1,24 com as deslistadas, e 0,068 e 1,04 sem elas.** Falta o C1c, que é o que dá
série para o erro-padrão.

**C1c, C1d e C3, na terceira rodada: o instrumento ficou pronto**
([habilidade_trimestral.md](validacao/habilidade_trimestral.md)):

- **C1c** — 31 coortes, no fim de cada trimestre de 31/03/2018 a 30/09/2025, com a
  série de DFPs e a ancorada no trimestre avaliadas sobre os mesmos insumos. O `t`
  do segundo passo passa a ser corrigido pela estrutura da sobreposição e
  comparado com o crítico simulado dela, com o Newey-West acima de 2 junto
  (decisão 96): 2,70 para as 22 coortes de 36 meses. **A série ancorada ordena
  mais** — IC de 0,124 contra 0,088 — **e não prova**: `t` corrigido da diferença
  de 0,70. Fica fora do padrão (decisão 98).
- **C1d** — a ponte vai a 189 companhias. A BRF e a Petz, incorporadas em 2025, e
  a Tupy e a Sequoia, que a fonte de preços não traz, estavam fora das duas
  amostras. Das 112 que seguem sem ponte, nenhuma tem código com pregão.
- **C3** — o preço, a contagem e o valor de mercado passam à base da data, e a
  ponte por papel passa a ser exercitada (decisão 97, e o C3 abaixo).

**A leitura, que não é o veredito**: em 36 meses, o potencial dado o B/M tem
coeficiente de 0,030 e `t` corrigido de 0,24 contra 2,70, com as deslistadas.

**O C1 foi para depois da Fase 3.** O usuário pediu, em 15/09/2026, para medir a
habilidade quando todas as fases estiverem completas: medir agora seria medir um
motor que a Fase 3 vai mudar.

### C2. Incerteza calibrada — **medida, e recalibrada**

`ScenarioEngine` existe e produz banda; a frequência de cobertura fora da amostra
nunca tinha sido medida. Uma banda de 80% que cobre 40% dos casos é pior que não
ter banda.

**Estado: feito** ([decisão 92](decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md),
[cobertura_banda.md](validacao/cobertura_banda.md)). A banda de cenários cobria
**8%** do que aconteceu contra 90% nominais, em 12 e em 36 meses: o realizado
fica acima dela em 71% dos casos, a 2,1 vezes a mediana, e ela tem 1,3 vez de
largura contra 43 a 47 vezes do erro realizado. Ela mede a sensibilidade do
preço justo às premissas, e passou a se declarar assim. **A incerteza que o
motor declara passou a ser a faixa calibrada**, os quantis da razão entre o
realizado e o preço justo nas coortes: fora da amostra, 90,2%, 80,3% e 54,2% em
12 meses, e 91,8%, 78,8% e 52,8% em 36, para 90, 80 e 50% nominais. É larga — de
0,62 a 9,2 vezes o preço justo, a de 80% em 12 meses —, e marginal: no terço de
maior potencial ela cobre menos. As alternativas estreitas, em torno do preço ou
da convergência parcial, não calibram em 36 meses. **Remedir com as deslistadas
é o C2b**, e só com ele o R2 fecha.

**C2b, em 15/09/2026: a faixa cobre a amostra com as deslistadas**
([decisão 94](decisoes/094-a-faixa-calibrada-sai-da-amostra-com-as-deslistadas.md),
[cobertura_banda.md](validacao/cobertura_banda.md) §7). Calibrada nas listadas e
testada em todas, fora da amostra, 89,9/79,9/53,5% em 12 meses e 92,2/79,4/52,9%
em 36; recalibrada com as deslistadas, 91,3/81,4/54,2% e 93,0/82,1/49,0%. A cauda
de baixo não desceu — as deslistadas terminaram, na mediana, a 3,6 vezes o preço
justo, contra 2,1 das listadas —, e a de cima subiu. O pacote do aplicativo
passou a sair da amostra com elas: a faixa de 80% em 12 meses vai de 0,64 a 10,7
vezes o preço justo. **O R2 fechou.**

**Desfeito na terceira rodada, pela correção da base** ([cobertura_banda.md](validacao/cobertura_banda.md)
§8). O C2 e o C2b foram medidos com o preço das coortes na base de ações de hoje.
Na base da data, trimestral e com as deslistadas, a faixa cobre fora da amostra
**84,8/74,9/49,1% em 12 meses e 83,6/73,0/47,0% em 36** — fora dos 5 p.p. nas de
90% e 80%. Cinco variantes exploratórias e uma aninhada, fixada por escrito antes
de rodar, não fecharam os dois horizontes. O pacote passou a sair da montagem
corrigida, e o cartão diz a cobertura medida e que a faixa não está calibrada
(decisão 97). **O R2 voltou a ficar aberto, e o C2b também.**

**Refeito na quarta rodada, e a faixa voltou a cobrir** ([decisão 100](decisoes/100-a-faixa-calibrada-sai-da-volatilidade-do-papel-e-o-justo-entra-com-o-peso-medido.md),
[cobertura_banda.md](validacao/cobertura_banda.md) §§9 e 10). O diagnóstico veio
antes da forma: as deslistadas cobrem — 90,4% e 96,3% —, o choque comum às coortes
é pequeno, e o que muda entre elas é a cauda de baixo. O que estava errado era o
**centro**: a forma antiga impõe convergência total ao preço justo, e o medido é
`b = 0,02` a `0,08`. A forma fixada por escrito antes de medir — convergência
parcial na escala da volatilidade do papel — cobre **87,9/79,0/50,3% em 12 meses e
88,2/80,4/51,2% em 36**, fora da amostra, contra 84,6/74,9/48,9% e 83,5/72,8/46,6%
da forma em torno do justo nas mesmas observações. **Ela calibra na média das
coortes, e não em cada uma** — de 59,8% a 100% em 12 meses —, e o 36 meses continua
com 1,4 janela independente de calibragem. A confirmação é o C2c, na Fase 4, que a
remede sobre o motor da Fase 3 **sem escolher outra forma**.

### C3. A validação não exercita a ponte por papel

§3.5: 351 de 351 ativos colapsam para `u = 1` sob a reescala do backtest. Três
peças do motor não têm evidência preditiva. **A contagem oficial da B3 não
resolve isto** (A3.3): ela é de hoje, e coorte não a usa. Resolve-se com a
contagem de ações por data (A3.4), que existe desde 14/09/2026 para as 164
deslistadas da ponte. **Em 15/09/2026 ela entrou nas coortes das deslistadas
(C1b), e não resolveu isto**: o valor de mercado delas é a contagem da data vezes
o preço, e a razão de unidade sai 1 por construção do mesmo jeito. Exercitar a
ponte pede um valor de mercado que não venha da própria contagem.

**Estado: feito, e o defeito era maior que o item** ([decisão 97](decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md),
[ponte_por_papel.md](validacao/ponte_por_papel.md)). O preço das coortes das
listadas vinha da fonte, que o publica ajustado por todo evento de ações até
hoje, e a contagem do exercício está na base daquele ano: 1.635 de 9.010
observações estavam fora da base da data por mais de 1,5 vez. A coorte passou a
levar a série à base da data pelo COTAHIST, a usar a contagem do FRE na data como
corrente e como oficial, e a formar o valor de mercado da companhia espécie a
espécie. **A razão de unidade deixou de colapsar**: confere com a composição
declarada na FCA em 141 de 220 observações de unit, e a unit e a espécie da mesma
companhia concordam a 1,5% na mediana, contra 80,1% antes. **E erra quando as
espécies negociam a preços diferentes** — é o B16.

### C4. Custos de transação

§2.5. O backtest é otimista. Baixo por não rebalancear, mas não medido.

---

## 5. Eixo D — Engenharia

### D1. `_evaluateLane` tinha 1.104 linhas

`compute_valuation.dart` tinha **3.358 linhas — 20% do núcleo inteiro** — e um
único método privado, `_evaluateLane`, ocupava as linhas 1164 a 2268 (conferido
em 14/09/2026, antes da quebra).

**Estado: feito, com o gabarito idêntico ao bit.** O `_evaluateLane` é o
condutor, de 180 linhas, e os estágios são funções com entrada e saída
declaradas: `_saida1` → `_Base`, `_saida2` → origem e taxa, `_premissas` →
`_Premissas`, `_fluxoBase`, `_resolverCusto` → `_Custo`, `_descontarVia`, que os
encadeia, `_descontarFluxo`, `_participacaoQueDecide` e `_concluir`. O contexto
que não muda viaja em `_Via`. **As duas migrações de via são decisões devolvidas
ao condutor**: a estrutura recusada volta como `_EstruturaRecusada`, a
participação que decide a ponte volta medida, e a segunda avaliação sai do
condutor, nunca de dentro de um estágio. O estágio mais longo tem 206 linhas, a
maior parte comentário que veio junto.

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

**O gabarito tinha um buraco, e foi ampliado antes de começar.** Nenhuma das duas
montagens passava o prior do beta, e sem ele não há taxa resolvida: o ponto fixo,
os passes do veredito, a rota derivada e a recursão da estrutura recusada — o
miolo do método — ficavam fora. A versão usada tem **nove montagens por ativo**:
dois pontos, curva, a do aplicativo, a série ancorada, a do aplicativo com o
prior, com Monte Carlo, com cada via imposta e com todas as imposições de
diagnóstico. E grava a impressão do **rastro de auditoria** de cada uma. Na
gravação, sobre 380 ativos: na montagem do aplicativo, 37 migrações pela ponte,
5 combinações de vias, 7 bases reconstruídas e 4 terminais de contrato; na do
prior, 108 com taxas resolvidas e 23 com a estrutura recusada e migrada; e 63
formas distintas de recusa no conjunto.

**A ressalva da entrada foi resolvida.** A gravação copia o cache da validação
para `data/gabarito/`, trata toda entrada presente como fresca e grava o
Ibovespa servido; a conferência repete os dois sem ir à rede, em três minutos. O
controle — conferir o código intacto — deu idêntico; e uma mutação que só troca
a ordem de dois passos do rastro, sem mudar número, **divergiu em 1.212 das 3.420
montagens**.

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

**Como foi feito.** A ordem mudou: a taxa, o fluxo-base, a base, as premissas e o
custo resolvido, e por último a ponte com a estrutura recusada — com os
*records* dos estágios de cima prontos, a ponta de baixo deixou de precisar de
duas dezenas de variáveis soltas. Os commits são do usuário, então cada passo
ficou guardado e foi conferido na ordem: **seis passos, seis gabaritos
idênticos**, e os 639 testes do núcleo passando no fim.

**O que o gabarito não cobre.** O que não está no universo de hoje, e **o
veredito que não se estabiliza em dez passes**: nenhum ativo das nove montagens
passa por ele, e nenhum teste o constrói — está no D3. Os testes de
`usecases_test`, `valuation_guards_test` e `audit_test` cobrem casos sintéticos e
continuam obrigatórios.

**Foi o primeiro item da Fase 2**, antes do C2: a validação instrumenta a
cascata — a cobertura da banda precisou dos cenários de 845 avaliações, com 10
mil sorteios cada —, e instrumentar um método de 1.104 linhas era o jeito mais
barato de criar o próximo defeito de costura.

### D2. Camada de dados com múltiplas fontes e procedência

**Feito.** São seis fontes — brapi, BCB, CVM, registro da B3, COTAHIST e
Tesouro —, e cada conflito tem regra explícita: brapi contra CVM campo a campo,
com procedência (`FundamentalsProvenance`, decisão 69); a contagem de ações pelo
registro oficial (decisão 83); a ponte ticker↔CNPJ pelo código CVM da B3
(decisão 82).

### D3. Cobertura de teste apontada pela lente `risco`

Pendências conferidas em 15/09/2026: as telas de estudo e de metas entram no
teste de estouro só vazias — **a de avaliação entrou carregada na matriz inteira
na segunda rodada**, a pedido da lente `risco`, e achou o alternador de Monte
Carlo estourando 51 px em 320 dp sob 2,0x, corrigido —; e o veredito da vantagem competitiva que não se
estabiliza em `moatMaxPasses` passes não tem teste nem caso no gabarito do D1.
**A tela de avaliação carregada ganhou teste em 320 e 1024 dp** com a faixa
calibrada, e ele achou na primeira execução o que a tela vazia escondia: o
gráfico de sensibilidade estourava 134 px em 320 dp. Corrigido — rótulo e valores
sobem para cima da barra quando não cabem na linha dela. **O recurso offline do cache macroeconômico ganhou teste**, e com ele um
defeito que a lente `dados` apontou: sem a fonte, o cache vencido servia sem
exigir a cobertura do início, e três meses guardados passavam por dez anos no
CAGR decenal. Corrigido, e o teste falha sem a correção.

---

## 6. Itens, estado e critério de pronto

> **A sequência foi fixada pelo usuário em 11/09/2026:** o eixo A inteiro e
> estável primeiro, e só depois as pernas de validação — porque a habilidade só
> é comprovável quando o dado necessário estiver acessível, e a incerteza só é
> calibrável contra o que o dado não conclui. **A Fase 1 fechou em 14/09/2026**:
> todo item do eixo A está pronto pelo critério dele, com o A2.2 por outro
> caminho (decisão 86). **A Fase 2 começou no mesmo dia**, pelo D1, pelo C2 e pelo
> C0.
>
> **E a medição da habilidade vai para o fim**, fixado pelo usuário em 15/09/2026:
> "Quero medir a habilidade do motor quando todas as fases estiverem completas."
> O C1 saiu da Fase 2 e virou a Fase 4.
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
| A1.8 | Série de doze meses no trimestre | R3 | ✅ | a série ancorada existe, testada, fora do padrão — atingido, com correlação de postos de 0,737 contra a anual ([decisão 73](decisoes/073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md)); **vira padrão só se** o C1c mostrar que ela ordena melhor que a anual — **o C1c mediu: ordena mais e não prova, e fica fora** ([decisão 98](decisoes/098-a-serie-ancorada-ordena-mais-sem-provar-e-fica-fora-do-padrao.md)) |
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
| D1 | Quebrar `_evaluateLane` | R1 prevenção | ✅ | o método vira funções de estágio com entrada e saída declaradas, a recursão da estrutura recusada vira decisão devolvida, e o gabarito **regravado antes** fica idêntico ao bit depois de cada passo — atingido: condutor de 180 linhas e dez funções de estágio, seis passos com o gabarito de nove montagens e do rastro idêntico, entrada do gabarito congelada (§5) |
| C2 | Cobertura da banda fora da amostra | R2 | ✅ | a fração de ativos cujo preço realizado cai na banda declarada é medida por coorte em 12 e 36 meses e fica a até 5 p.p. da nominal — ou a banda é recalibrada até ficar — atingido pela recalibragem: a banda de cenários cobria 8% contra 90%; a faixa calibrada cobre 90,2/80,3/54,2% em 12 meses e 91,8/78,8/52,8% em 36, fora da amostra, e é a que o aplicativo mostra ([decisão 92](decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md)) |
| C0 | O que as recusas custam | R3 | ✅ | o spread do B/M dentro dos recusados é medido por motivo de recusa e por liquidez, e para cada motivo há decisão registrada: manter a recusa ou soltá-la — atingido: oito motivos e três tercis de liquidez medidos, contrafactual sem o corte de liquidez, e todas as recusas mantidas ([decisão 91](decisoes/091-as-recusas-ficam-e-a-liquidez-e-remedida-com-as-deslistadas.md)) |
| C2b | Faixa calibrada com as deslistadas | R2 | ✅ | a cobertura fora da amostra da faixa calibrada é remedida com as companhias do C1b e fica a até 5 p.p. da nominal em 12 e 36 meses — ou a faixa é recalibrada com elas e o pacote do aplicativo, regerado — atingido em 15/09/2026 e **desfeito no mesmo dia** pela correção do C3 (84,8/74,9/49,1% e 83,6/73,0/47,0%, decisão 97); **refeito na quarta rodada por uma forma fixada por escrito antes de medir**, a convergência parcial na escala da volatilidade do papel: 87,9/79,0/50,3% e 88,2/80,4/51,2%, fora da amostra, com as deslistadas, e o pacote do aplicativo regerado na versão 2 ([decisão 100](decisoes/100-a-faixa-calibrada-sai-da-volatilidade-do-papel-e-o-justo-entra-com-o-peso-medido.md), [cobertura_banda.md](validacao/cobertura_banda.md) §§9 e 10) |
| C0b | Custo da recusa por liquidez com as deslistadas | R3 | ✅ | o IC do potencial sem o corte de liquidez, condicionado ao B/M, é remedido com as deslistadas do C1b, e a decisão 91 é mantida ou substituída pelo resultado — atingido: a recusa fica pelo nível, e a razão da investibilidade sai ([decisão 95](decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)); **remedido na base da data, trimestral**: 0,084 e 0,148 dado o B/M, `t` corrigido de 1,67 e 1,16 contra 2,24 e 2,70 — a ordenação é direção, e não prova; o nível, −25,4% contra −51,5%, mantém a recusa ([recusas_custo.md](validacao/recusas_custo.md) §7) |
| C1a | Erro-padrão para janelas sobrepostas | R3 | ✅ | o teste de habilidade reporta `t` com Newey-West ou com coortes não sobrepostas — atingido: Newey-West com defasagem da sobreposição, conferido contra a conta à mão, as coortes não sobrepostas ao lado, e o menor dos dois `t` valendo para o R3 ([decisão 93](decisoes/093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md)) |
| C1b | Amostra com deslistadas | R3 | ✅ | as coortes incluem as companhias da ponte do A3.2, com a contagem por data, os eventos e o retorno total do A3.4, excluída a janela que atravessa evento não localizado, e o resultado é reportado com e sem elas — atingido: 444 observações de 86 companhias, 106 avaliadas, fora também o salto que a série ajustada não explica, e o resultado com e sem elas na mesma execução ([habilidade_aplicativo.md](validacao/habilidade_aplicativo.md)) |
| C1d | Ponte das deslistadas que ficaram fora | R3, R2 | ✅ | das 126 companhias com ação em bolsa e sem ponte para o preço, as que negociaram em lote padrão têm ponte, contagem por data e eventos, e o C2b e o C0b são remedidos com elas — ou o registro mostra, companhia a companhia, por que não há preço a ligar — atingido: ponte de 164 para 189 companhias, com a BRF, a Petz e a Tupy; das 112 sem ponte, nenhuma tem código com pregão, e o registro diz o motivo de cada uma ([b3_deslistadas.md](validacao/b3_deslistadas.md) §6, [ponte_deslistadas_registro.json](validacao/ponte_deslistadas_registro.json)); C2b e C0b remedidos. **O critério mudou**: "o C1 é remedido" saiu, porque o C1 foi para o fim |
| C1c | Coortes trimestrais | R3 | ✅ | as coortes são trimestrais sobre a série ancorada, e há decisão registrada sobre ela virar padrão — atingido: 31 coortes trimestrais com as duas séries sobre os mesmos insumos, o `t` corrigido pela sobreposição contra o crítico dela ([decisão 96](decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)), e a ancorada fora do padrão pela regra fixada antes de medir ([decisão 98](decisoes/098-a-serie-ancorada-ordena-mais-sem-provar-e-fica-fora-do-padrao.md), [habilidade_trimestral.md](validacao/habilidade_trimestral.md)) |
| C3 | Validação da ponte por papel | R3 | ✅ | as coortes usam a contagem de ações da data do A3.4, e a razão de unidade e a regra do divisor deixam de colapsar para `u = 1` por construção — atingido: a contagem do FRE na data como corrente e oficial, o valor de mercado espécie a espécie e o preço na base da data; a razão confere com a composição declarada em 141 de 220 observações de unit, e o defeito de base que o item achou está corrigido ([decisão 97](decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md), [ponte_por_papel.md](validacao/ponte_por_papel.md)) |

**Por que o D1 abriu a fase.** A validação instrumenta a cascata — a cobertura
da banda precisou dos cenários, as coortes trimestrais vão rodar o motor
milhares de vezes —, e instrumentar um método de 1.104 linhas era o jeito mais
barato de criar o próximo defeito de costura. **E por que C0b e C2b esperaram o
C1b**: as duas medições da primeira rodada eram dos sobreviventes, e é justamente
nos recusados ilíquidos e na cauda de baixo da faixa que o viés pesaria mais. Na
segunda rodada ele pesou no nível do retorno, e não na ordenação nem na cobertura.
**E por que C2b e C0b foram remedidos de novo na terceira**: a correção do C3 mudou
o instrumento sob as duas medições.

### Fase 3 — método e nível

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| B1.0 | Ressalva na tela de metas | R1 | ✅ | a tela de metas diz ao usuário que a ordenação por potencial não supera o book-to-market, enquanto o C1 não aprovar — **defeito em produção desde a §0, e não depende de fase nenhuma** — atingido: o cartão do confronto cita a medição empacotada, com o critério da decisão 96 no núcleo, e a ressalva some quando ele aprovar ou diz "não medida" sem pacote, com teste do pacote contra a medição e da tela nos três casos ([decisão 99](decisoes/099-a-tela-de-metas-diz-que-o-premio-do-potencial-nao-esta-comprovado.md)) |
| B1 | O que o potencial serve | R3 | ⬜ 👤 | decisão registrada entre as três saídas da §3 (recomendada: medir DCF e modelo transversal lado a lado), e retorno esperado e tela de metas coerentes com ela |
| B10 | Migração de via descontínua | R1, E | ⬜ | um teste varia a taxa em torno do limiar de migração e o preço justo não sobe com a taxa, a PRIO3 é remedida, e a varredura do nível da curva do `dcf_reverso` é refeita no universo sem ativo não monótono |
| B9 | Convenção de dívida no WACC | R1, E | ⬜ | o WACC estático e o realavancado usam a mesma convenção de dívida, declarada, com teste |
| B11 | Prior do beta no aplicativo | R1, E | ⬜ | o aplicativo e a montagem padrão da validação avaliam com o prior do beta e o custo de capital resolvido das decisões 40 e 41, com a tensão da via do acionista resolvida, os cenários e a taxa exibida saindo das premissas resolvidas, e o efeito medido na mesma execução — **ou** uma decisão declara que o aplicativo fica com o beta cru, e as decisões que dependem do prior ficam marcadas como de diagnóstico |
| B16 | Razão de unidade pela composição declarada | R1, E | ⬜ | a composição de cada unit sai de fonte declarada — a FCA da CVM, por ano — no pacote do aplicativo e nas coortes, a razão medida do valor de mercado vira conferência, e as 79 observações de unit que a inferência erra nas coortes passam a sair com a composição, com teste |
| B13 | As duas vias discordam | R1, E | ⬜ | a via do acionista sobre LPA fica só para instituição financeira, ou as duas vias concordam dentro de tolerância declarada e medida no universo, ou uma decisão nova substitui a 39 e diz por que a discordância deixa de ser defeito — resolver junto com o B10 |
| B12 | Excedente do capital existente na perpetuidade | E | ⬜ | o peso de `EVA_{N+1}/r` no preço justo está medido no universo, declarado no aviso, e uma decisão diz se ele fica, decai ou acaba num horizonte |
| B14 | Beta de papel pouco negociado | E, R3 | ⬜ | um beta com correção por negociação não sincrônica é medido nos soltos do corte de liquidez, o nível do potencial deles é remedido com ele contra o das avaliadas, e uma decisão diz se a recusa por liquidez fica |
| B15 | Beta e alavancagem da perpetuidade | E | ⬜ | o custo de capital da perpetuidade declara de onde vêm o beta e a estrutura de capital, o efeito de levá-los ao estado estacionário — beta em direção a 1, alavancagem da mediana do setor — está medido no universo, e uma decisão escolhe |
| B17 | Série de preços das coortes limitada a dez anos | R3 | ⬜ | a série que a coorte usa para o beta cobre a janela inteira de cinco anos nas listadas, pelo COTAHIST, ou a coorte declara a janela curta — hoje a de 31/03/2018 estima beta com 383 pregões, contra 1.240, e as deslistadas, que vêm do COTAHIST, não têm o problema |
| B8 | Reapresentação no *point-in-time* | R3, R1 | ⬜ | a ingestão guarda cada versão com a data de recebimento dela, e a coorte usa a versão recebida até a data da avaliação |
| B2 | Potencial ortogonalizado | R3 | ⬜ | o IC do potencial ortogonalizado ao B/M sai do `backtest_valuation` em toda execução e fica registrado |
| B6 | Horizonte de projeção | E, R3 | ⬜ | a varredura de 5 a 20 anos está medida sobre o universo e sobre a habilidade, e o horizonte é escolhido por decisão |
| B7 | Consistência real × nominal | E, R1 | ⬜ | um teste confere que fluxo, taxa e perpetuidade usam a mesma convenção de inflação em todo o caminho |
| B3 | Prêmio de risco de mercado | E | ⬜ | o prêmio é estimado — implícito ou histórico com encolhimento —, por decisão e com efeito medido; hoje é 5,5% fixo |
| B4 | Risco-país e tamanho | E | ⬜ | decisão registrada sobre prêmio de risco-país e ajuste por tamanho, implementados ou recusados com medição |
| B5 | Triangulação por múltiplos | E | ⬜ | cada avaliação traz o preço justo por múltiplos de pares ao lado do DCF, com a divergência declarada — hoje não há modelo por múltiplos |
| C4 | Custos de transação | R3 | ⬜ | o custo de transação entra no backtest, e o efeito sobre o retorno medido é reportado |
| D3 | Cobertura de caminhos de erro | R1 prevenção | 🟨 | as telas carregadas entram no teste de estouro — **a de avaliação entrou, na matriz de três larguras e três escalas**, e faltam estudo e metas —, o cache macroeconômico tem teste de recurso offline — **feito**, com a cobertura do início exigida no recurso —, o veredito que não se estabiliza em `moatMaxPasses` passes tem teste, e os datasources de fundamentos e do Tesouro têm teste de payload malformado como o de cotações tem (lente `risco`, 15/09/2026) |

**A ordem tem uma razão.** O B1.0 primeiro porque é defeito em produção e custa
pouco. Depois os defeitos de método (B10 com B13, B9, B11, B16, B8), porque R1 não
fecha com eles abertos — e o B17 antes da Fase 4, porque é do instrumento que
mede o C1 e o C2c — e o B11 depois do B9, porque ligar o custo de capital resolvido
com convenções de dívida diferentes ligaria o defeito junto. B1 é decisão e destrava o sentido da ordenação. B2 e B6 não precisam de
dado novo. B3 a B5 movem nível e não ordenação — servem ao exemplar, e é a
ordenação que a §0 mostrou estar em dívida.

### Fase 4 — a medição final

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| C1 | Habilidade, com todas as fases completas | R3 | ⬜ | com as Fases 1 a 3 fechadas, `tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas --trimestral` monta as coortes do motor daquele dia, e o potencial condicionado ao B/M em 36 meses passa no critério da decisão 96 — `t` corrigido pela sobreposição acima do crítico dela, e Newey-West acima de 2 — **ou** o registro declara que não passa, e o B1 decide. **O instrumento está pronto** (C1a a C1d, C3); a leitura sobre o motor de hoje, que não é o veredito, dá 0,030 com `t` corrigido de 0,24 contra 2,70 ([habilidade_trimestral.md](validacao/habilidade_trimestral.md)) |
| C2c | A faixa calibrada sobre o motor da Fase 3 | R2 | ⬜ | **a forma da decisão 100 é remedida sobre o motor que a Fase 3 deixar, sem escolher outra**, e cobre fora da amostra a até 5 p.p. da nominal em 12 e 36 meses — **ou** uma decisão declara o que o aplicativo mostra e por que o R2 não se sustenta com a amostra que há. É a réplica que separa a forma fixada no C2b de um ajuste ao teste: ela foi a sétima tentada, e o motor sob ela vai mudar |

**Por que a Fase 4 é só isto.** A habilidade e a incerteza são do motor, e o motor
muda na Fase 3. O C2c está aqui porque a faixa calibrada é medida sobre as mesmas
coortes e o mesmo preço justo: **a forma já está fixada** (decisão 100), e o que
falta é medi-la sobre o motor que a Fase 3 deixar — que é o teste que uma sétima
tentativa pede.

### Fora dos dois objetivos

Conferidos em 14/09/2026 e **deixados fora da lista**, porque não mudam preço
justo, ordenação, incerteza nem a correção do motor:

- os achados da lente `nucleo` sobre o domínio de carteira — invariantes do
  construtor de `Portfolio`, listas paralelas no diagnóstico, nome de
  `sharesOutstandingAsOf`, `label` dos enums, `field` em `InvalidInput` —, os
  da primeira rodada da Fase 2 — o exercício que carrega valor de mercado de
  hoje, um tipo de data de calendário no lugar do `DateTime` convertido em UTC —
  os da segunda — falhas com texto em português, a taxa livre de risco pontual
  do backtest de carteira e a ordenação que `ValueDistribution` não garante
  sozinha — e os da terceira: listas paralelas em `TotalReturnIndex.build`, o
  capital investido operacional mantido para uma ferramenta, a porcentagem
  formatada em `Portfolio.weighted` e o `drift` em pontos percentuais;
- o alcance da lente `registro`, que só inventaria as decisões até a 30 — é
  ferramenta de QA, e está em tarefa própria.

Se um deles passar a afetar número, entra na tabela com *serve a* `R1`.

---

## 7. Critério de parada

Conferido contra o código e as medições em 15/09/2026, terceira rodada da Fase 2.
Cada condição cita os itens da §6 que a fecham.

**Valuation exemplar** — o preço justo de um ativo é defensável linha a linha:

- [x] **Insumos de fonte primária, com procedência** — demonstrações (CVM),
  contagem de ações e setor (B3), curva (Tesouro), proventos (B3) e prazo das
  outorgas (FRE) — A1 a A6
- [x] **Curva de desconto observada** — padrão do aplicativo (A2, A2.1); na web,
  do pacote do build, que serve por cerca de uma semana (A2.2)
- [ ] **Divisor por papel correto** — contagem oficial e tesouraria no divisor
  (A1.5, A3.3) feitos; falta o WACC com a mesma convenção de dívida (B9) e a
  razão de unidade pela composição declarada (B16)
- [ ] **Resposta coerente à taxa** — a migração de via é descontínua (B10)
- [ ] **Custo de capital completo e consistente** — prêmio de risco, risco-país,
  inflação e o prior do beta que o aplicativo não resolve (B3, B4, B7, B11)
- [x] **Horizonte compatível com o contrato onde há contrato** — o terminal da
  concessão corta o excedente no fim do contrato (A6); fora de contrato, o
  excedente perpétuo é premissa a declarar (B12)
- [ ] **Segunda leitura por múltiplos** (B5)

**Motor de referência** — as três condições combinadas:

- [ ] **R1. Nenhum defeito conhecido** — desmarcado em 14/09/2026. **Defeitos
  abertos hoje:** B10 (migração de via), B13 (as duas vias
  discordam — declarado na decisão 39 e fora da lista até 14/09), B9 (convenção
  de dívida), B11 (prior do beta fora do aplicativo), B8 (reapresentação nas
  coortes), B16 (razão de unidade inferida — entrou em 15/09/2026, pelo C3) e B7
  (inflação — a conferir; pode não ser defeito). O A5 fechou.
  Prevenção em aberto, que não conta: D3 — o D1 fechou.
- [x] **R2. Incerteza calibrada** — **atingida em 15/09/2026, desfeita no mesmo dia
  e refeita por outra forma.** A banda de cenários cobria 8% contra 90%, e a
  incerteza que o aplicativo mostra passou a ser a faixa calibrada (C2, decisão 92),
  que com as deslistadas cobria a até 5 p.p. (C2b, decisão 94) — as duas medições
  com o preço das coortes na base de ações de hoje (C3). Na base da data, a faixa
  em torno do justo cobre 84,8/74,9/49,1% e 83,6/73,0/47,0%, fora do critério. **A
  forma fixada por escrito antes de medir cobre**: 87,9/79,0/50,3% em 12 meses e
  88,2/80,4/51,2% em 36, fora da amostra, com as deslistadas (C2b, decisão 100). O
  que a faixa declara mudou junto: ela é o preço de hoje mais a volatilidade do
  papel, com o preço justo entrando pelo peso medido. **Confirma-se, ou cai, no C2c
  da Fase 4**, que a remede sobre o motor que a Fase 3 deixar
- [ ] **R3. Habilidade comprovada** — **a medir com as fases completas** (C1, Fase
  4). O instrumento está quase pronto: coortes trimestrais, deslistadas da ponte
  ampliada, base da data e o `t` corrigido pela sobreposição (C1a a C1d, C3,
  decisões 93, 96 e 97); falta o B17, a série de dez anos que deixa o beta das
  coortes de 2018 a 2021 em janela curta. A leitura sobre o motor de hoje, que não é o veredito: o
  potencial dado o B/M em 36 meses tem coeficiente de 0,030 e `t` corrigido de
  0,24 contra o crítico de 2,70

**A leitura honesta.** A Fase 1 deu ao preço justo fonte primária e procedência.
A Fase 2 construiu o instrumento que mede o motor, e **o instrumento tinha um
defeito que olhava para a frente**: o preço das coortes na base de ações de hoje
fazia parecer barata a companhia que depois desdobrou. Corrigido, o que ele mede
continua coerente, e mais duro. **O preço justo erra o realizado por um fator de
dezenas, o preço converge a ele menos de um décimo do caminho em 36 meses, e a
ordenação que ele produz não acrescenta à do book-to-market** — que, por sua vez,
ordena menos do que parecia. **O R2 fechou, e fechou por medir a incerteza onde
ela está**: no preço e na volatilidade do papel, com o preço justo entrando pelo
peso pequeno que a validação lhe deu. É uma faixa honesta e uma afirmação modesta
sobre o preço justo — a largura do erro dele continua sendo a da §8 de
[cobertura_banda.md](validacao/cobertura_banda.md). O R3 é medido no fim, sobre o
motor que a Fase 3 deixar; o R1 fecha nos defeitos de método dela, e o primeiro
deles — a tela de metas que usava a ordenação sem dizer o que ela vale — está
fechado.

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
ajudam, mas o mercado brasileiro tem o tamanho que tem. **Medido na terceira
rodada**: 22 coortes trimestrais de 36 meses exigem `t` corrigido de 2,70 para o
nível de `t > 2`, e só o book-to-market passa.

**O instrumento pode estar errado de um jeito que favorece a hipótese.** O preço
na base de ações de hoje inflou os dois sinais de valor por quatro dias de
medições, e passou por duas rodadas de lentes e pela conferência do C1b. Só
apareceu quando o C3 foi ao COTAHIST pelo preço bruto. Toda montagem de coorte
nova precisa conferir o preço contra a fonte bruta antes de medir.
