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
