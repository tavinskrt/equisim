---
numero: 104
titulo: A dívida dos pesos do WACC é a líquida, como no resto do modelo
status: aceita
origem: voce
data: 2026-09-20
citacao: >
  Seus itens de escopo para esta rodada são B9, B11 e B16.
afeta:
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - tool/deep_audit.dart
  - docs/validacao/divida_do_wacc.md
substitui: []
---

## Contexto

A lente `metodo` apontou em 14/09/2026, e o código confirmava, que o motor
usava **duas réguas de dívida no mesmo modelo**:

| onde | dívida | desde |
|---|---|---|
| pesos do WACC estático | **bruta** | sempre |
| realavancagem ano a ano | líquida | [decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) |
| desalavancagem do beta | líquida | [decisão 54](054-a-regua-da-alavancagem-e-uma-so.md) |
| apuração do capital próprio | líquida | [decisão 102](102-nenhuma-avaliacao-muda-de-via-e-a-firma-avalia-pelo-fluxo-do-acionista-derivado.md) |

A régua da desalavancagem já tinha sido decidida por medição: desalavancar
contra a bruta e realavancar contra a líquida fazia a ida e a volta não se
cancelarem, e o beta que voltava era menor que o medido em 100 dos 127
avaliados (decisão 54). O peso do WACC ficou de fora daquela decisão.

**O defeito não é de estilo, é de contagem dupla.** O fluxo da firma é
operacional: não traz o rendimento do caixa. O valor que ele desconta é,
portanto, o dos **ativos operacionais**, e o capital que os financia é
`E + D_líquida`. Dar à dívida o peso da **bruta** e depois devolver o caixa ao
acionista conta o mesmo caixa duas vezes — uma barateando a taxa, porque a
dívida entra com peso maior que o real; outra somando-se ao capital próprio na
apuração.

## Decisão

**A dívida dos pesos do WACC é a líquida**, a mesma do resto do modelo.

1. `CostOfCapital.debtValue` passa a receber `netDebt`. O `Kd` observado
   continua sendo `despesa financeira ÷ dívida bruta`, que é razão sobre o que
   de fato paga juro, e a alavancagem do prêmio de crédito continua sendo
   `dívida líquida ÷ EBITDA`, como já era.
2. **A estrutura só é desconhecida em dois casos**, e só neles o desconto
   degenera para o `Ke`: sem valor de mercado utilizável, não há peso a formar;
   e com dívida contratada cujo custo não é medível — despesa financeira
   ausente —, não há `K_d` a ponderar.
3. **Companhia sem dívida e com caixa tem estrutura conhecida**, e entra na
   conta com peso de dívida **negativo**. Sem dívida contratada não há prêmio de
   crédito a cobrar, e o `K_d` é a taxa livre de risco — é o que caixa rende
   ([decisão 58](058-a-carteira-de-acoes-nao-espera-a-renda-fixa.md)). Degenerar
   para o `Ke` ali devolveria o caixa duas vezes, uma no desconto brando e outra
   na apuração, que é exatamente o defeito que esta decisão corrige para quem
   tem dívida. **Apontado pela lente `metodo` em 20/09/2026**, sobre a primeira
   versão desta decisão, que media a ausência de estrutura pela dívida bruta.
4. **O peso do capital próprio não é confinado em `[0, 1]`**, nem no WACC
   estático nem no solucionador do caminho de taxas: `E + D` não positivo já é
   recusado, e confinar faria as duas rotas discordarem no mesmo ativo.
5. **Com caixa líquido o WACC fica acima do `Ke`, e a avaliação diz isso.** Não
   é anomalia: o ativo operacional sozinho é mais arriscado que a companhia
   inteira, que é a mesma leitura que o `β_U` faz ao desalavancar contra a
   líquida. A ressalva aparece na tela, com o peso negativo.

## O que foi medido

Sobre a entrada congelada do gabarito, em 20/09/2026
([divida_do_wacc.md](../validacao/divida_do_wacc.md)):

- **Na montagem do aplicativo**, que não resolve as taxas (item B11), o
  desconto sobe em 73 dos 114 avaliados, e o preço justo sobe 3,0% na mediana.
  A cobertura vai de 114 a 115: a MOVI3 volta, em R$ 0,07 por papel.
- **Na montagem com o prior**, que resolve as taxas, o preço justo muda em
  **2 de 102** — porque ali a dívida dos pesos já era a líquida, e o que sobrou
  foi o chute inicial do ponto fixo. Duas empresas muito alavancadas, a PNVL3 e
  a VAMO3, passam a ter a estrutura recusada já na primeira iteração.

**O preço justo subir com um desconto maior é sintoma, e o sintoma é o B11.**
Na montagem do aplicativo o fluxo da firma reinveste contra o WACC — a retenção
é `g ÷ ROIC`, e o retorno terminal neutro é o próprio WACC — enquanto o capital
próprio é descontado ao `Ke` do CAPM. Subir o WACC sobe o retorno terminal,
baixa a retenção e engorda o fluxo, sem mexer no desconto. **As duas taxas só
são a mesma conta no caminho resolvido**, e é por isso que ali o efeito
praticamente não existe. A decisão 102 já tinha declarado esse custo; esta
decisão o mede.

## Consequências aceitas

**O preço justo da montagem do aplicativo sobe onde há caixa.** É o efeito de
tirar o subsídio que a dívida bruta dava à taxa, e ele é maior justamente nas
empresas de mais caixa — a EMBJ3 em 41,9%, a VLID3 em 17,3%, a FESA4 em 13,1%.

**Duas empresas saem da montagem com o prior.** A PNVL3 e a VAMO3 têm o capital
próprio consumido pela dívida já na primeira iteração do ponto fixo, com o
chute inicial mais caro. Não é recuo: é a mesma recusa que a decisão 45 nomeia,
alcançada mais cedo.

**O rastro de auditoria mudou de rótulo.** A linha do WACC diz `D líquida`, e a
fórmula em LaTeX traz `D_liq`. Rastro que descreve outra conta é pior que
nenhum, e o gabarito do D1 compara o rastro junto com o número.

**A companhia sem dívida contratada não muda de número hoje.** São três no
universo — ALOS3, BRAP4 e SAUD3 —, e as três resolvem o caminho de taxas pelo
prior (decisão 105), de modo que o WACC estático só lhes serve de chute inicial e
o ponto fixo chega ao mesmo lugar. O que a correção conserta é o **recuo**: sem
prior, ou com pacote vencido, é ele que avalia.
