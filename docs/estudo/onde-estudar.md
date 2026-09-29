# Onde estudar: roteiro para quem começa do zero

Um roteiro de oito semanas, pensado para duas pessoas sem formação em finanças
ou estatística, com cerca de seis horas por semana. Cada semana diz o que ler
aqui, o que ver fora, e como praticar no próprio Equisim.

---

## O roteiro

| Semana | Tema | Nesta documentação | Fora dela | Prática no Equisim |
|---:|---|---|---|---|
| 1 | Juros, valor presente, inflação | [cap. 1](01-dinheiro-no-tempo.md) | Khan Academy, "Juros e dívida"; Assaf Neto, *Matemática Financeira*, caps. de juros compostos | Refazer à mão o "fator acumulado" de três anos de um caso |
| 2 | Balanço e resultado | [cap. 2](02-a-empresa-em-numeros.md) | CVM, "Caderno de Educação Financeira"; Póvoa, *Valuation*, caps. iniciais | Abrir o [JSON da WEGE3](casos/dados/WEGE3.json) e achar EBIT, dívida e patrimônio de 2025 |
| 3 | Estatística básica | [cap. 6](06-estatistica.md), seções 6.1 a 6.5 | Morettin e Bussab, *Estatística Básica*; StatQuest (YouTube) sobre regressão | Calcular a mediana e o MAD de oito retornos de um caso |
| 4 | Risco, beta, CAPM, WACC | [cap. 3](03-risco-e-retorno.md) | Damodaran Online, aulas "Risk and return" e "Cost of capital"; Bodie, Kane e Marcus, caps. de CAPM | Conferir o WACC da [VALE3](casos/vale3.md), passo 5, com calculadora |
| 5 | Fluxo de caixa descontado | [cap. 4](04-fluxo-de-caixa-descontado.md) | Damodaran, *Valuation*, caps. de crescimento e valor terminal; planilha "fcffginzu" | Refazer o ano 1 e o terminal da [WEGE3](casos/wege3.md) |
| 6 | Bancos | [cap. 5](05-bancos.md) e [caso ITUB4](casos/itub4.md) | Damodaran, "Valuing financial service firms" | Comparar, linha a linha, o painel de logs de um banco e de uma indústria |
| 7 | Validação | [cap. 6](06-estatistica.md), seção 6.10, e [cap. 7](07-como-o-motor-foi-validado.md) | Harvey, Liu e Zhu (2016); StatQuest sobre poder estatístico | Ler [poder_r3.md](../validacao/poder_r3.md) e explicar em uma frase o resultado |
| 8 | Revisão e casos | [VALE3](casos/vale3.md), [SAPR11](casos/sapr11.md), [RENT3](casos/rent3.md), [perguntas](perguntas-do-orientador.md) | — | Explicar um caso inteiro um para o outro, sem olhar |

---

## Os livros, em ordem de utilidade para este projeto

1. **Aswath Damodaran, *Valuation: como avaliar empresas e escolher as melhores
   ações*** (LTC, em português). A referência mais citada pelo motor: beta
   setorial, Hamada, prêmio de crédito sintético, normalização, bancos.
2. **Tim Koller, Marc Goedhart e David Wessels (McKinsey), *Valuation:
   Measuring and Managing the Value of Companies*** (Wiley; há edição em
   português pela Campus). A base da convergência do ROIC, do retorno neutro na
   perpetuidade e da passagem da firma ao acionista.
3. **Alexandre Póvoa, *Valuation: como precificar ações*** (Elsevier). Escrito
   para o Brasil: taxa Selic, impostos, bancos brasileiros.
4. **Alexandre Assaf Neto, *Matemática Financeira e Suas Aplicações*** (Atlas).
   Juros compostos, taxas equivalentes, base 252.
5. **Jeffrey Wooldridge, *Introdução à Econometria*** (Cengage). Regressão,
   teste t, séries temporais, Newey-West.
6. **Zvi Bodie, Alex Kane e Alan Marcus, *Investimentos*** (AMGH). Risco,
   diversificação, CAPM, eficiência de mercado.

## Material gratuito

- **Damodaran Online** (pages.stern.nyu.edu/~adamodar) — aulas completas de
  *Valuation* e *Corporate Finance* em vídeo, planilhas e os dados de prêmio de
  risco por país, atualizados todo ano.
- **Khan Academy** (pt.khanacademy.org) — matemática financeira e estatística,
  em português.
- **StatQuest** (YouTube, Josh Starmer) — estatística em vídeos curtos, com
  legenda.
- **Portal do Investidor da CVM** e **Tesouro Direto** — conceitos de mercado e
  simuladores de títulos.

## Artigos que o projeto cita (para a bibliografia do trabalho)

| Assunto | Referência |
|---|---|
| CAPM | Sharpe, W. (1964). Capital asset prices. *Journal of Finance*, 19(3). |
| Beta e alavancagem | Hamada, R. (1972). The effect of the firm's capital structure on the systematic risk of common stocks. *Journal of Finance*, 27(2). |
| Encolhimento do beta | Vasicek, O. (1973). A note on using cross-sectional information in Bayesian estimation of security betas. *Journal of Finance*, 28(5). |
| Perpetuidade com crescimento | Gordon, M. (1959). Dividends, earnings, and stock prices. *Review of Economics and Statistics*, 41(2). |
| Erro-padrão robusto | Newey, W. e West, K. (1987). A simple, positive semi-definite, heteroskedasticity and autocorrelation consistent covariance matrix. *Econometrica*, 55(3). |
| Teste transversal | Fama, E. e MacBeth, J. (1973). Risk, return, and equilibrium. *Journal of Political Economy*, 81(3). |
| Book-to-market | Fama, E. e French, K. (1992). The cross-section of expected stock returns. *Journal of Finance*, 47(2). |
| Vantagem competitiva | Mauboussin, M. e Johnson, P. (1997). Competitive advantage period: the neglected value driver. *Financial Management*, 26(2). |
| Múltiplos testes | Harvey, C., Liu, Y. e Zhu, H. (2016). …and the cross-section of expected returns. *Review of Financial Studies*, 29(1). |

## Como usar o painel de logs para estudar

O aplicativo tem um painel com cada passo de cada avaliação (menu do perfil →
"Abrir Painel de Logs de Cálculo"). Ele não diz onde estudar cada passo; a
[tabela do painel](../AUDITORIA_DE_CALCULOS.md) faz essa ponte: para cada nome
de passo que aparece lá, diz o que ele calcula e qual seção deste guia o
explica.
