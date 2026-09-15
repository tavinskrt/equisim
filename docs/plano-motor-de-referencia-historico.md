# Histórico das rodadas do plano do motor de referência

O que cada rodada de execução do [plano](plano-motor-de-referencia.md)
encontrou, o que as lentes do conselheiro disseram e o que a auditoria do gate
reprovou — do mais recente ao mais antigo.

Saiu do plano em 14/09/2026 para que ele ficasse com o que é acionável: itens,
estado, critério de pronto e critério de parada. **Nada foi resumido nem
cortado**; o texto é o mesmo, com os títulos promovidos um nível. Decisões
continuam em [decisoes/](decisoes/), e medições em [validacao/](validacao/).

---

## O que a primeira rodada da Fase 2 encontrou — D1, C2 e C0 (14 e 15/09/2026)

**O gabarito do D1 não enxergava o miolo do método.** As duas montagens que ele
gravava não passavam o prior do beta, e sem ele não há taxa resolvida: o ponto
fixo, os passes do veredito, a rota derivada e a recursão da estrutura recusada
ficavam fora da prova de que a refatoração não mudou nenhum número. O gabarito
passou a nove montagens, com o prior, as imposições de diagnóstico, o Monte Carlo
e a impressão do rastro de auditoria.

**A entrada do gabarito também derivava.** A primeira gravação levou dez minutos
para cinquenta ativos, porque o Ibovespa vinha da rede a cada montagem — e a
mesma deriva que contaminou 26 ativos em meia hora na Fase 1 valia aqui. A
gravação passou a copiar o cache e o Ibovespa servido, e a conferência os repete
sem rede, em três minutos. O controle sobre o código intacto deu idêntico, e uma
mutação que só troca a ordem de dois passos do rastro divergiu em 1.212
montagens.

**Os seis passos deram idênticos**, conferidos em ordem sobre cópias guardadas de
cada um — os commits são do usuário. A ordem mudou em relação à recomendada: com
os *records* dos estágios de cima prontos, a ponta de baixo deixou de precisar de
duas dezenas de variáveis soltas, e ela saiu por último.

**Quebrar o método expôs um defeito latente**, registrado no B11: com as taxas
resolvidas, o preço justo sai das premissas finais e os cenários, a taxa exibida e
o rastro saem das interpoladas. No aplicativo de hoje coincidem, porque ele não
resolve o prior. **E um caminho sem prova**: nenhum ativo das nove montagens passa
pelo veredito que não se estabiliza, e nenhum teste o constrói — foi para o D3.

**As coortes passaram a ser as do aplicativo.** O C2 e o C0 pediam medir o motor
de agora, e `tool/backtest_valuation.dart` só sabia montar o de 11/09. A montagem
por data leu o Formulário de Referência pelo recebimento de cada documento, e o
prazo lido em 14/09/2026 reproduziu o pacote do aplicativo em 35 de 35 tickers.

**A banda de cenários cobria 8%, contra 90% nominais.** Não é detalhe de
calibragem: o realizado ficou acima dela em 71% dos casos, a 2,1 vezes a mediana,
e a largura dela é de 1,3 vez contra 43 a 47 da dispersão realizada. Duas recalibragens
estreitas — em torno do preço e da convergência parcial — calibraram em 12 meses
e não em 36; a que calibra nos dois é a faixa em torno do preço justo, larga como
o erro dele. **E a regressão que mediu a convergência desmentiu a decisão 26**: o
preço anda um quarto do caminho até o preço justo em 36 meses.

**O C0 achou sinal onde se esperava cauda, e o testou antes de acreditar.**
Soltando o corte de liquidez, o potencial ordena além do B/M nas ilíquidas, e não
nas avaliadas. Começar o retorno um mês depois não o desfez, então não é reversão
de fechamento; o nível do potencial confirma o beta enviesado, e o retorno delas
tem a forma do viés de sobrevivência. A recusa ficou, e a remedição com as
deslistadas virou o C0b. A faixa calibrada tem o mesmo problema na cauda de baixo,
e virou o C2b.

**O que as lentes disseram.** Das seis, uma trouxe defeito que procede: a
`dados` apontou que o cache macroeconômico vencido, no recurso sem rede, não
exigia cobrir o início da janela — três meses guardados passariam por dez anos no
CAGR decenal. Conferido, corrigido, e o teste novo falha sem a correção. A `rumo`
trouxe de volta a não monotonia de 46 de 122 no nível da curva, medida no DCF
reverso e esquecida pelo plano: entrou no critério do B10. **Não procederam**: o
deadlock de repetição da `dados`, pela terceira vez; e, da `rumo` e da
`registro`, três achados lidos de texto antigo — os bancos sem setor, que o A5
resolveu; o módulo na alíquota efetiva, que o código já nega em vez de tirar; e a
nota de superação em `crescimento_log_linear.md`, que já existe. A `metodo` e a
`risco` não acharam tensão, com o material cortado por tamanho. Os achados da
`nucleo` — o exercício com valor de mercado de hoje, um tipo de data de
calendário, os rótulos dos enums — ficam fora dos dois objetivos.

**O auditor aprovou, com um INFO que levou a um defeito anterior.** Ele apontou
as duas colunas da faixa calibrada sem adaptação a tela estreita. O teste escrito
para isso montou a tela de avaliação **carregada** em 320 dp, pela primeira vez, e
quem estourou foi o gráfico de sensibilidade, que já existia: 134 px à direita.
A tela só entrava no teste de estouro vazia — a pendência do D3. As duas coisas
foram corrigidas.

---

## O que a rodada de A3.4 a A6 encontrou (14/09/2026)

**A fonte de proventos que o plano dava como existente não servia.** O registro do
A3.1 só traz doze meses; o histórico estava em outra consulta da B3, que responde
também para companhia deslistada, pelo nome de pregão.

**O orientador reabriu a decisão 23**, e a opção escolhida levou provento ao beta
além das coortes. Com o retorno total, a habilidade do motor de 11/09 não muda:
o IC sozinho sobe, o condicionado ao P/B e ao L/P continua sem significância.

**A classificação da B3 achou 51 tickers sem a porta certa**, e não três. E ao
conferir por que os três bancos não se moviam, apareceu uma divergência maior:
**o aplicativo nunca resolveu o prior do beta** — as decisões 40 e 41 descrevem um
motor que só roda nas ferramentas de diagnóstico. Virou o B11.

**O A6 estava errado na primeira versão.** A decisão afirmava que o terminal
neutro já era o valor do contrato finito, com um teste que definia o capital como
`lucro/r` — tautologia. A lente `metodo` apontou que `lucro_{N+1}/r` perpetua o
excedente do capital existente; a álgebra confirmou, e o terminal da concessão
passou a cortar esse excedente no fim do contrato. O mesmo excedente, fora das
concessões, virou o B12.

**A contagem por data errou antes de acertar.** Ler a declaração mais recente de
cada aprovação de capital levava a contagem de depois de um grupamento para antes
dele, e o P/VPA de 0,01 da CPFL Transmissão denunciou. A série passou a ter três
camadas.

**A data ex caía em 31/12**, que é dia útil bancário sem pregão. O calendário de
pregão passou a valer para proventos e para os eventos do registro da B3.

**A lente `rumo` achou um defeito que a revisão anterior perdeu:** a decisão 39
declara a discordância das duas vias defeito conhecido enquanto não for fechada,
e as decisões 42 e 43 registram que ela continua na via do acionista. Virou o
B13. A outra tensão dela — o perfil vazio de BRAP4, FESA4 e UNIP6 — o A5 resolveu.

**O que as lentes disseram e não procedeu:** o deadlock de repetição da lente
`dados` — o limitador libera a vaga antes de o repetidor reemitir — e o cache de
preços que recusaria janela anterior, da `risco` — a busca é sempre do histórico
inteiro. Os achados da `nucleo` ficam fora dos dois objetivos.

---

## A2.2: a função esbarrou no plano do Firebase (14/09/2026)

`firebase deploy --only functions` parou em *"must be on the Blaze
(pay-as-you-go) plan"*. O projeto está no plano sem cobrança, e a mesma saída
mostrou as APIs de função sendo ligadas pela primeira vez: nenhuma função do
repositório tinha sido publicada, nem o proxy da `brapi`.

Postos ao usuário três caminhos — ativar o Blaze, publicar o JSON como arquivo
estático por uma GitHub Action diária, ou deixar a web só com o pacote —, ele
escolheu o terceiro. A função `tesouro` e o `TESOURO_PROXY_URL` saíram; na web o
repositório nem chama o Tesouro, e sem curva a avaliação diz por quê
([decisão 86](decisoes/086-na-web-a-curva-vem-so-do-pacote.md)).

---

## O que a rodada de A1.10 a A3 encontrou

> Registro completo em [b3_registro.md](validacao/b3_registro.md),
> [b3_deslistadas.md](validacao/b3_deslistadas.md) e
> [fase1_padrao.md](validacao/fase1_padrao.md).

**Três decisões eram suas, e foram tomadas no início da rodada:** a curva é o
padrão do aplicativo, o pacote da CVM é versionado, e a web busca a curva por
função de nuvem.

**O divisor por papel estava errado em dez ativos grandes, e no sentido
contrário ao que o registro supunha.** A contagem oficial da B3 mostrou que a
"contagem do exercício" da fonte é, nesses dez, o capital autorizado — número
redondo, até 2,28x as ações emitidas. A regra do maior o adotava, e o árbitro
`lucro ÷ LPA` o confirmava porque a fonte calcula o LPA com a mesma contagem.
GGBR4, CSAN3, B3SA3, RENT3, COGN3 estavam todos com o preço justo deprimido.
**E MILS3 e MEAL3, os casos-símbolo da §1.7 das limitações, não eram
grupamento**: a B3 não registra evento nenhum, e a contagem "corrente" da fonte
simplesmente está errada.

**A ponte do A1.1 tinha duas ligações erradas**, nas fusões de 2025: MBRF3 na
BRF em vez da Marfrig, AUAU3 na Petz em vez da União Pet. Apareceu quando o
A1.11 passou a ler o PL da CVM: a MBRF3 foi de −27% a −82% por uma diferença de
5% na base, e a razão era a CVM de uma empresa sobre o mercado de outra. O
registro da B3 dá código CVM por emissor, e a ponte agora começa por ele.

**A validação da decisão 75 media a coisa errada.** Os 99,96% de retornos
diários batendo não diziam quantos eventos a inferência acha, porque evento é
raro no dia. Contra o registro: **41,5%**, e só 63,8% do que ela acha é evento
de fato — parte do resto é cisão (ITUB3 em 2021).

**A1.11 achou menos do que o item supunha.** A base de patrimônio de mercado já
era o PL consolidado da CVM em 99,4% dos exercícios; a CVM muda cinco ativos no
anual, e o ponto de junho da série ancorada.

**A FCA não tem código de negociação de 2010 a 2017**, em nenhuma linha. A
ponte das deslistadas desse período teve de ser por nome, com o nome anterior
que a FCA guarda — revisada à mão, 42 ligações.

**A Fase 1 inteira move a ordenação o bastante para que a §0 precise ser
refeita.** Na mesma execução, da montagem de antes ao padrão do aplicativo:
potencial mediano de −37,5% a −48,2%, correlação de postos de **0,884**, 76
ativos movendo mais de 10 p.p. Nada disso é habilidade: é o motor sobre o qual
o C1 tem de rodar.

**E uma descontinuidade do método.** Na PRIO3, a curva — mais alta que os dois
pontos em quase todo ano — **sobe** o potencial de −80,6% para −18,3%: a
perpetuidade maior leva o capital próprio a 14,4% do valor da firma, e a
cascata migra para a via do acionista, que vale mais. Taxa maior não deveria dar
preço justo maior. Virou o **B10**.

## O que as lentes disseram na rodada de A1.10 a A3

Cinco lentes, sobre o staging da rodada. **Um estrutural da `metodo` aceito e
corrigido**, um da `dados` e dois da `risco` aceitos e corrigidos, um da
`registro` aceito na forma do precedente e outro recusado por verificação.

| lente | achados | o que foi feito |
|---|---|---|
| `metodo` | 1 estrutural, 1 local | estrutural **corrigido** — o WACC estático readquiria o `marketCap` da fonte depois de a ponte arbitrar a contagem (decisão 83); local vira o **B9** |
| `dados` | 1 local | **corrigido** — snapshot corrente vazio deixava o valor de mercado da linha anual no lugar |
| `risco` | 3 locais | **2 corrigidos** com teste — falha do mercado no repositório da CVM, cache vencido de fundamentos —, 1 de tela vai para o **D3** |
| `nucleo` | 2 estruturais, 2 locais | inventariado — construtor de `Portfolio`, listas paralelas no diagnóstico, nomes; código anterior à rodada |
| `registro` | 2 estruturais | **1 aceito** pela decisão 85, no caminho da 26; **1 recusado** — `refinamento-do-valuation.md` existe, com 120 KB |

**Aceito e corrigido — o peso do capital próprio no WACC.** `_wacc` usava
`latest.marketCap` sempre que existia. Com a fonte errando a contagem, o valor
de mercado erra junto, e o WACC readquiria o erro que a ponte acabava de
arbitrar. O teste reproduz 1,07 p.p. de WACC com valor de mercado 2,6x errado.

**Aceito — a substituição que a decisão 23 não pôde declarar.** A 23 derrubou as
decisões 12, 16, 17 e 18 no corpo, sem o campo `substitui`, porque o gate não o
aceitava na época. A decisão 26 tirou o impedimento e fez o mesmo pela 14. A
[decisão 85](decisoes/085-a-substituicao-das-decisoes-12-16-17-e-18-pela-23-e-declarada.md)
faz pela 23, sem editá-la.

**Recusado por verificação.** A `registro` disse que a decisão 25 cita um
documento que não existe. `docs/refinamento-do-valuation.md` existe, tem 120 KB e
a tabela P1 a P13. A lente não o recebeu no material.

## O que a auditoria do gate disse na rodada de A1.10 a A3

**O staging das duas rodadas passou do teto do auditor.** Com 60 arquivos, o
material bateu nos 180 mil caracteres, foi truncado, e o `agy` respondeu vazio
duas vezes — código 2, falha de infraestrutura. Sem poder fazer commit, a
auditoria foi feita em grupos pelo índice: núcleo com seus testes, e aplicativo
com ferramentas, função e scripts.

- **Núcleo: aprovado, 0 FAIL / 0 WARN / 0 INFO.**
- **Aplicativo, ferramentas e função: reprovado na primeira passada com 3 FAIL**,
  todos nas ferramentas de medição — empate de postos comparado com `==`,
  variância comparada com `== 0`, correlação sem guarda de denominador. Corrigidos,
  **aprovado com 2 WARN e 1 INFO**: diferença de dias em hora local, sujeita ao
  horário de verão, no COTAHIST e na conferência de eventos. Eram código desta
  sessão, e foram corrigidos também — no detector do núcleo inclusive.

**E o gate local tinha um defeito de leitura.** O leitor da tabela congelada do
`PLANO_ARQUITETURA.md` só reconhecia linha que começa em `|` com número sem
negrito. As decisões 0 a 8 estão dentro de uma citação (`> |`) e a 0 e a 18 em
negrito: dez das dezenove ficavam de fora, e a decisão 85 foi bloqueada por citar
a 18. A expressão passou a aceitar os dois formatos, e lê exatamente 0 a 18.

## O que a rodada de A1.8 a A3 encontrou

> Registro completo em [cvm_trimestral.md](validacao/cvm_trimestral.md),
> [curva_de_juros.md](validacao/curva_de_juros.md) e
> [b3_cotahist.md](validacao/b3_cotahist.md).

**Um defeito da rodada anterior, achado ao construir a de agora.** O ITR traz,
no segundo e no terceiro trimestres, **duas linhas por conta** na DRE — o
trimestre e o acumulado do ano — com o mesmo `ORDEM_EXERC`. A ingestão ficava
com a primeira que aparecesse. **19.237 dos 29.218 ITRs** tinham a duplicação.
No A1.7 ela só entrava pelo defeito seguinte; a série de doze meses teria
somado trimestre com acumulado em todo o universo
([decisão 72](decisoes/072-a-ingestao-le-o-periodo-e-o-tipo-do-documento.md)).

**Uma atribuição da rodada anterior, corrigida.** O A1.7 classificava como
anual o exercício que termina em dezembro. Companhia de exercício fora do
calendário — AGRO3 em junho, SMTO3, JALL3 e RAIZ4 em março, CAML3 em
fevereiro — tinha o ITR de dezembro lido como ano cheio. **O SMTO3 (−45,2 p.p.)
e o AGRO3 (−5,6 p.p.) da tabela do A1.7 eram artefato disso**, e não efeito da
CVM; refeita a medição, o SMTO3 move −0,9 p.p. A ingestão passou a ler o tipo do documento, e não o mês.

**O lucro por ação da CVM sai da mescla.** A conta 3.99 vem **zerada em 14.684
dos 15.206** exercícios que a trazem, e zero sobrescrevia o LPA da fonte de
mercado — que é o árbitro da contagem de ações da §1.7. Passou a ser campo só
de mercado.

**A fonte tem buraco.** A CVM não publica o ITR de 2025 (404). A primeira
versão da série ancorada leu 2024 → 2026 como um ano, e a QUAL3 foi de −22% a
**+908%**. A série agora recua para DFP quando há buraco, e o baixador lista o
que falta. Hoje, **toda série recua** — o que é o comportamento certo, e quer
dizer que o A1.8 não tem efeito até a CVM publicar o arquivo. Ver limitações
§1.10.

**O motor é sensível à janela do exercício** — correlação de postos de
**0,683** entre a ordenação anual e a ancorada no trimestre, depois da
decisão 78 (0,816 na medição com o defeito da mescla). Não é defeito da soma,
conferido no caso extremo (CSNA3); é consistente com a §0. Ver limitações §3.8,
e é por isso que a série ancorada não é padrão.

**A conferência do COTAHIST mediu a coisa errada primeiro.** Comparado nível
contra nível, o ajuste batia em 68%, com papéis discordando em todos os pregões
e sem evento algum — a fonte de mercado ajusta até **hoje**, e com anos
parciais um evento fora da janela vira deslocamento constante. Por retorno
diário, que é invariante a isso, bate em **99,96%**.

**Três itens novos no A3, e um no A2.** A inferência pelo preço tem teto
medido (limitações §3.9) — é o **A3.1**. As deslistadas têm demonstrativo e
preço, mas não a ponte entre ISIN e CNPJ — é o **A3.2**, e é o que o C1b
espera. O fator detectado não entra no divisor — é o **A3.3**. E a curva existe
só na ferramenta de validação — é o **A2.1**, junto com a decisão do padrão.

## O que as lentes disseram na rodada de A1.8 a A3

Cinco lentes, sobre o código em staging. **Dois estruturais da `dados`
conferidos e corrigidos**, um local da `metodo` aceito como limite declarado, e
**dois defeitos achados por revisão própria** enquanto elas rodavam — um deles
no código desta rodada.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 2 estruturais | **os dois corrigidos** ([decisão 77](decisoes/077-o-snapshot-corrente-e-o-ativo-omitido-seguem-a-regra-da-falha.md)); o cache negativo, metade do segundo, fica de fora com razão |
| `metodo` | 1 estrutural, 3 locais | estrutural **já decidido** (62); `CorporateEvents` **aceito** como limite de uso; escudo fiscal **recusado** (37); RONIC = ROIC inventariado no eixo B |
| `nucleo` | 3 estruturais | inventariado — código anterior à rodada, e o `label` dos enums já foi recusado duas vezes |
| `risco` | 4 locais | cobertura de caminho de erro em código anterior — **D3** |
| `registro` | 0 tensões | **o inventário parou de novo na decisão 30** — conferência feita à mão, ver abaixo |

**Aceito e corrigido — o snapshot corrente.** A `dados` apontou que a regra da
decisão 68 parou nos quatro demonstrativos: a busca do snapshot corrente falhava
em silêncio. A conferência achou efeito pior que o descrito — sem o corrente,
cada linha anual fica com o **próprio** `marketCap`, que é o inflado pelo fator
da unit (SAPR11 com R$ 59,9 bi contra R$ 10,1 bi), e isso ia para o cache. E
esses são exatamente os campos que a CVM delega ao mercado no aplicativo.

**Aceito e corrigido — o ativo omitido.** A lente descreveu custo de cota; o
teste reproduziu **perda de dado**: um lote que responde e deixa um ativo de
fora fazia o ativo sumir, com o histórico dele em disco.

**Aceito como limite — `CorporateEvents`.** A lente diz que bonificação pequena
vira prejuízo falso na carteira. Hoje nada no aplicativo lê a série ajustada, e
o prejuízo não acontece; mas aconteceria no dia em que alguém a ligasse a
retorno. A documentação do serviço passou a dizer que ela **não é série de
retorno** até o A3.1.

**Recusado — o escudo fiscal.** A lente quer o escudo do WACC na alíquota
estrutural. A [decisão 37](decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md)
tratou disso: a dedutibilidade do juro vale na margem, e a margem é a alíquota
cheia.

**Já decidido — retorno total contra simulação de preço.** A
[decisão 62](decisoes/062-o-esperado-e-retorno-total-e-nao-pede-yield.md)
declarou o esperado como retorno total e removeu o *yield* que o duplicava. O
*backtest* histórico de preço é outra régua, e a reabertura dos proventos é o A4.

**O alcance da `registro`, de novo.** Recebeu 66 blocos, incluídas as decisões
72 a 76, e inventariou até a 30. **Duas rodadas seguidas**: o "sem tensões"
dela nunca cobre as decisões deste ciclo. Conferido à mão: todo identificador
citado nas decisões 72 a 76 existe no código, e as constantes citadas batem
(`minDesvio` 0,19, `maxDiasEntrePregoes` 7, `diasDeRecuo` 7). O conserto da
lente é trabalho à parte, nos arquivos de regra dela.

**Achado por revisão própria — a mescla misturava janelas.** A série ancorada
completava um ponto de doze meses até junho com o exercício de mercado de
dezembro: a despesa de juros de outra janela ia para o custo da dívida, o NOPAT
publicado de outra janela vencia o derivado do EBIT, e o LPA de outro lucro
entrava no árbitro da contagem. **A medição do A1.8 foi feita com esse
defeito** — ver [decisão 78](decisoes/078-a-mescla-nao-empresta-fluxo-de-outra-janela.md)
e a remedição.

**Achado ao investigar a remedição — documento do futuro apagava o ano.** A
USIM3 foi de "ancorada = anual" para "ancorada = só mercado" com a correção, o
que ela não explicava. A DFP de 2023 foi reapresentada, e a versão ingerida tem
recebimento em 16/01/2025; em 04/09/2024 o caminho anual a mesclava mesmo
assim, descartava o exercício de mercado de 2023 — publicado de fato — e a
cascata removia o ponto mesclado por ser do futuro. **O ano sumia.** USIM3
(−47 p.p.) e USIM5 (−42 p.p.) da lista de movimentos do A1.7 em 2024 eram isso.
Corrigido na decisão 78; a correção certa do dado é o B8.

**Achado por revisão própria — o pacote era decodificado por chamada.** O
repositório da CVM guardava o resultado, e não a leitura em curso: avaliações
simultâneas decodificavam os 9 MB cada uma. Corrigido na decisão 77.

**Achado ao corrigir o anterior — a cascata não lê o patrimônio da CVM.** A
primeira versão da regra da mescla também recusava emprestar o VPA e a contagem
do exercício, e **106 de 113 avaliados** da série ancorada foram recusados como
insolventes, com R$ 20 bi de PL na própria linha. A base de patrimônio da
cascata é `VPA × contagem do exercício`, sempre; o `totalStockholderEquity` que
a CVM traz não é lido. Virou o **A1.11**.

## O que a auditoria do gate disse

**Reprovado na primeira passada, com 4 FAIL**, todos conferidos e corrigidos
([decisão 79](decisoes/079-o-prazo-da-curva-conta-dias-uteis.md)):

- **Prazo da curva em dias corridos para taxa na base 252** (R9). Estava
  declarado como aproximação de "fração de ponto base", sem medição. Medido
  contra o PU do próprio Tesouro, a convenção certa é **dias úteis da
  liquidação, pelo calendário conhecido na data-base** — o 20 de novembro só
  entra para quem já conhecia a lei de 2023 —, e bate ao dia em 99,13% de 19.171
  LTN. O efeito na taxa é de até 4,7 bp; a declaração subestimava o erro, e o
  motor ganhou um calendário de dias úteis que não tinha.
- **`double` como chave de mapa, elemento de conjunto e operando de `==`**
  (R6), na curva, nos fatores de evento e no codec do pacote. Nenhum produzia
  número errado hoje.

**O gabarito do D1 gravado nesta rodada fica velho** na montagem da curva, que
mudou em até 4,7 bp. Não altera a análise de viabilidade: o procedimento já
manda gravar de novo imediatamente antes de começar.

## O que as lentes disseram na rodada do A1.7

Cinco lentes. **Um estrutural aceito e corrigido**, um recusado por
conferência, o resto inventariado para a Fase 3.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 1 estrutural, 1 local | **corrigido** ([decisão 71](decisoes/071-a-validade-do-cache-macro-nao-cobre-a-janela.md)) |
| `nucleo` | 2 estruturais, 1 local | inventariado — são B/D, e um deles já foi recusado antes |
| `metodo` | 1 estrutural, 1 local | é o **B1** |
| `risco` | 1 estrutural, 1 local | cobertura — **D3** |
| `registro` | 0 tensões | **mas leu só as decisões 0 a 30** — ver abaixo |

**A ressalva do `registro`.** Ele voltou com "nenhuma tensão", e o relatório
declara ter examinado *"as decisões 0 a 30"*. **São 71 hoje.** O aval dele
cobre o terço mais antigo do registro, e não as decisões 31 a 71 — que são
justamente as deste ciclo. Não é achado nem contra-indicação; é um limite de
alcance que o quadro esconderia se ficasse só em "sem tensões".

**Aceito.** A validade do cache macro é por **série** e o recorte é por
**janela**, e as duas não conversavam: um gráfico de três meses de CDI marcava
a série como fresca, e a simulação de dez anos recebia os três meses **achando
que recebeu dez anos**. O CAGR decenal, a taxa de equilíbrio da estrutura a
termo e o Sharpe sairiam apurados sobre um trimestre, sem aviso. O caminho
normal passa a exigir cobertura do início; o degradado continua aceitando o que
houver.

**Recusado.** A `nucleo` voltou a pedir a remoção do `label` dos enums do
domínio. Os avisos da cascata são narrativa econômica em português **por
construção** — é o que a tela mostra e o que a auditoria registra —, e a
proposta trataria isso como vazamento de apresentação. Já inventariado.

## O que as lentes disseram na rodada anterior

Cinco lentes rodadas. **Um achado estrutural aceito, um recusado por
conferência**, o resto inventariado.

| lente | achados | o que foi feito |
|---|---|---|
| `dados` | 2 estruturais, 1 local | **1 corrigido** ([decisão 68](decisoes/068-falha-de-um-demonstrativo-reprova-a-busca.md)), 1 **recusado** |
| `risco` | 1 estrutural, 2 locais | reforça o mesmo defeito; teste acrescentado |
| `nucleo` | 0 estruturais, 2 locais, 1 polimento | inventariado — Fase 3 |
| `metodo` | 2 estruturais | é o B1, e depende de medição — Fase 3 |
| `registro` | — | sem tensões |

**Aceito.** `fundamentalsHistory` devolvia `Ok` quando **algum** dos quatro
endpoints respondia. Falha na DRE produzia série com balanço preenchido e
resultado ausente — a forma que a decisão 52 trata como "ausência não é zero"
—, e o repositório **grava isso no cache**, de modo que a corrupção sobrevivia
à falha de rede. Pior: o filtro downstream a transformava em "histórico
curto", e um 503 aparecia como ativo inelegível.

**Recusado por conferência.** A mesma lente pediu inverter a ordem dos
interceptors, para que a espera da repetição ficasse fora do slot do
limitador. `ThrottleInterceptor` libera o slot no `onError` e está registrado
**antes** do `RetryInterceptor`: a liberação já acontece primeiro, e a
inversão proposta **criaria** o defeito descrito.

**Adiado com razão.** A `metodo` quer reintroduzir `impliedIrr` e reverter o
estimador transversal da decisão 58. Isso é o **B1** — a pergunta de o que o
potencial serve —, e a §0 mostrou que ela é real. Mas reverter para o IRR
implícito não é obviamente a resposta, e a régua desta rodada é medir antes.

## Itens que entraram durante a execução

**A1.7 — ligar a ingestão ao motor.** A ingestão produz
`data/cvm_exercicios.json` e o motor continua lendo a brapi. Ligar as duas
exige o D2 (procedência por campo), e é o que transforma todo o trabalho
acima em mudança de resultado. **É o próximo item de maior alavancagem.**

**A3 mudou de posição.** Os 3.537 exercícios de companhias deslistadas não têm
ticker nem série de preço, e sem preço não há retorno a confrontar. O A3
deixou de ser item de higiene e virou **pré-requisito** de C1b — a amostra sem
viés de sobrevivência só existe com preço histórico das deslistadas.

**D1 não foi feito, e a razão é honesta.** O plano dizia "D1 antes de A1.3,
porque a ingestão vai acrescentar caminhos a `_evaluateLane`". Executando, o
acoplamento revelou-se mais fraco do que eu supus: a ingestão acrescenta
**campos** a `FundamentalsSnapshot`, e não caminhos à cascata. `_evaluateLane`
segue com 1.087 linhas e segue sendo o maior risco estrutural — mas misturar
a refatoração dele com a ingestão teria piorado as duas. Fica na Fase 1, antes
do A1.7, que é quando os caminhos de fato mudam.

---

## Retrato da §6 e da §7 antes da revisão de 14/09/2026

Na revisão que acrescentou as colunas *serve a* e *pronto se*, as tabelas de
itens e o critério de parada foram reescritos contra o código. Esta é a versão
de antes, sem alteração, para quem precisar reconstruir o que mudou.

### Fase 1 — o eixo A, até estar estável

> **A1.1 a A1.6 concluídos em 11/09/2026.** Registro em
> [cvm_ingestao.md](validacao/cvm_ingestao.md). **A1.7 a A3 executados em
> 14/09/2026 de manhã**, com a análise de viabilidade do D1. **A1.10 a A3
> executados à tarde**: o eixo A está estável até A3. Entraram A2.2, A3.4, B9 e
> B10.

| # | item | estado |
|---|---|---|
| A1.0 | Conferência de campos | ✅ [cvm_conferencia.md](validacao/cvm_conferencia.md) |
| A1.1 | Ponte ticker↔CNPJ | ✅ **371/375 = 98,9%**, zero ambíguo, zero conflito de raiz |
| A1.2 | Leitor do plano de contas | ✅ `CvmChart`, 19 testes; **0 faltas em 5.838 exercícios** |
| A1.3 | Ingestão DFP + ITR, `con` com recuo | ✅ 2.107 recuos, **0 sem DRE** |
| A1.4 | *Point-in-time* por `DT_RECEB` | ✅ `PointInTimeView` prefere a data observada |
| A1.5 | Contagem líquida de tesouraria | ✅ **ligada ao divisor** pela contagem oficial da B3, pela fração — [decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md) |
| A1.6 | Todos os anos, com deslistadas | ✅ baixador; **60,6% dos exercícios fora do universo vivo** |
| A1.7 | Ligar a ingestão ao motor | ✅ **mescla com procedência**; refeito nesta rodada sem os artefatos de exercício fora do calendário: 127 → 128 avaliados, mediana do Δ em 0,0% |
| A1.8 | Série trimestral no motor | ✅ **capacidade** — doze meses ancorados no trimestre, 16 testes; **não é o padrão** (postos **0,683** contra a anual, remedido pela [decisão 78](decisoes/078-a-mescla-nao-empresta-fluxo-de-outra-janela.md)) — [decisão 73](decisoes/073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md) |
| A1.9 | Levar a ligação ao aplicativo | ✅ pacote de 371 tickers (8,9 MB; 1,5 MB comprimido) e repositório decorador — [decisão 76](decisoes/076-a-cvm-chega-ao-aplicativo-por-pacote.md) |
| A1.10 | O pacote no processo de build | ✅ **pacote versionado**, por decisão sua; teste que reprova a suíte sem ele; a ausência vira ressalva na avaliação — [decisão 80](decisoes/080-o-pacote-da-cvm-e-versionado-e-a-ausencia-aparece.md) |
| A1.11 | A cascata lê o patrimônio da CVM | ✅ VPA derivado do PL da CVM; a base de mercado **já era** o PL consolidado em 99,4%, e o que muda é o ponto de junho (postos anual × ancorada 0,683 → 0,737) e cinco ativos — [decisão 81](decisoes/081-a-base-de-patrimonio-e-o-pl-da-cvm.md). Revelou a ponte errada da MBRF3 — [decisão 82](decisoes/082-a-ponte-comeca-pelo-registro-oficial-da-b3.md) |
| A2 | Curva de juros observada | ✅ **capacidade** — Tesouro prefixado, *flat-forward*, 13 testes; **o padrão é decisão sua** — [decisão 74](decisoes/074-a-taxa-livre-de-risco-segue-a-curva-observada.md) |
| A2.1 | Curva no aplicativo, e a decisão do padrão | ✅ **a curva é o padrão**, por decisão sua; nativo lê só o começo do arquivo do Tesouro, web pela função `tesouro`, recuo para o pacote e depois para os dois pontos, declarado — [decisão 84](decisoes/084-a-curva-e-o-padrao-do-aplicativo.md) |
| **A2.2** | **Publicar a função `tesouro`** | ⬜ **novo, ação sua** — `firebase deploy --only functions` e o `TESOURO_PROXY_URL` no build web. Até lá, a web usa a curva do pacote, que vale uma semana |
| A3 | Eventos de ações e contagem de papéis | ✅ inferência pelo preço ([decisão 75](decisoes/075-eventos-de-acoes-inferidos-do-cotahist.md)) e registro oficial — com o teto da inferência **medido contra o registro**: 41,5% dos eventos oficiais encontrados, 63,8% dos inferidos confirmados |
| A3.1 | Registro oficial de eventos da B3 | ✅ 297 de 297 emissores; convenção do fator medida, eventos da mesma data compostos, **93,4% de 243 batem com o preço a 15%** — [b3_registro.md](validacao/b3_registro.md) |
| A3.2 | COTAHIST inteiro e ponte das deslistadas | ✅ 2010 a 2026, 1,63 milhão de pregões; **164 de 290** companhias deslistadas com ação em bolsa ligadas ao preço, 1.272 exercícios — [b3_deslistadas.md](validacao/b3_deslistadas.md) |
| A3.3 | Eventos no divisor por papel | ✅ **a contagem oficial arbitra o divisor**, líquida de tesouraria, e o WACC estático pondera por ela; potencial mediano −37,6% → −28,7% com postos 0,982 — [decisão 83](decisoes/083-a-contagem-oficial-da-b3-arbitra-o-divisor.md) |
| **A3.4** | **Evento e contagem por data para as deslistadas** | ⬜ **novo** — a ponte do A3.2 dá preço bruto; a coorte precisa do ajuste por evento, que para deslistada só a inferência dá (com o teto acima), e da contagem de ações na data, que a CVM dá sem escala. **É o que falta ao C1b** |
| A4 | Proventos por fonte independente | ⬜ §1.2, §2.7; reabrir a decisão 23 é **decisão do orientador** |
| A5 | Taxonomia setorial B3 | ⬜ §1.5, §2.14 |
| A6 | Prazo das outorgas — FRE | ⬜ §2.16 |
| D1 | Quebrar `_evaluateLane` | 🟨 **viável** — gabarito ao bit construído; **recomendado como primeiro item da Fase 2** (§5). O gabarito da manhã ficou velho com as decisões 81, 83 e 84: gravar de novo antes de começar, como o procedimento já manda |
| D2 | Camada multi-fonte com procedência | ✅ `FundamentalsProvenance`, campo a campo |

### Fase 2 — validação, sobre a base completa

| # | item |
|---|---|
| D1 | Quebrar `_evaluateLane`, passo a passo contra o gabarito — **antes de a validação instrumentar a cascata** |
| C2 | Cobertura da banda fora da amostra — **incerteza calibrada** |
| C0 | O que as recusas custam |
| C1a | Erro-padrão para janelas sobrepostas |
| C1b | Amostra com deslistadas — preço e ponte prontos (A3.2); **exige o A3.4** |
| C1c | Coortes **trimestrais** (vem do A1.8) — **decide se a série ancorada vira padrão** |
| C1 | Reexecutar a habilidade — **o alvo**, sobre o motor da Fase 1, que moveu a ordenação (postos 0,884 contra o de antes) |

### Fase 3 — método e nível

> **Detalhada em 11/09/2026**, a pedido: a lista faseada trazia o eixo B só por
> sigla. Os itens estão descritos na §3; aqui está a ordem e o estado.

| # | item | por que, e o que decide |
|---|---|---|
| **B1** | **O que o potencial serve** | É **decisão sua**, não trabalho meu, e destrava o resto. A §0 mostrou que a ordenação do motor não acrescenta ao book-to-market; a `metodo` propõe reverter ao IRR implícito. Três saídas: o DCF é o produto e a ordenação sai de outro modelo; o DCF tem de ganhar; ou os dois medidos lado a lado. **Recomendo o terceiro**, com o primeiro implantado enquanto o segundo é perseguido |
| **B2** | Potencial ortogonalizado como produto | Transforma a §0 de acusação em **métrica de acompanhamento**: o resíduo do potencial contra o B/M é o que o DCF sabe que o valor patrimonial não sabe. Hoje vale +0,0394 em 36 meses |
| **B6** | Horizonte de projeção | Fixo em dez anos para todo mundo, sem medição. É o item **mais barato** do eixo: uma varredura de 5 a 20 anos sobre o universo, sem dado novo |
| **B3** | Prêmio de risco deixa de ser parâmetro | 5,5% fixo (§2.2). Move o **nível** de todos juntos, e quase nada na ordenação — é "exemplar", não "referência" |
| **B4** | Risco-país e o que falta no custo de capital | Não há prêmio de risco-país nem ajuste por tamanho. CAPM de fator único é defensável numa monografia e fraco num motor de referência |
| **B5** | Triangulação por múltiplos | Nenhuma avaliação profissional entrega DCF sozinho. Dá a segunda leitura e o teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa |
| **B7** | **Consistência real × nominal** | **Novo.** O motor desconta fluxo nominal a taxa nominal e usa o IPCA só no teto da perpetuidade. Nunca foi conferido que as duas pontas usam a mesma convenção de inflação |
| **B9** | **WACC estático com dívida bruta, e o resolvido com líquida** | **Novo, da lente `metodo`.** O custo de capital realavancado da decisão 41 pondera pela dívida líquida; o WACC estático de recuo, pela bruta, e a ponte desconta a líquida. As duas vias de taxa não usam a mesma convenção, e a diferença cai sobre ativo com muito caixa |
| **B10** | **A migração de via é descontínua** | **Novo.** Na PRIO3, uma curva mais alta levou o capital próprio a 14,4% do valor da firma, a cascata migrou para a via do acionista, e o potencial **subiu** de −80,6% para −18,3%. Taxa maior dando preço justo maior é resposta que um motor de referência não pode ter. Ver [fase1_padrao.md](validacao/fase1_padrao.md) |
| **B8** | **Reapresentação no *point-in-time*** | **Novo.** A ingestão adota a **última versão** de cada documento, e **24,8% dos anuais têm mais de uma**. A data de cada versão está gravada; usá-la é o que torna a coorte honesta. **Evidência de 14/09/2026:** a DFP de 2023 da USIM3 foi reapresentada e a versão ingerida tem recebimento em 16/01/2025 — em 04/09/2024 o ano ficava sem CVM, e a decisão 78 o devolveu ao mercado em vez da versão original |

Fecham a fase os itens de higiene: **C4** (custos de transação) e **D3**
(cobertura apontada pela lente `risco`).

**A ordem tem uma razão.** B1 primeiro porque é decisão e porque o defeito que
ela resolve está **em produção**. B2 e B6 depois porque não precisam de dado
novo. B3 a B5 por último dentro da fase, porque movem nível e não ordenação —
e é a ordenação que a §0 mostrou estar em dívida.

**A exceção à sequência:** o defeito que a §0 expõe está **em produção** — a
tela de metas ordena por um potencial que não bate um fator de uma linha.
Isso não precisa esperar o eixo A. Recomendo declarar a ressalva na tela agora
e decidir o B1 quando a habilidade for remedida sobre a base nova.

---

## 7. Critério de parada

**Valuation exemplar** — o preço justo de um ativo é defensável linha a linha:

- [ ] Nenhum defeito conhecido em aberto *(a tesouraria do A1.5 tem tratamento; falta **ligá-la ao divisor**, que depende do A3)*
- [ ] Insumos de fonte primária, com procedência declarada *(A1 **construído**; falta A1.7 ligar, mais A3 e A4)*
- [ ] Curva de desconto observada, não interpolada *(A2)*
- [ ] Horizonte compatível com o contrato onde há contrato *(A6)*
- [ ] Segunda leitura por múltiplos *(B5)*

**Motor de referência** — as três condições combinadas:

- [x] **Nenhum defeito conhecido** — atingido em 11/09/2026, 66 decisões
- [ ] **Incerteza calibrada** — não medida *(C2)*
- [ ] **Habilidade comprovada** — **medida e reprovada** *(C1: t = +0,24 em 12m, +1,16 em 36m, condicionado ao B/M)*

A primeira condição estava certa, e as outras duas não estavam medidas. Agora
uma delas está, e o resultado é negativo. **Isso é progresso**: um alvo que não
se sabia estar longe passou a ter distância conhecida.

---
