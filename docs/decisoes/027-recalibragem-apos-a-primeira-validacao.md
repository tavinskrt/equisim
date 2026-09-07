---
numero: 27
titulo: Recalibragem do motor de avaliação após a primeira validação fora da amostra
status: aceita
origem: orientador
data: 2026-09-07
citacao: >
  Em relação aos três pontos que exigem decisão metodológica, seguem as
  definições homologadas: instrumentar no log de avaliação qual das condições
  barrou cada ativo; reduzir o multiplicador de rentabilidade de 2,0x para
  1,5 * WACC_inf (ou ROIC_ciclo - WACC_inf >= 5 p.p.); ajustar o histórico
  mínimo de n >= 12 para n >= 8 anos; manter Phi <= 0,35; manter o Preço Justo
  rigorosamente como calculado pelo DCF; desacoplar a geração de retorno
  esperado para a carteira da taxa nominal crua; e a condição Phi > 1,0 não deve
  operar como trava impeditiva de normalização.
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - lib/presentation/goals/goal_page.dart
  - lib/presentation/study/study_page.dart
  - tool/validation/out_of_sample.dart
  - docs/refinamento-do-valuation.md
substitui: []
---

## Contexto

A primeira validação fora da amostra da arquitetura da
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) rodou sobre os 373
papéis do universo negociável e avaliou 120. Ela deixou três perguntas em
aberto, registradas nas §12.4 e §12.5 do
[refinamento](../refinamento-do-valuation.md), e nenhuma delas era resolvível
por medição: as três eram escolhas de método.

1. **A exceção de vantagem competitiva residual ativou em 2 dos 120** — BBSE3 e
   SAUD3. WEGE3, RADL3, TOTS3, ITUB4 e EGIE3, que a literatura brasileira trata
   como franquias óbvias, seguiam no estado estacionário. Não se sabia qual das
   três condições prendia cada uma, porque nada instrumentava isso.

2. **A mediana do potencial ficou em −39,4%**, com o quartil superior ainda
   negativo (−14,5%). O nível carrega o conservadorismo que a estrutura a termo
   e o terminal neutro impõem ao custo de capital brasileiro, e ele se propaga
   para a meta da carteira: anualizado em 36 meses, o ativo mediano entra na
   carteira com retorno esperado de −15,4% ao ano.

3. **SUZB3 (+259,1%) e QUAL3 (+477,3%)** não são erro de escala — são pico de
   ciclo extrapolado com a normalização da base bloqueada. A §12.5 atribuiu o
   bloqueio à guarda de comparabilidade (P6), que via `Φ > 1,0` e impedia a
   convergência ao ciclo.

   **Essa atribuição estava errada, e a instrumentação desta rodada a
   desmentiu.** A SUZB3 tem `Φ = 0,77`, abaixo do limiar; quem segura a base
   dela é a **Guarda 1**, porque a tendência do ROE domina a reversão à média e
   o modelo lê 41,5% de retorno corrente contra 18,4% de ciclo como nível
   estrutural. A QUAL3 tem `Φ = 0,01` e **já era normalizada** antes desta
   rodada. Fica o registro: a §12.5 escreveu "não medi qual das três condições
   prende cada uma" a respeito do *moat* e, sobre a normalização, afirmou o
   mecanismo sem medir — foi a segunda afirmação que não se sustentou.

## Decisão

**1. O critério de vantagem residual é recalibrado, e passa a ser
instrumentado.**

A rentabilidade estrutural passa a aprovar por **união de duas pernas**:
`ROIC_ciclo ≥ 1,5 · WACC_∞` **ou** `ROIC_ciclo − WACC_∞ ≥ 5 p.p.` As duas se
cruzam em `WACC_∞ = 10%`: acima disso decide o excedente absoluto, abaixo decide
o múltiplo — o que impede que custo de capital baixo transforme 5 pontos de
spread em vantagem competitiva declarada. O histórico mínimo cai de 12 para 8
exercícios, alinhado ao piso da Porta 0 e à janela do ciclo. `Φ ≤ 0,35` fica
como está, porque é o que separa franquia de aporte.

O log de avaliação passa a registrar, por ativo, **quais** condições barraram —
todas, não apenas a primeira. A avaliação deixa de ser em curto-circuito: quem
reprova por duas condições continuaria reprovado se só uma fosse afrouxada, e
uma calibragem guiada pelo primeiro motivo prometeria um destravamento que não
aconteceria.

**2. O preço justo do ativo continua sendo o do DCF; o retorno esperado da
carteira deixa de ser o nível do potencial.**

No ativo individual nada muda: o preço justo segue saindo do fluxo descontado
com estrutura a termo e terminal neutro, sem afrouxamento de premissa. O que
muda é o número que a carteira usa para se comparar com a meta, que passa a ser
o **estimador transversal**:

```
E[R_i] = CDI_spot + z_i · prêmio,   z_i = (u_i − mediana(u)) / MAD*(u)
```

com o escore confinado a ±2 desvios robustos e o prêmio igual ao do CAPM que
desconta o fluxo. O ativo mediano da seção recebe o CDI à vista; quem está
descontado em relação aos pares recebe prêmio proporcional, e quem está esticado
recebe menos — sem nunca ficar negativo.

**3. A Guarda 2 declara, não barra.**

`Φ > 1,0` deixa de impedir a normalização do retorno. Quando a Guarda 3 acusa
desvio do ciclo, a convergência é aplicada sobre a base de capital **corrente**,
qualquer que seja Φ. O motivo é de unidade: Φ mede *tamanho*, e o que se
normaliza é o **retorno percentual**, que é grandeza intensiva. Que uma empresa
tenha dobrado por incorporação não torna o ROIC de um exercício de pico um
patamar perene — a rentabilidade da commodity reverte à mediana do ciclo
independentemente do tamanho alcançado.

O que Φ acima do limiar continua significando é que **níveis absolutos** de
lucro não são comparáveis entre as pontas da janela, e isso passa a ser dito nos
avisos do resultado em vez de virar um bloqueio silencioso.

## Consequências aceitas

- **A exceção de *moat* deixa de ser rara por desenho.** A decisão 25 escolheu
  torná-la restritiva porque o preço dela é alto: o valor terminal volta a
  depender de `g_∞`, que o retorno neutro havia eliminado. Afrouxar duas das
  três condições aumenta o número de ativos cujo terminal volta a essa
  dependência, e a robustez que o terminal neutro comprou é, nessa medida,
  devolvida. A instrumentação existe para que isso seja medido a cada rodada em
  vez de suposto.

- **A união das duas pernas é a leitura adotada para o "ou" da homologação.**
  A determinação pode ser lida como duas especificações alternativas — escolher
  uma delas — ou como um critério em união. Foi implementada como **união**, que
  é a leitura literal do conectivo e a mais permissiva das duas; as duas pernas
  são registradas em separado no log, de modo que trocar para a leitura estrita
  é uma linha, e a medição para decidir já está disponível.

- **O retorno esperado da carteira passa a ser uma afirmação de ordenação, não
  de nível.** Ele não é mais um preço-alvo anualizado, e não deve ser lido como
  previsão de rentabilidade: é o CDI mais um prêmio pela posição relativa do
  ativo na seção avaliada. A leitura só é significativa contra uma seção larga —
  medir uma carteira de cinco ativos contra ela mesma a centra no CDI por
  construção, e o resultado carrega o tamanho da seção junto para que isso não
  passe despercebido.

- **A meta da carteira fica mais fácil de atingir.** É consequência direta, e
  precisa ser dita: o número que a carteira compara com a rentabilidade exigida
  deixa de carregar o deslocamento de nível do potencial. A alternativa
  descartada era afrouxar as premissas do DCF para levantar o nível — recusada
  porque contaminaria o preço justo, que é o produto principal do trabalho, para
  consertar um problema que é do consumidor do número, não da avaliação.

- **P6 deixa de ser um corte de bloqueio e vira limiar de declaração.** A
  decisão 25 o homologou entre os treze parâmetros como guarda de
  comparabilidade que travava a normalização. Ele continua sendo medido, com o
  mesmo valor e a mesma fórmula; o que muda é o que ele decide. O corte que
  ainda barra por crescimento inorgânico é o `moatMaxExternalCapital`, de 0,35.

- **A normalização passa a operar nos dois sentidos com mais frequência.** Não é
  só o pico que passa a ser corrigido: um exercício de vale sobre base
  inorgânica também converge ao ciclo, e para cima. Treze ativos passaram a ser
  normalizados por esta mudança, e o preço justo deles muda nas duas direções.

- **A correção da precedência é boa por si, e não resolve os dois casos que a
  motivaram.** O argumento de unidade — Φ mede tamanho, o retorno é intensivo —
  vale independentemente. Mas a SUZB3 continua em +259,1% e a QUAL3 em +490,7%
  depois da mudança, porque nenhuma das duas era caso de Φ. O que efetivamente
  segura a SUZB3 é a Guarda 1, que esta decisão não toca. Fica registrado como
  pendência aberta, não como resolvido.

- **O fator de normalização continua sem teto, e a mudança amplia a exposição.**
  `f = ciclo / atual` explode quando o exercício corrente tem retorno próximo de
  zero, e o DCF é homogêneo de grau 1 no fluxo-base: a MBRF3 recebeu fator de
  21,4x e saiu a +406,1% de potencial. **A ausência de teto é anterior a esta
  decisão** — FESA4 e DXCO3 já apareciam com fatores de 10,8x e 10,5x tendo
  `Φ < 1` —, mas Φ vinha barrando parte desses casos por efeito colateral, e
  isso deixou de valer. Pôr um teto no fator é decisão nova, com a medição
  disponível na §13 do refinamento; nada foi limitado aqui por conta própria.

- **Esta decisão não abre reconstrução.** Ela opera dentro do `afeta` da
  [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md), cuja
  `postura: reconstrucao` segue aberta, e não a substitui: a arquitetura de
  portas, vias e crescimento fundamental continua valendo integralmente. O que
  esta decisão faz é executar a parte da decisão 25 que dizia que os parâmetros
  "continuam sendo escolhas" e que "a validação fora da amostra é o que a
  completa".
