# Perguntas que o orientador (ou um leitor do artigo) pode fazer

Respostas curtas, com o número e o lugar onde o assunto está explicado. Servem
para preparar a reunião de validação, e não substituem os capítulos.

---

### Sobre o método

**1. Por que fluxo de caixa descontado, e não múltiplos?**
Porque o DCF diz *de onde* vem o valor (quanto a empresa gera, por quanto tempo,
a que custo), e cada premissa pode ser conferida. Múltiplos entram como segunda
leitura, para conferir o nível, e nunca mudam o preço justo (decisão 118;
[cap. 4, seção 4.13](04-fluxo-de-caixa-descontado.md)).

**2. Por que dez anos de projeção?**
Porque é o horizonte em que o retorno excepcional costuma convergir ao custo de
capital, e porque a participação do terminal no valor se estabiliza (decisão
115). Com menos anos, o terminal pesaria mais.

**3. Por que bancos são avaliados de outro jeito?**
Porque a dívida do banco é matéria-prima: não dá para separar operação de
financiamento. O motor desconta direto o lucro do acionista ao Ke
([cap. 5](05-bancos.md)).

**4. De onde vem a taxa de desconto?**
CAPM sobre a curva de juros do Tesouro: para cada ano, o forward daquele ano
mais beta × 5,5%. Nas não financeiras, o beta é recalculado ano a ano pela
dívida projetada (ponto fixo) ([cap. 3](03-risco-e-retorno.md)).

**5. Por que a taxa livre de risco é a curva, e não o CDI de hoje?**
O CDI é taxa de um dia; a empresa gera caixa por décadas. A curva dá a taxa que
o mercado de títulos atribui a cada prazo, sem o motor prever nada (decisão 74).

**6. O orientador pediu para usar a Selic prevista pelo Focus. Isso foi feito?**
Foi medido ([selic_focus.md](../validacao/selic_focus.md)): a Selic do Focus sobe
o preço justo mediano de 18% a 33% e mexe pouco na ordenação. A recomendação
registrada é **não trocar a base** — a curva é preço de mercado, o Focus é
previsão — e oferecer o Focus como sensibilidade. A decisão é do usuário com o
orientador (item B33 do plano).

**7. Por que 5,5% de prêmio de mercado?**
Porque as duas formas de medir falharam de modo informativo: o histórico tem
erro de 7,85 pontos, e o encolhimento devolve 5,49%; o implícito sai negativo
(decisão 116; [cap. 3, seção 3.7](03-risco-e-retorno.md)).

**7a. Dá para capturar o prêmio do mercado em vez de fixá-lo?**
Foi medido em 29/09/2026, a pedido do orientador, pelas duas vias. O
**histórico** — quanto o Ibovespa rendeu acima do CDI — depende da janela e sai
negativo na maior parte das datas ([premio_historico.md](../validacao/premio_historico.md)).
O **implícito** — o retorno que o preço da bolsa embute, dado o dinheiro que ela
distribui — é −0,98% hoje, mas a média dele em cinco anos (1,55%) e em dez anos
(1,23%) fica positiva em todas as datas testadas
([premio_implicito.md](../validacao/premio_implicito.md)). Nada foi ligado: a
escolha está aberta (item B42 do plano). O «implícito» da pergunta 7 é outra
conta — o prêmio que faria o motor concordar com o preço mediano.

**7b. Por que o crescimento é a mediana da variação do patrimônio, e não ROE × retenção?**
Porque é a mesma conta olhada para trás: o lucro retido vira patrimônio, e a
variação anual do patrimônio é o `ROE × retenção` daquele ano (decisão 25). A
versão que olha para a frente — o ROE normalizado vezes a retenção do payout
praticado, com o PIB do setor para as companhias de pouco capital — foi medida
em 01/10/2026: erra menos o crescimento que veio depois, mas quase não muda o
preço justo, porque crescer só vale mais quando o ROE passa o custo de capital
([crescimento_fundamental.md](../validacao/crescimento_fundamental.md); item B45
do plano).

**8. O que é o "moat" e quando ele vale?**
É o retorno acima do custo que sobrevive depois de dez anos, medido pela
persistência φ do próprio histórico (φ¹⁰ do excedente sobrevive). Só com oito
exercícios, crescimento orgânico e excedente positivo, e nunca para concessão
(decisão 36; [caso WEGE3](casos/wege3.md)).

**9. Como o motor evita usar informação do futuro?**
Toda avaliação tem data, e só entram exercícios já entregues à CVM naquela data
(visão *point-in-time*; [cap. 2, seção 2.9](02-a-empresa-em-numeros.md)).

### Sobre os resultados

**10. Por que os preços justos são tão menores que os preços de mercado?**
É o viés de nível, medido e declarado: upside mediano de −45% nos 97 avaliados
com os dados de 14/09/2026 (medido com o motor de 28/09/2026). As causas são o conjunto das premissas conservadoras — juros de
14% na curva inteira, retorno convergindo ao custo em dez anos, terminal
neutro —, e não um parâmetro isolado. O prêmio que zeraria o upside mediano
seria negativo (decisão 116; [limitações](../validacao/limitacoes.md)).

**11. Então o motor está errado?**
O motor responde "quanto vale se a concorrência fizer o que costuma fazer e o
capital custar o que a curva diz". O mercado pode estar precificando outra
coisa. A validação não mostrou que o motor ordena melhor que o acaso, e também
mostrou que o teste não teria poder para mostrar
([cap. 7](07-como-o-motor-foi-validado.md)).

**12. O que a faixa calibrada garante?**
Que, medida em coortes que não foram usadas para ajustá-la, a faixa de 80%
conteve o preço mais os proventos em 79,4% dos casos em 12 meses e 79,9% em 36.
Ela **não** é um intervalo em torno do preço justo: sai sobretudo do preço de
hoje e da volatilidade ([cap. 4, seção 4.12](04-fluxo-de-caixa-descontado.md)).

**13. E os cenários pessimista e otimista?**
São sensibilidade: mostram quanto o número depende das premissas. Nas coortes,
contiveram o resultado em só 8% dos casos (decisão 92). E o "otimista" pode sair
abaixo do "pessimista" quando a empresa rende abaixo do custo — crescer destrói
valor (item B38, aguardando decisão).

**14. O motor tem habilidade?**
"Habilidade testada, com o poder declarado" (decisão 140): o teste fixado antes
não passou (t de 0,40 contra 2,70), e o menor efeito que ele detectaria é nove
vezes o medido. "Comprovada" depende da réplica selada, com leituras em 2029 e
2031.

### Sobre confiabilidade

**15. Como garantir que o número mostrado é o calculado?**
O painel de logs mostra cada passo com fórmula, variáveis e resultado, e a soma
das parcelas fecha com o preço justo (conferido nos [casos](casos/)). Um
gabarito com a saída completa de 376 ativos é refeito a cada mudança e conferido
ao bit.

**16. Quantos defeitos foram achados, e como?**
O plano registra cada um (itens B). Na rodada desta documentação, conferir cada
linha do código achou sete (B35 a B41): três no rastro e em textos que
descreviam contas que não aconteciam, um nos cenários, um na taxa dos bancos,
um nos múltiplos de pares e um de rótulo (B38, pendente de decisão).

**17. O que o motor *não* faz?**
Não lê proventos na avaliação, não prevê preço de commodity, não modela
aquisições, não usa análise de crédito real (o custo da dívida é sintético), não
tem prêmio variável no tempo. A lista completa está nas
[limitações](../validacao/limitacoes.md).
