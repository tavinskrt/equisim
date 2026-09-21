# Histórico das rodadas do plano do motor de referência

O que cada rodada de execução do [plano](plano-motor-de-referencia.md)
encontrou, o que as lentes do conselheiro disseram e o que a auditoria do gate
reprovou — do mais recente ao mais antigo.

Saiu do plano em 14/09/2026 para que ele ficasse com o que é acionável: itens,
estado, critério de pronto e critério de parada. **Nada foi resumido nem
cortado**; o texto é o mesmo, com os títulos promovidos um nível. Decisões
continuam em [decisoes/](decisoes/), e medições em [validacao/](validacao/).

---

## O que a sexta rodada da Fase 3 encontrou — B6, B7, B3, B4 e B5 (21/09/2026)

**A rodada achou um defeito grande no meio dela, e teve de refazer a própria
medição.** A lente `metodo` apontou que a separação do caixa que a decisão 113
fez no WACC tinha um **segundo lugar**: a ponte do acionista da rota derivada —
o caminho de produção da via da firma desde a decisão 102 — calculava o serviço
da dívida como `D_líquida·(K_d(1−τ) − g)`, de modo que o caixa rendia ao custo de
**empréstimo**. A correção
([decisão 119](decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md))
derruba o preço justo em **73 dos 97, todos**, com mediana de −4,63% e p10 de
−42,8%, e tira ENGI11 e GOAU4. **Todas as cinco medições da rodada foram
refeitas depois dela**, e as decisões 114 a 118 carregam os números de depois.

O aviso de método que fica: **corrigir uma ocorrência não corrige a regra.** Duas
rodadas seguidas, a mesma lente, o mesmo argumento, lugares diferentes do mesmo
caminho. A varredura por `K_d` aplicado a grandeza líquida foi feita e não achou
um terceiro.

**O B7 virou prova, e não inspeção.** Conferir no código que cada linha está na
unidade certa é a mesma leitura que deixou passar tudo o que as rodadas
anteriores acharam. O que prova é a **invariância de unidade**: valor presente é
quantia de hoje, e reexpressa a conta em moeda constante por Fisher, o preço
justo tem de ficar onde estava. Vale **ao último dígito** no desconto dos fluxos,
no decaimento linear do crescimento e na estrutura a termo — e o decaimento
sobreviver a Fisher **não era óbvio**, porque a interpolação é linear e Fisher
não é. **Não vale em três lugares, e os três têm forma fechada**: caixa no meio
do ano, `(1+π)^−1/2`; terminal neutro, `r∞ ÷ (r∞ − π)`, que é 1,305 na mediana;
e o freio de reinvestimento. **A raiz é uma só** — operação sobre taxa líquida
não é neutra à unidade, e `g = b·ROIC` é identidade **nominal**. A formulação do
motor é a correta, e a tradução ingênua para termos reais é que estaria errada.

**O B6 fechou com um achado que não procurava.** A mediana do preço justo anda
entre −1,0% e +0,8% de cinco a vinte anos: quadruplicar a projeção explícita não
move o ativo mediano. O que muda é **onde o valor mora** — o peso do terminal vai
de 59,2% a 8,4%. **Isso é o terminal neutro funcionando**: `VT = lucro/r` com
`RONIC_∞ = r` transfere valor do terminal para os fluxos sem mudar o total, e é
exatamente o que se observa. Evidência independente de que a construção está
certa, saída de uma varredura que perguntava outra coisa. Dez anos ficam, entre o
terminal dominante e a extrapolação de duas décadas.

**O B3 rodou as duas saídas que o item pedia, e as duas devolveram o
parâmetro.** O prêmio **histórico** do Ibovespa contra o CDI é de 0,39%, com
erro-padrão de **7,85 p.p.** — são precisos **308 anos** de série para um
erro-padrão de um ponto. O **encolhimento** dá peso de 0,1% à amostra e devolve
**5,49%**. E o **implícito** é **−3,9%**: o acionista exigindo quase quatro
pontos abaixo do CDI. **Mas a varredura resolveu outra coisa, e é a mais
importante da rodada**: o desacordo de nível do motor **não é do prêmio de
risco**. Zerá-lo move o potencial mediano de −44,7% para −29,9%, e dois terços do
desacordo sobrevivem a um prêmio **nulo**. Uma hipótese aberta desde a §0 fechou.

**O B4 recusou os dois ajustes, com medição.** O `R_f` deste motor é brasileiro e
rende **9,23% real** contra ~2% do americano: somar prêmio-país é contar duas
vezes, e custaria −13,3% de preço justo e quatro avaliações. O tamanho já é
cobrado pelo beta — o tercil menor tem beta 1,387 contra 0,876 do maior, que é
**2,81 p.p.** de `Ke`, **acima** do prêmio por tamanho da literatura. Somar 2
p.p. por cima não move a ordenação (postos de 0,992) e derruba 11,6% do preço
justo do tercil **de potencial menos negativo**.

**O B5 construiu o modelo por múltiplos, e ele confirmou o diagnóstico por outro
caminho.** P/L, P/VP e EV/EBITDA, com mediana de pares em pacote versionado —
porque o núcleo avalia um ativo por vez e não calcula mediana de bolsa sem
deixar de ser puro. 93 dos 97 recebem leitura, e **a divergência mediana é de
+78,2%**: o DCF fica acima dos pares em **apenas 13 de 93**. O potencial mediano
é de −48,4% pelo fluxo e de −2,3% pelos múltiplos. **O −2,3% é quase mecânico** —
as medianas saem dos preços dos pares, e avaliação relativa devolve o preço de
mercado por construção —, e lê-lo como confirmação do mercado seria tomar
tautologia por prova. **O que fica é que o desacordo do motor não é com o
mercado: é com qualquer leitura relativa.** E os postos entre as duas ordenações
são de **0,470**, o que faz do múltiplo relativo sinal **distinto** — item
**B22**.

### O que as lentes disseram nesta rodada

**A `metodo` achou o defeito da rodada**, descrito acima, e um segundo que não
procede agora: o minoritário fica fora dos pesos do WACC, enquanto o fluxo
descontado é o consolidado. **O obstáculo é o dado** — o valor de **mercado** do
minoritário não é observável, e usar o contábil num peso de mercado troca uma
distorção por outra. Virou o item **B23**, declarado no código.

**A `risco` achou dois buracos de cobertura, e nenhum defeito.** O `BcbDatasource`
e o `TesouroDatasource` não tinham teste para falha de rede **sem status HTTP** —
a captura é central, no `ApiClient`, mas a cobertura precisa ser de cada fonte,
porque quem acrescentar uma quarta amanhã pode não passar por lá. E a falha de
**gravação** no cache depois de uma busca bem-sucedida não era exercitada.
**A primeira tentativa do segundo teste passou sem testar nada**: fechar o banco
não o quebra, e diretório inexistente o `sqlite3` cria sozinho. O teste agora
atravessa um **arquivo** como se fosse pasta, e o grupo abre com uma conferência
da própria premissa — sem ela, os outros dois passariam vazios.

**A `dados`, a `registro` e a `tela` não acharam nada.**

**A `nucleo` voltou à mesma dívida pela terceira vez em duas rodadas**: o núcleo
carrega `double` onde o domínio pede inteiro e centavo, e os enums carregam
`label` pronto para a tela. O item **B21** foi alargado para nomear as três
metades — inclusive a confissão de que **ela cresceu nesta rodada**, com os enums
do B5 seguindo a convenção existente. Desviar num enum novo seria incoerência,
não melhoria; a dívida vira tarefa por decisão, e não por iniciativa dentro de
item alheio.

**A `rumo` repetiu dois falsos positivos da rodada anterior, e desta vez a
correção foi na lente.** Ela lia o `## Contexto` de decisões imutáveis como se
fosse o estado de hoje — os bancos sem setor que a decisão 87 resolveu, a
alíquota efetiva em valor absoluto que já é limitação declarada. **O plano
passou a ser material dela**, e a disciplina ganhou duas linhas: o Contexto
descreve o dia em que a decisão foi escrita, e limitação já declarada no próprio
comentário não é tensão. Reexecutada, os dois falsos positivos sumiram. A mesma
disciplina entrou na `registro`.

**Sobrou da `rumo` um achado que não procede**: a divergência entre as vias, que
a decisão 102 fechou — nenhum ativo tem o preço escolhido entre as duas, e o item
B13 está feito. É discordância de juízo sobre item encerrado, e não fabricação.

### A auditoria do gate

**Dois FAIL, os dois em código desta rodada, os dois na mesma ferramenta.**
Igualdade estrita entre `double` na busca do prêmio implícito — com a agravante
de que a linha seguinte dividia pela diferença — e `indexOf` numa lista de
`double`, que é a mesma regra por outro nome. Corrigidos por guarda de
denominador e por constante declarada com conferência de coerência. Mais dois
WARN, também meus: variância amostral sem guarda de `n < 2` e formatador sem
guarda de `NaN`.

**E o `agy` alternou REPROVADO e APROVADO no mesmo alvo**, duas vezes. Vale o
FAIL mais severo visto, e não o último — foi a segunda passada que achou o
`indexOf`.

---

## O que a quinta rodada da Fase 3 encontrou — B17, B18, B19, B8 e B2 (21/09/2026)

**O `data/` sumiu de novo.** O discard do merge levou junto a FCA baixada e a
entrada congelada. O cache da validação sobreviveu — ele mora em
`docs/validacao/`, e não em `data/` —, de modo que o gabarito se recriou do
zero e reproduziu 376 ativos e 102 avaliados, o estado exato do fim da rodada
anterior. **A entrada congelada é reconstruível; a base bruta não**, e é isso
que separa o que esta rodada pôde medir do que não pôde.

**O B18 era verdade, e era pequeno.** Os 14 ativos que saíram ao ligar o prior
foram recusados no ano zero da primeira iteração — antes de o ponto fixo
iterar. O ponto fixo passou a ser tentado de duas partidas: a interpolação de
dois pontos, que é o recuo, e o custo de capital **desalavancado**, que é o
mesmo caminho no limite de dívida zero. **Um volta** — a CAML3 —; os outros 13
continuam recusados pelas duas, e a recusa passou a dizer isso. Nenhum preço
justo se move.

**E a pergunta de fundo do item foi respondida por medição.** "A resposta
depende de qual conta o motor alcançou primeiro?" Agora dá para verificar: as
duas convergências são comparadas, e divergir acima de um décimo de por cento é
ressalva. **Não há divergência em nenhum ativo do universo, nas duas montagens** —
o ponto fixo é independente da partida onde converge, e agora isso é fato medido
em vez de propriedade suposta.

**O B17 fechou pela saída de declarar.** A cobertura pelo COTAHIST nas listadas
depende da base bruta; declarar a janela curta, não. O preparo mede a extensão
da série que estimou o beta — extensão, e não contagem de pares, porque feriado
tira dias e o que se quer separar é série que não existe — e a cascata avisa
abaixo de 80% da janela pedida. **A CYRE4, com 0,7 ano de cotação, já sai com a
ressalva no aplicativo de hoje**: o defeito não era só das coortes.

**O B19 respondeu o B12, e a resposta tem duas metades.** A rentabilidade
brasileira **reverte, e rápido**: AR(1) no painel de 3.246 pares dá `φ` de 0,237
com meia-vida de meio ano, e a leitura sem forma funcional mostra o quinto
superior indo de 14,3% de spread a 0,1% em dez anos — o horizonte que a projeção
explicita. **Mas reverte para onde?** A mediana do `ROIC` do universo é de 9,5%,
entre 6,0% e 15,7% em quinze anos, contra 18,6% de custo de capital de
equilíbrio mediano. **A rentabilidade reverte à metade do que o capital custa.**
Converger o terminal a `r` afirmaria uma rentabilidade que esta seção
transversal nunca teve; e o retorno implícito que o motor já usa — 12,9% — está
entre os dois, mais perto do destino medido. O terminal fica, agora por medição
em vez de por ausência dela. **E a alternativa andaria para baixo**: a escolha
da decisão 107 não era a otimista.

**O B2 já existia e não estava terminado.** O IC incremental era medido e
reportado, mas contra o P/B **e** o L/P — e o item nomeia o P/B. As duas
ortogonalizações passaram a sair lado a lado, com a inferência do resto: `t`
corrigido pela sobreposição contra o crítico e Newey-West. O resíduo contra o
P/B vale **+0,016** em 36 meses, com `t` corrigido de 0,13 contra 2,70, positivo
em 10 de 22 coortes — indistinguível de zero. A grandeza ganhou documento
próprio, com o histórico entre rodadas e a ressalva de que a série começa em
16/09/2026, porque antes disso o instrumento era outro.

**O B8 é duas metades, e só uma é medível daqui.** A que o pacote versionado
permite — o exercício que **some** porque a última versão chegou depois da
coorte — é **pequena**: de 0,0% a 1,1% dos exercícios que deviam estar públicos,
com a pior coorte em 30/06/2020, quando a CVM prorrogou prazos. Um sexto dos
documentos chega além do prazo regulamentar, e os extremos são grandes — a DFP de
2011 do Itaú tem recebimento em 2020, 3.000 dias depois. **A outra metade — o
número reapresentado entrando na coorte como se fosse o original — não é medível
sem as versões antigas**, e é a maior por construção: 24,8% dos anuais têm mais
de uma. O item ficou **em curso**, com o tamanho de uma das metades no registro.

### O que as lentes disseram nesta rodada

As sete rodaram. **A `metodo` achou o defeito da rodada**, e ele estava na
metade que a decisão 104 tinha deixado em aberto: com dívida contratada e caixa
maior que ela, a perna negativa do WACC remunerava o caixa ao custo de
**empréstimo**. O argumento que a 104 usou para o caso sem dívida — «caixa rende
a taxa livre de risco» — valia igual aqui, e não estava aplicado. A perna se
abriu em duas, nas duas rotas, e virou a
[decisão 113](decisoes/113-o-caixa-rende-a-taxa-livre-de-risco-e-nao-o-custo-de-emprestimo.md).
**Custou três avaliações** — MOTV3, MYPK3 e QUAL3 —, e obrigou a remedir o
terminal excedente do B12 e o destino da reversão do B19 na mesma tarde.

O segundo achado da `metodo` era escolha, e não defeito: o cenário de desconto
soma o deslocamento ao `Ke` um a um, e `Ke` e `WACC` não se movem na mesma razão.
**Qual é a razão depende do que o cenário perturba**, e ele não diz — são três
leituras e três fatores. Ficou o um a um, agora **declarado no código** com as
três leituras e o motivo (as duas vias precisam querer dizer a mesma coisa), e
virou o item **B20**.

A `risco` achou duas asserções de teste vazias: um `expect(isOk || isErr)`, que é
tautologia — quem cobra a ausência de exceção ali é o `await` —, e um `closeTo`
com tolerância sobre a contagem de ações da B3, que é inteiro publicado. As duas
foram corrigidas.

A `nucleo` achou um defeito real e calado: com `contributionDay` acima de 28, o
mês sem aquele dia **perdia o aporte**, e o patrimônio e o TWR de toda a
simulação saíam de um cronograma que ninguém pediu. O aporte passa a sair no
último pregão do mês quando o dia pedido não chega a existir nele.

A `dados` achou o terceiro: com a rede fora e o cache vencido cobrindo **parte**
do lote, o repositório devolvia `Ok` com meio lote e engolia o motivo — o 429, a
credencial —, que reaparecia três camadas adiante como "ativo sem cotação". O
recuo ao cache vencido passou a valer só quando ele cobre tudo que faltou.

**A `tela` não achou nada.** A `rumo` e a `registro` trouxeram cinco apontamentos
que **não procedem**: quatro citam o texto histórico de decisões e do plano —
os três bancos sem setor que a decisão 87 resolveu (A5 ✅), a discordância entre
as vias que a decisão 102 fechou (B13 ✅), a alíquota efetiva em valor absoluto
que já é limitação declarada, e a tarja de depreciação do
`crescimento_log_linear.md`, **que já está lá desde que foi escrita**. É o modo
de falhar próprio dessas duas lentes: ler a narrativa de um registro imutável
como se fosse o estado de hoje.

O que sobrou delas é dívida de arquitetura, inventariada e não acionada, porque
o repositório está sob preservação: o `Failure` do núcleo monta frase e formata
percentual para a tela, e o `Money` em centavos inteiros vale na carteira mas
não no caminho de avaliação. Virou o item **B21**.

---

## O que a quarta rodada da Fase 3 encontrou — B12, B14 e B15 (21/09/2026)

**Três itens que eram premissa não declarada, e nenhum número mudou.** O gabarito
confere idêntico ao da rodada anterior nas duas montagens — 102 e 102 —, e o que
a rodada produziu foi o motor dizendo de si o que antes carregava em silêncio.
Duas das três alternativas propostas pelos itens foram medidas e **recusadas**;
a terceira inverteu a pergunta.

**O terminal neutro não é neutro, e o sinal estava trocado.** `VT = lucro_{N+1}/r`
reagrupa em `capital_N + EVA_{N+1}/r`: o retorno neutro fixa o do capital **novo**
e não diz nada do instalado. O item supunha que o motor mantinha um excedente
para sempre; medido, ele mantém um **déficit**. O capital instalado rende **0,71
vez** o custo de capital de equilíbrio na mediana — 12,9% contra 18,9% — e fica
abaixo dele em 71 dos 83 avaliados em que a decomposição se aplica. O peso é de
−14,1% do preço justo na mediana, passa de 10% em módulo em 50 e de 20% em 33; a
EMBJ3 chega a −610%, com peso do terminal de 238%.

**E a terceira saída do item não existe.** A 18,9% ao ano, truncar o excedente em
20 anos devolve 0,4% do preço justo e em 30 anos, 0,1%: decair num horizonte é
indistinguível de manter. A escolha é binária — manter, ou zerar de imediato, o
que move +14,1% na mediana. Manter é o que fica, porque zerar afirma reversão da
rentabilidade à média, que o motor não mediu, e a decisão 35 exige de quem troque
o terminal um argumento que não seja o viés de nível. **Medir essa reversão virou
o B19.** A decomposição é conferida contra o terminal de contrato da decisão 88:
com prazo zero as duas contas têm de bater ao centavo, e o teste trava isso.

**O beta do papel pouco negociado: o viés existe e não é a causa.** Nos 185
recusados só por liquidez, Dimson sobre o beta diário dá mediana de 1,052 contra
0,988 nos avaliados, e o efeito se concentra onde a teoria manda: nos 37 que
negociam menos de 120 pregões por ano, o beta vai de **0,134** a 0,294 com uma
defasagem e a 0,367 com cinco. **Mas não chega perto** — com o mesmo encolhimento
que a produção aplica, o beta dos soltos vai a 0,723 contra 0,955 dos avaliados,
e o potencial mediano deles vai de −30,4% a −36,9% contra −48,2%: dos 17,8 p.p.
de distância, Dimson fecha 6,5. A correção ainda **triplica** o erro-padrão nos
dois grupos, e o encolhimento pondera por `1/SE²`. A recusa por liquidez fica,
agora por duas razões medidas. **E sobra um grupo nomeado**: os 100 soltos que
negociam todo pregão têm beta de 0,801, quase o dos avaliados, e a distância de
nível inteira — ali a não sincronia não tem o que explicar.

**A perpetuidade: metade do apontamento já tinha caído, e a outra metade se
resolveu sozinha.** A alavancagem de equilíbrio deixou de ser a de hoje com a
decisão 105 — é a do ano N do modelo, e medida ativo a ativo ela fica a −0,01 da
de hoje, de modo que o modelo chega perto de onde partiu. Sobrou o beta, e
convergi-lo em direção a 1 move a taxa de equilíbrio em −0,0% e o preço justo em
**+0,1%**: o encolhimento da decisão 40 já puxou cada beta ao prior transversal, e
o que chega ao preço tem mediana de 0,955. Impor a mediana setorial move 0,0% e
**custa cinco avaliações**. As duas ficam como imposição de diagnóstico.

**O que as lentes disseram.** Procederam quatro achados, em três lentes. A
`metodo` achou que o rastro de auditoria imprimia a perpetuidade de Gordon nas
**concessões**, onde o terminal é o do contrato (decisão 88) — a mesma forma de
defeito que a ponte `EV − D` tinha antes da decisão 102, e corrigida com teste
que confere as duas formas pela cascata real. A `risco` achou que o cache de
cotações pode **misturar duas bases de ações**: a fonte devolve o fechamento
ajustado por todo evento até hoje numa janela de dez anos, e o que está em disco
fora dela foi ajustado até o dia em que foi baixado — um desdobramento no meio
deixa um degrau exatamente na borda. Agora, quando o disco discorda da resposta
no pregão comum por mais de meio por cento, o histórico em outra base sai;
perder profundidade é menos grave que servir série com degrau que ninguém vê. A
mesma lente achou que o leitor de demonstrativos não tinha teste de payload de
tipo indevido, como a fonte de cotações e a do Banco Central já têm — ganhou. E a
`dados` achou que o repositório macroeconômico devolvia **a janela do SGS** logo
depois de atualizar e **a união do banco** depois do TTL, de modo que a
profundidade da série sobre a qual o CAGR decenal é apurado dependia do relógio:
é a mesma correção que os fundamentos receberam na rodada anterior, agora no
irmão.

**A `rumo` achou meio achado.** Ela disse que a migração v2 → v3 do cache deixa
os campos novos vazios até a validade de trinta dias vencer. O comportamento está
certo — quem vem da v2 passa também pelo bloco da v4, que invalida a chave de
fundamentos —, mas o **comentário** da v3 dizia o contrário do que o da v4 diz
para o mesmo tipo de mudança. O comentário foi corrigido.

**Não procederam nove.** Da `metodo`, o divisor das units aplicado a todo o
balanço — é a limitação 3.13, declarada, e a decisão 106 a endereçou — e o
`expectedReturn` fora do `RebalanceOutcome`, que arrastaria a camada de avaliação
para dentro de uma operação de carteira. Da `risco`, a trava da alíquota efetiva
sem outlier — ela **tem** teste com outlier, no núcleo, onde a regra mora — e a
derivação só no ano completo, coberta pelos casos de ausência do mesmo arquivo.
Da `rumo`, o setor das preferenciais, resolvido pelo A5, e a discordância entre as
vias, que lê a decisão 39 substituída pela 102. Da `registro`, três dos quatro
achados são **eco do próprio prompt da lente** — ela devolveu como tensão o texto
que o enunciado dá como fato conhecido —, e o quarto pede um aviso no
`crescimento_log_linear.md` que já está lá, em negrito, na primeira linha. Da
`dados`, o upsert de fundamentos sobrescrevendo com nulo: a fonte é autoritativa
por exercício, e apagar o que ela deixou de publicar é o comportamento certo. As
três da `nucleo` e as duas da `tela` são contratos declarados e preferências de
nomenclatura, fora dos objetivos.

**O instrumento ganhou um módulo, e ele se confere sozinho.**
`tool/validation/congelado.dart` monta a entrada congelada do gabarito para quem
só quer medir sobre ela, e `conferirContraGabarito` compara as avaliações ativo a
ativo com as que o gabarito gravou. As duas medições da rodada abriram com
"montagem idêntica à do gabarito" — sem isso, os números descreveriam outro motor.

---

## O que a terceira rodada da Fase 3 encontrou — B9, B11 e B16 (20/09/2026)

**A base bruta tinha sumido, e isso mudou o instrumento.** O diretório `data/`
não existe mais nesta máquina: a base ingerida da CVM, o COTAHIST e o arquivo do
Tesouro são ignorados pelo git e não vêm no clone. O gabarito da cascata
dependia dos três. Ele passou a ler os **pacotes versionados** — os mesmos que o
aplicativo lê —, e com isso se reproduz num clone limpo: as 376 avaliações, as
nove montagens e a varredura reproduzem o estado de 16/09/2026 exatamente, 114 e
104 avaliados. O backtest não se reproduz, e virou o item C5.

**O B9 era contagem dupla, e não estilo.** A dívida dos pesos do WACC era a
bruta; a da realavancagem, a do beta desalavancado e a da apuração do capital
próprio, a líquida. O fluxo da firma é operacional — não traz o rendimento do
caixa —, de modo que dar peso de dívida bruta e depois devolver o caixa ao
acionista conta o mesmo caixa duas vezes. Com a líquida, o preço justo sobe 3,0%
na mediana em 73 de 114, e até 41,9% na EMBJ3. **Na montagem com o prior o efeito
é de 2 em 102** — ali a dívida já era a líquida.

**E a medição do B9 expôs o sintoma que era do B11.** O desconto subiu e o preço
justo subiu junto, porque sem taxas resolvidas a via da firma reinveste contra o
WACC — a retenção é `g/ROIC` e o retorno terminal neutro é o próprio WACC — e
desconta ao `Ke` do CAPM. **As duas taxas só são a mesma conta no caminho
resolvido.**

**O B11 tinha quatro pendências, e uma delas estava com o sinal trocado.** O
custo da dívida do solucionador era o **observado**, que a decisão 31 já
descartara e que não decai com a curva: sozinho, trocá-lo pelo sintético move o
preço justo em 76 de 98 da montagem com prior, com mediana de −7,0% — e faz a
RADL3 ir de R$ 3,43 a R$ 7,42, contra R$ 8,07 da montagem sem prior, de modo que
as duas param de discordar por um fator de dois. A tensão da via do acionista,
que a lente `metodo` descreveu como desalavancagem, era **re**alavancagem: com
`g = 8%`, `D/E` ia de 0,63 a 0,81 e o `Ke` subia. A causa é o fluxo — ele já
desconta a retenção que financia o crescimento, e crescer a dívida junto
financiava o mesmo crescimento duas vezes. Com a dívida constante, `D/E` vai de
0,61 a 0,43 e o `Ke` cai. As premissas exibidas passaram a ser as finais: a taxa
do ano 1 resolvido, a faixa centrada no preço justo, e o cenário movendo o
caminho de `Ke`. E os dois ativos que subiam com a taxa no caminho resolvido
ficaram monótonos.

**O prior vem do pacote, e a razão está medida.** Resolvê-lo é varrer o universo
inteiro para avaliar um ativo. Ele anda devagar — a mediana desalavancada do
universo vai de 0,6421 a 0,6620 recuando um ano, 3,1% —, e o pacote vale por um
ano; fora disso o motor volta ao beta cru **e a avaliação diz que voltou**.

**Ligar custou catorze ativos.** 83 das 102 avaliações passam a resolver as taxas,
e todas as 82 da via da firma. Saem RENT3, RENT4, UGPA3, RAIL3, ECOR3, ENEV3,
DXCO3, LOGG3, CAML3, DASA3, MOVI3, PNVL3, VAMO3 e VBBR3, todos pela recusa da
decisão 45 — e todos no ano zero da primeira iteração, o que virou o item B18: **o
veredito é do chute de que o ponto fixo parte, e não do ponto fixo**. A mediana da
rodada inteira, somando o B9, é de −0,4%: os dois itens andam em direções opostas
e quase se cancelam no nível.

**O que as lentes disseram.** Procederam quatro achados, em três lentes. A
`metodo` achou o caso que o B9 deixou passar: **companhia sem dívida contratada e
com caixa** ainda degenerava para o `Ke`, enquanto a apuração devolvia o caixa —
a mesma contagem dupla, no canto que a guarda da dívida bruta protegia. São três
no universo (ALOS3, BRAP4, SAUD3), e hoje não muda número nenhum, porque as três
resolvem as taxas pelo prior e o WACC estático só lhes serve de chute; o que a
correção conserta é o **recuo**. A `risco` achou que o `BcbDatasource` e o
`TesouroDatasource` não tinham teste de payload malformado, como a fonte de
cotações tem — os dois ganharam, e passaram: a proteção existia, a cobertura não.
A `dados` achou duas: `FundamentalsRepositoryImpl.history` devolvia **a janela da
fonte** logo depois de atualizar e **a união do banco** depois do TTL, de modo que
a profundidade da série dependia do relógio — corrigido, com teste que falha sem
a correção; e o comentário de `_cobreOInicio` prometia acomodar série que nasce
depois da janela pedida, o que o código não faz — o comentário passou a dizer o
que o código faz.

**Não procederam quatro.** Da `metodo`, o prêmio de crédito fixo ao longo da
projeção — é a classificação da companhia hoje, e movê-la com a alavancagem
projetada é do mesmo tipo do B15 — e o teto de zero no crescimento perpétuo, que
é a recusa deliberada de modelar *run-off*. Da `rumo`, as três: a discordância
entre as vias lê a decisão 39, substituída pela 102; o setor das preferenciais
foi resolvido pelo A5, por emissor; e a alíquota efetiva não tem `abs()` algum —
crédito tributário vira zero pelo piso, e não despesa inventada. Da `dados`, a
meta que não se apaga no Firestore é comportamento **declarado** no próprio
código, e mudá-lo é decisão de produto. A `registro` e a `tela` não acharam
tensão; as três da `nucleo` são as de sempre, fora dos objetivos.

**O B16 não mudou número nenhum no aplicativo, e o ponto é esse.** Nas sete units
avaliadas, a razão medida no valor de mercado coincide com a composição que a
companhia declara. O que muda é a dependência: o motor deixa de depender de uma
convenção de valor de mercado que ninguém conhece, o rastro traz as duas razões e
diz qual valeu, e a divergência vira aviso. A chave do pacote é o **CNPJ**, porque
o código de negociação da FCA vem em branco em 44% das linhas e zerado no BTG. O
leitor do texto livre foi para o núcleo e ganhou o caso que errava: código de três
letras, a ENGI11 de 2018 com "1 ENG3 e 4 ENGI4" — quatro ações em vez de cinco, um
dos doze erros de inteiro que o C3 tinha achado.

---

## O que a segunda rodada da Fase 3 encontrou — B1, B10 e B13 (16/09/2026)

**O instrumento vem antes do conserto.** O gabarito da cascata, conferido no
código intacto como controle, divergia em 384 montagens sem mudança de código: a
reingestão do ITR de 2025 mexia na `ancorada`, e **o universo vinha da rede** — a
fonte tinha passado a listar a EQPA7 e a deixar de listar a COCE3. O universo
passou a ser congelado com o resto da entrada, e o gabarito ganhou a varredura do
nível da taxa livre de risco — a corrente, a de equilíbrio e a curva inteira — de
−3 a +3 p.p., sobre a mesma entrada.

**A varredura achou duas causas, e só uma estava no item.** Dos 128 avaliados pelo
aplicativo, 25 tinham o preço justo subindo com a taxa. Em 18 era a troca de via;
em 7 era outra coisa: a regra que decide se a cobertura de juros entra no prêmio de
crédito compara o custo da dívida observado com `[Rf, Rf + 10 p.p.]`, e a faixa
andava com a taxa suposta — na SMTO3, 25 pontos-base tiravam a cobertura da conta e
o desconto caía 2,3 p.p. Medida na taxa da data, os 7 somem, e o WACC corrente e o
de equilíbrio passam a ler o mesmo veredito.

**42 dos 109 não financeiros avaliados tinham o preço de outro modelo.** Migrados
ou mesclados com a via do acionista sobre LPA, pela ponte fina. A decisão 102 tirou
a pós-condição, a mescla e as duas migrações: a via da firma avalia o capital próprio
pelo fluxo do acionista derivado — a rota da decisão 43, agora também sem taxas
resolvidas — e a via do acionista fica para o que o roteamento manda. **Nenhum dos
114 avaliados sobe mais com a taxa.** O custo: 16 saem do aplicativo, entre eles a
CSNA3, a CSAN3 e a MRVE3, que tinham potencial positivo pelo LPA e não têm capital
próprio positivo pela firma; entram a AMER3 e a DASA3; e o preço justo da via da
firma cai 5,5% na mediana, porque sem taxas resolvidas o `Ke` do CAPM e o WACC de
pesos de mercado não são as taxas coerentes que tornariam as duas contas a mesma.
A PRIO3 vai de −17,9% a −72,3%.

**O terminal do contrato, na rota derivada, punha o contrato longo acima do
perpétuo.** Era o terminal da firma menos a dívida, ao WACC, contra a perpetuidade
do acionista, ao `Ke`. Virou a perpetuidade do acionista truncada, com o capital
devolvido no fim — coincide no contrato que acaba no horizonte e tende ao perpétuo
no contrato sem fim. O teste de concessão mostrou outra coisa: ao `Ke` do CAPM, o
capital devolvido pode valer mais que a perpetuidade do acionista mesmo com a firma
rendendo acima do WACC, e a ordem entre contrato e perpétuo passou a ser a do
excedente do acionista.

**O B1 foi fixado antes de medir, e a regra tirou o prêmio.** Três ordenações — o
composto dos escores do potencial, do book-to-market e do lucro sobre o preço; o
book-to-market; o potencial —, sobre as mesmas observações, e o prêmio da primeira
que passasse. **Nenhuma passou.** O book-to-market, que passava com 2,92 contra 2,70
no motor de antes, fica com 2,52 neste: a amostra é a das avaliadas, e a decisão 102
tirou dela as endividadas. O IC dele até subiu; caiu a estabilidade entre coortes.
**O retorno esperado da meta e do estudo é o `Ke` de cada ativo**, declarado total,
e a aba Análise passou a dizer que o XIRR dela é só de preço.

**A faixa calibrada teve a primeira réplica sem querer.** O motor mudou, o
backtest foi reexecutado, e a forma da decisão 100, sem mudança, cobriu
88,2/78,7/51,6% e 88,9/78,7/49,6%.

**O que as lentes disseram.** Procederam quatro. A `metodo` achou que o rastro de
auditoria continuava mostrando a ponte `EV − D` depois de a ponte ter saído do
preço — corrigido, com teste que confere que o passo soma ao preço justo. A `risco`
achou três testes de dados com asserção frouxa — a taxa do Tesouro aceita abaixo de
20%, o CDI anualizado entre 8% e 16%, e a dívida líquida sem asserção —; os três
passaram a conferir os números do arquivo, e o do CDI distingue a composição da
média linear. **Não procederam**: a retenção `b = g/ROIC`, da `metodo`, porque o
`ROIC_t` que converge ao WACC é o do capital novo, e a fórmula é a do vetor de valor
de livro-texto; e as duas da `rumo`, que leram a decisão 39, substituída, e os
bancos sem setor, que o A5 resolveu. A `registro` e a `tela` não acharam tensão — a
`tela` pelo modelo rebaixado, que vale pouco. **Fora dos objetivos**: as três da
`nucleo`, de sempre, e as duas da `dados` — a conferência de cobertura do cache
macroeconômico e o proxy que não publica sem o plano Blaze.

**O que a auditoria do gate reprovou.** Um `DateTime.now()` direto no provider dos
sinais — a data passou ao núcleo, pela forma `asOf ?? DateTime.now()` —; uma
divisão pela escala do escore robusto que a função da escala já protege, e a guarda
foi repetida no ponto; e a igualdade entre floats nos postos das ferramentas de
recusa e de cobertura, que passou a tolerância relativa de 1e-12 — e mudou, de fato,
a referência das avaliadas no grupo só de deslistadas, onde resíduos iguais
diferiam na 16ª casa.

---

## O que a quarta rodada encontrou — C2b e B1.0 (15/09/2026)

**O que estava errado na faixa era o centro, e não a amostra.** A terceira rodada
tinha medido seis formas de recalibrar e nenhuma fechou. Antes de tentar a sétima,
o diagnóstico foi refeito e escrito: as deslistadas cobrem — 90,4% em 12 meses e
96,3% em 36 —, o choque comum às coortes é pequeno — desvio de 0,18 entre coortes
contra 0,98 dentro delas —, e o que muda entre elas é a cauda de baixo, que se
alarga de 2018 para 2021. A forma do aplicativo impunha `b = 1` — convergência
total ao preço justo — onde o medido é 0,02 a 0,08, e era isso que a fazia cobrir
68,9% no terço de maior potencial.

**A forma e a regra foram escritas antes de medir**, na §9 de
`cobertura_banda.md`, e postas em staging antes de a ferramenta rodar: a
convergência parcial na escala da volatilidade do papel — a simulação histórica
filtrada —, medida como a §8 mede, com as formas de controle sobre as mesmas
observações, e o que fazer com cada resultado. **Ela cobre**: 87,9/79,0/50,3% em
12 meses e 88,2/80,4/51,2% em 36, fora da amostra, contra 84,6/74,9/48,9% e
83,5/72,8/46,6% da forma em torno do justo. A regra do pacote virou código
(`regra_do_pacote`), e não decisão de quem lê o resultado.

**O R2 fechou, e o que ele declara encolheu.** Com `b = 0,028` em 12 meses e
`0,083` em 36, dobrar o preço justo move a faixa 2% e 6%: a incerteza que o motor
declara é o preço de hoje mais a volatilidade do papel. A faixa de 80% de um papel
de 30% de volatilidade vai de 0,76 a 1,57 vez o preço em 12 meses, contra 0,76 a
8,16 vezes o preço **justo** na forma anterior. É honesta e é modesta — e o erro
do preço justo contra o realizado continua sendo o da §8, de dezenas de vezes.

**Ela calibra na média das coortes, e não em cada uma.** De 59,8% a 100% em 12
meses, e de 70,2% a 96,6% em 36 — dispersão maior que a da forma antiga. O 36
meses continua com 1,4 janela independente de calibragem. A réplica sobre o motor
da Fase 3 é o C2c, e é ela que separa a sétima tentativa de um ajuste ao teste.

**A tela de metas passou a dizer o que a §0 mediu.** O prêmio somado ao `Ke` sai
do potencial, e o potencial não comprovou ordenar: a ressalva cita a correlação de
postos — 0,09 contra 0,18 do book-to-market — e o `t` corrigido de 0,24 contra
2,70. **A frase sai do pacote da medição**, e o critério da decisão 96 mora no
núcleo: quando o C1 aprovar, ela some sem mudar código; sem pacote, ela diz que a
habilidade não foi medida. Era o defeito em produção que a §0 apontou em 11/09, e
que a conferência de 14/09 encontrou intocado.

**A execução do backtest reproduziu a anterior.** As 10.863 observações são
idênticas nas comparáveis; mudaram três valores de liquidez e entrou um papel que
a fonte passou a listar (EQPA7, ilíquido), com 11 observações. As medições
derivadas foram regeradas e os documentos, corrigidos no terceiro decimal — o
maior efeito foi no contrafactual das recusas, que ganhou dez observações.

**O que as lentes disseram.** A `dados` levou ao achado maior da rodada: no
caminho de sucesso, a renovação do cache devolvia o recorte da resposta, e a fonte
devolve uma janela fixa de dez anos — quando o disco acumular mais que ela, a
série sairia encurtada justamente quando a rede funciona. Corrigido, com teste que
reprova sem a correção. **Conferir o achado expôs outra coisa, maior**: a série de
qualquer listada começa em setembro de 2016, e a coorte de 31/03/2018 estima beta
com 383 pregões em vez de 1.240, sem ressalva — enquanto as deslistadas, que vêm
do COTAHIST, têm a janela inteira. Virou o item **B17**, a resolver antes da Fase
4. A `registro` apontou que a decisão 28 elevou o limiar Φ da 27 sem marcar
`substitui`; o código aplica 0,60, a 27 diz 0,35, e decisão aceita não se edita —
entrou a decisão 101, que declara as duas substituições parciais (28 sobre 27 no
Φ, 89 sobre 23 no provento) e fixa o critério para as próximas. A `tela` não achou
tensão nas capturas novas. **Não procederam**: as duas da `rumo`, que são o B13 e
o B10, já no plano; a do `metodo` sobre contagem de ações em `double`, porque a
contagem do divisor é estimada de valor de mercado sobre preço e arredondá-la
fingiria precisão que ela não tem — a regra de ação inteira é da simulação, que a
cumpre. **Ficam registradas sem virar item**: a âncora do retorno esperado ser a
Selic corrente, que é assunto do B1; a cobertura de payload malformado nos
datasources de fundamentos e do Tesouro, que entrou no critério do D3; e as três
da `nucleo` — listas paralelas em `TotalReturnIndex`, `ContributionPlan` sem
validar o dia do aporte, e a contagem em `double`.

---

## O que a terceira rodada da Fase 2 encontrou — C1d, C1c e C3 (15/09/2026)

**O preço das coortes estava na base de ações de hoje.** Foi o que o C3 achou ao
ir ao COTAHIST pelo preço bruto: a MGLU3 de 30/09/2020 entrava a R$ 212,38, e o
fechamento do dia tinha sido R$ 84,95. A fonte publica o fechamento ajustado por
todo evento de ações até hoje, e a coorte o multiplicava pela contagem do
exercício, na base daquele ano. Uma em cada três observações das listadas estava
fora da base da data, uma em cinco por mais de 1,5 vez, e o volume da fonte, que
não é ajustado, errava a Porta 0 pelo mesmo fator. **O defeito olhava para a
frente**: a companhia que desdobrou depois — a que subiu — parecia barata. Nas
mesmas observações, o IC do book-to-market em 36 meses cai de 0,255 para 0,151
quando o preço vai à base da data, e o do potencial, de 0,179 para 0,085. Ele
passou por quatro dias de medições, por duas rodadas de lentes e pela conferência
do C1b.

**O registro de eventos da B3 não serve para desfazer o ajuste.** Ele repete
evento: a BBAS3 de 2018 tem fator 2 no preço e produto 8 no registro. O fator
passou a ser medido, pregão contra pregão.

**A razão de unidade deixou de colapsar, e mostrou que erra.** Contra a
composição que a FCA declara, acerta 141 de 220 observações de unit; quando a
ordinária e a preferencial negociam a preços diferentes, cai em 1 ou no inteiro
errado. É o B16.

**A faixa calibrada fechava o R2 sobre o defeito.** Sem ele, cobre 84,8/74,9% em
12 meses e 83,6/73,0% em 36, nas faixas de 90 e 80%. Cinco variantes exploratórias
não fecharam, e a sexta foi fixada por escrito antes de rodar e também não. O
cartão do aplicativo dizia "8 de cada 10"; passou a dizer a cobertura medida.

**O `t` da decisão 93 era otimista.** Com coortes que compartilham janela, o `t`
comum mente por construção, e o Newey-West com poucas coortes não tem
distribuição conhecida. A correção pela estrutura da sobreposição, com crítico
simulado — que reproduz a t de Student no caso sem sobreposição —, leva a leitura
anual de 1,24 da rodada anterior a 0,63 contra 3,24, e a ordenação dos soltos do
corte de liquidez, de 3,08 a 1,56.

**A série ancorada ordena mais e não prova.** A regra de quando ela viraria padrão
foi escrita antes de o backtest terminar, e o resultado caiu do lado de "não
provado": diferença de IC de +0,036 em 36 meses, `t` corrigido de 0,70.

**A BRF estava fora das duas amostras.** A ponte excluía companhia da lista de
hoje, e a BRF estava nela quando a ponte foi montada; a coorte, porém, só tinha
como listada a companhia que a fonte de preços devolve, e a fonte não a devolvia
mais. A Petz, a Tupy e a Sequoia estavam no mesmo buraco. **E a CVM republicou o
ITR de 2025 no dia anterior**, o que deixou a série ancorada medível em 2025.

**O usuário moveu a medição da habilidade para o fim.** O C1 virou a Fase 4, com o
C2c, a faixa calibrada na montagem corrigida.

**O que as lentes disseram.** Procederam duas. A `dados` achou que o snapshot
corrente da fonte só limpava os campos de hoje quando vinha inteiro vazio: um
corrente com a contagem e sem o `marketCap` deixava o da linha anual — o do fim
do exercício, inflado pela unit — passando por valor de hoje. Conferido no código
e corrigido campo a campo, com teste que reprova sem a correção. A `metodo` achou
que o retorno esperado da meta é total pelo CAPM e a simulação é de preço — e o
comentário de `expectedReturn` dizia o contrário da decisão 62; o comentário foi
corrigido, e a decisão entrou no B1. **Não procederam**: a `rumo`, que só respondeu
pelo modelo rebaixado, pediu recalibrar a faixa até passar — busca de
especificação contra a regra fixada antes, e a faixa já é o C2c — e medir o R3
agora, contra o pedido do usuário; a `registro` não achou tensão, com o material
cortado por tamanho. **Fora dos objetivos**: o `touch` do ativo que o lote de
cotações omite, da `dados`, que é cache de ausência; os quatro da `risco`, de
teste de caminho de erro em código antigo; e os quatro da `nucleo` — listas
paralelas em `TotalReturnIndex.build`, o capital investido operacional mantido
para uma ferramenta, a porcentagem formatada em `Portfolio.weighted` e o `drift`
em pontos percentuais.

---

## O que a segunda rodada da Fase 2 encontrou — C1a, C1b, C0b e C2b (15/09/2026)

**O portal da B3 responde para boa parte das deslistadas.** O `GetDetail` devolve
a classificação oficial de 43 das 164 companhias da ponte — 62 dos 231 papéis —,
e para as outras o setor veio da FCA da CVM, pela classificação da B3 que
representa cada setor de atividade nas listadas. A tradução não foi escrita à
mão: foi medida nas próprias listadas, sem a companhia, e acerta as três portas
em 91% delas.

**A série das deslistadas tinha eventos que ninguém declarou.** Ajustada pelos
eventos do FRE e pelos inferidos, ela ainda saltava mais de três vezes em 44
pregões — o grupamento de 2024 da KRSA3 e da NGRD3, a TOYB3 dividida por 270 mil.
O critério do C1b só excluía evento declarado e não localizado; o salto entrou
na mesma regra, e 48 das 492 observações saíram.

**O Newey-West subiu o `t` em vez de baixar.** Com cinco coortes, a
autocovariância dos coeficientes saiu negativa, e a correção que devia alargar o
erro das janelas sobrepostas o estreitou — o `t` do potencial dado o P/B foi de
1,24 a 1,81, e o IC incremental sem as deslistadas passou de 2. Ler aquilo como
habilidade seria aprovar o R3 por ruído na estimativa do próprio erro. Vale o
menor dos dois até as coortes trimestrais.

**O viés de sobrevivência não estava onde se esperava.** A cauda de baixo da faixa
calibrada não desceu com as deslistadas, e a ordenação dos recusados por
liquidez não caiu — o viés pesou no nível do retorno. As deslistadas avaliadas
terminaram mais acima do preço justo que as listadas; o motivo da saída de cada
uma não foi levantado.

**O R2 fechou**, primeira das três condições do motor de referência, e fechou
por declarar uma faixa larga.

**O que as lentes disseram.** Procederam três: a `risco`, sobre a tela de
avaliação só testada vazia na matriz de estouro — posta carregada, ela achou o
alternador de Monte Carlo estourando 51 px em 320 dp sob 2,0x, e ele desce para
a linha de baixo quando não cabe; a `registro`, sobre o `CLAUDE.md` e o auditor
ainda falarem de cota de FII, que a decisão 0 tirou do projeto — corrigidos; e a
`metodo`, sobre o custo de capital da perpetuidade manter o beta e a
alavancagem de hoje, conferido no código e registrado como B15, e sobre o
retorno esperado somar prêmio por um potencial sem habilidade demonstrada, que
foi para o B1. **Não procederam**: o deadlock de repetição da `dados`, pela
quarta vez — agora com um teste que dispara oito requisições com 429 contra o
teto de quatro vagas e que reprova quando a liberação da vaga sai, e com a
disciplina da lente dizendo isso —; o texto da tela de metas que a `registro`
leu da decisão 24, já corrigido na tela; a mescla de vias da `metodo`, que é a
decisão 38; e, da `rumo`, três achados de decisão antiga já no plano ou
resolvidos — B13, os bancos sem setor que o A5 resolveu, e a não monotonia do
B10. Os da `dados` sobre cache de ausência e os quatro da `nucleo` ficam fora
dos dois objetivos.

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
