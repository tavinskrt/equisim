# COTAHIST inteiro e a ponte das deslistadas — item A3.2

Medido em 14/09/2026. Ferramentas: `tool/b3_baixar.py` e `tool/b3_ponte.py`.

## 1. Por que

A amostra sem viés de sobrevivência (C1b) precisa das duas pontas de cada
companhia que deixou de existir: a **demonstração**, que a ingestão da CVM já
tem desde o A1.6, e o **preço**, que está no COTAHIST da B3. As duas não se
conhecem: a CVM identifica por CNPJ, o COTAHIST por ticker e ISIN.

## 2. O COTAHIST de 2010 a 2026

O arquivo anual é lido em fluxo, e só o registro à vista em lote padrão é
gravado — data, ticker, ISIN, especificação, nome, fechamento bruto, fator de
cotação, `DISMES` e volume.

| | |
|---|---:|
| anos | 2010 a 2026, nenhum ausente |
| pregões à vista | **1.629.984** |
| ZIPs baixados | 641 MB |
| gravado | **110 MB** de CSV, contra mais de 5 GB descompactado |

O servidor da B3 recusa o User-Agent padrão do `urllib` com 403, e aceita o do
navegador. Registrado no baixador.

## 3. A ponte, e o que a limitava

**A FCA da CVM só preenche o código de negociação a partir de 2018.** De 2010 a
2017 a coluna `Codigo_Negociacao` vem vazia em **todas** as linhas de todos os
anos — conferido arquivo a arquivo. É exatamente a janela das deslistadas mais
antigas.

Mas a FCA desses anos ainda diz se a companhia tinha **ação em bolsa**, e guarda
os nomes empresariais anteriores. Daí as duas pontes, em ordem de confiança:

1. **Código declarado** (2018 em diante) → ticker do COTAHIST → emissor pelo
   ISIN, que traz as outras classes.
2. **Nome com sobreposição de anos**, para quem tinha ação em bolsa e nenhum
   código: o nome resumido do emissor no COTAHIST tem de ser prefixo do nome
   empresarial — atual ou anterior — e os anos de DFP e de pregão têm de se
   tocar. Mais de um candidato é ambíguo e fica de fora.

## 4. Cobertura

| | companhias | exercícios com pregão no ano seguinte |
|---|---:|---:|
| com DFP na base | 1.217 | |
| no universo de hoje | 293 | |
| fora dele | 924 | |
| **fora dele e com ação em bolsa** | **290** | |
| ligadas por código | 122 | 1.113 |
| ligadas por nome | 42 | 159 |
| **ligadas, total** | **164** | **1.272** |
| ambíguas por nome | 1 | |
| sem ponte | 126 | |

**As outras 634 companhias fora do universo não tinham ação em bolsa** —
emissoras de dívida, concessionárias fechadas, companhias abertas sem negócio.
Elas não têm preço, e não pertencem a uma amostra de retorno.

**As 42 ligações por nome foram revisadas uma a uma**, e nenhuma está
claramente errada. Várias só casaram pelo nome anterior que a FCA guarda: Prio
Forte ← Dommo (DMMO3), M&G Poliéster ← Rhodia-Ster (RHDS3), Évora ← Petropar
(PTPA3), Vale Fertilizantes ← Fosfertil (FFTL3).

**Das 126 sem ponte**, uma parte declara código de negociação que não aparece
em pregão à vista de lote padrão de 2010 em diante — papel de balcão, ou que
nunca negociou. O resto é nome que não casa com nenhum emissor do COTAHIST.

## 5. O que isto destrava, e o que não

O C1b tem agora, para 164 companhias deslistadas, a série de preço bruto e o
exercício da CVM. **Faltam duas coisas antes de uma coorte usá-la:**

- **O ajuste por evento.** A série é bruta. Para as deslistadas não há registro
  oficial da B3 — ele só cobre emissor listado hoje —, e o ajuste tem de vir da
  inferência pelo preço (decisão 75), com o teto medido em
  [b3_registro.md](b3_registro.md).
- **A contagem de ações por data.** O valor de mercado da coorte é contagem
  vezes preço, e a contagem da CVM não tem escala (decisão 70). A fração em
  tesouraria é invariante; a contagem absoluta, não.

O arquivo `data/b3/ponte_deslistadas.json` fica fora do git, como toda base
bruta: é reproduzível pelas duas ferramentas.

## 6. As que ficaram sem ponte — item C1d

Medido em 15/09/2026 por `python tool/b3_ponte.py`, depois de levantar, uma a uma,
as companhias com ação em bolsa e sem ponte. Registro de cada uma em
[ponte_deslistadas_registro.json](ponte_deslistadas_registro.json).

### 6.1 Por que ficavam fora

Das 128 que o levantamento achou sobre a base de hoje — eram 126 no §4 —, a
causa se divide assim:

| causa | companhias |
|---|---:|
| último DFP antes de 2017: não chega à primeira coorte, de 2018 | 46 |
| **o código tem pregão, e a companhia estava na lista de hoje quando a ponte foi montada** | **2** |
| código declarado sem pregão à vista de lote padrão | 35 |
| a FCA declara algo que não é ticker — `0000`, `N/A`, as quatro letras do emissor | 43 |
| sem código e sem nome que case | 2 |

**As duas do meio são as grandes.** A BRF (BRFS3) e a Petz (PETZ3) saíram da bolsa
por incorporação em 2025. A ponte excluía a companhia com ticker em
`universo.json`, e elas estavam lá quando foi montada; a coorte, porém, não as
tinha como listadas, porque a fonte de preços não as devolve mais. Ficavam sem as
duas pontas — e a BRF é das maiores companhias do período. **Pela mesma razão**,
a Tupy (TUPY3), a Sequoia (SEQL3) e a Contax (CTAX3), listadas em
`universo.json` e sem série na fonte, não estavam em amostra nenhuma.

### 6.2 O que mudou na ponte

- **Viva é quem as coortes observam como listada**, e não a lista de hoje. O
  backtest grava o universo que usou em
  [universo_coortes.json](universo_coortes.json), e a ponte o lê. No backtest,
  papel da ponte que já entrou como listado na coorte não entra de novo.
- **Código de emissor.** Parte da FCA declara as quatro letras do emissor em vez
  do ticker; o COTAHIST as tem no ISIN. Com os anos de DFP e de pregão tocando,
  e um emissor só.
- **Nome contido e nome curto.** O nome do COTAHIST dentro do nome empresarial,
  com seis letras ou mais, ou nome de três a quatro letras que também é a raiz do
  ISIN. Com um candidato só e os anos tocando, como a regra do nome.

**As doze ligações por nome relaxado foram revisadas uma a uma**, e todas são a
companhia certa: NET (NETC3), TAM (TAMM3), Vivo Participações (VIVO3), BHG
(BHGR3), Amil (AMIL3), Raia (RAIA3), Sofisa (SFSA4), Daycoval (DAYC4),
Providência (PRVI3), Cacique (CIQU3), Schlosser (SCLO3) e DHB (DHBI3). As três
por código de emissor: Prio Forte (DMMO3, que antes casava por nome), Fiação São
José (SJOS3) e OranjeBTC (OBTC3).

### 6.3 A cobertura depois

| | antes | depois |
|---|---:|---:|
| fora do universo das coortes e com ação em bolsa | 290 | 301 |
| **ligadas** | **164** | **189** |
| por código | 122 | 133 |
| por código de emissor | — | 3 |
| por nome | 42 | 41 |
| por nome relaxado | — | 12 |
| sem ponte | 126 | 112 |

Entraram 26 e saiu uma: a Marfrig, que agora é listada nas coortes pelo MBRF3,
com o preço de antes do novo código encadeado pela FCA (item C3). Duas das 26 —
a Livetech da Bahia (WDCN3) e a União Pet (AUAU3) — entraram na segunda passada:
o backtest trimestral as tirou do universo das coortes, porque só negociam depois
de 30/09/2025, e a ponte refeita as ligou. **A ponte convergiu nisso**: elas não
têm pregão em data de coorte nenhuma, e o backtest não muda com elas. **Das 112 sem
ponte, nenhuma tem código com pregão**: 36 terminam antes da janela das coortes,
35 declaram código que nunca negociou à vista em lote padrão — papel de balcão
organizado ou sem negócio —, 40 declaram código que não é ticker, e uma, a Inepar
Equipamentos, não tem código na FCA nem nome que case com emissor do COTAHIST.

A contagem por data do A3.4 cobre 185 das 189; os proventos, 148 companhias, com
1.906 de 1.932 preços com direito batendo com o COTAHIST a 1%; e a classificação
da B3 respondeu para 12 das 26 novas.
