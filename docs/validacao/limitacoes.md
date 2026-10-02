# Limitações do Equisim

O que o motor não faz, faz com aproximação, ou faz de um jeito que muda a
leitura do resultado. Cada item diz **o que é**, **por que importa** e **o que o
projeto faz a respeito**, com a evidência.

> Reescrito do zero em 28/09/2026, conferindo o código
> ([decisão 141](../decisoes/141-a-documentacao-do-motor-e-refeita-do-zero-contra-o-codigo.md)).
> A versão anterior, com a história das limitações já resolvidas, está no
> histórico do git (commit `6827219`). Termos técnicos estão no
> [glossário](../estudo/glossario.md).

As limitações estão em ordem de importância para quem lê um preço justo.

---

## 1. O que muda a leitura de qualquer resultado

### 1.1 O motor é mais pessimista que o mercado, de forma sistemática

**O que é.** Com os dados congelados de 14/09/2026 e o motor de 01/10/2026, dos
108 ativos avaliados, o upside mediano é **−37%**, e só 28 tinham upside
positivo. A WEG sai a R$ 16,18 contra R$ 50,74; o Itaú a R$ 29,14 contra
R$ 42,35. Com o prêmio de 5,5% de antes da decisão 142, eram −45% e 15.

**Por que importa.** Um preço justo abaixo do mercado não quer dizer "ação cara"
no sentido de uma recomendação: quer dizer que as premissas do motor são mais
conservadoras que as que o mercado usa.

**De onde vem.** Do conjunto das premissas, e não de um parâmetro isolado: taxa
livre de risco de 13,6% a 14,6% ao ano na curva inteira, retorno sobre o capital
convergindo ao custo em dez anos, retorno neutro na perpetuidade, crescimento
perpétuo limitado ao da economia. O prêmio de mercado já é o que o preço da
bolsa embute (1,21%, decisão 142), e o desacordo continua: não é o prêmio que
desloca o nível ([premio_implicito.md](premio_implicito.md);
[dcf_reverso.md](dcf_reverso.md)).

**O que o projeto faz.** Declara; a tela mostra a faixa calibrada (que parte do
preço de hoje) ao lado do preço justo. A Selic prevista pelo Focus, pedida pelo
orientador, foi medida: sobe o preço justo mediano de 18% a 33% e mexe pouco na
ordenação; a recomendação é mantê-la como sensibilidade, e a decisão está
pendente (item B33; [selic_focus.md](selic_focus.md)).

### 1.2 A habilidade de escolher ações não está comprovada

**O que é.** O teste pré-registrado (as ações de maior upside, controlando pelo
book-to-market, renderam mais em 36 meses?) deu `t` corrigido de 0,18 contra o
crítico de 2,70, remedido em 01/10/2026. Não passou. Nem o book-to-market
sozinho passou (`t` de 2,27), e por isso o retorno esperado não leva prêmio de
ordenação (decisão 103).

**Por que importa.** Não há evidência de que ordenar por upside ajude a escolher
ações.

**E o teste não teria poder para passar.** O menor efeito que ele detecta com
80% de chance é 0,65, vinte vezes o medido (0,032, remedido em
01/10/2026); o book-to-market só teria esse poder no efeito dele com 54
coortes, em 2034
([poder_r3.md](poder_r3.md), [habilidade_trimestral.md](habilidade_trimestral.md)).

**O que o projeto faz.** O critério passou a ser "habilidade testada, com o
poder declarado" (decisão 140). O retorno esperado da carteira não usa o upside
(é o custo de capital; decisão 103), e a tela de metas diz que o prêmio do
potencial não está comprovado (decisão 99). A réplica selada continua, com
leituras em 2029 e 2031 (decisões 133 e 138).

### 1.3 O preço converge pouco ao preço justo

**O que é.** Na faixa calibrada, o peso do preço justo sobre o preço futuro é
pequeno: `b` = 0,03 em 12 meses e 0,09 em 36 meses.

**Por que importa.** O preço justo explica pouco de onde o preço vai estar. A
faixa de "8 em 10" sai sobretudo do preço de hoje e da volatilidade do papel.

**O que o projeto faz.** A faixa foi construída assim de propósito, porque é o
que a evidência sustenta, e a tela diz isso (decisões 100 e 124;
[cobertura_banda.md](cobertura_banda.md)).

### 1.4 Os cenários são sensibilidade, e o "otimista" pode valer menos

**O que é.** Os cenários pessimista e otimista (crescimento ±3 p.p., desconto
±2 p.p.) contiveram o que de fato aconteceu em 13% a 15% dos casos, e a faixa
de 90% do Monte Carlo em 9%, contra 90% que um intervalo de confiança
prometeria (decisão 92; remedido em 01/10/2026). E o otimista soma
crescimento: quando o retorno da empresa fica abaixo do custo de capital,
crescer destrói valor, e o "otimista" sai abaixo do "pessimista". Com o motor de
01/10/2026, isso acontece em 15 dos 88 ativos da via da firma (com o prêmio de
5,5%, eram 17 de 77, e só o crescimento +3 p.p. baixava o preço justo em 53 dos
97 avaliados).

**Por que importa.** O rótulo "Otimista" supõe que crescer é sempre bom.

**O que o projeto faz.** A tela diz "sensibilidade". A conta está certa; o
rótulo e a definição do cenário dependem de decisão (item B38 do
[plano](../plano-motor-de-referencia.md)).

---

## 2. Dados

### 2.1 Só balanços anuais

O motor usa os demonstrativos anuais (DFP). Os de doze meses móveis ancoram a
série mas não entram por padrão (decisão 73). **Efeito:** entre um balanço anual
e o seguinte, a avaliação não vê trimestres novos.

### 2.2 O dado só existe depois de publicado — e às vezes a data é estimada

A avaliação só usa exercícios entregues à CVM até a data. Quando a data de
entrega não é conhecida, supõe 90 dias depois do fim do exercício (a mediana real
medida é 78 dias) ([point_in_time_view.dart](../../packages/equisim_core/lib/src/time/point_in_time_view.dart)).

### 2.3 A fonte de mercado tem falhas conhecidas

- O preço ajustado da brapi (`adjustedClose`) não ajusta proventos brasileiros
  direito, e não é usado; o preço de fechamento vem ajustado por desdobramento e
  grupamento, mas nem sempre por bonificação, e o motor completa o ajuste dos
  eventos que a fonte deixou (decisão 136, item B29).
- O valor de mercado da fonte pode estar errado para empresas com mais de uma
  classe de ação (na SAPR11, R$ 3,6 bi em vez de R$ 10,5 bi). Por isso a
  contagem oficial da B3 arbitra (decisão 83).
- O universo é o que a fonte devolve: 376 papéis na entrada congelada.

### 2.4 A curva de juros da web vence em uma semana

No aplicativo web, a curva do Tesouro vem de um pacote que vale cerca de sete
dias; vencido, a avaliação usa duas pontas do CDI em linha reta e avisa
(decisão 86). A NTN-F entra como taxa à vista, embora tenha cupom (diferença
medida de −20 a +2 pontos-base).

### 2.5 Eventos de capital que ninguém declarou

O capital emitido depois do último balanço entra quando está declarado no
Formulário de Referência (decisão 135, item B28); o que não está declarado gera
aviso e fica de fora. Recompras depois da contagem oficial também não aparecem
até a próxima contagem.

### 2.6 Validação histórica com série de preços limitada

As coortes vão de 2018 a 2025, com no máximo dez anos de preços; o beta das
coortes antigas tem janela curta. Das deslistadas, algumas ficam de fora por
evento de ações não localizado ou salto de preço (por exemplo, 11 na coorte de
31/03/2018).

---

## 3. Modelo

### 3.1 Premissas iguais para todas as empresas

- Dez anos de projeção (decisão 115).
- O crescimento cai em linha reta até o perpétuo, e o retorno sobre o capital
  converge em linha reta ao custo de capital, no mesmo ritmo para toda empresa.
- A dívida cresce junto com a empresa (alavancagem constante na projeção); a
  recusa por estrutura de capital depende disso.

**Efeito:** empresas com vantagem competitiva longa (a WEG, por exemplo) são
avaliadas como se a concorrência chegasse no prazo padrão. A vantagem residual
(seção 3.4) atenua isso só quando a persistência medida é alta.

### 3.2 Prêmio de mercado tirado do preço da bolsa

O prêmio é a média de dez anos do prêmio implícito: o retorno que o valor de
mercado das listadas embute, dados os dividendos e JCP que elas pagam, menos o
prefixado de dez anos — 1,21% em 14/09/2026 (decisão 142,
[premio_implicito.md](premio_implicito.md)). O mesmo para todo ativo, como o
CAPM manda. O que ele carrega:

- **Uma premissa de crescimento**: os dividendos crescem com a economia nominal.
  Um ponto a mais ou a menos move o prêmio em cerca de um ponto.
- **Sem recompra de ações** no dinheiro distribuído, o que o deixa um pouco
  abaixo do que seria com ela.
- **Só as companhias listadas hoje** nas datas antigas da série.
- **Uma circularidade**: um prêmio tirado do preço do mercado inteiro calibra o
  **nível** do motor pelo mercado. O teste de **ordem** entre as ações (R3) não
  é afetado, porque o prêmio é igual para todas.
- **Muito abaixo do prêmio total que Damodaran publica para o Brasil**, porque é
  medido contra o prefixado brasileiro, que já carrega o risco do país.

### 3.3 Beta, dívida e imposto

- Beta contra um índice só (Ibovespa), cinco anos diários, encolhido para o
  setor pela precisão (decisão 40).
- Na fórmula de Hamada, dívida ÷ patrimônio é limitada a 3.
- O custo da dívida é **sintético** (taxa livre de risco mais um prêmio pela
  alavancagem ou pela cobertura), não o custo real de cada empresa (decisões 31
  e 130).
- O escudo fiscal usa 34%. Bancos pagam até 45%, mas não passam por essa conta:
  a via do acionista parte do lucro já tributado.

### 3.4 A perpetuidade

- **Retorno neutro** (padrão): o capital novo rende o custo. O capital que já
  existe continua rendendo o que a projeção alcança, para sempre; a parcela
  correspondente é medida, aparece no rastro e vira aviso acima de 20% do valor
  (item B12, decisão 107).
- **Vantagem residual:** a persistência `φ` do excedente é estimada com 7 a 15
  pares de anos, sem correção do viés de amostra pequena (a correção dominava o
  dado; decisão 36).
- **Concessão:** quando o prazo não foi lido do Formulário de Referência, a
  perpetuidade é tratada como sem prazo, com a ressalva "prazo determinado" (caso
  SAPR11).

### 3.5 A base e o ciclo

- A normalização supõe que o retorno volta à mediana dos oito anos anteriores.
  O motor não prevê preço de commodity nem mudança estrutural que não apareça
  como tendência estatística.
- A lista de setores cíclicos (que decide a precedência do ciclo e a isenção da
  trava de saúde) é mantida à mão.
- O setor é o do emissor na classificação oficial da B3, baixada em 14/09/2026;
  mudança de setor exige reempacotar (decisão 87).

### 3.6 Crescimento

O crescimento vem só da história da própria empresa. Aquisições aparecem como
"capital externo" declarado (guarda Φ), e não são modeladas.

### 3.7 Preço por ação frágil quando a dívida é grande

Quando o capital próprio é uma fatia pequena do valor da empresa, pequenos erros
no valor da operação viram erros grandes no valor por ação. A ressalva "ponte
frágil" aparece abaixo de 35%, mas a tela não mostra o **tamanho** da
fragilidade (proposta B34). No limite, a conta recusa a avaliação (caso RENT3).

### 3.8 Proventos não entram na avaliação

O fluxo descontado não lê dividendos publicados, e a simulação da carteira não
credita proventos: o retorno é de preço. Proventos entram só como dado conferido
no retorno total do beta, das coortes e da faixa calibrada (decisões 23, 89 e 92).
**Efeito:** quem recebe proventos obtém mais do que a simulação mostra.

### 3.9 Múltiplos de pares

A leitura por pares é segunda leitura, e não muda o preço justo (decisão 118).
Usa a mediana de outras companhias do mesmo subsetor (ou setor, ou mercado,
quando faltam cinco), uma por companhia, sem a própria (item B41, corrigido em
28/09/2026). Grupos pequenos caem para o setor, que é mais heterogêneo.

---

## 4. Aplicativo e simulação

- **Sem rebalanceamento:** a simulação divide cada aporte pelos pesos-alvo, e os
  pesos derivam com o mercado (decisão 9).
- **Ação inteira:** a sobra de cada aporte fica em caixa por ativo, sem render,
  até completar uma ação.
- **Custos:** a tarifa da B3 (0,030%) entra; corretagem, spread e imposto não.
  Nas coortes de validação, tarifa e meio spread entram e não mudam o veredito
  (decisão 126).
- **Janela:** até dez anos, encurtada até o primeiro pregão da ação mais nova.
- **Retorno esperado da carteira:** é o custo do capital próprio de cada ação,
  ponderado pelos pesos — não usa o preço justo (decisão 103).

---

## 5. Escopo

- Só ações; sem fundos imobiliários (decisão 0, no
  [PLANO_ARQUITETURA.md](../../PLANO_ARQUITETURA.md)).
- Ferramenta de análise para uso pessoal, e não sistema de recomendação:
  o motor "não atinge nossos critérios de poder tomar a decisão por si só"
  (decisão 140).
- O projeto roda no plano sem cobrança do Firebase: o proxy da credencial
  (Cloud Function) não está publicado, e o token da brapi fica no build.
