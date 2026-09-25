# Plano para o motor de referência

O que falta para dois objetivos distintos, item a item, com o critério que diz
quando cada um está pronto. **Este documento é mantido atualizado a cada
rodada**: a §6 traz o estado e o *pronto se* de cada item, e a §7 diz, com a
mesma régua, onde cada objetivo está. O que cada rodada encontrou, o que as
lentes disseram e o que a auditoria reprovou ficam no
[histórico](plano-motor-de-referencia-historico.md).

> **Última atualização: 24/09/2026 — o C7 começou: a réplica fora da amostra
> está selada.** As previsões das três coortes novas — 31/12/2025, 31/03 e
> 30/06/2026, 1.018 observações, 284 avaliadas — estão em `docs/validacao/c7/`,
> com o hash de cada arquivo no índice e o motor identificado pela impressão das
> fontes do núcleo. A leitura fica travada até 30/09/2029 (12 meses) e
> 30/09/2031 (36 meses) ([decisão 133](decisoes/133-a-replica-fora-da-amostra-comeca-selada.md)).
> **O painel de logs passou a receber o rastro íntegro**: serializável sempre,
> com o diagnóstico inteiro, e emitido por toda saída da avaliação, inclusive
> exceção, falha de preparo e isolate (D4, [decisão 131](decisoes/131-o-rastro-exportado-e-integro.md)).
> **As lentes acharam dois defeitos, fechados como B27 e D5**: a cópia dos
> insumos que tirava a segunda leitura de quatro concessionárias, e o cache que
> misturava bases de preço depois de um desdobramento. Nenhum dos dois muda
> preço justo no gabarito. **E a `metodo` achou uma premissa que ninguém tinha
> declarado**, aberta como **B28**: a emissão de ações entre o balanço e a data
> entra no divisor e não entra no patrimônio. Por isso o valuation exemplar tem
> **oito de nove** condições até ela ser medida. **R1 e R2 continuam atingidos,
> e o motor de referência não**, porque o R3 exige habilidade comprovada. O C8 fica
> para depois, por decisão do usuário. As rodadas anteriores estão no
> [histórico](plano-motor-de-referencia-historico.md).

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
>
> **E sobre o motor da decisão 102, em 16/09/2026**, o potencial dado o B/M cai a
> 0,010, com `t` corrigido de 0,08; o B/M tem IC de 0,186 e deixa de passar no
> critério da decisão 96. **O B1 tirou o prêmio do retorno esperado** até uma
> ordenação passar ([ordenacao_lado_a_lado.md](validacao/ordenacao_lado_a_lado.md)).

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

**Estado: decidido em 16/09/2026 pela recomendação, e medido** ([decisão 103](decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md),
[ordenacao_lado_a_lado.md](validacao/ordenacao_lado_a_lado.md)). **O preço justo é o
produto, e o prêmio do retorno esperado sai da ordenação comprovada** — a saída
(a), com a (c) como método. A medição e a regra foram fixadas por escrito antes de
medir: o composto dos escores do potencial, do book-to-market e do lucro sobre o
preço, com pesos iguais; o book-to-market; e o potencial, sobre as mesmas
observações, pelo critério da decisão 96; o prêmio sai da primeira que passar, e
de nenhuma se nenhuma passar. **Nenhuma passou**: em 36 meses, o composto tem IC
de 0,173 e `t` corrigido de 1,57; o book-to-market, 0,186 e 2,52; o potencial,
0,078 e 0,61 — crítico de 2,70. O aplicativo espera de cada ativo o `Ke` dele, a
tela de metas diz por quê, e **o retorno esperado é declarado total**, com a aba
Análise dizendo ao lado do XIRR que a simulação é só de preço. A regra mora no
núcleo: quando uma ordenação passar, o prêmio volta dela sem mudar código.

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
o que o prêmio deve ser é o B1. **O B1 decidiu em 16/09/2026**, e a ressalva passou
a dizer também de onde sai o prêmio — hoje, que não há.

### B2. Medir o potencial ortogonalizado como produto

Se o motor tem `IC = +0,0394` ortogonalizado ao B/M em 36 meses, esse resíduo é
exatamente "o que o DCF sabe que o valor patrimonial não sabe". Publicá-lo como
grandeza própria — e medi-lo a cada rodada — transforma a §0 de acusação em
métrica de acompanhamento.

### B3. Prêmio de risco de mercado deixa de ser parâmetro

§2.2: hoje é 5,5% fixo. Alternativas: prêmio implícito (Damodaran), histórico
com encolhimento, ou implícito da própria seção. **Move o nível de todo mundo
junto, e portanto quase nada na ordenação** — item de "exemplar".

**Estado: feito em 21/09/2026, e as duas saídas foram rodadas**
([decisão 116](decisoes/116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md),
[premio_de_mercado.md](validacao/premio_de_mercado.md)). O **histórico** do
Ibovespa contra o CDI dá **0,39%**, com erro-padrão de **7,85 p.p.** e intervalo
de 95% de −15,0% a +15,8%: são precisos **308 anos** de série para um
erro-padrão de um ponto. O **encolhimento** — a saída que o item nomeia — dá
peso de 0,1% à amostra e **devolve 5,49%**. O **implícito** que zera o potencial
mediano é de **−3,9%**: o acionista exigindo quase quatro pontos abaixo do CDI.

**5,5% fica, e deixa de ser convenção.** A previsão da seção se confirmou —
postos de 0,996 ou mais entre 4% e 7% —, **mas a varredura resolveu outra
coisa**: o desacordo de nível do motor **não é do prêmio**. Zerá-lo move o
potencial mediano de −44,7% para −29,9%, e dois terços do desacordo sobrevivem a um prêmio
nulo. A explicação está na [decisão 112](decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md).

### B4. Risco-país e o que mais falta no custo de capital

Não há prêmio de risco-país, nem ajuste por tamanho, nem qualquer fator além do
beta. Um CAPM de fator único é defensável num artigo e é fraco como motor
de referência.

**Estado: os dois recusados, com medição, em 21/09/2026**
([decisão 117](decisoes/117-risco-pais-e-tamanho-sao-recusados-com-medicao.md),
[risco_pais_e_tamanho.md](validacao/risco_pais_e_tamanho.md)).

**Risco-país já está no desconto.** A taxa livre de risco é brasileira, em
reais, e rende **9,23% real** contra ~2% do americano de longo prazo: os sete
pontos de diferença são exatamente o que um prêmio-país serve para introduzir.
A forma usual — prêmio maduro mais prêmio-país, perto de 8% — custa **−13,3%** de
preço justo e quatro avaliações, para contar duas vezes a mesma coisa. O caminho
correto de usá-lo seria avaliar em dólar contra a curva americana, e não é o
deste projeto.

**O tamanho já é cobrado pelo beta.** Postos de **−0,327** entre o logaritmo do
valor de mercado e o beta: o tercil menor tem beta mediano de **1,387** contra
**0,876** do maior, e a diferença de 0,511 vale **2,81 p.p.** de custo do capital
próprio — **acima** da magnitude do prêmio por tamanho da literatura. Somar 2
p.p. por cima só do tercil menor derruba **11,6%** do preço justo dele, deixa a
ordenação em postos de 0,992, e o faz **no tercil de potencial menos negativo**.

**A recusa é do ajuste, e não da crítica**: o CAPM continua de fator único, e
isso continua declarado.

### B5. Triangulação por múltiplos

Nenhuma avaliação profissional entrega DCF sozinho. Um múltiplo de pares —
EV/EBITDA, P/L, P/VP setorial — dá uma segunda leitura e, principalmente, um
teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa.

**Estado: feito em 21/09/2026** ([decisão 118](decisoes/118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md),
[multiplos.md](validacao/multiplos.md)). Os três múltiplos entram, com a mediana
de pares vinda de **pacote versionado** — o núcleo avalia um ativo por vez e não
calcula mediana de bolsa sem deixar de ser puro, que é o arranjo do prior do beta
e do registro da B3. Grupo por múltiplo, na ordem subsetor, setor e mercado, com
mínimo de cinco pares; aplicabilidade declarada quando morde — prejuízo tira o
P/L e **não o inverte**, banco não usa EV/EBITDA; e o **divisor da ponte dos dois
lados**, ou a comparação mediria a ponte.

**O teste de sanidade que a §2.8 discutia em prosa agora tem número.** Os 97
recebem leitura, 70 as três, e a divergência mediana é de **+73,4%** — o DCF fica
acima dos pares em **apenas 14 de 97**. O potencial mediano é de −45,4% pelo
fluxo e de −3,2% pelos múltiplos, com postos de **0,445** entre as duas
ordenações. São os números de 24/09/2026, sobre o motor que fecha a Fase 3: até
ali, quatro concessionárias ficavam sem leitura por um campo que a cópia dos
insumos perdia (B27).

**O −3,2% é quase mecânico** e não é evidência: as medianas saem dos preços dos
pares, e avaliação relativa devolve o preço de mercado por construção. O que fica
estabelecido é que **o desacordo de nível do motor não é com o mercado, é com
qualquer leitura relativa** — e que as duas ordenações são meio diferentes, o que
faz do múltiplo relativo candidato à comparação da §0 (item **B22**).

### B6. O horizonte de projeção é fixo em dez anos

Para todo mundo, independentemente de ciclo, setor ou maturidade. Nunca foi
medido se dez é melhor que sete ou quinze.

**Estado: medido e decidido em 21/09/2026**
([decisão 115](decisoes/115-o-horizonte-fica-em-dez-anos-por-medicao.md),
[horizonte.md](validacao/horizonte.md)). **A mediana do preço justo anda entre
−1,0% e +0,8% de cinco a vinte anos**: quadruplicar a projeção explícita não move
o ativo mediano. O que muda é **onde o valor mora** — o peso do terminal vai de
**59,2%** a **8,4%** —, as caudas (p10 de −3,3% a −23,3%) e a cobertura (102 a
94 avaliados).

**Dez ficam**, entre o terminal dominante a cinco anos e a extrapolação de duas
décadas a vinte. E a varredura deu de graça uma evidência que não procurava: **a
invariância ao horizonte é o terminal neutro funcionando** — o valor terminal
neutro transfere valor do terminal para os fluxos sem mudar o total, e é
exatamente o que se observa.

**A perna da habilidade depende do C5.** No lugar dela fica o limite superior do
efeito: com postos de 0,9828 entre os extremos, a desigualdade
`|ΔIC| ≤ (1−ρ)·IC + √(1−ρ²)` dá **+0,20** — e não é apertada. A aposta de que a
habilidade esteja escondida no horizonte é fraca, e não está descartada.

### B7. Consistência real × nominal

O motor desconta fluxo nominal a taxa nominal e usa o IPCA só no teto da
perpetuidade. Nunca foi conferido que as duas pontas usam a mesma convenção de
inflação em todo o caminho.

**Estado: provado em 21/09/2026, por invariância**
([decisão 114](decisoes/114-o-motor-e-nominal-e-a-nao-neutralidade-de-unidade-esta-medida.md),
[real_nominal.md](validacao/real_nominal.md)). Conferir lendo o código não é
prova: é a mesma inspeção que deixou passar tudo o que as rodadas anteriores
acharam. A prova é que **valor presente é quantia de hoje** — reexpressa a conta
em moeda constante, o preço justo tem de ficar onde estava.

**Vale ao último dígito** no desconto dos fluxos, no decaimento linear do
crescimento e na estrutura a termo da taxa. O decaimento sobreviver a Fisher não
era óbvio, e fecha porque interpolar linearmente entre dois fatores brutos é o
mesmo que interpolar entre os deflacionados.

**Não vale em três lugares, e os três têm forma fechada**: o caixa no meio do
ano, que custa meia inflação; o terminal neutro, que vale `r∞ ÷ (r∞ − π)` —
**1,305** na mediana dos 97 —; e o freio de reinvestimento. **A raiz é uma só**:
operação sobre taxa **líquida** não é neutra à unidade, e `g = b·ROIC` é
identidade **nominal**. A formulação nominal é a correta, e a tradução ingênua
para termos reais é que estaria errada.

### B8. Reapresentação no *point-in-time*

A ingestão adota a **última versão** de cada documento, e 24,8% dos anuais têm
mais de uma. A data de cada versão está gravada; usá-la é o que torna a coorte
honesta. Evidência: a DFP de 2023 da USIM3 foi reapresentada, e a versão
ingerida tem recebimento em 16/01/2025 — em 04/09/2024 o ano ficava sem CVM, e
a decisão 78 o devolve ao mercado em vez da versão original.

**Estado: medido em 21/09/2026, e o conserto depende do C5**
([reapresentacao.md](validacao/reapresentacao.md)). **São duas metades.** A
primeira — o documento que **some** porque a última versão chegou depois da
coorte — é medível com o pacote versionado, e é pequena: de 0,0% a 1,1% dos
exercícios que deviam estar públicos, com a pior coorte em 30/06/2020, quando a
CVM prorrogou prazos. Um sexto dos documentos chega além do prazo regulamentar —
784 DFP e 2.385 ITR —, e os extremos são grandes: a DFP de 2011 do Itaú tem
recebimento em 2020, 3.000 dias depois. **A segunda metade — o número
reapresentado entrando na coorte como se fosse o original — não é medível sem as
versões antigas**, e é a maior por construção. Guardar cada versão é trabalho de
ingestão sobre a base bruta.

**Estado: feito em 22/09/2026** ([decisão 128](decisoes/128-a-coorte-le-a-versao-que-era-publica-na-data.md),
[reapresentacao.md](validacao/reapresentacao.md) §4). **A versão original não
estava nos CSVs, e estava no RAD**: o índice da CVM traz o `ID_DOC` de cada
versão, e o RAD entrega o pacote dela. As 626 versões vigentes em alguma coorte
foram baixadas — 616 convertidas, com a conversão conferida conta a conta contra
os CSVs nos dois formatos que o RAD usou —, a ingestão as grava à parte com a data
de cada uma, e o núcleo escolhe a vigente em cada data. **Medido com duas
execuções sobre o mesmo motor**: o preço justo muda em 2,8% das observações
avaliadas, muito quando muda, e a leitura do R3 não se move.

### B9. WACC estático e WACC resolvido com convenções de dívida diferentes

Da lente `metodo`, em 14/09/2026. O custo de capital realavancado da decisão 41
pondera pela **dívida líquida**; o WACC estático, que é o recuo, pela **bruta**; a
ponte desconta a líquida. As duas vias de taxa não usam a mesma convenção, e a
diferença cai sobre ativo com muito caixa.

**Estado: feito em 20/09/2026** ([decisão 104](decisoes/104-a-divida-do-wacc-e-a-liquida-como-no-resto-do-modelo.md),
[divida_do_wacc.md](validacao/divida_do_wacc.md)). A dívida dos pesos passou a ser
a líquida — a mesma que a apuração do capital próprio subtrai, que a
realavancagem pondera e contra a qual o beta é desalavancado (decisão 54). **Não
era questão de estilo**: o fluxo da firma é operacional, o valor que ele desconta
é o dos ativos operacionais, e dar peso de dívida bruta e devolver o caixa ao
acionista conta o mesmo caixa duas vezes. A ausência de estrutura passou a ser
medida na bruta, e com caixa líquido o peso da dívida é negativo, o WACC fica
acima do `Ke` e a avaliação diz isso. **O efeito, na montagem de então:** o preço
justo sobe 3,0% na mediana em 73 de 114, e até 41,9% na EMBJ3; na montagem com o
prior, que já usava a líquida, muda em 2 de 102. **E a medição expôs um sintoma
que é do B11**: um desconto maior subindo o preço justo, porque sem taxas
resolvidas a via da firma reinveste contra o WACC e desconta ao `Ke`.

**A regra valia pela metade, e foi completada em 21/09/2026**
([decisão 113](decisoes/113-o-caixa-rende-a-taxa-livre-de-risco-e-nao-o-custo-de-emprestimo.md)).
A decisão 104 disse, no caso **sem dívida contratada**, que o que remunera o peso
negativo é caixa, e caixa rende `R_f`. Com dívida contratada e caixa maior que
ela — peso negativo, `hasContractedDebt` verdadeiro — o `K_d` aplicado continuava
sendo `R_f + spread`: o caixa era creditado com **prêmio de crédito**. A lente
`metodo` apontou a diferença, e a perna do financiamento se abriu em duas,
`+ w_bruta·K_d(1−escudo) − w_caixa·R_f(1−τ)`, sobre o mesmo denominador. **Os
pesos não mudam** — a diferença dos dois é a participação da líquida —, e o que
muda é a taxa de cada metade, nas duas rotas. **O efeito:** o WACC sobe em todo
ativo com caixa (ANIM3, de 17,7% para 19,6% no primeiro ano); o preço justo muda
em 61 dos 99, com mediana de +0,28%, e **três ativos deixam de ser avaliáveis** —
MOTV3, MYPK3 e QUAL3, cujo valor de firma não cobre mais a dívida líquida.

**E o mesmo defeito tinha um segundo lugar, achado na rodada seguinte pela mesma
lente** ([decisão 119](decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md)).
A ponte do acionista da rota derivada — que é o **caminho de produção** da via da
firma desde a decisão 102 — calculava o serviço da dívida como
`D_líquida·(K_d(1−τ) − g)`: com caixa, o caixa rendia ao custo de **empréstimo**,
e o fluxo do acionista saía inflado em toda companhia com caixa no balanço. A
correção é a mesma álgebra, e o efeito é grande: **o preço justo cai em 73 dos
97, todos**, com mediana de −4,63% e p10 de −42,8%; ENGI11 e GOAU4 deixam de ser
avaliáveis. **Toda a medição da rodada foi refeita depois dela.** Fica o aviso de
método: **corrigir uma ocorrência não corrige a regra**.

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

**Estado: feito em 16/09/2026** ([decisão 102](decisoes/102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md)).
A varredura foi refeita sobre a entrada congelada do gabarito, com o nível da taxa
livre de risco — a corrente, a de equilíbrio e a curva inteira — de −3 a +3 p.p.:
**25 de 128 avaliados pelo aplicativo subiam com a taxa**, 18 por trocarem de via
na grade e **7 por outra causa**, que a varredura achou: a faixa que decide se a
cobertura de juros entra no prêmio de crédito andava com a taxa suposta, e 25
pontos-base tiravam a cobertura da conta. Com as duas correções — nenhuma
avaliação muda de via, e a faixa do crédito é medida na taxa da data —, **nenhum
dos 114 avaliados sobe com a taxa**. A PRIO3 foi a −72,3%, pela via da firma e
monótona. Na montagem com o prior do beta, que o aplicativo não usa, sobram 2 de
104, pelo veredito da perpetuidade que alterna entre passes — foi para o B11.

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

**Estado: feito em 20/09/2026** ([decisão 105](decisoes/105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md),
[prior_no_aplicativo.md](validacao/prior_no_aplicativo.md)). **O prior é
empacotado com o build**, como a curva na web e o registro da B3: resolvê-lo em
tempo de execução é varrer o universo inteiro para avaliar um ativo. Ele anda
devagar, e isso foi medido — a mediana desalavancada vai de 0,6421 a 0,6620
recuando um ano, 3,1% —, e o pacote vale por um ano; fora da validade, o motor
volta ao beta cru **e a avaliação diz que voltou**.

As quatro pendências do item foram resolvidas antes de ligar. **O custo da dívida
do solucionador** era o observado, que a decisão 31 já descartara e que não decai
com a curva: passou a ser `Rf_t + prêmio`, e só isso move o preço justo em 76 de
98 da montagem com prior, com mediana de −7,0% — a RADL3 vai de R$ 3,43 a R$ 7,42,
e as duas montagens param de discordar por um fator de dois. **A tensão da via do
acionista** estava com o sinal invertido: o modelo **re**alavancava, porque a
dívida crescia a `g` enquanto o fluxo já financiava o crescimento com lucro
retido — o mesmo crescimento financiado duas vezes. A dívida ficou constante em
termos nominais, e a desalavancagem passou a ser a do lucro retido. **O que a tela
mostra** passou a sair das premissas finais: a taxa exibida é a do ano 1
resolvido, a faixa é centrada no preço justo e o cenário move o caminho de `Ke`.
**E os dois ativos que subiam com a taxa** no caminho resolvido — RADL3 e SEER3 —
ficaram monótonos.

**O efeito de ligar:** 83 das 102 avaliações resolvem as taxas, e todas as 82 da
via da firma; 14 ativos saem pela recusa de estrutura da decisão 45 — RENT3,
RENT4, UGPA3, RAIL3, ECOR3, ENEV3, DXCO3, LOGG3, CAML3, DASA3, MOVI3, PNVL3,
VAMO3, VBBR3 —, a GOAU4 entra, e o preço justo cai 2,4% na mediana. Somando o B9
da mesma rodada, a mediana do aplicativo se move **−0,4%**: os dois itens andam
em direções opostas e quase se cancelam no nível.

### B12. O excedente do capital existente na perpetuidade

Da lente `metodo`, em 14/09/2026, conferido na álgebra do DCF. O terminal neutro
`lucro_{N+1}/r` recusa o valor do capital novo, e mantém para sempre o retorno
acima do custo do capital que já existe no ano N: é `capital_N + EVA_{N+1}/r`.
Nas concessões o A6 corta esse excedente no fim do contrato. **Fora delas é
premissa não declarada** — o comentário de `DcfAssumptions` dizia que o terminal
neutro era a afirmação de que "não há lucro econômico em perpetuidade", e não é.
Declarar, medir o peso dele no preço justo e decidir se decai.

**Estado: feito em 21/09/2026** ([decisão 107](decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md),
[terminal_excedente.md](validacao/terminal_excedente.md)). **A medição inverteu o
que este item supunha.** O capital instalado rende, na perpetuidade, **0,71 vez**
o custo de capital de equilíbrio na mediana — 12,9% contra 18,9% — e fica
**abaixo** dele em 71 dos 83 avaliados em que a decomposição se aplica: o terminal
mantém um **déficit** para sempre, e não um excedente. O peso é de −14,1% do preço
justo na mediana, passa de 10% em módulo em 50 e de 20% em 33.

**E decair num horizonte não é uma terceira saída.** A 18,9% ao ano o excedente é
quase todo valor presente dos primeiros anos: truncá-lo em 20 anos devolve 0,4% do
preço, e em 30, 0,1%. A escolha é binária — ou o instalado mantém o retorno que
tem, ou converge ao custo de imediato, o que move +14,1% na mediana.

**Decidido: o número fica, o rótulo muda, o peso é declarado.** Trocar o terminal
por `capital_N` é afirmar reversão da rentabilidade à média, que o motor não
mediu — e a decisão 35 exige, de quem proponha trocar o terminal, um argumento que
não seja o viés de nível. O rótulo passa a ser `RONIC_∞ = r`, sobre o capital
novo; o peso sai nos diagnósticos, sempre no rastro de auditoria, e vira ressalva
acima de 20% em módulo. **Medir a reversão à média virou o B19.**

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

**Estado: feito em 16/09/2026, junto com o B10** (decisão 102, que substitui a 39).
Dos 109 não financeiros avaliados pelo aplicativo, 42 tinham o preço, inteiro ou
em parte, da via do acionista — 37 migrados e 5 mesclados. **Nenhum tem mais**: a
via da firma avalia o capital próprio pelo fluxo do acionista derivado do da
firma, sem ponte, sem pós-condição e sem migração, e a via do acionista fica para
o que o roteamento manda — instituição financeira e lucro operacional não
sustentado, fatos de longo prazo que não dependem da taxa nem da conta. **A
discordância entre as duas vias deixa de ser defeito**, porque nenhum ativo tem o
preço escolhido entre elas. O custo: 16 ativos saem do aplicativo, onde o fluxo do
acionista derivado não sustenta capital próprio positivo, e o preço justo dos que
eram só da firma cai 5,5% na mediana, porque sem taxas resolvidas o `Ke` do CAPM e
o WACC de pesos de mercado não coincidem.

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

**Estado: feito em 21/09/2026, e a recusa fica** ([decisão 108](decisoes/108-a-recusa-por-liquidez-fica-e-o-beta-corrigido-fecha-um-terco-da-distancia.md),
[beta_liquidez.md](validacao/beta_liquidez.md)). **O viés existe e cresce com a
iliquidez**: nos 37 soltos que negociam menos de 120 pregões por ano, o beta vai
de 0,134 a 0,294 com uma defasagem e a 0,367 com cinco. **E não chega perto.** Com
o mesmo encolhimento que a produção aplica, o beta dos soltos vai de 0,527 a 0,723
com cinco defasagens, contra 0,955 dos avaliados, e o potencial mediano deles vai
de −30,4% a −36,9% contra −48,2% — **dos 17,8 p.p. de distância, Dimson fecha
6,5**. A correção ainda triplica o erro-padrão nos dois grupos, e o encolhimento
pondera por `1/SE²`: adotá-la no universo transferiria peso para o prior setorial
onde o beta diário está certo. **Sobra um grupo sem explicação**, e ele é
nomeado: os 100 soltos que negociam todo pregão têm beta de 0,801, quase o dos
avaliados, e a distância de nível inteira.

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

**Estado: feito em 21/09/2026** ([decisão 109](decisoes/109-a-perpetuidade-declara-de-onde-vem-o-beta-e-a-estrutura-e-nao-os-converge.md),
[perpetuidade.md](validacao/perpetuidade.md)). **Metade do apontamento caiu com a
decisão 105**: o aplicativo resolve o caminho de taxas, e a alavancagem de
equilíbrio é a do ano N do modelo, não a de hoje — medida ativo a ativo, ela fica
a **−0,01** da de hoje na mediana, de modo que o modelo chega perto de onde
partiu. Sobrou o beta, e ele **já convergiu por outro caminho**: o encolhimento da
decisão 40 puxa cada beta ao prior transversal, o beta mediano que chega ao preço
é 0,955, e Blume por cima move a taxa de equilíbrio em −0,0% e o preço justo em
**+0,1%**. Impor a mediana setorial move 0,0% e **custa cinco avaliações**, porque
a alavancagem imposta quebra o ponto fixo. **Decidido: declarar a origem das duas
pontas — `terminalEquityShare` sai nos diagnósticos — e não adotar nenhuma das
alternativas**, que ficam como imposição de diagnóstico para a próxima leitura não
refazer a pergunta sem instrumento.

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

**Estado: feito em 20/09/2026** ([decisão 106](decisoes/106-a-razao-de-unidade-sai-da-composicao-declarada-e-a-medida-confere.md),
[ponte_por_papel.md](validacao/ponte_por_papel.md) §7). **A composição declarada
decide, e a medida vira conferência** — no aplicativo e nas coortes, pelo
formulário mais recente até a data da avaliação. A chave é o **CNPJ**, e não o
código de negociação: a coluna de código vem em branco em 44% das linhas e zerada
no BTG, que declara a BPAC11 sob `000000`. Nove das dez units do universo saem com
composição declarada; na ONCO11, que a companhia não declara, o motor infere **e
diz que inferiu**. **No aplicativo nenhum número muda**, porque a razão medida
coincidia com a declarada nas sete units avaliadas — o que muda é a dependência
de uma convenção de fonte que não é conhecida, e o rastro passa a trazer as duas
razões. A leitura do texto livre foi para o núcleo, porque deixou de ser
conferência e passou a decidir número, e ganhou o caso que errava: código de três
letras, a ENGI11 de 2018 com "1 ENG3 e 4 ENGI4". **Nas coortes o ganho só entra
quando o backtest for reexecutado** (C5).

### B18. A recusa de estrutura é decidida pelo chute inicial do ponto fixo

**Achado em 20/09/2026, ao ligar o prior** ([prior_no_aplicativo.md](validacao/prior_no_aplicativo.md)
§5). Os 14 ativos que saíram do aplicativo foram recusados pela decisão 45, e
todos no **ano zero da primeira iteração**: o valor da firma, descontado à
interpolação de dois pontos de que o ponto fixo parte, não cobre a dívida
líquida. O guarda dispara antes de o ponto fixo ter chance de convergir.

A direção é conservadora — mais alavancagem eleva o `Ke`, que eleva o WACC, que
baixa o valor da firma —, mas **o veredito é do recuo, e não do ponto fixo**, e o
recuo é a taxa que a própria decisão 41 descartou. É a mesma forma de defeito que
o B10 mediu: a resposta depende de qual conta o motor alcançou primeiro.

**Estado: feito em 21/09/2026** ([decisão 110](decisoes/110-o-ponto-fixo-e-tentado-de-duas-partidas-e-a-recusa-deixa-de-ser-do-chute.md)).
O ponto fixo passou a ser tentado de **duas partidas** — a interpolação de dois
pontos, que é o recuo, e o custo de capital **desalavancado**, que é o mesmo
caminho no limite de dívida zero. A recusa só vale quando nenhuma das duas fecha,
e o texto dela diz isso. **Um dos 14 volta** — a CAML3 —, e a cobertura vai de 102
a 103; os outros 13 continuam recusados pelas duas partidas, de modo que a recusa
passou a ser do método. **E, porque um ponto fixo é um ponto fixo**, as duas
convergências são comparadas: divergir acima de um décimo de por cento no capital
próprio do ano zero é ressalva declarada, e **não há divergência em nenhum ativo
do universo**, nas duas montagens. Nenhum preço justo se move. A via do acionista
recebeu o mesmo tratamento, pela mesma razão.

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

**Estado: feito em 21/09/2026, pela segunda saída** ([decisão 111](decisoes/111-a-avaliacao-declara-a-janela-curta-do-beta.md)).
A avaliação passou a **declarar a janela curta**: o preparo mede a extensão da
série que estimou o beta — da primeira à última cotação alinhada, e não a
contagem de pares, porque feriado tira dias e o que se quer separar é série que
não existe —, e a cascata avisa abaixo de 80% da janela pedida. A constante da
janela mora na cascata, e o preparo a referencia, para que as duas não divirjam.
A coorte grava a janela efetiva. **Um dos 103 avaliados do aplicativo já tem
janela curta** — a CYRE4, com 0,7 ano —, e agora diz. **A cobertura pelo COTAHIST
nas listadas, que é a primeira saída, depende da base bruta (C5)**, e com ela a
contagem de quantas observações de 2018 a 2021 sofrem.

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
coeficiente de 0,030 e `t` corrigido de 0,24 contra 2,70, com as deslistadas. **Sobre
o motor da decisão 102, em 16/09/2026: 0,010 e 0,08.**

**O C1 foi para depois da Fase 3.** O usuário pediu, em 15/09/2026, para medir a
habilidade quando todas as fases estiverem completas: medir agora seria medir um
motor que a Fase 3 vai mudar.

**Estado: fechado em 22/09/2026, com o veredito de que o R3 não passa**
([decisão 129](decisoes/129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md),
[poder_r3.md](validacao/poder_r3.md)). Sobre o motor final, o potencial dado o
B/M em 36 meses dá **0,052 com `t` corrigido de 0,30 contra 2,70**, e nenhuma das
cinco ordenações passa, bruta ou líquida de custo. **E a reprovação veio com o
poder medido**, porque sem ele ela não diria nada: o menor coeficiente que o
critério vê com 80% de chance, com 22 coortes sobrepostas, é **0,62**; o
book-to-market, com a estabilidade que tem, precisaria de 0,28 e tem 37% de
chance de passar no próprio efeito. **O teste não aprovaria nenhum motor
realista** — e o potencial também não é um efeito grande escondido: a
estimativa pontual é pequena e o sinal é duas vezes mais instável que o do
book-to-market. A única via para o R3 mudar é dado novo, e ela ficou
pré-registrada (C7).

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

**Estado: feito em 22/09/2026** ([decisão 126](decisoes/126-a-tarifa-entra-na-simulacao-e-o-custo-nao-muda-a-ordem.md),
[custos_transacao.md](validacao/custos_transacao.md)). «O backtest» eram dois, e
o custo entrou nos dois. **Na simulação da carteira**, a tarifa da B3 sai do
caixa antes de cada compra, a identidade passou a ser aportado = alocado +
custos + caixa, e o efeito é quase nada: 0,024% do patrimônio em cinquenta
carteiras sorteadas — a tarifa custa menos que o arredondamento de uma ação. **Nas
coortes**, tarifa e meio spread nas duas pontas tiram 0,86 p.p. do retorno
mediano de 36 meses, e nenhuma leitura do R3 muda. O spread foi estimado papel a
papel pelo método de Abdi e Ranaldo sobre a máxima e a mínima diárias, que
passaram a ser baixadas à parte (`b3_baixar.py --extremos`); o de Corwin e
Schultz, mais citado, ordenou a liquidez ao contrário nesta amostra.

### C5. A base bruta e a reexecução do backtest

**Achado em 20/09/2026, no começo da terceira rodada da Fase 3.** O diretório
`data/` **não existe mais nesta máquina**: a base ingerida da CVM
(`data/cvm_exercicios.json`), o COTAHIST e seus derivados (`data/b3/`) e o
arquivo do Tesouro (`data/tesouro/`) são todos ignorados pelo git, e por isso não
vêm no clone. O que sobreviveu foram os **pacotes versionados** — documentos da
CVM, registro da B3, proventos, curva, outorgas — e o cache da validação.

**O que isso permitiu e o que impediu.** O gabarito da cascata passou a ler os
pacotes versionados em vez da base bruta, e com isso se reproduz num clone limpo:
as 376 avaliações, as nove montagens e a varredura do nível da curva foram
refeitas nesta rodada, e reproduzem o estado de 16/09/2026 exatamente — 114
avaliados, 104 na montagem com o prior. **O backtest não**: ele precisa do
COTAHIST papel a papel, da ponte das deslistadas e do FRE.

**Consequência.** As medições de coorte — a habilidade
([habilidade_trimestral.md](validacao/habilidade_trimestral.md)), a faixa
calibrada ([cobertura_banda.md](validacao/cobertura_banda.md)), o custo das
recusas ([recusas_custo.md](validacao/recusas_custo.md)) e a ponte por papel
([ponte_por_papel.md](validacao/ponte_por_papel.md)) — continuam sendo as do
motor da decisão 102, e não as do motor que esta rodada deixou. O C1 e o C2c da
Fase 4 dependem disto.

**Estado: feito em 21/09/2026.** A base foi restaurada e o backtest
reexecutado. A sequência inteira, que é a que um clone limpo precisa rodar:

```bash
python tool/tesouro_baixar.py                            # curva
python tool/cvm_baixar.py                                # 6,8 GB, 2010–2026
python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre   # 276 MB
python tool/b3_baixar.py                                 # COTAHIST, 17 anos
python tool/b3_ponte.py                                  # ponte das deslistadas
python tool/b3_companhias_baixar.py                      # registro por emissor
python tool/b3_complemento_baixar.py                     # setor e proventos
python tool/cvm_versoes_baixar.py                        # versões antigas (B8), do RAD
python tool/b3_baixar.py --extremos --de 2017            # máxima e mínima (C4)
dart run tool/cvm_ingerir.dart data/cvm
dart run tool/b3_deslistadas_contagem.dart
dart run tool/backtest_valuation.dart --montagem aplicativo \
    --com-deslistadas --trimestral
python tool/custos_spread.py                             # custo por observação (C4)
```

**Desde 22/09/2026 há três passos a mais** (itens B8 e C4). As versões antigas
dependem da ponte das deslistadas, e o RAD reseta conexões longas: repita o
comando até ele dizer que nada falta — ele retoma de onde parou. Sem elas, a
ingestão e o backtest avisam e seguem com a última versão de cada documento.

**A ordem não é livre**, e três dependências não estavam escritas em lugar
nenhum: `b3_deslistadas_contagem` precisa da ponte, que precisa do COTAHIST; o
backtest precisa do complemento da B3, que precisa do registro por emissor.
Descobri-las custou três execuções abortadas, e por isso o bloco acima existe.

**A ingestão:** 42.145 documentos, 1.224 companhias, 14,5% de reapresentados, e a
identidade ativo = passivo fechando em 42.015 de 42.021. **O backtest:** 10.919
observações, 31 coortes, 381 ativos no universo.

**As quatro medições foram regeradas, e duas mudam a leitura.** A **faixa
calibrada replica** sobre o motor da Fase 3 — e isso fecha o C2c e o R2 (decisão
124). E **nenhuma das cinco ordenações passa**: o potencial vai a 0,089, o
condicionado ao B/M a 0,027, e o **book-to-market cai de `t` corrigido 2,52 para
1,98** — deixando de passar também ele.

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
Ibovespa servido e o universo; a conferência repete os três sem ir à rede, em
três minutos. O controle — conferir o código intacto — deu idêntico; e uma
mutação que só troca a ordem de dois passos do rastro, sem mudar número,
**divergiu em 1.212 das 3.420 montagens**.

**E, desde 20/09/2026, o gabarito se reproduz num clone limpo.** Ele lia a curva
do CSV do Tesouro e os documentos da base ingerida da CVM, e os dois moram em
`data/`, que é ignorado pelo git: numa máquina sem a base bruta ele não roda. Ele
passou a ler os **pacotes versionados** — `assets/tesouro/curva.json` e
`assets/cvm/documentos.json` —, que são as duas fontes de que aqueles arquivos
são gerados e o que o aplicativo de fato lê. A montagem `aplicativo` passou a
ler também o prior do beta e a composição das units dos pacotes, pela mesma
razão. **A troca foi conferida**: sobre a entrada congelada, ela reproduz o
estado de 16/09/2026 exatamente — 114 avaliados na montagem do aplicativo e 104
na do prior. O modo `--regravar` grava sem atualizar a entrada congelada, que é
o que permite medir o efeito de uma mudança sem misturá-lo com a deriva do dado.

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

**Estado: fechado em 22/09/2026.** Estudo e metas entraram **populadas** na
matriz de estouro, e a de metas estourava: o título do veredito, num `Row` sem
`Expanded`, passava 141 px em 320 dp sob 2,0x. E o veredito do moat que não se
estabiliza ganhou teste do jeito que dava para ter: a volta foi extraída para
`MoatFixedPoint.iterate`, uma função pura das três funções que a compõem, e o
teste alimenta um veredito que alterna para sempre. Fabricar um ativo na
fronteira seria frágil — o primeiro parâmetro que mudasse o tiraria de lá —, e
o gabarito confere, bit a bit, que a cascata continua fazendo a mesma conta.

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
| C0b | Custo da recusa por liquidez com as deslistadas | R3 | ✅ | o IC do potencial sem o corte de liquidez, condicionado ao B/M, é remedido com as deslistadas do C1b, e a decisão 91 é mantida ou substituída pelo resultado — atingido: a recusa fica pelo nível, e a razão da investibilidade sai ([decisão 95](decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)); **remedido na base da data, trimestral**: 0,084 e 0,148 dado o B/M, `t` corrigido de 1,67 e 1,16 contra 2,24 e 2,70 — a ordenação é direção, e não prova; o nível, −25,4% contra −51,5%, mantém a recusa ([recusas_custo.md](validacao/recusas_custo.md) §7); **sobre o motor da decisão 102**, 0,074 e 0,137, `t` corrigido de 1,47 e 1,10, nível de −27,6% contra −49,4% — a leitura não muda (§8); **remedido em 24/09/2026 com a cópia dos insumos corrigida (B27)**: 0,061 e 0,093 dado o B/M, `t` corrigido de 1,19 e 0,70, e nível de −28,1% contra −54,3% — a leitura não muda ([recusas_custo.md](validacao/recusas_custo.md) §9) |
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
| B1 | O que o potencial serve | R3 | ✅ | decisão registrada entre as três saídas da §3 (recomendada: medir DCF e modelo transversal lado a lado), e retorno esperado e tela de metas coerentes com ela — atingido: a saída (a) com a (c) como método, autorizada pelo usuário; as três ordenações medidas lado a lado pela regra fixada antes de medir, nenhuma passa, e o retorno esperado da meta e do estudo é o `Ke` de cada ativo, declarado total, com a regra no núcleo e o pacote contra a medição testados ([decisão 103](decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md), [ordenacao_lado_a_lado.md](validacao/ordenacao_lado_a_lado.md)) |
| B10 | Migração de via descontínua | R1, E | ✅ | um teste varia a taxa em torno do limiar de migração e o preço justo não sobe com a taxa, a PRIO3 é remedida, e a varredura do nível da curva do `dcf_reverso` é refeita no universo sem ativo não monótono — atingido: a varredura do nível, de −3 a +3 p.p., refeita sobre a entrada congelada do gabarito, dá 0 de 114 avaliados pelo aplicativo subindo com a taxa, contra 25 de 128; o teste do nível da curva inteira e o da faixa do crédito reprovam no código de antes; a PRIO3 vai de −17,9%, migrada, a −72,3%, monótona ([decisão 102](decisoes/102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md), [monotonia_vias.json](validacao/monotonia_vias.json)). **O critério ficou mais largo que o item**: a varredura achou uma segunda causa, a faixa do prêmio de crédito, e ela entrou |
| B9 | Convenção de dívida no WACC | R1, E | ✅ | o WACC estático e o realavancado usam a mesma convenção de dívida, declarada, com teste — atingido: a dívida dos pesos é a **líquida**, a mesma da apuração do capital próprio, da realavancagem e da desalavancagem do beta; a ausência de estrutura é medida na bruta, o caixa líquido dá peso negativo e a avaliação declara o WACC acima do `Ke`; quatro testes, e o efeito medido — +3,0% na mediana de 73 de 114 na montagem de então, e 2 de 102 na resolvida ([decisão 104](decisoes/104-a-divida-do-wacc-e-a-liquida-como-no-resto-do-modelo.md), [divida_do_wacc.md](validacao/divida_do_wacc.md)) |
| B11 | Prior do beta no aplicativo | R1, E | ✅ | o aplicativo e a montagem padrão da validação avaliam com o prior do beta e o custo de capital resolvido das decisões 40 e 41, com a tensão da via do acionista resolvida, os cenários e a taxa exibida saindo das premissas resolvidas, e o efeito medido na mesma execução; e, desde 16/09/2026, a varredura do nível no caminho resolvido sem ativo subindo com a taxa e o custo da dívida sintético nas duas rotas — **atingido**: o prior vem do pacote do build, com deriva medida (3,1% em um ano) e validade de um ano; 83 das 102 avaliações resolvem as taxas, e todas as 82 da via da firma; `K_d = Rf_t + prêmio` no solucionador e na rota derivada; a dívida da via do acionista fica constante, porque o fluxo já financia o crescimento com lucro retido; a taxa exibida é a do ano 1 resolvido e a faixa é centrada no preço justo; **0 de 102 sobem com a taxa nas duas montagens** ([decisão 105](decisoes/105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md), [prior_no_aplicativo.md](validacao/prior_no_aplicativo.md)) |
| B16 | Razão de unidade pela composição declarada | R1, E | ✅ | a composição de cada unit sai de fonte declarada — a FCA da CVM, por ano — no pacote do aplicativo e nas coortes, a razão medida do valor de mercado vira conferência, e as 79 observações de unit que a inferência erra nas coortes passam a sair com a composição, com teste — atingido: pacote por CNPJ e por ano com as nove units declaradas, leitura do texto livre no núcleo com o caso de três letras corrigido, conferência declarada na avaliação e no rastro, e a ONCO11, que a companhia não declara, seguindo inferida e dizendo que é; **as coortes só recolhem o ganho com a reexecução do backtest (C5)** ([decisão 106](decisoes/106-a-razao-de-unidade-sai-da-composicao-declarada-e-a-medida-confere.md), [ponte_por_papel.md](validacao/ponte_por_papel.md) §7) |
| B13 | As duas vias discordam | R1, E | ✅ | a via do acionista sobre LPA fica só para instituição financeira, ou as duas vias concordam dentro de tolerância declarada e medida no universo, ou uma decisão nova substitui a 39 e diz por que a discordância deixa de ser defeito — resolver junto com o B10 — atingido pela terceira saída: a decisão 102 substitui a 39; nenhuma avaliação muda de via, a via do acionista fica para as Portas 1 e 3, e nenhum ativo tem o preço escolhido entre as duas — 42 dos 109 não financeiros tinham antes |
| B12 | Excedente do capital existente na perpetuidade | E | ✅ | o peso de `EVA_{N+1}/r` no preço justo está medido no universo, declarado no aviso, e uma decisão diz se ele fica, decai ou acaba num horizonte — atingido: o instalado rende 0,70 vez o custo de capital na mediana e o peso é de **−12,2%** do preço justo, déficit em 69 de 80 (remedido em 21/09/2026 sob as decisões 113 e 119); truncar em 20 anos devolve 0,4%, de modo que a escolha é binária; o número fica, o rótulo passa a `RONIC_∞ = r`, e o peso sai nos diagnósticos, sempre no rastro e como ressalva acima de 20% ([decisão 107](decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md), [terminal_excedente.md](validacao/terminal_excedente.md)) |
| B14 | Beta de papel pouco negociado | E, R3 | ✅ | um beta com correção por negociação não sincrônica é medido nos soltos do corte de liquidez, o nível do potencial deles é remedido com ele contra o das avaliadas, e uma decisão diz se a recusa por liquidez fica — atingido: Dimson com uma e com cinco defasagens, nos 185 soltos e nos 102 avaliados; o viés existe e cresce com a iliquidez (0,134 → 0,367 em quem negocia menos de 120 pregões), mas fecha **6,5 dos 17,8 p.p.** de distância e triplica o erro-padrão onde não há viés: **a recusa fica** ([decisão 108](decisoes/108-a-recusa-por-liquidez-fica-e-o-beta-corrigido-fecha-um-terco-da-distancia.md), [beta_liquidez.md](validacao/beta_liquidez.md)) |
| B15 | Beta e alavancagem da perpetuidade | E | ✅ | o custo de capital da perpetuidade declara de onde vêm o beta e a estrutura de capital, o efeito de levá-los ao estado estacionário — beta em direção a 1, alavancagem da mediana do setor — está medido no universo, e uma decisão escolhe — atingido: a estrutura é a do ano N do modelo desde a decisão 105, e ela fica a −0,01 da de hoje ativo a ativo; o beta é o de hoje encolhido, e Blume por cima move **+0,1%** do preço justo porque o encolhimento já o aproximou de 1; a mediana setorial move 0,0% e custa cinco avaliações; as duas ficam como imposição de diagnóstico ([decisão 109](decisoes/109-a-perpetuidade-declara-de-onde-vem-o-beta-e-a-estrutura-e-nao-os-converge.md), [perpetuidade.md](validacao/perpetuidade.md)) |
| B17 | Série de preços das coortes limitada a dez anos | R3 | ✅ | a série que a coorte usa para o beta cobre a janela inteira de cinco anos nas listadas, pelo COTAHIST, **ou a coorte declara a janela curta** — atingido pela segunda saída: o preparo mede a extensão da série que estimou o beta e a cascata declara abaixo de 80% da janela pedida, com a constante numa fonte só; a coorte grava a janela efetiva, e um dos avaliados do aplicativo — a CYRE4, com 0,7 ano — já sai com a ressalva. **A cobertura pelo COTAHIST depende do C5**, e com ela a contagem nas coortes de 2018 a 2021 ([decisão 111](decisoes/111-a-avaliacao-declara-a-janela-curta-do-beta.md)) |
| B18 | Recusa de estrutura decidida pelo chute | R1, E | ✅ | a recusa da decisão 45 sai do ponto fixo, e não da interpolação de que ele parte — atingido: o ponto fixo é tentado da interpolação **e** do custo de capital desalavancado, e só recusa quando nenhuma das duas fecha; a CAML3 volta, os outros 13 continuam recusados pelas duas, nenhum preço se move, e a independência da partida é verificada em todo o universo — **zero divergências** ([decisão 110](decisoes/110-o-ponto-fixo-e-tentado-de-duas-partidas-e-a-recusa-deixa-de-ser-do-chute.md)) |
| B19 | Reversão da rentabilidade à média | E | ✅ | a persistência do `ROIC` contra o custo de capital está medida na série do universo — horizonte, dispersão e viés do estimador declarados —, e uma decisão diz se o terminal mantém o retorno do capital instalado ou o faz convergir — atingido: AR(1) no painel de 3.246 pares com `φ` de 0,237 e meia-vida de meio ano, `φ` mediano por ativo de 0,392 com o viés de Kendall declarado, e a leitura sem forma funcional mostrando o quinto superior indo de 14,3% a 0,1% em dez anos; **mas o destino é a mediana do mercado, 9,5%, contra 18,9% de custo de capital**, e converger o terminal a `r` afirmaria rentabilidade que a seção transversal nunca teve — **o terminal fica**, agora por medição ([decisão 112](decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md), [reversao_roic.md](validacao/reversao_roic.md)) |
| B8 | Reapresentação no *point-in-time* | R3, R1 | ✅ | a ingestão guarda cada versão com a data de recebimento dela, e a coorte usa a versão recebida até a data da avaliação — **feito em 22/09/2026** ([decisão 128](decisoes/128-a-coorte-le-a-versao-que-era-publica-na-data.md), [reapresentacao.md](validacao/reapresentacao.md) §4). Os CSVs anuais da CVM trazem só a última versão, e as antigas vieram do RAD pelo `ID_DOC` do índice: **626** vigentes em alguma coorte, **616** convertidas, com a conversão conferida conta a conta contra os CSVs nos dois formatos do RAD. A ingestão grava as antigas à parte, a base vigente ficou idêntica, e `CvmSeries.vigentes` escolhe a versão publicada mais recente na data. **O efeito é raro e grande**: o preço justo muda em 84 de 3.045 observações avaliadas (2,8%), com mediana de 21% entre elas — a ENAT3 de R$ 3,81 a R$ 20,16 —, e **a leitura do R3 não muda** (0,027 → 0,028, `t` corrigido 0,15). As dez versões que o RAD não entregou caem na última, declaradas |
| B2 | Potencial ortogonalizado | R3 | ✅ | o IC do potencial ortogonalizado ao B/M sai do `backtest_valuation` em toda execução e fica registrado — atingido: `regressao_condicional.dart`, que é o que lê a saída do backtest, passou a medir o resíduo contra o **P/B sozinho** ao lado do que já media contra P/B e L/P, com a mesma inferência do resto — `t` corrigido pela sobreposição contra o crítico e Newey-West (decisão 96) —, e o número mora em [potencial_ortogonalizado.md](validacao/potencial_ortogonalizado.md), com o histórico entre rodadas: **+0,016 em 36 meses, `t` corrigido de 0,13 contra 2,70**, positivo em 10 de 22 coortes |
| B6 | Horizonte de projeção | E, R3 | ✅ | a varredura de 5 a 20 anos está medida sobre o universo e sobre a habilidade, e o horizonte é escolhido por decisão — atingido no universo: **a mediana do preço justo anda entre −1,0% e +0,8%** de 5 a 20 anos, e o que muda é o peso do terminal, de 59,2% a 8,4%; a ordenação fica em postos de **0,9828** entre os extremos, e a cobertura vai de 102 a 94. **Dez ficam**, entre o terminal dominante e a extrapolação de duas décadas. A invariância ao horizonte saiu de graça como evidência de que o terminal neutro está bem especificado. **A perna da habilidade depende do C5**, e no lugar dela fica o limite superior do efeito — `(1−ρ)·IC + √(1−ρ²)` = +0,20, que não é apertado ([decisão 115](decisoes/115-o-horizonte-fica-em-dez-anos-por-medicao.md), [horizonte.md](validacao/horizonte.md)) |
| B7 | Consistência real × nominal | E, R1 | ✅ | um teste confere que fluxo, taxa e perpetuidade usam a mesma convenção de inflação em todo o caminho — atingido por **invariância de unidade**, e não por inspeção: reexpressa a conta inteira em moeda constante por Fisher, o preço justo tem de ficar onde estava. Vale **ao último dígito** no desconto dos fluxos, no decaimento linear do crescimento e na estrutura a termo; **não vale em três lugares, e os três têm forma fechada** — caixa no meio do ano `(1+π)^−1/2`, terminal neutro `r∞÷(r∞−π)` (1,305 na mediana dos 97) e o freio de reinvestimento. A raiz é uma só: operação sobre taxa **líquida** não é neutra à unidade, e `g = b·ROIC` é identidade nominal ([decisão 114](decisoes/114-o-motor-e-nominal-e-a-nao-neutralidade-de-unidade-esta-medida.md), [real_nominal.md](validacao/real_nominal.md)) |
| B3 | Prêmio de risco de mercado | E | ✅ | o prêmio é estimado — implícito ou histórico com encolhimento —, por decisão e com efeito medido — atingido, e as duas saídas foram rodadas: o **histórico** dá 0,39% com erro-padrão de **7,85 p.p.** (308 anos de série para 1 p.p. de erro), e o **encolhimento devolve 5,49%** porque o peso da amostra é de 0,1%; o **implícito** é **−3,9%**, que é absurdo econômico. **5,5% fica, e deixa de ser convenção.** E a varredura resolveu de passagem uma hipótese aberta desde a §0: **o desacordo de nível não é do prêmio** — zerá-lo deixa dois terços do potencial mediano de pé, de −44,7% para −29,9%; postos de 0,996 ou mais entre 4% e 7% ([decisão 116](decisoes/116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md), [premio_de_mercado.md](validacao/premio_de_mercado.md)) |
| B4 | Risco-país e tamanho | E | ✅ | decisão registrada sobre prêmio de risco-país e ajuste por tamanho, implementados ou recusados com medição — atingido: os **dois recusados, com medição**. O `R_f` deste motor é brasileiro e rende **9,23% real** contra ~2% do americano: somar prêmio-país é contar duas vezes, e custaria −13,3% de preço justo e quatro avaliações. O tamanho já é cobrado pelo beta — postos de **−0,327** contra `log`(valor de mercado), e o tercil menor tem beta 1,387 contra 0,876 do maior, que é **2,81 p.p.** de `Ke`, **acima** da magnitude do ajuste da literatura; somar 2 p.p. por cima move a ordenação em postos de 0,992 e derruba 11,6% do preço justo do tercil **de potencial menos negativo** ([decisão 117](decisoes/117-risco-pais-e-tamanho-sao-recusados-com-medicao.md), [risco_pais_e_tamanho.md](validacao/risco_pais_e_tamanho.md)) |
| B5 | Triangulação por múltiplos | E | ✅ | cada avaliação traz o preço justo por múltiplos de pares ao lado do DCF, com a divergência declarada — atingido: P/L, P/VP e EV/EBITDA, com mediana de pares em pacote versionado (`tool/multiplos_empacotar.dart`), grupo escolhido por múltiplo na ordem subsetor → setor → mercado com mínimo de cinco pares, aplicabilidade declarada quando morde e o **divisor da ponte dos dois lados**. **Os 97 recebem leitura**, 70 as três; a divergência mediana é de **+73,4%**, o DCF fica acima dos pares em só 14 de 97, e os postos entre as duas ordenações são de **0,445** — remedido em 24/09/2026, depois do B27, que devolveu a leitura a quatro concessionárias. A tela traz o cartão e a ressalva acima de 50%; **o preço justo não muda em ativo nenhum**, conferido contra o gabarito ([decisão 118](decisoes/118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md), [multiplos.md](validacao/multiplos.md)) |
| B20 | Tradução do cenário para o `Ke` | E | ✅ | uma decisão diz o que o cenário de desconto perturba, e a tradução sai dessa escolha com o efeito na faixa medido — atingido: as três leituras estão no enum `ScenarioTranslation`, e o **um a um fica**. Medido nos 77 da via da firma: a largura mediana da faixa vai de **24,9%** no um a um a 40,2% na estrutura fixa (**1,246×**) e 28,2% na taxa livre (1,070×); **o preço justo não muda em nenhuma**, e a pós-condição da decisão 105 — o cenário base volta ao preço justo — vale nas três. **E amplificar apaga uma faixa**: sob estrutura fixa a YDUQ3 perde os cenários, porque o lado otimista derruba `Ke_∞ − g_∞` abaixo do mínimo. Fica o um a um porque é a leitura que o rótulo da tela nomeia, porque é a única que faz as duas vias quererem dizer a mesma coisa, e porque é a única que não apaga faixa ([decisão 121](decisoes/121-o-cenario-move-o-ke-um-por-um-e-as-tres-leituras-estao-medidas.md), [cenario.md](validacao/cenario.md)) |
| B22 | O múltiplo relativo como ordenação | R3 | ✅ | a ordenação por `múltiplos ÷ preço` é medida lado a lado com as três da [decisão 103](decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md), pelo mesmo critério fixado antes de medir, e o registro diz se ela passa — atingido sobre as coortes reexecutadas pelo C5: **IC de +0,075 em 36 meses, `t` corrigido de 1,04 contra 2,70 — não passa**; em 12 meses é o mais fraco dos cinco, +0,029. **A mediana setorial é da própria coorte**, e não do pacote de hoje, que seria conhecimento futuro; e o potencial não passa pela ponte, porque é `valor implicado ÷ valor de mercado − 1`. Nenhuma das 2.165 observações ficou sem mediana usável: as cinco ordenações são medidas sobre o mesmo conjunto. **Nenhuma passa, e o book-to-market caiu de 2,52 para 1,98** ([decisão 123](decisoes/123-o-multiplo-de-pares-entra-como-quarta-ordenacao-e-nao-passa.md), [multiplos_ordenacao.md](validacao/multiplos_ordenacao.md)). **Remedido em 24/09/2026**, com o backtest reexecutado pelo B27: IC de 0,078, `t` corrigido de 1,15 — não passa |
| B23 | O minoritário não entra nos pesos do WACC | E | ✅ | os pesos do custo médio incluem a parcela dos não controladores, ou uma decisão diz por que não — atingido pela segunda saída, e a medição estabeleceu primeiro o **escopo**: o caminho **resolvido** pondera por `V − D` sobre fluxo consolidado, que já inclui o minoritário, e a via do acionista não tem WACC. A exposição exige via da firma **e** recuo estático **e** minoritário material, e essa interseção é **vazia** nos 97 — os 19 que recuam ao estático são todos da via do acionista. Impor o minoritário no peso move **0,00%** nos 97, pelas duas formas. **Recusado porque o dado não existe e porque não muda nada; e a condição de exposição passa a ser declarada** pela avaliação, com a fatia medida, para o dia em que a interseção deixar de ser vazia ([decisão 120](decisoes/120-o-minoritario-fica-fora-do-peso-e-a-condicao-de-exposicao-e-declarada.md), [minoritario.md](validacao/minoritario.md)) |
| B24 | O juro da rota derivada não segue a curva | R1 | ✅ | a rota derivada projeta o serviço da dívida e o rendimento do caixa com as mesmas taxas de cada ano que o ponto fixo usou para fechar o `Ke` que a desconta — **aberto e fechado em 22/09/2026**, da lente `metodo` ([decisão 127](decisoes/127-o-juro-da-rota-derivada-segue-a-curva-como-o-ponto-fixo.md)). O ponto fixo fecha o WACC com `K_d,t = Rf_t + spread` sobre os forwards da curva, e a rota derivada usava o `K_d` do primeiro ano parado — limitação declarada no código, que deixava de ser simplificação porque o `Ke` do desconto já vinha do caminho. **Medido no gabarito**: o preço justo muda em 64 de 97, mediana de −0,65%, p90 de 2,9%, e a YDUQ3 −13,1%; nenhuma recusa muda. O gabarito foi regravado |
| B25 | O rastro do custo da dívida descreve a regra antiga | R1 | ✅ | o Passo 3 do WACC no rastro de auditoria diz a regra que a conta usa — **aberto e fechado em 22/09/2026**, da lente `metodo`, na rodada do C1. Ele escrevia «custo observado fora da banda; limitado a X» e «observado dentro da banda → X», que é a regra anterior à decisão 31; desde ela o `K_d` é sempre `R_f` mais o prêmio sintético, e o observado **só arbitra** se a cobertura pode pesar. Um leitor do rastro — e a própria lente — concluía que o observado entrava na taxa. Agora o passo mostra o prêmio pela alavancagem, se a cobertura fala e por quê, e diz que o observado não entra. **Nenhum preço muda**: só o rastro, e o gabarito foi regravado. Na mesma leitura a lente pediu o prêmio de crédito recalculado ano a ano no ponto fixo, e ele foi **recusado com prova**: a dívida projetada cresce ao ritmo do lucro, e a razão que dá o prêmio — dívida sobre EBITDA — fica parada por construção; um teste cobra a premissa |
| B26 | Sem despesa financeira, o prêmio de crédito sumia | R1 | ✅ | a empresa com dívida contratada e despesa financeira não publicada paga o prêmio de crédito que a alavancagem dá, no WACC estático e no ponto fixo — **aberto e fechado em 22/09/2026**, da lente `metodo` ([decisão 130](decisoes/130-sem-despesa-financeira-o-premio-de-credito-sai-da-alavancagem.md)). O WACC estático degenerava para o `Ke` sem a despesa, e o prêmio que o ponto fixo recebe era derivado do custo que ele devolvia: **a degeneração o zerava, e o caminho resolvido tomava dinheiro à taxa livre de risco**. A NATU3 trazia no mesmo rastro «desconto ao custo do capital próprio» e um WACC de 16,3% com `Ke` de 21,0%. Agora a despesa ausente tira a cobertura da conta — sem cair no teto de 10 p.p. que a tabela dá à cobertura não medível — e o prêmio sai da alavancagem. **No gabarito, só a NATU3 muda** (−13,3%). **Nas coortes, 546 observações**, 314 delas deslistadas, que são montadas só com dado da CVM e caíam todas no defeito: mediana de −1,1% no preço justo, e o potencial condicionado ao B/M vai de 0,028 a 0,052 |
| B27 | A cópia dos insumos perdia campos | R1 | ✅ | toda cópia de `ValuationInputs` passa por um lugar só e preserva os campos que não troca, com um teste que preenche os 34 — **aberto e fechado em 24/09/2026**, achado ao conferir a integridade do rastro (D4) ([decisão 132](decisoes/132-a-copia-dos-insumos-passa-por-um-lugar-so.md)). Cada cópia repetia a lista de campos à mão, e as rodadas recentes não lembraram de todas: **`withProjectionYears`, que a concessão que acaba dentro da projeção usa em produção, perdia os múltiplos de pares**, e EGIE3, EQTL3, TAEE11 e TAEE4 ficavam sem a segunda leitura na tela; `withRiskFreeShift` perdia os mesmos campos; e as cópias do backtest e do gabarito perdiam a composição declarada da unit, a taxa de referência do crédito e a janela do beta. **Nenhum preço justo muda**, no gabarito nem no aplicativo. A triangulação vai de 93 para 97 ativos (B5 remedido), e nas montagens de diagnóstico os avisos mudam em 5, 10 e 7 ativos. **No backtest, as leituras secundárias mudam**, e ele foi reexecutado: a ancorada e o contrafactual sem o corte de liquidez passavam pelas cópias com defeito. A SAPR4 de 30/06/2021 tinha justo ancorado de R$ 5,94 contra R$ 30,15 do anual. Remedidas, **nenhum veredito muda**: a ancorada continua fora do padrão pela regra da decisão 98 (diferença de IC de +0,021, `t` corrigido de 0,27 contra 2,70), e o C0b mantém a recusa por liquidez (0,093 com `t` corrigido de 0,70; potencial mediano de −28,1% nos soltos contra −54,3%). O critério do R3 não passa por essas cópias e fica em 0,052 com 0,30 ([habilidade_trimestral.md](validacao/habilidade_trimestral.md) §10, [recusas_custo.md](validacao/recusas_custo.md) §9) |
| B28 | Evento de capital entre o balanço e a data | E | ⬜ | a variação da contagem de ações entre a data do balanço usado e a data da avaliação que não é desdobramento, grupamento nem bonificação — emissão, recompra, conversão — está medida nas coortes (a contagem do FRE por data, decisão 90) e no aplicativo (a contagem oficial da B3 contra a do exercício), com o efeito no preço justo, e uma decisão diz se o capital do evento entra no patrimônio da ponte ou se a avaliação o declara onde ele pesa — **aberto em 24/09/2026**, da lente `metodo`. A ponte por papel divide o capital próprio do último balanço pela contagem que forma a cotação de hoje, `VM ÷ P`, e isso tira desdobramento, grupamento e unit da conta por construção. **Uma emissão depois do balanço, porém, entra no divisor e não entra no numerador**: a contagem nova está no valor de mercado, e o caixa que a emissão trouxe não está no patrimônio publicado. O preço justo por papel sai subavaliado na proporção do capital captado, e a recompra faz o contrário. **Nenhuma decisão nem comentário do núcleo declara essa premissa**, e ela nunca foi medida. O balanço usado tem até cerca de um ano nas coortes, e nove meses no aplicativo de hoje. **Só a medição diz se isto move preço ou é caso de borda**, e por isso o item mede antes de decidir |
| B21 | O `Failure` carrega formatação de tela | E, prevenção | ✅ | o erro do núcleo transporta a grandeza que a regra violou, e a frase é montada na apresentação — **as três metades fecharam**. (a) em 21/09/2026 ([decisão 122](decisoes/122-o-erro-do-nucleo-transporta-a-grandeza-e-a-frase-e-montada-na-tela.md)): `InvalidInput` ganhou `limit` e `unit`, e `FailureCopy` escreve «Informado: X. Limite: Y.». (b) e (c) em 22/09/2026 ([decisão 125](decisoes/125-o-dinheiro-arredonda-o-decimal-escrito-e-o-rotulo-de-tela-sai-do-nucleo.md)): **(b) medida antes de reescrita, e só uma das três partes era defeito** — `Money.fromReais`, a única ponte do `double` para centavos, fazia `(reais * 100).round()` e perdia o meio (R$ 1,005 → R$ 1,00); agora arredonda o decimal escrito, e o gabarito continua idêntico. Os insumos contábeis em `double` não perdem centavo — a ida e volta é exata até R$ 45 trilhões, e o teste confere 20 mil valores —, e a contagem de ações do motor é **fracionária por construção** (unidade negociada, contagem implícita no valor de mercado). (c) os catorze enums perderam `label`; o rótulo de tela mora em `lib/presentation/shared/domain_copy.dart` com `switch` exaustivo, e o diagnóstico do rastro ficou privado no núcleo, com o mesmo texto — o rastro não mudou uma letra. `TerminalValueMethod`, sem uso, saiu |
| C5 | Base bruta e reexecução do backtest | R2, R3 | ✅ | a base bruta está na máquina, e o backtest é reexecutado sobre o motor da Fase 3, com habilidade, faixa, recusas e ponte regeradas — atingido em 21/09/2026: **6,8 GB da CVM** (2010–2026), **17 anos de COTAHIST**, Tesouro, FRE (276 MB), registro e complemento da B3 por emissor, a ponte das deslistadas e as contagens por data. Ingestão: **42.145 documentos**, 1.224 companhias, identidade ativo = passivo em 42.015 de 42.021. Backtest: **10.919 observações, 31 coortes**. **As quatro medições foram regeradas**, e duas mudam a leitura: a **faixa calibrada passa** sobre o motor da Fase 3 — 88,1% em 12 meses e 89,3% em 36 contra 90% nominal, desvio máximo de 2,6 p.p. —, e **nenhuma das cinco ordenações passa**, com o book-to-market caindo de `t` corrigido 2,52 para 1,98 |
| C4 | Custos de transação | R3 | ✅ | o custo de transação entra no backtest, e o efeito sobre o retorno medido é reportado — feito em 22/09/2026 nos dois backtests ([decisão 126](decisoes/126-a-tarifa-entra-na-simulacao-e-o-custo-nao-muda-a-ordem.md), [custos_transacao.md](validacao/custos_transacao.md)). **A simulação cobra a tarifa da B3** (0,030% por compra, em centavos inteiros) e mostra a linha «Custos»; em cinquenta carteiras sorteadas ela tira 0,024% do patrimônio e 0,006 p.p. do XIRR, e o spread fica declarado com a sensibilidade de 0,5% (0,53% e 0,12 p.p.). **As coortes pagam tarifa e meio spread nas duas pontas**, com o spread estimado por Abdi e Ranaldo da máxima e da mínima do COTAHIST — o de Corwin e Schultz saiu invertido na amostra e foi descartado. O retorno mediano de 36 meses cai de 14,00% para 13,14%, e **o critério da decisão 96 não muda em nenhuma ordenação**: o custo muda o nível, e não a ordem |
| D3 | Cobertura de caminhos de erro | R1 prevenção | ✅ | as telas carregadas entram no teste de estouro, o cache macroeconômico tem teste de recurso offline, o veredito que não se estabiliza em `moatMaxPasses` passes tem teste, e os datasources têm teste de payload malformado — **fechado em 22/09/2026**. As telas de estudo e de metas entraram **populadas** na matriz de três larguras e três escalas, com os providers da captura, e **a de metas achou defeito na primeira execução**: o título do veredito estourava 14, 71 e 141 px em 320 e 390 dp sob escala ampliada — corrigido. A volta entre o veredito do moat e a taxa de equilíbrio foi extraída para `MoatFixedPoint.iterate`, função pura testada com veredito sintético que alterna até o teto, trava no solucionador e respeita a imposição externa; o gabarito confere que a cascata faz a mesma conta. O offline e os datasources tinham fechado em 20 e 21/09 |
| D4 | O rastro que o painel de logs exporta é íntegro | R1 prevenção | ✅ | todo evento da avaliação chega ao painel serializável, completo e por qualquer saída — **pedido pelo usuário e fechado em 24/09/2026** ([decisão 131](decisoes/131-o-rastro-exportado-e-integro.md)). Conferi o caminho do cálculo ao arquivo, e ele perdia informação em nove lugares: `jsonEncode` lançava diante de `NaN` e derrubava a exportação e, dentro da transação, a própria avaliação; o arredondador do rastro transformava `NaN` e infinito em zero; o evento levava 5 dos 19 campos do diagnóstico, sem a volatilidade da faixa nem a triangulação; a entrada omitia a curva, a contagem oficial, a composição da unit, o prior do beta, os pares e as imposições; as ressalvas de contexto entravam depois, pela tela, e faltavam no arquivo; exceção no meio da cascata, falha de preparo e avaliação que migra de isolate não deixavam evento; e o anel único de 200 descartava as avaliações em silêncio, empurradas pelo ruído de rede. **Os nove fecharam com teste**: `AuditJson.safe`, o diagnóstico inteiro no evento, as ressalvas pela cascata, a exceção que fecha a transação, o preparo que emite, o rastro que atravessa a isolate, dois anéis com descarte contado e a exportação que diz filtro, busca e total. **No gabarito, nenhum preço justo muda** nas 3.384 avaliações; o rastro muda nas 3.258 que chegam à cascata |
| D5 | O cache de cotações não mistura bases | R1 | ✅ | depois de um desdobramento entre duas buscas, nenhuma cotação da base velha fica no disco — **aberto e fechado em 24/09/2026**, da lente `dados` ([decisão 134](decisoes/134-a-mudanca-de-base-apaga-o-ativo-inteiro-do-cache.md)). O tratamento de 21/09 apagava só o que vinha antes da resposta: o pregão que a resposta omitia **dentro** da janela ficava na escala velha (a fixture real da fonte tem um desses). E a mudança só era vista no primeiro dia da resposta, que podia faltar no disco. Agora sai o ativo inteiro, e a comparação é no primeiro pregão em comum, com um teste para cada caso. A série serve ao beta, à volatilidade da faixa e ao corte de liquidez do aplicativo. **Outros dois achados da mesma lente foram recusados com o consumidor citado**, e a disciplina dela passou a exigir essa citação |

**A ordem tem uma razão.** O B1.0 primeiro porque é defeito em produção e custa
pouco. Depois os defeitos de método (B10 com B13, B9, B11, B16, B18, B8), porque R1 não
fecha com eles abertos — e o B17 antes da Fase 4, porque é do instrumento que
mede o C1 e o C2c — e o B11 depois do B9, porque ligar o custo de capital resolvido
com convenções de dívida diferentes ligaria o defeito junto. B1 é decisão e destrava o sentido da ordenação. B2 e B6 não precisam de
dado novo. B3 a B5 movem nível e não ordenação — servem ao exemplar, e é a
ordenação que a §0 mostrou estar em dívida.

**A fase fechou em 22/09/2026 e ganhou um item aberto em 24/09**: o B28, a
premissa que a lente `metodo` achou na ponte por papel. Ele é de método e de
nível, e por isso fica aqui, e não na Fase 5. Não depende de dado novo: a
contagem por data do FRE e a oficial da B3 já estão na máquina.

### Fase 4 — a medição final

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| C6 | O poder do teste do R3 | R3 | ✅ | a reprovação do R3 diz o que o teste conseguiria ver: o efeito mínimo detectável a 80%, o limite superior que a amostra sustenta e quantas coortes cada ordenação pediria — **aberto e fechado em 22/09/2026** ([poder_r3.md](validacao/poder_r3.md), `tool/poder_r3.dart`). A simulação usa a estrutura de sobreposição com que o crítico da decisão 96 é simulado, e está calibrada: sem efeito passa em 2,4% contra 2,3% nominal. **Em 36 meses o efeito mínimo detectável é 0,62** para o critério do R3 e 0,28 para o book-to-market, que tem 37% de poder no próprio efeito e precisaria de 66 coortes — retornos em 2037. **Em 12 meses** a amostra descarta coeficiente condicionado acima de 0,20. Aberto porque «não passa» sem o poder não distingue falta de habilidade de falta de amostra |
| C1 | Habilidade, com todas as fases completas | R3 | ✅ | com as Fases 1 a 3 fechadas, o backtest monta as coortes do motor daquele dia, e o potencial condicionado ao B/M em 36 meses passa no critério da decisão 96 — `t` corrigido pela sobreposição acima do crítico dela, e Newey-West acima de 2 — **ou** o registro declara que não passa — **fechado em 22/09/2026: o registro declara que não passa** ([decisão 129](decisoes/129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md)). Sobre o motor final, com o B26 corrigido: **0,052 com `t` corrigido de 0,30 contra 2,70**, e nenhuma das cinco ordenações passa, bruta ou líquida de custo ([habilidade_trimestral.md](validacao/habilidade_trimestral.md) §9, [custos_transacao.md](validacao/custos_transacao.md)). A regra da decisão 103 devolve prêmio nenhum, e o retorno esperado continua no `Ke`. O poder do teste acompanha o veredito (C6). **Remedido em 24/09/2026**, com o backtest reexecutado pelo B27: os mesmos 0,052 e 0,30 ([habilidade_trimestral.md](validacao/habilidade_trimestral.md) §10) |
| C2c | A faixa calibrada sobre o motor da Fase 3 | R2 | ✅ | **a forma da decisão 100 é remedida sobre o motor que a Fase 3 deixar, sem escolher outra**, e cobre a até 5 p.p. da nominal em 12 e 36 meses — atingido em 21/09/2026, com as coortes reexecutadas pelo C5 e o motor doze decisões adiante: **90% nominal cobre 88,1% em 12 meses e 89,3% em 36**, desvios de **1,9** e **2,6 p.p.** contra o limite de 5, estável por tercil de potencial e entre listadas e deslistadas. **A forma não foi reescolhida** — é a mesma `VolatilityBandTable`, o que faz disto réplica e não reajuste. **O R2 é atingido sobre o motor da Fase 3** ([decisão 124](decisoes/124-a-faixa-calibrada-replica-sobre-o-motor-da-fase-3.md), [cobertura_banda.md](validacao/cobertura_banda.md)) |

**Por que a Fase 4 é só isto.** A habilidade e a incerteza são do motor, e o motor
muda na Fase 3. O C2c está aqui porque a faixa calibrada é medida sobre as mesmas
coortes e o mesmo preço justo: **a forma já está fixada** (decisão 100), e o que
falta é medi-la sobre o motor que a Fase 3 deixar — que é o teste que uma sétima
tentativa pede.

### Fase 5 — o que só o tempo mede

**Aberta em 22/09/2026, com o veredito do C1.** O R3 não passa, e a medição do
poder (C6) mostra que nenhuma quantidade de trabalho sobre as coortes de 2018 a
2025 pode mudar isso sem virar ajuste ao teste: cinco ordenações já foram
testadas nelas. O que pode mudar o veredito é **dado novo**, e ele chega em
tempo de calendário. Esta fase guarda o que depende dele e o que depende de
decisão.

| # | item | serve a | estado | pronto se |
|---|---|---|---|---|
| C7 | A réplica fora da amostra, pré-registrada | R3 | 🟨 | as coortes trimestrais a partir de 31/12/2025 — que nenhuma decisão do motor viu — são medidas pelo critério da decisão 96 **nas datas fixadas antes de vê-las**: 12 meses em **30/09/2029** (12 coortes novas), 36 meses em **30/09/2031** (12 coortes novas), e a cada ano depois; a leitura reporta o motor pré-registrado e o da data, e **não junta** as coortes antigas às novas para passar ([decisão 129](decisoes/129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md)). **O poder será baixo** — 12 coortes são menos que as 22 de hoje —, e a réplica é registrada assim mesmo: sinal positivo e consistente fora da amostra é evidência que nenhuma reanálise das coortes antigas produz. **Em curso desde 24/09/2026: as três primeiras coortes estão seladas** ([decisão 133](decisoes/133-a-replica-fora-da-amostra-comeca-selada.md)). As previsões de 31/12/2025, 31/03 e 30/06/2026 — 1.018 observações, 93, 96 e 95 avaliadas — estão em [`docs/validacao/c7/`](validacao/c7/), sem campo de desfecho e com o hash do git de cada arquivo no índice. O motor pré-registrado é o da primeira selagem, de impressão `689fad50738d…`. Ele difere do de 22/09 (`e1a843d`) só no rastro e nas cópias dos insumos, e nenhum campo do gabarito se move entre os dois. `tool/c7_leitura.dart` recusa a leitura antes da data e, até lá, só diz quantas coortes estão seladas e maduras. **A cada trimestre fechado**, `tool/backtest_valuation.dart --c7` e `tool/c7_selar.dart` selam a coorte nova: a próxima é 30/09/2026 |
| C8 | O que o terceiro critério exige | R3 | 👤 | o usuário decide entre manter **«habilidade comprovada»** — que a série brasileira não sustenta para nenhum motor no critério de 36 meses antes de 2037, nem para o book-to-market — e ler o R3 como **«habilidade testada, com o poder declarado»**, que está atingido pelo C1 e pelo C6. O registro não troca a definição sozinho: ela é do usuário desde 09/09/2026 |

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
- o alcance da lente `registro`, que só inventariava as decisões até a 30 —
  **resolvido em 24/09/2026**: o material das lentes `registro` e `rumo` passou
  a trazer primeiro o indispensável e as decisões das recentes para as antigas,
  e a incluir os arquivos novos ainda sem commit;
- os achados da lente `nucleo` na rodada do C7 — `viaMigrada` e o construtor
  sem validação que leem resultado gravado antes das decisões correntes — e os
  da `risco` em dois testes antigos, o do cache macroeconômico que confere a ida
  à rede e não a janela devolvida, e o do Tesouro cujo nome promete a ressalva
  que ele não confere;
- **o apontamento de 09/09/2026, que espera decisão do usuário** (lente
  `registro`, 24/09/2026). A tela de avaliação mostra preço de mercado, preço
  justo e upside como três valores da mesma natureza e com o mesmo peso, sem
  dizer que o do meio não é previsão de nível — o que a decisão 32 já afirma e o
  B1 mediu. A faixa calibrada, logo abaixo, diz isso da incerteza, mas não do
  justo. O apontamento vira decisão sobre o cartão de preço
  (`valuation_page.dart`, que está no `afeta` da decisão 32) ou é descartado com
  registro: **quem escolhe é o usuário**, pela regra da caixa de entrada.

Se um deles passar a afetar número, entra na tabela com *serve a* `R1`.

---

## 7. Critério de parada

Conferido contra o código e as medições em 24/09/2026, com a Fase 4 fechada e
a réplica do C7 selada. Cada condição cita os itens da §6 que a fecham.

**Valuation exemplar** — o preço justo de um ativo é defensável linha a linha:

- [x] **Insumos de fonte primária, com procedência** — demonstrações (CVM),
  contagem de ações e setor (B3), curva (Tesouro), proventos (B3) e prazo das
  outorgas (FRE) — A1 a A6
- [x] **Curva de desconto observada** — padrão do aplicativo (A2, A2.1); na web,
  do pacote do build, que serve por cerca de uma semana (A2.2)
- [x] **Divisor por papel correto** — contagem oficial e tesouraria no divisor
  (A1.5, A3.3), WACC com a mesma convenção de dívida do resto do modelo (B9,
  decisão 104) e razão de unidade pela composição declarada na FCA (B16,
  decisão 106)
- [x] **Resposta coerente à taxa** — nenhuma avaliação muda de via (B10 e B13,
  decisão 102), e a varredura do nível da curva não acha ativo subindo com a
  taxa em nenhuma das duas montagens: 0 de 102 (B11, decisão 105)
- [x] **Custo de capital completo e consistente** — o prior do beta e o custo
  resolvido ano a ano agem em produção desde 20/09/2026 (B11, decisão 105); o
  prêmio de mercado fica em 5,5% por medição das duas alternativas (B3, decisão
  116), risco-país e tamanho são recusados com medição (B4, decisão 117), e a
  convenção de inflação é conferida por invariância de unidade (B7, decisão
  114) — os três fecharam em 21/09/2026, e esta caixa ficou desmarcada até ser
  conferida em 22/09
- [x] **Horizonte compatível com o contrato onde há contrato** — o terminal da
  concessão corta o excedente no fim do contrato (A6); fora de contrato, o
  excedente perpétuo do capital instalado é **premissa declarada** desde
  21/09/2026, com o peso medido — −14,1% do preço justo na mediana, e déficit em
  71 de 83 (B12, decisão 107). **E a reversão foi medida** (B19, decisão 112): ela
  existe e é rápida, mas o destino é a mediana do mercado — 9,5% contra 18,6% de
  custo de capital —, de modo que convergir o terminal a `r` afirmaria
  rentabilidade que esta seção transversal nunca teve
- [x] **A perpetuidade diz de onde vêm o beta e a estrutura de capital** — a
  estrutura é a do ano N do modelo (decisão 105) e o beta é o de hoje,
  encolhido; convergi-lo em direção a 1 move 0,1% do preço justo, porque o
  encolhimento já o fez (B15, decisão 109)
- [ ] **O patrimônio da ponte é o da companhia na data** — **aberta em
  24/09/2026** pela lente `metodo` (B28). O capital próprio vem do último
  balanço e o divisor é a contagem que forma a cotação de hoje: uma emissão ou
  uma recompra entre os dois entra num lado da divisão e não no outro. A
  premissa não estava declarada em lugar nenhum, e o quanto ela move o preço
  justo não foi medido
- [x] **Segunda leitura por múltiplos** — P/L, P/VP e EV/EBITDA de pares, com
  a mediana em pacote versionado, a aplicabilidade declarada quando morde e a
  divergência contra o fluxo descontado dita acima de 50%. **O preço justo não
  muda**: ela é teste de sanidade, e não modelo de preço. A divergência mediana é
  de **+73,4%**, e o DCF fica acima dos pares em só 14 de 97 (B5, decisão 118;
  remedido com o B27)

**Motor de referência** — as três condições combinadas:

- [x] **R1. Nenhum defeito conhecido** — **atingida em 22/09/2026**, depois de
  desmarcada em 14/09. **Os dois últimos fecharam nesta rodada**: o **B8** — a
  coorte passou a ler a versão do documento que era pública na data dela, com as
  versões antigas baixadas do RAD (decisão 128) — e o **B24**, que a lente
  `metodo` abriu na mesma rodada — o juro da rota derivada passou a seguir a curva
  como o ponto fixo que fecha o `Ke` (decisão 127). A prevenção também fechou: o
  **D3** e as duas metades que faltavam do **B21** (decisão 125). O A5, o B1.0, o
  B10 e o B13 fecharam antes; em 20/09/2026 o B9, o B11 e o B16; em 21/09 o B18,
  o B17, o B7, o B6, o B3, o B4, o B5, o B20, o B22 e o B23. **«Conhecido» é a
  palavra que carrega o critério**: as sete lentes rodaram nesta rodada, e o que
  apontaram de defeito foi corrigido nela — o peso negativo que estourava exceção
  na carteira, o juro da rota derivada, duas lacunas de teste. **E na rodada do C1 a
  `metodo` achou mais um, no rastro de auditoria** — o Passo 3 do WACC descrevia
  a regra de custo da dívida anterior à decisão 31 —, aberto e fechado como
  **B25**, sem mudar preço algum; e o **B26**, o prêmio de crédito que zerava no
  ponto fixo quando a despesa financeira faltava (decisão 130). **Na rodada do
  C7, em 24/09/2026, mais dois foram abertos e fechados**: o **B27**, a cópia dos
  insumos que perdia campos e tirava a segunda leitura de quatro concessionárias
  na tela (decisão 132), e o **D5**, da lente `dados`, o cache de cotações que
  deixava pregão da base velha no meio da série depois de um desdobramento
  (decisão 134). Nenhum preço justo do gabarito mudou com eles. O **D4**
  fechou a integridade do rastro que o painel de logs exporta (decisão 131). O
  **B28** fica aberto e não conta aqui: é premissa não declarada, e não conta
  errada, e por isso pesa no exemplar.
- [x] **R2. Incerteza calibrada** — **atingida em 15/09/2026, desfeita no mesmo dia
  e refeita por outra forma.** A banda de cenários cobria 8% contra 90%, e a
  incerteza que o aplicativo mostra passou a ser a faixa calibrada (C2, decisão 92),
  que com as deslistadas cobria a até 5 p.p. (C2b, decisão 94) — as duas medições
  com o preço das coortes na base de ações de hoje (C3). Na base da data, a faixa
  em torno do justo cobre 84,8/74,9/49,1% e 83,6/73,0/47,0%, fora do critério. **A
  forma fixada por escrito antes de medir cobre**: 87,9/79,0/50,3% em 12 meses e
  88,2/80,4/51,2% em 36, fora da amostra, com as deslistadas (C2b, decisão 100). O
  que a faixa declara mudou junto: ela é o preço de hoje mais a volatilidade do
  papel, com o preço justo entrando pelo peso medido. **Remedida sobre o motor da
  decisão 102, sem mudar a forma, continua cobrindo**: 88,2/78,7/51,6% e
  88,9/78,7/49,6% ([cobertura_banda.md](validacao/cobertura_banda.md) §11). **E
  replicada em 21/09/2026 sobre o motor da Fase 3**, doze decisões adiante e com
  a base bruta reconstruída do zero pelo C5: **88,1%** em 12 meses e **89,3%** em
  36 contra 90% nominal, desvios de 1,9 e 2,6 p.p. contra o limite de 5. **A
  forma não foi reescolhida, e por isso isto é réplica e não reajuste** — que era
  a pergunta do C2c, e a razão de ele existir: a forma da decisão 100 foi a
  sétima tentada (C2c, decisão 124). **E remedida em 22/09/2026 sobre o motor que
  fecha a Fase 3** — com as versões antigas dos documentos e o juro pela curva —:
  **87,8%** e **88,4%**, desvios de 2,2 e 2,8 p.p.; e, com o B26, **87,8%** e
  **88,9%**, desvios de 2,2 e 3,5 p.p.
- [ ] **R3. Habilidade comprovada** — **não passa, e o C1 o declarou em
  22/09/2026** ([decisão 129](decisoes/129-o-r3-nao-passa-e-o-teste-declara-o-poder-que-tem.md)). Sobre o motor final — 10.919
  observações, 31 coortes, as versões antigas dos documentos, o B26 corrigido
  —, o potencial condicionado ao book-to-market em 36 meses dá **0,052 com `t`
  corrigido de 0,30 contra o crítico de 2,70**, e nenhuma das cinco ordenações
  passa, bruta ou líquida de custo. **O poder do teste está medido** (C6): o menor
  coeficiente que o critério vê com 80% de chance é 0,62, e nem o book-to-market tem poder
  para passar no próprio efeito. **Comprovar habilidade não é atingível com a
  série de hoje por nenhum motor**; o que está atingido é habilidade **testada,
  com o poder declarado**. Qual das duas o R3 exige é o C8, decisão do usuário;
  a única via para a primeira é a réplica pré-registrada (C7), **selada desde
  24/09/2026** com três coortes, e com a leitura travada até 30/09/2029
  (decisão 133).

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
[cobertura_banda.md](validacao/cobertura_banda.md). **Na Fase 3, o motor ficou
coerente com a taxa e parou de escolher entre dois modelos**: nenhuma avaliação
sobe com o capital mais caro, e nenhuma troca de via pela conta. **E parou de
afirmar prêmio que não mediu**: nenhuma ordenação — nem a do DCF, nem a do
book-to-market, nem a das duas juntas — passa no critério que o projeto adotou
para 22 coortes sobrepostas, e o retorno esperado ficou no `Ke`. O R3 é medido no
fim, sobre o motor que a Fase 3 deixar; o R1 fecha nos defeitos de método que
sobram — **B18, B8 e B7**. **Na terceira rodada o aplicativo passou a rodar o
motor que o registro descreve**: o prior do beta e o custo de capital resolvido
ano a ano deixaram de ser diagnóstico, a dívida passou a ser a mesma nas três
pontas do modelo, e a razão de unidade passou a sair da declaração da companhia
em vez de ser inferida de um valor de mercado cuja convenção ninguém conhece. O
preço custou cobertura: 114 avaliados viraram 102, e catorze companhias grandes
saem porque a conta coerente diz que a dívida consome o valor da operação delas.
**E ficou uma dívida de medição**: as coortes ainda descrevem o motor da decisão
102, porque a base bruta não está na máquina (C5). **Paga em 21 e 22/09/2026**:
o C5 restaurou a base, e **a Fase 3 fechou em 22/09** com o B8, o B21, o C4, o D3
e o B24. As coortes descrevem agora o motor final. **O R1 e o R2 estão atingidos
sobre ele, e o R3 está medido e reprovado** — o que falta é o C1 declarar o
veredito, que é a Fase 4. **A Fase 4 fechou no mesmo dia**: o C1 declarou que o
R3 não passa, e o C6 mediu que o teste não aprovaria nenhum motor realista com
22 coortes sobrepostas. **O motor é exemplar e mensurável — sem defeito
conhecido, com a incerteza que cobre o que promete e a habilidade testada até
onde o instrumento enxerga —, e não é «motor de referência» pela definição que
exige habilidade comprovada.** O que resta é a Fase 5: dado novo (C7) e a
decisão sobre o que o terceiro critério exige (C8).

**Na rodada do C7 a réplica ficou selada, e o rastro ficou íntegro.** As
previsões de 31/12/2025, 31/03 e 30/06/2026 estão guardadas antes do desfecho,
com o motor identificado pela impressão, e a leitura não pode ser feita antes
da data. A cada trimestre fechado, uma coorte nova é selada. O painel de logs
passou a exportar o que a tela mostra, e o que ela não mostra: diagnóstico
inteiro, entrada inteira, e as saídas por exceção e por falha de preparo. **O
exemplar perdeu uma condição, e o motivo é honesto**: a lente de método achou
uma premissa que ninguém tinha escrito — o patrimônio do balanço tratado como
se fosse o de hoje, mesmo quando uma emissão aconteceu no meio. Ela pode ser
pequena, mas até agora não tinha sido medida (B28).

**Na quinta rodada o R1 ficou a um defeito de fechar.** O B18 saiu — o ponto
fixo passou a ser tentado de duas partidas, e a recusa de estrutura deixou de
ser do chute que a antecede — e o B17 saiu pela saída de declarar. Sobram o B8,
cuja metade medível é pequena e cuja outra metade depende da base bruta, e o B7,
que o próprio item diz que pode não ser defeito. **E o B19 fechou a pergunta que
o B12 tinha deixado aberta**: a rentabilidade brasileira reverte, e rápido — em
dez anos não sobra nada da vantagem relativa —, mas reverte para a mediana do
mercado, que vive na metade do custo de capital. O déficit perpétuo que o
terminal carrega não é peculiaridade do modelo: é o que a seção transversal
mostra, e um DCF honesto sobre esta amostra tem de dizê-lo. **O B2 virou métrica
com inferência**, e fixou o número que a próxima mudança de método terá de
bater: +0,016, com `t` corrigido de 0,13 contra 2,70.

**Na quarta rodada nenhum número mudou, e o que mudou foi o que o motor diz de
si.** O B12, o B14 e o B15 eram três premissas não declaradas, e as três foram
medidas antes de serem decididas — o gabarito confere idêntico nas duas
montagens. Duas delas se resolveram **contra** a alternativa proposta: a correção
do beta por não sincronia fecha um terço da distância que justifica a recusa por
liquidez, e convergir o beta da perpetuidade move 0,1% do preço justo porque o
encolhimento da decisão 40 já o fez. A terceira inverteu a pergunta: o terminal
não mantém um excedente perpétuo, mantém um **déficit** — o capital instalado
rende 0,71 vez o custo de capital na mediana —, e mantê-lo é a leitura
conservadora enquanto a reversão da rentabilidade à média não for medida (B19).
**Três premissas que o preço justo carregava em silêncio passaram a sair no
rastro, nos diagnósticos e, onde dominam, na tela.**

---

## 8. O que pode dar errado

**A distância pode não fechar.** É possível que um DCF sobre fundamento anual
brasileiro simplesmente não bata um fator de valor, e que a resposta certa seja
a opção (a) da B1 — o DCF como produto de análise individual, e a ordenação
saindo de um modelo declarado. Se for isso, o registro deve dizê-lo, e o artigo
fica mais forte por dizê-lo do que por escondê-lo. **Em 16/09/2026 o B1 implantou
(a)**, e a medição acrescentou um fato que esta seção não previa: nem o fator de
valor passa no critério, com a amostra que há.

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
