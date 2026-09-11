# CVM Dados Abertos — conferência de campos (item A1)

Medido em 11/09/2026, sobre DFP 2024, ITR 2024 e sete anos de FCA
(2019–2025), contra os **375 tickers** do universo.

O [plano](../plano-motor-de-referencia.md) exigia isto antes de qualquer
código: *"o registro deste projeto não aceita plano escrito sobre suposição de
campo"*. Este documento é a conferência, e ela **corrigiu duas conclusões que
eu tinha tirado cedo demais**.

---

## 1. Acesso

`https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/{DFP,ITR,FCA}/DADOS/*_YYYY.zip`

Sem cadastro, sem token, sem limite observado. HTTP 200 para 2010, 2011 e 2012
— a profundidade histórica cobre as oito coortes do backtest.

| arquivo | tamanho |
|---|---:|
| `dfp_cia_aberta_2024.zip` | 13,4 MB |
| `itr_cia_aberta_2024.zip` | 32,7 MB |
| `fca_cia_aberta_2024.zip` | 0,4 MB |

Cada zip traz 19 CSVs: metadados, BPA/BPP (ativo/passivo), DRE, DFC método
direto e indireto, DMPL, DVA, DRA, `composicao_capital` e `parecer` — cada um
em versão **consolidada** (`con`) e **individual** (`ind`). Codificação
`latin-1`, separador `;`, `ESCALA_MOEDA` em MIL.

---

## 2. A ponte ticker↔CNPJ: 95,7%, e o campo publicado não serve sozinho

O plano supunha que `Codigo_Negociacao` do FCA resolveria o casamento. **Ele é
texto livre e está sujo.** Em 1.023 linhas do FCA 2024:

- **453 (44%) com o campo em branco**;
- CSN Mineração traz `25585` — código CVM, não ticker;
- BTG Pactual traz `000000`;
- Marfrig traz a string `ADR`;
- Marisa traz `022055`.

Filtrando por **formato de ticker** (`^[A-Z]{4}[0-9]{1,2}$`) sobre sete anos de
FCA, sobram 644 códigos válidos e **zero ambiguidade** — nenhum ticker aponta
para dois CNPJs.

| via | tickers |
|---|---:|
| FCA, código direto | 332 |
| FCA, pela raiz de 4 letras com CNPJ único | 15 |
| nome normalizado **idêntico** ao `DENOM_CIA` | 12 |
| **resolvido** | **359 / 375 = 95,7%** |
| sem ponte | 16 |

Os 16: `AXIA7 B1003 B3SA3 BPAC11 BPAC3 BPAC5 CSNA3 CTAX3 EQPA5 FASA3 HAGA3
HAGA4 LUXM4 MAPT3 NORD3 OBTC3`. A maioria são classes secundárias de companhias
já resolvidas — resolver por **companhia** e anexar todas as classes derruba
quase todos. Restam B3SA3 e CSNA3 para tabela manual.

**Casamento aproximado de nome é proibido, e a razão está medida.** Com corte
de similaridade em 0,62, `CSNA3` (Companhia Siderúrgica Nacional, cujo nome na
brapi é só "CSN") casa com **COSAN S.A.** a 0,75 — confiante e errado. Só
similaridade **1,00** após normalização é aceitável.

A ponte está gravada em [ponte_cvm.json](ponte_cvm.json): 359 tickers para
**286 CNPJs** — várias classes por companhia.

---

## 3. O plano de contas tem quatro layouts, não um

Os códigos de nível ≤ 2 são padronizados e quase universais: `1 = Ativo Total`,
`2 = Passivo Total`, `2.03 = Patrimônio Líquido Consolidado`, `3.01 = Receita`
aparecem em 467 de 467 companhias do DFP consolidado. Abaixo do nível 2 a
descrição é texto livre da companhia e **não deve ser usada**.

Mas o plano padronizado **não é único**. No universo:

| layout (rótulo da conta 3.01) | companhias |
|---|---:|
| Receita de Venda de Bens e/ou Serviços | 513 |
| Receitas **de** Intermediação Financeira | 18 |
| Receitas **da** Intermediação Financeira | 7 |
| Receitas das Atividades Seguradoras/Resseguradoras | 4 |

E **o lucro líquido mora em código diferente em cada um**:

| layout | consolidado | individual |
|---|---|---|
| Não financeira | **3.11** | **3.11** |
| Banco "de Intermediação" | **3.11** | **3.11** |
| Banco "da Intermediação" | **3.09** | **3.13** |
| Seguradora | **3.13** | **3.13** |

Os dois layouts de banco se distinguem por **uma preposição** — "da" contra
"de" — num rótulo em português, e essa preposição decide onde está o lucro.

**Isto invalidou uma medição minha.** Eu havia medido "33 companhias sem `3.11`
no consolidado, todas resolvidas pelo individual" e quase escrevi cobertura de
100%. Conferido no Itaú, `3.11` no individual dele é **"Reversão dos Juros
sobre Capital Próprio"** — um número pequeno que teria entrado como lucro
líquido. O casamento era de código, não de significado.

O mesmo vale para o EBIT: em não financeira, `3.05` é *"Resultado Antes do
Resultado Financeiro e dos Tributos"*, que é EBIT por definição. No layout de
banco "da Intermediação", `3.05` é *"Resultado Antes dos Tributos"* — R$ 47,6
bi no Itaú contra os R$ 42,1 bi de lucro. Ler um pelo outro erraria 13%.

**Consequência de projeto:** o integrador tem de **detectar o layout** e
resolver conta por `(código, padrão de descrição)` dentro dele, recusando
quando ambíguo — a mesma disciplina que a cascata já usa. Uma tabela fixa de
códigos está errada.

---

## 4. Cobertura das contas

Sobre os 286 CNPJs do universo, no DFP 2024:

| conta | significado | consolidado |
|---|---|---:|
| 3.01 | receita | 89,5% |
| 3.05 | EBIT (não financeira) | 89,5% |
| 3.06 / 3.07 / 3.08 | financeiro, antes de tributos, IR/CSLL | 89,5% |
| 3.11 | lucro líquido (não financeira) | 88,5% |
| 3.99 | lucro por ação | 89,5% |
| 1 / 1.01 / 1.02 | **ativo total**, circulante, não circulante | 89,5% |
| 2.01 / 2.02 / 2.03 | passivo circulante, não circulante, **PL** | 89,5% |
| 6.01 / 6.02 | caixa operacional e de investimento | 88,1% |

Os ~10,5% ausentes do consolidado são companhias que **só arquivam
individual** — Sanepar, Comgás, Coelba, Elektro e afins, que não têm
controladas — mais os bancos do layout alternativo. Com o recuo
`consolidado → individual` e o mapa de layout da §3, a cobertura vai a
**100% dos 286**.

### O que isso resolve, item a item

| limitação | estado depois da CVM |
|---|---|
| §2.12 — fonte não publica lucro de banco | **resolvido**: Itaú tem lucro de R$ 42,1 bi em 2024, conta 3.09 |
| §2.17 — sem conferência analítica do balanço | **resolvido**: `1 = Ativo Total` existe, e a rota operacional passa a fechar |
| §1.9 — exercício com DRE zerada | **resolvido** onde a CVM tem o documento |
| §2.14 — minoritário | valor em `2.03.09` (256 de 286) e `2.07.02` no layout de banco — continua **contábil**, mas agora é da fonte primária |
| §2.1 — CapEx aproximado | **parcial**: 86% têm linha de imobilizado/intangível em `6.02.*`, mas a descrição é texto livre com 8+ variantes |

---

## 5. Trimestralidade e defasagem — o achado que ataca o diagnóstico da §0

Todas as **286 companhias do universo têm ITR**, com **3 trimestres cada** — o
quarto é coberto pela DFP anual, que é a convenção brasileira. Isso quadruplica
a frequência de revisão: 4 observações por ano contra 1 hoje.

E a defasagem real, de `DT_RECEB` menos `DT_REFER`:

| documento | p10 | p25 | **mediana** | p75 | p90 | máx |
|---|---:|---:|---:|---:|---:|---:|
| DFP (anual) | 50 | 58 | **78** | 86 | 90 | 472 |
| ITR (trimestral) | 35 | 38 | **40** | 45 | 46 | 380 |

**A premissa de 90 dias da §2.3 é conservadora, e agora é dispensável.** Ela
acerta o p90 do anual e erra a mediana em 12 dias; para o trimestral, erra em
50. Com `DT_RECEB` o *point-in-time* deixa de ser premissa e passa a ser dado.

**Reapresentação é comum: 24,8% dos documentos anuais têm `VERSAO > 1`**, e
12,6% dos trimestrais. A ressalva declarada na §0.3 do plano — "os fundamentos
vêm como a fonte os publica hoje, e reapresentação entra como conhecimento
futuro" — afeta **um quarto** da amostra anual, e a CVM traz a versão e a data
de cada uma.

---

## 6. Achado novo: 62% do universo tem ação em tesouraria

`composicao_capital` publica `QT_ACAO_ORDIN/PREF/TOTAL_CAP_INTEGR` e
`QT_ACAO_TOTAL_TESOURO`. Sobre os 286 do universo, **178 (62%) têm ações em
tesouraria maiores que zero**.

O motor **não trata tesouraria em lugar nenhum**. A contagem que divide o valor
do capital próprio deveria ser a integralizada **menos** a em tesouraria — ação
em tesouraria não tem direito a fluxo. Não estava em lista nenhuma porque a
fonte atual não publica o campo.

Tamanho ainda não medido: exige comparar `CAP_INTEGR − TESOURO` contra a
contagem que a ponte usa hoje, ativo a ativo. Fica como primeira medição
depois da integração.

---

## 7. O que a CVM **não** resolve

- **Preço, valor de mercado e volume.** Continuam sendo da brapi ou da B3. A
  §1.7 (as duas contagens) e a razão de unidade só se resolvem cruzando a
  contagem da CVM com o preço — e é aí que o A3 entra.
- **Proventos.** Não estão no DFP/ITR; ficam na DMPL ou em documento próprio,
  e valem investigação separada no A4.
- **Prazo de outorga.** Está no FRE, que é outro arquivo — item A6.
- **Setor.** A CVM não classifica por setor de negócio; §1.5 continua com a
  taxonomia da brapi ou exige a B3.
- **Deslistadas.** O arquivo é histórico por ano, então uma companhia que
  fechou capital em 2019 aparece nos arquivos até 2019 — o que **resolve** o
  viés de sobrevivência —, mas exige baixar todos os anos e não confiar no
  universo de hoje.

---

## 8. Reprodução

```bash
# baixe DFP, ITR e FCA de um ano
curl -O https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_2024.zip
curl -O https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2024.zip
curl -O https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/FCA/DADOS/fca_cia_aberta_2024.zip

dart run tool/dump_universo.dart   # grava docs/validacao/universo.json
```

A ponte medida está em [ponte_cvm.json](ponte_cvm.json).
