# A3 — COTAHIST da B3, eventos de ações

Medido em 14/09/2026 sobre os arquivos de 2019 e 2024.

```bash
curl -O https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2024.ZIP
# descompactar em data/b3
dart run tool/b3_cotahist.dart data/b3   # grava b3_eventos.json
```

---

## 1. A fonte

Arquivo histórico oficial da B3, aberto. Um ZIP por ano — 79 MB em 2024, com
651 MB de texto de largura fixa. Registro `01`, mercado à vista (`010`), lote
padrão (BDI `02`).

| campo | posições | uso |
|---|---|---|
| data | 3–10 | pregão |
| ticker | 13–24 | papel |
| fechamento | 109–121 | **bruto**, duas casas implícitas |
| ISIN | 231–242 | identidade do papel |
| `DISMES` | 243–245 | número de distribuição |

**O preço é bruto.** BBAS3, 16/04/2024: R$ 56,46 → R$ 27,91, razão 0,494, na
bonificação de 100%.

## 2. Cobertura

| | |
|---|---:|
| papéis à vista, lote padrão, em 2019 + 2024 | 830 |
| do universo de hoje presentes | **343 de 375** |
| **fora do universo de hoje** | **487** |
| negociados em 2019 e ausentes em 2024 | 386 |

Os ausentes em 2024 misturam BDRs e deslistagens reais — ADHM3, ALSC3 (a
Aliansce, incorporada à ALOS3). **É o preço das deslistadas que o viés de
sobrevivência exige**, e ele está aqui.

## 3. Detecção

35 eventos em 34 papéis nos dois anos. Entre eles: BBAS3 ×2 (2024), MGLU3 ×8
(2019) e ×0,1 (2024, grupamento), PRIO3 ×10 (2019), EQTL3 ×5 (2019), CMIG3/4
×1,3 (2024).

## 4. A conferência, e o erro da primeira versão

**Primeira versão, por nível: 68,16%.** SBSP3, POMO3, ALUP11, RENT3 e ITUB3
discordavam em **499 de 499** pregões com **zero** eventos detectados — um
deslocamento constante.

A causa não era o detector. A fonte de mercado ajusta por todo evento **até
hoje**; com só dois anos do COTAHIST, um evento de 2021 ou de 2025 fica fora da
janela e desloca a série inteira.

**Segunda versão, por retorno diário: 99,96%** — 118.826 de 118.871 pares de
pregões batem a 1%. No retorno o deslocamento constante some.

## 5. Os 45 dias que não batem

| grupo | exemplos | causa |
|---|---|---|
| evento com o mercado andando junto | AERI3 15:1 com +22,8% (razão 18,4); AZEV3 4:1 com +17,9% | a razão sai da folga |
| evento sem troca de `DISMES` | AFLT3, razão exatamente 2,0; HETA4; EALT3 | o `DISMES` não marca todo evento |
| bonificação ≤ 20% | GGBR3/4 (20%), LREN3, CRPG5/6 (10%) | não detectável por preço — declarado |
| a fonte de mercado ajusta sem evento no bruto | AHEB3, IFCM3, MAPT3, CGAS5, EUCA3 | ajuste da fonte fora de data, ou indevido |

## 6. O que fica em aberto

- **A3.1 — registro oficial de eventos da B3.** Fecha os dois primeiros grupos:
  declara o fator em vez de deixá-lo ser inferido.
- **A3.2 — histórico completo e ponte das deslistadas.** Baixar 2010–2026
  (~1,4 GB comprimido) e ligar cada papel deslistado ao CNPJ da CVM — pelo FCA
  de 2010 a 2018, que ainda não foi baixado, e pelo ISIN. É o pré-requisito do
  C1b.
- **A3.3 — eventos na ponte por papel.** Usar os eventos detectados para
  explicar a divergência entre a contagem do exercício e a corrente (§1.7).
