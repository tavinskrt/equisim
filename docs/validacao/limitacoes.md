# Limitações do trabalho

Documento de referência para a seção de limitações do artigo. Cada item
traz o que foi observado, o efeito prático e o que seria necessário para
resolver.

---

## 1. Fonte de dados

### 1.1. Granularidade dos fundamentos é apenas anual

A brapi entrega **16 exercícios anuais** (2010–2025) nos quatro demonstrativos.
Testado: `mode=history&type=quarterly` devolve dados anuais do mesmo jeito.

**Efeito.** A avaliação não pode ser revista trimestralmente. Entre a
divulgação de um exercício e a do seguinte, o preço justo permanece congelado
enquanto o preço de mercado se move — o *upside* muda por variação de preço,
não por revisão de fundamento.

**Para resolver.** Fonte com dados trimestrais (CVM, B3 ou provedor pago).

**Atualizado em 14/09/2026.** A CVM publica ITR, e a ingestão o lê
(decisão 72). A série de doze meses **ancorada no trimestre** existe e está
testada (decisão 73), mas **não é o padrão**: ela move a ordenação de metade do
universo — correlação de postos de 0,683 contra a série anual em 04/09/2024 — e
se isso é informação ou ruído é a pergunta da coorte trimestral (C1c). Ver
[cvm_trimestral.md](cvm_trimestral.md).

### 1.2. `adjustedClose` diverge de forma material

Medido sobre 11 ativos em janela de 10 anos: **desvio mediano de 9,1%** entre o
fator de ajuste implícito no fluxo de proventos publicado pela fonte e a razão
`adjustedClose/close` observada. Máximo de 38,5% (BBAS3). Seis dos onze ativos
acima de 5%. A medição é de 20/08/2026, quando o fluxo de proventos ainda
estava no projeto.

**Efeito.** A série de retorno total da fonte é inutilizável para cálculo. Todo
cálculo do sistema parte de `close`, que a fonte ajusta apenas por
desdobramento e grupamento.

**Sobre a causa.** Ativos com maioria de JCP desviam mais na média (11,2%
contra 7,7%), mas a correlação entre proporção de JCP e desvio é de apenas
**0,19**, e há contraexemplos nos dois sentidos — PETR4 tem 38% de JCP e desvia
2,1%; EGIE3 tem 31% e desvia 21,0%. **A divergência é fato medido; a explicação
pelo tratamento de JCP é hipótese plausível não confirmada.**

**Consequência para o beta, medida em 11/09/2026.** O retorno que entra na
regressão do CAPM é de preço, e não total. Corrigir isso exige a série acima, e
ela erra 9,1% na mediana — o remédio é maior que a doença. A
[decisão 57](../decisoes/057-a-correcao-de-nao-sincronia-e-medida-e-recusada.md)
registra o bloqueio, e a Fase B é onde ele se resolve: segunda fonte para o
fluxo de proventos, ou nada.

**Remedido em 14/09/2026, com a B3 como segunda fonte.** Contra o histórico de
proventos do portal de empresas listadas, sobre 278 ativos e dez anos, o desvio
mediano do ajuste da fonte é de **3,3%**, com p90 de 16,5% e 101 ativos acima de
5%. Erra menos do que se media, e ainda erra; continua fora de cálculo. O
bloqueio de dado da decisão 57 **caiu**: o beta passou a sair do retorno total
com os proventos da B3
([decisão 89](../decisoes/089-proventos-voltam-como-dado-conferido.md),
[proventos.md](proventos.md)).

### 1.3. Viés de sobrevivência

`/v2/tickers?type=stock` lista **781 ações vivas**. Empresas deslistadas não
aparecem.

**Efeito.** Qualquer análise histórica sobre o universo herda viés de
sobrevivência. O sistema mitiga parcialmente resolvendo renomeações
(`/v2/tickers/resolve`), mas não recupera deslistagens.

**Estado em 14/09/2026: as duas pontas existem, e falta a ponte entre elas.**
Os demonstrativos das deslistadas estão ingeridos — 60,6% dos exercícios da CVM
são de companhias fora do universo vivo. O preço delas está no COTAHIST da B3,
que lista todo papel negociado no ano: em 2019 e 2024, os dois anos baixados,
há **487 papéis fora do universo de hoje** com fechamento bruto. O que falta é ligar
um ao outro — o COTAHIST identifica o papel por ISIN e a CVM por CNPJ, e a FCA
faz a ponte — e baixar o histórico inteiro. É o item A3.2 do
[plano](../plano-motor-de-referencia.md), e é pré-requisito do C1b.

**Atualizado à tarde: a ponte existe.** O COTAHIST de 2010 a 2026 está baixado —
1,63 milhão de pregões à vista —, e **164 das 290** companhias fora do universo
que tinham ação em bolsa estão ligadas ao preço, com 1.272 exercícios que têm
pregão no ano seguinte. As outras 634 fora do universo nunca tiveram ação
negociada. Faltam, para a coorte, o ajuste por evento e a contagem de ações por
data (item A3.4). Ver [b3_deslistadas.md](b3_deslistadas.md).

**Onde o viés pesa, medido na Fase 2.** As duas medições da primeira rodada — a
cobertura da faixa de incerteza e o custo das recusas — são dos sobreviventes, e
o viés cai exatamente sobre elas: os recusados por liquidez renderam 73% em média
em 36 meses, contra 31% dos avaliados, e a cauda de baixo do realizado, que decide
a borda inferior da faixa calibrada, é a que as quebras esconderiam. Remedir as
duas com as deslistadas são os itens C2b e C0b.

**Atualizado em 15/09/2026: as deslistadas da ponte entram nas coortes** (item
C1b, decisão 93) — 444 observações de 86 companhias, 106 delas avaliadas, com a
CVM pelo CNPJ, o COTAHIST ajustado pelos eventos até a data, a contagem do FRE e
o setor da B3 ou o representante do setor da CVM. **O viés pesou no nível, e não
na ordenação**: com elas, os recusados por liquidez rendem 68% em média em 36
meses, e o potencial deles continua ordenando além do B/M; a faixa calibrada
continua cobrindo, e a cauda de baixo não desceu. **O que resta do viés**: as
126 companhias com ação em bolsa e sem ponte, e as 48 observações que saem por
evento não localizado ou salto na série.

**Atualizado à tarde: a ponte chegou a 189 companhias** (item C1d). Das 128 que
ficavam sem ela, duas eram grandes e o motivo era da própria ponte: a BRF e a
Petz, incorporadas em 2025, estavam na lista de hoje quando ela foi montada, e a
fonte de preços já não as traz. A ponte passou a excluir só quem as coortes
observam como listado, e ganhou o código de emissor e o nome relaxado, revisados
um a um. **Das 112 que seguem sem ponte, nenhuma tem código com pregão**: 36
terminam antes da janela das coortes, e as outras declaram código que nunca
negociou à vista ou que não é ticker — registro companhia a companhia em
[ponte_deslistadas_registro.json](ponte_deslistadas_registro.json). Nas coortes
trimestrais entram 1.864 observações de 103 deslistadas, 449 avaliadas.

### 1.4. Limite de requisições inobservável

A API **não expõe nenhum cabeçalho de rate limit** — verificado: nenhum
`X-RateLimit-*`, nenhum `Retry-After`.

**Mitigação adotada.** Concorrência contida na origem (4 simultâneas), busca em
lote sempre que possível, espera exponencial com ruído em caso de `429`, e
cache agressivo.

### 1.5. Taxonomia setorial própria

O campo `sector` usa taxonomia da brapi em português (`energia`,
`petroleo-e-gas-integrado`). **Não é GICS nem a classificação setorial oficial
da B3.**

**Efeito.** O alerta de concentração setorial depende dessa classificação. Uma
taxonomia diferente produziria agrupamentos diferentes.

**Resolvida em 14/09/2026.** O setor de todo ativo passou a ser o da
classificação oficial da B3, por emissor — 297 de 297 classificados —, com a
taxonomia da fonte como recuo. 51 tickers do universo mudam de porta, quase
todos por chegarem sem setor da fonte
([decisão 87](../decisoes/087-o-setor-e-o-da-b3-por-emissor.md),
[b3_classificacao.md](b3_classificacao.md)).

### 1.6. IFIX indisponível

`historical?symbols=IFIX` devolve **um único ponto**. Sem consequência para
este trabalho, já que fundos imobiliários estão fora do escopo — mas registrado
porque foi levantado na auditoria.

### 1.7. Duas contagens de ações, que divergem em 14% dos ativos

A fonte publica uma contagem **corrente** e uma **do exercício**. Medido em
07/09/2026 sobre 334 ativos com as duas preenchidas: **47 divergem** além de
1,5×, e a divergência chega a **4.868×** — o MILS3 vem com 48.172 ações
correntes contra 234.178.210 do exercício.

**Efeito.** A ponte de equity divide o valor da firma pela contagem. Com a
corrente crua, o MILS3 saía com preço justo de R$ 37.708,72 contra R$ 15,79 de
mercado. O mesmo campo alimenta o lucro por unidade negociada e o peso do equity
no WACC.

**Mitigação implementada.** A contagem é conciliada com o lucro por ação
publicado, por `N = lucro ÷ LPA`. Nos 38 divergentes com LPA utilizável, o
árbitro confirmou a contagem do exercício em 34 e a corrente em nenhum.

**O que sobra, agora medido.** A contagem do exercício tem a idade do último
encerramento. Grupamento ou desdobramento posterior a ele não aparece nela, e o
preço já o reflete.

O resíduo **não é simétrico**, e isso é consequência da regra do maior que a
ponte adota na divergência. `reconciledShares` só pode confirmar a contagem do
exercício — o árbitro `N = lucro ÷ LPA` compara dois campos das **mesmas**
demonstrações. Um grupamento reduz a contagem corrente sem tocar a do
exercício, de modo que a candidata contábil fica maior **sempre** e vence
**sempre**; um desdobramento faz o contrário, e a regra o absorve bem.

Medido em 11/09/2026: **29 ativos com grupamento aparente** (exercício acima de
1,5× a corrente), e em **27** a contábil vence. O divisor fica maior que o
implícito no valor de mercado por praticamente o mesmo fator do grupamento —
MILS3 4.852×, MEAL3 858×, COGN3 11,5×, SAPR 2,93×, RENT 1,8×. O preço justo
desses 27 é menor na mesma proporção.

**A regra fica.** Invertê-la faria o MILS3 sair com preço justo de R$ 37.708,72
contra R$ 15,79 de mercado, que é falso desconto de 238.000% — o pior sentido
possível. Nada no dado arbitra: o `close` da fonte já vem ajustado por ação
societária e não denuncia salto em dez anos. O motor declara a escolha e o
sentido do erro no aviso do resultado. Tabela completa em
[unidade.md §4](unidade.md).

**Atualizado em 14/09/2026: o dado passa a poder arbitrar.** O COTAHIST traz o
fechamento **bruto**, e um grupamento aparece nele como salto da razão entre
pregões — `CorporateEvents` o detecta e mede o fator (decisão 75). **Ainda não
arbitra nenhum dos 27**: nenhum deles tem evento em 2019 ou 2024, os dois anos
baixados, e o fator detectado ainda não entra no divisor. Os dois passos são os
itens A3.2 (histórico inteiro) e A3.3 (evento no divisor) do
[plano](../plano-motor-de-referencia.md).

**Revisto na tarde de 14/09/2026: o diagnóstico desta seção estava errado, e o
divisor tem árbitro.** O registro de empresas listadas da B3 dá a contagem
oficial de ações de cada emissor ([b3_registro.md](b3_registro.md)):

- **MILS3 e MEAL3 não eram grupamento.** A B3 registra 234.286.833 e 286.676.540
  ações, e nenhum evento de ações. A contagem "corrente" da fonte — 48.172 e
  307.010 — está errada. A regra do maior acertava nelas, pelo motivo errado.
- **Em dez ativos, a "contagem do exercício" da fonte é o capital autorizado** —
  número redondo: GGBR3/4 com 4.499.999.700 contra 1.978.018.049 emitidas,
  CSAN3 com 8 bilhões contra 3,97, B3SA3 com 7,5 contra 5,05, RENT3/4, COGN3,
  ENMT3/4, VIVR3. A regra do maior o adotava, e o preço justo saía até 2,28x
  subestimado.
- **E o erro também ia para o lado ruim**: AUAU3 com 451 milhões contra 861, e
  AZUL3 com 21,7 milhões implícitos contra 368,6.

**Mitigação implementada ([decisão 83](../decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md)):**
a contagem oficial arbitra o divisor, líquida da fração em tesouraria. Medido na
mesma execução, o potencial mediano do universo sai de −37,6% para −28,7%, com
correlação de postos de 0,982: quase ninguém muda de posição, e os que mudam são
os de divisor errado.

**O que sobra.** O registro é o da data do build do aplicativo; um evento de
ações entre o build e a avaliação passa despercebido por até 31 dias, quando a
fonte ainda não o refletiu. E ele não existe para o passado: coorte de backtest
não o usa, e a §3.5 continua valendo.

### 1.8. O universo devolvido é parcial

`/v2/tickers?type=stock&limit=1000` devolveu **373 ações** em 07/09/2026, contra
as 781 registradas em medição anterior. A causa não foi isolada — teto do plano
ou mudança da fonte.

**Efeito.** A cobertura da validação fora da amostra é do que a fonte devolve no
dia, e não do universo da B3. Números de cobertura entre execuções só são
comparáveis se o tamanho do universo for igual.

---

## 2. Modelagem

### 2.1. CapEx aproximado

A fonte não entrega CapEx isolado. O sistema usa `investmentCashFlow` como
aproximação, que **inclui fusões, aquisições e aplicações financeiras**, não só
imobilizado.

**Mitigação.** O reinvestimento **não passa mais por aqui.** A soma que ele pede
— `CapEx − Depreciação + ΔNKG` — é, por identidade de balanço, a variação do
capital investido, que se obtém do próprio balanço sem o CapEx isolado. Medido,
as duas rotas concordam dentro de 3 p.p. em 7 de 9 ativos. O `investmentCashFlow`
segue impróprio para conta de reinvestimento: contra `Δ(imobilizado) + D&A` ele
erra por fatores de 0,25× a 2,42×, e para os dois lados.

### 2.1-b. A alíquota da fonte é estatutária para todo mundo

`/v2/stocks/financial-data` publica `NOPAT = EBIT × 0,66` — a alíquota
estatutária brasileira de 34% aplicada a **toda** empresa, em 4.572 de 4.572
exercícios do cache.

**Efeito, medido em 10/09/2026.** A alíquota efetiva mediana dos 122 avaliados
é de **22,1%**, e **112 dos 122** pagam menos que a estatutária. Usar 34% para
todos subestimava o lucro operacional de quase todo o universo.

**Corrigido** pela [decisão 37](../decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md):
o fluxo da firma passa a ser tributado pela mediana dos exercícios do próprio
ativo, que a medição mostrou ser regime — dispersão de 7,5 p.p. dentro da
empresa sobre quinze exercícios. Ver [fluxo_explicito.md](fluxo_explicito.md).

**Corrigido também o sinal**, em 10/09/2026. A fonte grava a despesa
tributária **negativa** — `lucro líquido = lucro antes + incomeTaxExpense`,
conferido pela identidade no cache —, e `effectiveTaxRate` tirava o módulo. O
módulo acertava o caso comum pelo motivo errado e transformava **crédito** em
imposto a pagar. A conta passou a negar o sinal em vez de modulá-lo: a alíquota
estrutural mediana caiu de 22,1% para 18,9% e 33 dos 122 preços justos se
moveram. Ver a §8 de [fluxo_explicito.md](fluxo_explicito.md).

### 2.1-c. O CAGR do índice depende da janela das pontas

`marketCagr` sai do Ibovespa, e até 11/09/2026 saía **ponta a ponta** — o
fechamento do primeiro pregão contra o do último. A [decisão 60](../decisoes/060-as-pontas-do-cagr-do-indice-sao-medias.md)
passou a promediar 63 pregões em cada ponta e a contar os anos de centro a
centro, como o índice de atividade já fazia.

O que sobra é que **a escolha da janela move o número**. Na janela de dez anos,
2.479 pregões:

| ponta | CAGR |
|---|---:|
| 1 pregão | 12,57% |
| 21 pregões | 11,43% |
| 63 pregões | 11,06% |
| 252 pregões | 10,24% |

Do trimestre para o ano sobra 0,82 p.p. de sensibilidade que nenhuma convenção
elimina — ela é o próprio nível do índice mudando com o recorte. O trimestre é
o menor prazo em que o resultado para de se mover muito com a janela, e essa é
a justificativa inteira: não há verdade a apurar aqui, há uma convenção a
declarar.

### 2.2. Prêmio de risco de mercado é parâmetro, não observação

O CAPM usa prêmio parametrizado (padrão 5,5%). Estimá-lo pela média histórica
do Ibovespa produz valores instáveis e às vezes negativos em janelas ruins, o
que quebraria o modelo.

**Efeito.** A avaliação depende de uma escolha metodológica declarada. A
[análise de sensibilidade](sensibilidade.md) quantifica o impacto.

### 2.3. Defasagem de publicação é premissa

Assume-se que um exercício se torna público **90 dias** após o encerramento.
É aproximação: a divulgação real varia por empresa.

**Efeito.** Medido na análise de sensibilidade, variando de 0 a 365 dias.

**Agora medida, e com solução conhecida.** A CVM publica `DT_RECEB` por
documento. Sobre o universo em 2024: a defasagem real do documento anual tem
mediana de **78 dias** (p90 de 90, máximo de 472) e a do trimestral, **40**.
A premissa de 90 dias acerta o p90 do anual, erra a mediana em 12 dias e a do
trimestral em 50. Com a ingestão do A1 ela deixa de ser premissa.
Ver [cvm_conferencia.md §5](cvm_conferencia.md).

### 2.4. Beta com índice de referência único

O beta é calculado contra o Ibovespa. O beta publicado pela fonte foi
descartado de propósito: sua janela e seu índice de referência não são
documentados, o que é incompatível com reprodutibilidade.

### 2.5. Backtest sem custos de transação

O motor não modela corretagem, emolumentos nem *spread* de compra e venda.

**Efeito.** Os retornos simulados são otimistas em relação ao que o investidor
obteria. Como o modelo **não rebalanceia**, o número de operações é baixo — o
aporte inicial mais um por mês —, o que limita a distorção.

### 2.6. Caixa parado entre aportes

Desde a [decisão 23](../decisoes/023-remocao-de-proventos.md), a simulação
compra **ações inteiras**: a fatia de cada aporte que não completa mais uma
ação fica em caixa, sem render, até o aporte seguinte.

**Efeito.** É o comportamento da corretora, e não uma aproximação — mas o caixa
real ficaria em conta remunerada ou no CDI, e aqui não rende nada. Numa carteira
de papel caro diante de um aporte pequeno, isso subestima levemente o
patrimônio. O saldo é exibido na tela, e não fica implícito.

### 2.7. Nenhum provento é modelado

O retorno apurado é de **preço**. Dividendo, JCP e a tributação deles saíram do
projeto pela [decisão 23](../decisoes/023-remocao-de-proventos.md), depois de a
premissa de base bruta do campo `rate` permanecer sem conferência documental.

**Efeito.** O resultado é conservador por construção: o acionista que recebe
provento obtém mais que o simulado. Um papel de *dividend yield* alto é
sistematicamente subestimado em relação a um de yield baixo com a mesma
valorização — o que importa quando duas carteiras são comparadas.

**Efeito colateral na comparação com o índice.** O Ibovespa é de retorno total
por construção; o `close` dos ativos não. Beta e correlação misturam as duas
convenções. O efeito é de segunda ordem, porque essas medidas olham
covariância de variações e não nível.

**Reaberta em parte em 14/09/2026, pelo orientador.** Provento voltou como dado
conferido da B3 em dois lugares: o **retorno total nas coortes de validação** e o
**beta**, que sai do retorno total dos dois lados
([decisão 89](../decisoes/089-proventos-voltam-como-dado-conferido.md)). A
simulação da carteira, a cascata e o retorno esperado **continuam de preço**, e o
que se lê acima continua valendo para eles. Nas coortes, o retorno total fica 7%
a 11% acima do de preço em 36 meses, e não muda a conclusão sobre a habilidade
([proventos.md](proventos.md)).

### 2.8. O terminal neutro comprime o valor — mas não é ele que desloca o nível

> **Correção de 09/09/2026.** Esta seção atribuía ao terminal neutro o
> deslocamento do nível do potencial. O [DCF reverso](dcf_reverso.md) mediu, e
> **não é ele**: o retorno terminal é *inatingível* em 73 dos 122 avaliados —
> nem 200% ao ano perpétuo alcança o preço de mercado — e não é explicação
> exclusiva em ativo nenhum, contra 56 ativos em que o nível da curva de
> desconto resolve e o terminal não. O que se lê abaixo continua verdadeiro
> como **mecanismo**: o múltiplo terminal cai de `1/(r − g_∞)` para `1/r`, e
> isso comprime. O que deixou de se sustentar é a atribuição do nível
> observado a ele. Ver a [decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md).


A [decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) adotou
`ROIC_∞ = WACC` e `ROE_∞ = Ke`: nenhuma empresa preserva retorno excedente na
perpetuidade. O terminal vira `NOPAT/WACC`, imune a `g_∞` — que era o defeito
que motivou a decisão.

**Efeito, medido.** O múltiplo terminal passa de `1/(r − g_∞)` para `1/r`. A um
desconto ilustrativo de 15% com `g_∞ = 6,86%`, isso é **6,7× contra 12,3×**, e o
terminal carrega a maior parte do valor.

**Parcialmente compensado em 07/09/2026** pela estrutura a termo do desconto
(ver [2.9](#29-a-estrutura-a-termo-é-linear-e-de-dois-pontos-não-uma-curva-observada))
e pela exceção de vantagem competitiva residual. A mediana do potencial passou de
**−55,1% para −39,4%**, e a fração com potencial positivo de 10,9% para **15,8%**.

**A compressão não desapareceu.** Em 07/09/2026 a mediana estava em −38,0% e o
p75 em −7,5%, sobre 121 avaliados. Se o deslocamento remanescente é comum a todos
os ativos, a **ordenação** relativa continua informativa e o **nível** não deve
ser lido como preço-alvo.

**A escolha entre nível e ordem foi feita, e é assimétrica.** Pela
[decisão 27](../decisoes/027-recalibragem-apos-a-primeira-validacao.md), o preço
justo do ativo individual continua sendo o do DCF, com o nível intacto; o que
deixou de usar o nível é o retorno esperado **da carteira**, que passou a ser
`E[R_i] = CDI_spot + z(potencial) · prêmio`. Pelo caminho antigo, 97 dos 121
avaliados entravam numa otimização de média-variância com retorno esperado
negativo. **A limitação continua existindo onde sempre esteve** — no nível do
potencial —; o que mudou é que ela não se propaga mais para a meta.

**Isso troca uma limitação por outra, e a nova precisa ser lida junto.** O
retorno esperado da carteira deixou de ser uma previsão de rentabilidade e virou
uma afirmação de posição relativa: o ativo mediano da seção recebe o CDI por
construção. Uma seção estreita — a carteira medida contra ela mesma — centra tudo
no CDI e não informa nada. O resultado carrega o tamanho da seção junto, e é
contra a seção dos avaliados que a leitura faz sentido.

> **Defasado desde 09/09/2026.** A [decisão 36](../decisoes/036-decaimento-medido-do-excedente-na-perpetuidade.md)
> trocou o degrau por decaimento medido: são **23 dos 117** com preservação
> positiva, e o `λ` mediano é de 0,0015 contra os 0,30 fixos. O parágrafo
> abaixo descreve o regime anterior.

**A exceção de *moat* ativa em 7 dos 121 avaliados** (ABEV3, BBSE3, EGIE3,
LEVE3, SAUD3, VBBR3 e WEGE3), contra 2 antes da recalibragem. O passo é
instrumentado desde 07/09/2026, e a
[decisão 28](../decisoes/028-travas-de-ciclo-saturacao-e-saude.md) usou a medição
para elevar o corte de capital externo a `Φ ≤ 0,60` — que admitiu a EGIE3 — e
para acrescentar um filtro de saúde operacional, que reprova quem teve lucro ou
EBITDA caindo mais de 50% no triênio. Foi ele que tirou a QUAL3 (queda de 83,2%)
e a KEPL3 (59,1%). Ver §14.3 do [refinamento](../refinamento-do-valuation.md).

**O ITUB4 não entra na exceção por falta de dado, não por calibragem.** A fonte
não publica `netIncome` para ele em nenhum dos dezesseis exercícios; sem lucro
não há série de retorno, sem retorno não há mediana de ciclo, e sem ela o *moat*
não tem excedente a preservar. A avaliação sai pelo LPA publicado, com o freio de
reinvestimento desligado — o que o resultado declara. É lacuna de cobertura, e
nenhum parâmetro a resolve.

**O fator de normalização da base é saturado em `[0,33; 3,00]`, e o limite é de
política.** Sem teto, `f = ciclo / atual` explode quando o exercício corrente tem
retorno próximo de zero, e o DCF é homogêneo de grau 1 no fluxo-base: a MBRF3
chegou a receber 21,4x e sair a +406,1% de potencial. Não há teste que diga onde
um exercício deixa de ser atípico — a §2 da
[normalizacao_fluxo_base.md](normalizacao_fluxo_base.md) já mostrava isso para
`τ`. O que a banda afirma é **quanta autoridade um único exercício tem sobre a
avaliação inteira**. Quatorze ativos foram confinados na consolidação de
07/09/2026, onze no teto e três no piso; o preço justo deles é conservador por
essa escolha, e o aviso traz o fator bruto que teria sido aplicado.

**O maior potencial do universo continua sendo o da QUAL3, em +477,3%.** O filtro
de saúde retirou dela a vantagem residual e **não** tocou na avaliação: o número
sai da mediana de ROIC de oito anos, que ainda carrega os exercícios anteriores à
queda. Levar o sinal de deterioração também para a Porta 0 ou para a janela do
ciclo é pergunta aberta, registrada na §14.6.

### 2.9. A estrutura a termo é linear e de dois pontos, não uma curva observada

Até 07/09/2026 a taxa livre de risco do CAPM era o **CDI corrente** para todos os
períodos, inclusive a perpetuidade — um indexador *overnight* precificando fluxo
perpétuo. Num pico de ciclo monetário isso esmagava o valor terminal; num vale, o
inflava.

**O que passou a valer.** A taxa decai linearmente do CDI corrente ao CDI médio
decenal ao longo dos dez anos de projeção, e a perpetuidade é descontada à taxa
de equilíbrio. Como `Ke` e `WACC` são afins na taxa livre de risco, decair o
custo de capital equivale a decair a taxa e remontar o custo a cada ano. O fator
de desconto **acumula** as taxas ano a ano.

**A limitação que sobra, e não é pequena.** Isto não é uma curva de juros: é uma
interpolação entre dois pontos, ambos medidos do CDI. Não vem da estrutura a
termo negociada, não tem vértices, e a forma do decaimento — linear — é escolha,
não observação. O CDI médio decenal é uma média histórica usada como **proxy** de
taxa de equilíbrio, e ela não é uma previsão.

**Para resolver.** Curva da ANBIMA ou do Tesouro (NTN-B), com desconto por
vértice.

**Resolvida como capacidade em 14/09/2026, e não ligada por padrão.** A curva
nominal dos títulos prefixados do Tesouro Direto entra por
`ValuationInputs.riskFreeCurve` (decisão 74). Medida contra o motor, a
perpetuidade da curva ficou **2,9 a 4,5 p.p. acima** da média decenal do CDI em
todas as coortes de 2021 a 2025, e ligá-la derruba o potencial mediano em cerca
de 12 pontos — de −37,6% a **−48,6%** na primeira medição, de −33,1% a −53,2%
na remedição com o prazo em dias úteis (decisão 79) —, com correlação de postos
de 0,93 e 0,92. **O padrão é decisão do usuário**, porque muda o nível de toda
avaliação.

**Decidido em 14/09/2026: a curva é o padrão do aplicativo**
([decisão 84](../decisoes/084-a-curva-e-o-padrao-do-aplicativo.md)). Sem curva
de até sete dias — Tesouro fora no nativo, ou pacote do build vencido —, a
avaliação recua para os dois pontos do CDI e diz no aviso qual das duas foi.
**Na web o pacote é a única fonte**
([decisão 86](../decisoes/086-na-web-a-curva-vem-so-do-pacote.md)): a função
que buscaria a curva do dia exige o plano Blaze do Firebase, e o build web serve
a curva por cerca de uma semana. Ver [curva_de_juros.md](curva_de_juros.md).

### 2.10. As primitivas estatísticas do núcleo, e sua conferência externa

O [`cross_validation.py`](cross_validation.py) existe porque o Dart não tem NumPy
nem SciPy: ele recalcula as métricas em Python e reporta a diferença. Ele cobre
volatilidade, *drawdown*, CAGR, beta, correlação, semidesvio e Sortino.

**Não cobre `inference.dart`**, introduzido pela decisão 25 — OLS, erro-padrão
Newey-West com núcleo de Bartlett, quantil da t de Student e R² crítico, todos
escritos à mão.

**Resolvido em 07/09/2026.** `tool/validation/inference_export.dart` gera séries
sintéticas determinísticas, roda as primitivas e grava os dados **junto** dos
resultados; `inference_cross_validation.py` recalcula com `statsmodels` e
`scipy.stats` sobre os mesmos números. Nenhum gerador pseudoaleatório é
compartilhado entre os dois lados — se cada um gerasse a própria amostra, a
comparação dependeria de duas sequências coincidirem.

**Resultado: 99 de 99 comparações dentro da tolerância**, incluindo as seis do
erro-padrão HAC, que concordam com o `statsmodels` na ordem de `1e-14` relativo.
Ver [conferencia_inferencia.md](conferencia_inferencia.md).

**O que sobra.** A tolerância dos quantis da t é de `1e-5`, não de igualdade em
ponto flutuante: o núcleo os obtém por bisseção sobre a beta incompleta, e o que
se confere é concordância dentro do erro do método.

### 2.11. Sem imposto de espécie alguma

Não há IRRF sobre provento — não há provento —, e ganho de capital na venda
também não é modelado. O segundo é coerente com uma estratégia sem
rebalanceamento, em que não há venda, mas a limitação existe se o usuário
interpretar o resultado como líquido de tributos.

### 2.12. A fonte não publica lucro líquido de instituição financeira

> **FECHADA em 11/09/2026 pela ingestão da CVM (A1.7).** A CVM publica o lucro
> de instituição financeira: o Itaú tem R$ 42,1 bi em 2024, na conta `3.09` do
> layout de banco. Com a mescla, o ITUB4 passa a ser avaliado como qualquer
> outro — com freio de reinvestimento e série de retorno — e sai de **+3,6%
> para −35,8%** de potencial. Cinco dos sete ativos que mais se moveram na
> ligação são bancos. Ver [cvm_ligacao.md §2](cvm_ligacao.md).
>
> A seção fica como registro do que era, e do que a troca de fonte resolveu.
> O texto abaixo descreve o estado anterior.

**Registro formal de uma lacuna de cobertura, não de método.**

O `/v2/stocks/financial-data` da brapi devolve `netIncome` nulo para bancos ao
longo de **toda** a série. Verificado no ITUB4 em 07/09/2026: dezesseis
exercícios, de 2010 a 2025, com `netIncome` ausente em todos, enquanto
`bookValuePerShare` e `earningsPerShare` vêm preenchidos.

**O que isso faz na cascata.** A série de capital mede o retorno por
`lucro_t ÷ base_{t−1}`, e o lucro que ela usa é o `netIncome`. Sem ele:

| O que depende | O que acontece |
|---|---|
| Série de retorno (ROE) | fica **vazia** |
| Mediana do ciclo | não é medível |
| Guardas 1 e 3 | não avaliáveis; a base fica como observada |
| Freio de reinvestimento `b_t = g_t/ROE` | **desligado** — `returnOnCapital = 0` |
| Vantagem competitiva residual | barrada por `retorno do ciclo não medido` |
| Filtro de saúde operacional | não medível; não reprova |

**O ativo continua sendo avaliado, por caminho alternativo declarado.** O
fluxo-base sai do `earningsPerShare` publicado — é a via B, sobre o LPA — e o
crescimento sai da variação do patrimônio, que não depende de lucro. O ITUB4 sai
a R$ 40,24 contra R$ 41,92 de mercado.

**A leitura que isso exige.** Com o freio desligado, o fluxo descontado é o lucro
inteiro, sem retenção — o que é conservador na direção oposta à usual: subestima
o crescimento financiável e superestima o fluxo distribuível do mesmo exercício.
O resultado declara a degradação nos avisos, mas quem compara um banco com uma
empresa não financeira está comparando duas montagens diferentes.

**Nenhum parâmetro resolve isso**, e não é candidato a calibragem: a
[decisão 28](../decisoes/028-travas-de-ciclo-saturacao-e-saude.md) elevou o corte
de capital externo a `Φ ≤ 0,60` justamente pensando em bancos, e o ITUB4
continuou fora da exceção — porque o que o barra é a ausência do dado, não o
limiar. Sanar exigiria segunda fonte para a demonstração de resultado de
instituição financeira, ou preencher `netIncome` por `LPA × ações
reconciliadas`, que é identidade contábil mas introduz um valor derivado onde a
série espera um publicado.

### 2.13. A dívida projetada cresce a `g`, e a recusa depende disso

A rota (b) da [decisão 41](../decisoes/041-custo-de-capital-realavancado-ano-a-ano.md)
projeta a dívida sobre a base de capital, que cresce a `g` por construção; o
valor da firma cresce a outra taxa. É premissa deliberada — a alternativa,
amarrar a dívida ao valor, foi a saída (a) descartada —, mas ela tem
consequência que a [decisão 45](../decisoes/045-estrutura-de-capital-recusada.md)
tornou visível.

Quando o custo do capital próprio é reprecificado pela alavancagem, seis
ativos ficam com capital próprio não positivo no ano zero ou com WACC de
equilíbrio abaixo do crescimento perpétuo, e o motor **recusa a via da firma**
para eles. **A recusa é sobre a estrutura dada essa projeção de dívida**, e não
sobre a empresa: com a dívida amarrada ao valor, os mesmos seis fechariam.

Não há como decidir entre as duas premissas com o que a fonte publica — nenhuma
delas é observação, e a fonte não traz plano de endividamento. Fica declarado
que a recusa carrega a premissa junto.

### 2.14. Três bancos chegam sem setor, e escapam da exceção da Porta 1

A Porta 1 manda instituição financeira para a via do acionista **e** a isenta da
realavancagem da [decisão 46](../decisoes/046-custo-de-capital-do-acionista-resolvido.md),
porque ali depósito e captação são insumo do negócio e não financiamento. O
teste é o `sectorKey`, e a fonte não o preenche sempre: **BRSR6, PINE4 e SANB4
chegam vazios**, a Porta 1 não os pega, e a Porta 3 os captura — pelo motivo
certo, já que o NOPAT de um banco realmente não se sustenta, mas sem a isenção.

Passam, portanto, a ser realavancados como se o depósito fosse dívida. **O
efeito medido é de terceira casa decimal** — −0,27%, −0,15% e −0,10% no preço
justo — porque a alavancagem de um banco está muito além do teto de `D/E = 3,0`,
o fator de Hamada satura, e o `Ke` resolvido reencontra o do CAPM, que já fora
estimado sobre a ação alavancada.

No mesmo emissor a SANB11 é classificada e a SANB4 não. Sanar exige completar a
taxonomia por emissor em vez de por papel, e é trabalho de dado.

**Resolvida em 14/09/2026.** A classificação oficial da B3 é por emissor, e os
três passam pela Porta 1, por subsetor
([decisão 87](../decisoes/087-o-setor-e-o-da-b3-por-emissor.md)). Na montagem do
aplicativo o preço justo deles não se move: a isenção de realavancagem só age com
o beta desalavancado, e o aplicativo não resolve o prior do beta (item B11 do
plano).

### 2.14. O minoritário é subtraído pelo valor contábil

A [decisão 49](../decisoes/049-a-ponte-devolve-o-que-nao-e-do-controlador.md)
passou a descontar a participação dos não controladores do valor do capital
próprio. O correto seria descontar o **valor de mercado** da parcela deles, que
não existe para controlada de capital fechado — que é o caso quase sempre.

O contábil é o disponível, e **erra nos dois sentidos**: subestima a dedução
onde a controlada vale mais que o livro, e a superestima onde ela vale menos.
No universo brasileiro de holdings o segundo caso domina — a GOAU4 desconta
R$ 34,7 bi de não controladores da Gerdau enquanto a fatia deles vale bem menos
que isso em bolsa —, de modo que o preço justo do controlador sai **baixo**
justamente onde o termo é grande.

Sanar exigiria avaliar cada controlada em separado, o que a fonte não sustenta:
ela publica o consolidado e a linha de participação, não a demonstração da
controlada.

### 2.15. Propriedade para investimento fica fora da ponte

`longTermInvestments` decompõe-se em `shareholdings` — participação societária,
cuja receita entra no EBIT por equivalência patrimonial — e
`investmentProperties`. A segunda gera receita de aluguel que **pode ou não**
estar no resultado operacional conforme o setor e a classificação contábil da
empresa.

Sem como distinguir os dois casos na fonte, nada é feito com ela. O termo é
pequeno no universo — R$ 219,5 mi na CSNA3 contra R$ 8,07 bi de participação
societária — e é zero na maioria.

### 2.16. O horizonte é infinito, inclusive onde o contrato tem prazo

Quinze dos 120 avaliados operam sob concessão — transmissão, distribuição,
saneamento, rodovia, ferrovia — e o valor terminal deles é perpétuo.

A [decisão 50](../decisoes/050-concessao-nao-preserva-excedente.md) recusou o
excedente de retorno perpétuo nesses ativos, que é o que o contrato nega
diretamente, e **deixou o horizonte como está**: o prazo das outorgas não é
campo de demonstração financeira, e o estimador disponível mede giro da base de
ativos, não vencimento — dá 6,3 anos para a TAEE11, cujos contratos vão a 2042.

O tamanho está medido: se o contrato acabasse em dez anos, o preço justo
mediano dos expostos ficaria em 0,80 do publicado; em vinte, 0,90. Sanar exige
o prazo médio ponderado das outorgas, que existe em nota explicativa e no
formulário de referência da CVM — dado da Fase B. E exige, junto, modelar a
indenização do investimento não amortizado na reversão: truncar sem indenizar
trocaria um viés por outro.

**Resolvida em 14/09/2026, e a medição de cima estava mal posta.** A truncagem
para 0,80 não devolvia nada no fim do contrato. O terminal neutro mantém para
sempre o excedente de retorno do capital existente, e é esse excedente que o
contrato corta: o terminal da concessão com prazo passa a ser o capital mais o
excedente até o fim do contrato, e a projeção termina nele quando ele acaba antes.
O prazo vem do Formulário de Referência, pela mediana das outorgas vigentes.
Na mesma execução, a correlação de postos fica em 0,998, e a EGIE3 se move 34
p.p.; o excedente tem sinal, e três elétricas com capital rendendo abaixo do custo
sobem.
([decisão 88](../decisoes/088-o-prazo-da-concessao-corta-o-excedente.md),
[outorgas.md](outorgas.md)). **O que sobra:** sem peso por contrato no FRE, a
mediana não é o prazo ponderado pela receita, e o quadro de intangíveis parou em
2023.

### 1.9. A fonte publica exercício sem demonstração de resultado

Em 4 dos 376 ativos — 7 exercícios ao todo — a linha do exercício vem com o
balanço preenchido e receita, resultado operacional, lucro e lucro por ação
todos zerados. A TIMS3 aparecia assim em 2024 e 2025, com patrimônio líquido de
R$ 24 bilhões e EBIT de R$ 4,7 bi em 2023.

A [decisão 52](../decisoes/052-ausencia-nao-e-zero.md) passou a excluir esses
exercícios da série, porque ausência não é zero. **O que ela não faz é
recuperar o dado**: a TIMS3 fica com seis exercícios utilizáveis de oito
publicados, e é recusada por histórico curto.

Sanar exige segunda fonte para a demonstração de resultado — CVM ou B3 —, o que
é trabalho da Fase B. Não há como inferir o resultado a partir do balanço sem
inventar a variação do patrimônio como se fosse lucro, o que a decisão 23
proíbe ao remover provento da cadeia: a diferença entre dois patrimônios mistura
lucro, distribuição e evento societário.

---

### 2.17. Não há conferência analítica do balanço, e não pode haver

O capital investido tem duas rotas. A do **financiamento**,
`PL + dívida bruta − caixa`, é a que o motor usa: é o denominador do ROIC, e
portanto o freio de reinvestimento `b = g/ROIC` e o veredito de fosso saem
dela. Ela fecha por construção.

A do lado **operacional**, `imobilizado + intangível + capital de giro`,
existiria para conferi-la. O comentário de `investedCapital` afirmava que a
concordância entre as duas "serve de teste de qualidade" — **e esse teste nunca
foi executado**: `investedCapitalOperating` não é lido por linha nenhuma do
motor, só por um despejo de auditoria.

Executado em 11/09/2026 sobre 3.915 exercícios de 316 ativos, ele **reprova**:
distância multiplicativa com mediana de 1,199×, p90 de 3,165×, máximo de 316×,
e 28% dos exercícios acima de 1,5×. O viés é de mão única — a rota do
financiamento é 1,35× a operacional, em média geométrica.

**A causa é falta de linha na fonte, não erro de conta.** A rota operacional
não soma propriedade para investimento, participação em coligada, recebível de
longo prazo nem crédito tributário diferido, e a fonte não publica nenhuma
dessas — nem o ativo total de onde inferi-las. Por isso a cauda é setorial:
as quinze piores são imobiliário e *holding* (HBRE3 316×, BRAP 239×, LOGG3
157×, IGTI 125×, SYNE3 89×, SCAR3 100×, CURY3 74×), cujo ativo é exatamente o
que falta.

**Nada de numérico muda por isso**, porque a metade quebrada é a que não é
usada. O que sobra é a ausência de uma conferência independente do balanço, e
a alternativa — inventar o não circulante que falta — seria pior. Medição em
[capital_investido.md](capital_investido.md).

## 3. Escopo e método

### 3.1. Ferramenta, não experimento

O trabalho é de **engenharia de software**: constrói e valida uma ferramenta de
apoio à decisão. Não testa a hipótese de que alguma estratégia supere o
mercado, e nada aqui deve ser lido como recomendação de investimento.

### 3.2. O *upside* precisa de horizonte declarado

O DCF produz valorização **total** até o preço justo, sem prazo. A meta exige
taxa **por período**. A conversão assume convergência em horizonte declarado —
**36 meses** desde a [decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md),
antes 12. Continua sendo premissa forte: nada garante que o preço convirja, nem
nesse prazo nem em outro.

Com 12 meses a anualização era a identidade, e o retorno esperado da carteira
era o *upside* cru — o que fazia um potencial de −55% virar retorno esperado de
−55% ao ano. Com 36 a conversão é `(1+u)^{1/3}−1`, e a premissa fica explícita
em vez de embutida.

### 3.3. Amostra de validação reduzida

Os relatórios de invariantes, sensibilidade e conferência cobrem **11 a 20
ativos**. A limitação é de quota de API, não de capacidade: `--limit` aceita
qualquer valor, e o cache torna reexecuções baratas.

A **validação fora da amostra** é a exceção: cobre as 373 ações que a fonte
devolveu, das quais 119 chegam a ser avaliadas. Ver a [1.8](#18-o-universo-devolvido-é-parcial)
sobre por que 373 e não 781.

### 3.4. Dart sem ecossistema científico

Não há NumPy nem SciPy. Toda a estatística foi implementada à mão.

**Mitigação.** [Conferência cruzada em Python](cross_validation.py) recalcula
tudo de forma independente. A conferência **encontrou um defeito real** no
semidesvio de Sortino — divisor errado, desvio de até 32% — que foi corrigido.
As 80 comparações atuais estão dentro de 1e-4.

---

### 3.5. A validação fora da amostra não exercita a ponte por papel

`tool/backtest_valuation.dart` reconstrói o valor de mercado de cada exercício
como `contagem do exercício × preço da coorte`. É necessário: a fonte repete o
valor de mercado **de hoje** em todos os exercícios, e deixá-lo assim daria a
uma avaliação de 2018 a capitalização de 2026.

A consequência não declarada é que, com `marketCap = N·P` e
`sharesOutstanding = N`, a razão de unidade vale `N·P ÷ (N·P) = 1` sempre, e a
contagem implícita no valor de mercado fica **idêntica** à conciliada pelas
demonstrações. Conferido em 11/09/2026, e não suposto: **351 de 351 ativos**
saem com `u = 1` e sem divergência sob a reescala do backtest.

**Três peças do motor ficam, portanto, sem evidência preditiva:** a razão de
unidade da [decisão 61](../decisoes/061-a-tolerancia-da-razao-de-unidade-e-relativa.md),
a regra do maior na divergência de divisores, e a escolha entre as duas
contagens da §1.7. Nenhuma delas é exercitada por coorte alguma.

O backtest continua válido para o que mede — a ordenação do universo, em que
116 dos 127 avaliados não são afetados por essas peças. O que ele **não** é, e
não pode ser com esta reescala, é evidência sobre a ponte por papel. Consertar
isso exigiria preservar a contagem implícita no valor de mercado ao longo das
coortes, o que injetaria a base societária de hoje numa avaliação de 2018 — a
troca de um viés declarado por outro, e não uma melhora óbvia. Medição em
[unidade.md §6](unidade.md).

**O dado que faltava existe desde 14/09/2026.** A contagem de ações por data vem
do Formulário de Referência — aprovação de capital, evento de ações declarado e
formulário que a série não explica —, conferida contra a contagem oficial da B3
nas listadas e contra a composição do capital do DFP e do ITR nas deslistadas
([b3_contagem_por_data.md](b3_contagem_por_data.md)). Com ela, a coorte pode
formar o valor de mercado pela contagem **daquela data**, e a ponte por papel
deixa de colapsar para `u = 1`. **Ligá-la às coortes é o C1**, da Fase 2.

**Resolvido em 15/09/2026, e o defeito era maior que a limitação** (item C3,
[decisão 97](../decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md)).
O preço da coorte das listadas estava **na base de ações de hoje** — a fonte o
publica ajustado por todo evento posterior —, e a contagem do exercício, na base
daquele ano. Uma em cada três observações estava fora da base da data, e uma em
cinco por mais de 1,5 vez; o defeito olhava para a frente, e fazia parecer barata
a companhia que depois desdobrou. A coorte passou a montar preço, contagem e valor
de mercado na base da data, e a ponte por papel passou a ser exercitada: a razão
de unidade confere com a composição declarada em 141 de 220 observações de unit,
e a unit e a espécie da mesma companhia concordam a 1,5% na mediana, contra 80%
antes. Ver [ponte_por_papel.md](ponte_por_papel.md) e a §3.13.

### 3.6. A cascata não supera um fator de valor de uma linha

**É a limitação mais importante do trabalho, e a última a ser medida.**

O cabeçalho de `tool/backtest_valuation.dart` sempre declarou o critério: *"se
o motor não os supera, a cascata inteira está cobrando um custo de complexidade
que não entrega."* Executado em 11/09/2026 sobre 8 coortes *point-in-time* e o
motor atual:

| horizonte | n | motor | book-to-market | earnings yield |
|---|---:|---:|---:|---:|
| 12 meses | 685 | +0,0696 | **+0,1394** | +0,0571 |
| 36 meses | 470 | +0,1559 | **+0,2403** | +0,1383 |

E o teste que decide — regressão transversal com os três preditores em posto
normalizado por coorte: o coeficiente do motor tem **t = +0,24** em 12 meses e
**t = +1,16** em 36. Sozinho ele tem sinal (t = +1,85 e +3,42); **condicionado
ao book-to-market, não tem**. O IC ortogonalizado é de +0,0066 e +0,0394.

**Por quê, medido:** o potencial já é um fator de valor — Spearman de **+0,54**
com o B/M e **+0,69** com o E/P, estável nas oito coortes —, e é lento, com
autocorrelação de posto de **+0,666** entre coortes consecutivas. Não é o
provento: sob retorno ajustado a distância persiste. Não são as ressalvas:
restringir aos casos sem ressalva **piora** o motor.

**O que isto não é.** Não é prova de que o DCF esteja errado. É prova de que a
*ordenação* que ele produz não acrescenta à de um fator de uma linha, nesta
amostra e neste horizonte. Um DCF pode valer como afirmação auditável sobre
**um** ativo sem ser o melhor ordenador de uma seção transversal — mas o
projeto usa a ordenação no retorno esperado, na meta e na recomendação de
troca, e para esse uso o teste é o certo.

**Ressalvas da amostra:** janelas de 36 meses de coortes vizinhas se sobrepõem,
o `n` efetivo é menor que 470 e os erros-padrão estão subestimados nos dois
lados; há viés de sobrevivência; os fundamentos vêm como publicados hoje.
Nenhuma favorece o motor seletivamente.

Reprodução: `python tool/habilidade.py`. Plano de ataque em
[plano-motor-de-referencia.md](../plano-motor-de-referencia.md).

**Atualizado em 15/09/2026, sobre o motor de hoje.** Com a montagem do aplicativo
na data de cada coorte, o retorno total, as deslistadas da ponte e o `t` que
corrige a sobreposição das janelas (itens C1a e C1b), o coeficiente do potencial
condicionado ao book-to-market em 36 meses é de **0,070, com `t` de 1,24** — o
menor entre o comum e o de Newey-West, que com cinco coortes estreitou o erro por
autocovariância negativa. Sem as deslistadas, 0,068 e 1,04. **A conclusão não
muda.** Ver [habilidade_aplicativo.md](habilidade_aplicativo.md).

**Remedido à tarde, com o instrumento pronto, e as medições acima carregam o
defeito de base** (§3.5). Na base da data, com 31 coortes trimestrais e as
deslistadas da ponte ampliada, o potencial condicionado ao book-to-market em 36
meses tem coeficiente de **0,030**, com `t` corrigido pela sobreposição de 0,24
contra o crítico de 2,70 (decisão 96). **A conclusão continua — e o fator de uma
linha fica menor do que parecia**: nas mesmas observações, o IC do B/M em 36 meses
cai de 0,255 para 0,151 quando o preço vai à base da data. O defeito inflava os
dois sinais de valor, e o B/M mais. Não é o veredito do R3, que fica para o fim
das fases. Ver [habilidade_trimestral.md](habilidade_trimestral.md).

### 3.7. Ação em tesouraria não é tratada em lugar nenhum

**Descoberto em 11/09/2026 pela conferência do A1**, e sem lista anterior
porque a fonte atual não publica o campo.

O `composicao_capital` da CVM publica `QT_ACAO_TOTAL_CAP_INTEGR` e
`QT_ACAO_TOTAL_TESOURO`. Sobre os 286 CNPJs do universo, **178 (62%) têm ações
em tesouraria maiores que zero**.

Ação em tesouraria não tem direito a fluxo, e a contagem que divide o valor do
capital próprio deveria ser a integralizada **menos** a em tesouraria. O motor
não faz essa subtração em caminho nenhum, e não tem como fazer com a fonte de
hoje.

**Tratada em 11/09/2026, e não pela contagem absoluta.** A medição mostrou que
o `QT_ACAO_TOTAL_CAP_INTEGR` **não tem escala declarada**: sobre 2.081 pares
comparáveis, 60,9% vêm em unidades e **34,5% em milhares**, e a escala varia
por declarante. A ABEV3 aparece com 15.757.657 contra 15.761.638.000 papéis
reais. Importar o absoluto levou a MILS3 a **+14.037% de potencial**.

O que entra é a **fração** `tesouraria ÷ integralizadas`, invariante de escala
porque as duas saem do mesmo registro
([decisão 70](../decisoes/070-a-contagem-de-acoes-da-cvm-nao-tem-escala.md)).
`FundamentalsSnapshot.sharesNetOfTreasury` a prefere sobre o absoluto.

**O que sobra:** a contagem primária continua indisponível, e a base sobre a
qual a fração se aplica é a do agregador. Ver
[cvm_ligacao.md §3](cvm_ligacao.md).

### 1.10. A CVM não publica o ITR de 2025

**Registrado em 14/09/2026.** O diretório de dados abertos da CVM lista
`itr_cia_aberta_2017.zip` a `2024` e `2026`, e o endereço de 2025 devolve 404.
DFP de 2025 existe; o ITR, não.

**Efeito.** Toda série de doze meses ancorada em trimestre de 2026 tem um
buraco em 2025, e recua para a âncora de DFP (decisão 73). A primeira versão da
série não recuava, e as guardas leram dois anos como um: QUAL3 de −22% a
+908%. O baixador passou a listar anos ausentes em vez de pular em silêncio.

**Para resolver.** A CVM republicar o arquivo. Nada do lado do motor.

**Resolvido em 15/09/2026.** A CVM republicou `itr_cia_aberta_2025.zip` em
14/09/2026, às 11h06, com 30 MB. Baixado e reingerido: 42.145 documentos
montados, 31.299 deles ITR — eram 29.218 —, com ativo igual a passivo em 42.015
de 42.021. A série ancorada deixa de recuar em 2025, e as coortes trimestrais do
item C1c a usam. Só o arquivo de 2025 foi baixado de novo: os de 2022 a 2024
têm data de 13/09/2026 no diretório da CVM, e a cópia local, de 14/09/2026, já é
posterior a ela.

### 3.8. O motor é sensível à janela do exercício

**Medido em 14/09/2026.** Deslocar os exercícios seis meses — doze meses
terminados em junho em vez de dezembro —, com o mesmo preço, dá correlação de
postos de **0,683** entre as duas ordenações — contra 0,977 entre a montagem só
de mercado e a anual da CVM. A mediana do `|Δ potencial|` é de 14,8%, e 60
ativos se movem mais de 10 p.p.

A primeira medição dava 0,816, e estava contaminada: a mescla completava o
ponto de junho com fluxos do dezembro anterior, o que o ancorava parcialmente
em dezembro e amortecia a diferença (decisão 78).

Não é defeito da soma: na CSNA3 o lucro de doze meses de junho de 2023 é
prejuízo de R$ 0,10 bi, onde o exercício de 2022 tinha lucro de R$ 2,17 bi. A
janela de junho vê a virada do ciclo antes, e as guardas — trava de saúde, base
por ciclo, veredito de fosso — reagem com limiares.

**Leitura.** Uma ordenação que muda desse tanto por um deslocamento de seis
meses carrega ruído de calendário. É consistente com a §3.6 — o motor não supera
um fator de valor de uma linha —, e a coorte trimestral (C1c) é onde isso se
separa em informação e ruído.

### 3.9. Eventos de ações inferidos do preço têm teto

**Medido em 14/09/2026** sobre o COTAHIST de 2019 e 2024: os retornos diários
ajustados batem com a fonte de mercado em **99,96%** dos 118.871 pares. O que
não bate:

- **Bonificação de até 20% não é detectável pelo preço** — uma de 10% e uma
  queda de 8,5% em data ex ficam a 0,6% uma da outra. GGBR3/4, LREN3, CRPG5/6.
- **Evento com o mercado andando junto** sai da folga: AERI3 agrupou 15:1 e
  subiu 22,8% no mesmo pregão.
- **O `DISMES` não marca todo evento**: AFLT3 dobra de preço sem troca.

**Para resolver.** O registro oficial de eventos da B3, que declara o fator
(item A3.1). Ver [b3_cotahist.md](b3_cotahist.md).

**Medido contra o registro em 14/09/2026, o teto é mais baixo do que os 99,96%
sugeriam.** Aqueles eram retornos diários batendo, e evento é raro no dia. Papel
a papel, de 2010 em diante: a inferência encontra **41,5%** dos 289 eventos
oficiais, e **63,8%** do que ela encontra é evento de fato — parte do resto é
cisão, como a da XP no ITUB3 em 2021. Bonificação de até 20% sai com 1,6% de
cobertura; grupamento de papel de centavos escapa pelo tick. **Para emissor
listado, o registro substitui a inferência. Para deslistada, ela é a única
fonte, e retorno de coorte ajustado só por ela erra o evento em mais da metade
dos casos.** Ver [b3_registro.md](b3_registro.md).

### 1.11. A FCA não traz código de negociação de 2010 a 2017

**Conferido em 14/09/2026, arquivo a arquivo.** A coluna `Codigo_Negociacao` da
FCA vem vazia em todas as linhas de 2010 a 2017, e preenchida de 2018 em diante.

**Efeito.** Companhia deslistada antes de 2018 não tem ponte declarada entre o
CNPJ e o ticker. A ponte do item A3.2 usa o nome — atual e anteriores — com
sobreposição de anos, e liga 42 companhias assim, revisadas à mão. É ponte
inferida, e carrega o risco que a proibição de casamento aproximado da decisão
do A1.1 existe para evitar; o casamento aqui é de prefixo exato do nome
normalizado, e não de similaridade.

### 3.10. A migração de via é descontínua na taxa

**Medido em 14/09/2026, na PRIO3.** Com a curva do Tesouro — mais alta que os
dois pontos do CDI em quase todo ano —, o potencial **sobe** de −80,6% para
−18,3%. A perpetuidade maior leva o capital próprio a 14,4% do valor da firma, a
cascata migra para a via do acionista (decisão 43), e a outra via vale mais.

**Efeito.** A resposta do preço justo à taxa não é monótona perto do limiar de
migração. Um ativo perto dele pode mudar dezenas de pontos por uma variação
pequena de taxa, no sentido contrário ao da teoria.

**Para resolver.** Item B10 do [plano](../plano-motor-de-referencia.md): a
migração precisa de transição, e não de degrau.

### 3.11. A banda de cenários não mede incerteza

**Medido em 14/09/2026, nas coortes da montagem do aplicativo.** A banda `P5–P95`
do Monte Carlo cobriu **8,2%** do preço mais proventos realizado em 12 meses e
7,7% em 36, contra 90% nominais; a dos cenários pessimista e otimista, 12,6% e
13,2%. O realizado fica acima dela em 71% dos casos, e a largura dela é de 1,3
vez contra 43 a 47 vezes da dispersão realizada em torno do preço justo. Ver
[cobertura_banda.md](cobertura_banda.md).

**Efeito.** A banda desloca premissas e mede a sensibilidade do preço justo a
elas; lida como intervalo de probabilidade, afirmava uma precisão que o motor não
tem.

**Estado.** Resolvido na tela pela [decisão 92](../decisoes/092-a-incerteza-e-a-faixa-calibrada-e-os-cenarios-sao-sensibilidade.md):
os cenários se declaram sensibilidade, e a incerteza apresentada é a faixa
calibrada fora da amostra, que cobre a até 5 p.p. da nominal em 12 e 36 meses.
**O que continua limitação:** a faixa é larga — de 0,64 a 10,7 vezes o preço justo
na de 80% em 12 meses —, a calibração é marginal e não por ativo, e os 36 meses
têm duas coortes de teste. **A amostra deixou de ser só a dos sobreviventes em
15/09/2026** (item C2b, decisão 94): com as deslistadas da ponte, a faixa cobre a
até 5 p.p. da nominal, e o pacote passou a sair dessa amostra; as 126 companhias
com ação em bolsa e sem ponte seguem fora.

**Desfeito à tarde, na base da data** (§3.5, decisão 97). A faixa calibrada fechava
os 5 p.p. sobre coortes com o preço na base de ações de hoje. Na montagem
corrigida, trimestral e com as deslistadas, ela cobre **84,8/74,9/49,1% em 12
meses e 83,6/73,0/47,0% em 36**, fora da amostra, e seis formas de recalibrar não
fecharam os dois horizontes. O aplicativo mostra a faixa com a cobertura medida e
diz que ela não está calibrada. Ver [cobertura_banda.md](cobertura_banda.md) §8.

### 3.12. O preço converge ao preço justo um quarto do caminho em 36 meses — e menos de um décimo na base da data

**Medido em 14/09/2026.** Na regressão `log(W/P₀) = a + b·log(V/P₀)` sobre as
coortes, com `W` o preço mais proventos realizado e `V` o preço justo da data,
`b` é **0,06 em 12 meses e 0,24 em 36**. A [decisão 26](../decisoes/026-horizonte-de-convergencia-de-36-meses.md)
anualiza o potencial supondo convergência completa em 36 meses — `b = 1/3` e `1`.

**Efeito.** A premissa que dá prazo ao potencial não se sustenta nas coortes, e
a decisão 26 já a declarava forte. O aplicativo não usa a anualização na
carteira — o retorno esperado transversal ancora no custo de capital de cada
ativo, e a tela diz que o potencial é "total, sem prazo" —, mas
`ExpectedReturn.annualizedFromUpside` continua no núcleo supondo o que o mercado
não entregou.

**Para resolver.** Entra no B1 do [plano](../plano-motor-de-referencia.md): o
que o potencial é para servir decide se ele precisa de prazo, e qual.

**Remedido em 15/09/2026, na base da data** (§3.5): `b` de **0,019 em 12 meses e
0,077 em 36**, nas coortes trimestrais com as deslistadas. O um quarto era, em
parte, o defeito de base, que dava ao preço justo e ao realizado o mesmo erro. Ver
[cobertura_banda.md](cobertura_banda.md) §8.

### 3.13. A razão de unidade inferida do valor de mercado erra com ágio entre espécies

**Medido em 15/09/2026, nas coortes na base da data.** `quotedUnitRatio` mede
`contagem × preço da unit ÷ valor de mercado`, e o resultado só é o número de
ações da unit quando ordinária e preferencial valem o mesmo. Contra a composição
que a FCA declara, ele acerta **141 de 220** observações de unit: a SANB11 em 31 de
31, a SAPR11 e a TAEE11 em 30, a ENGI11 em 4, a IGTI11 e a BRBI11 em nenhuma. Em 49
a razão cai em 1 — a ON da ALUP11 de 2019 negociava 35% acima da PN, e a razão foi
de 2,69 —, em 12 cai no inteiro errado dentro da folga, e em 18 a companhia não
tem espécie negociando.

**Efeito.** Unit com a razão errada é avaliada por ação, e o potencial sai de três
a cinco vezes errado — ou 25% errado, no inteiro vizinho, sem aviso. No aplicativo,
as nove units passaram em 04/09/2026 (decisão 61), mas a convenção do valor de
mercado da fonte não é conhecida, e é ela que decide se o erro aparece.

**Para resolver.** Item B16 do [plano](../plano-motor-de-referencia.md): a
composição declarada entra no pacote do aplicativo, e a razão medida vira
conferência.

## 4. O que foi verificado, e como

| Evidência | Método | Resultado |
|---|---|---|
| Corretude do motor | invariantes matemáticas sem fonte externa | [aprovadas](invariantes.md) |
| Estatística | Recálculo independente em `pandas`/`numpy` | [80/80 dentro de 1e-4](conferencia_python.md) |
| Robustez às premissas | Varredura em três eixos | [medida](sensibilidade.md) |
| **Habilidade preditiva** | IC incremental contra fatores ingênuos, 8 coortes | **reprovada** — [§3.6](#36-a-cascata-não-supera-um-fator-de-valor-de-uma-linha) |
| **Incerteza calibrada** | cobertura da banda fora da amostra | **não medida** |
| Cobertura de testes | **685** testes automatizados — 419 no núcleo, 266 na aplicação (11/09/2026) | — |

> O oráculo `adjustedClose` previsto no plano original **não pôde ser usado**:
> a própria auditoria mostrou que aquela série é inconsistente com o fluxo de
> proventos publicado. As invariantes matemáticas o substituíram, e são
> evidência mais forte — não dependem de nenhuma fonte externa de verdade.
