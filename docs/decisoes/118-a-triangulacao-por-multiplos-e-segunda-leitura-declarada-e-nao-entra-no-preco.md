---
numero: 118
titulo: A triangulação por múltiplos de pares entra como segunda leitura declarada, e não entra no preço
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B6, B7, B3, B4 e B5.
afeta:
  - packages/equisim_core/lib/src/services/valuation/peer_multiples.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/test/peer_multiples_test.dart
  - lib/data/repositories/peer_multiples_repository.dart
  - lib/presentation/valuation/valuation_page.dart
  - tool/multiplos_empacotar.dart
  - tool/multiplos.dart
  - assets/mercado/multiplos_setoriais.json
  - docs/validacao/multiplos.md
substitui: []
---

## Contexto

O item B5 dizia: «nenhuma avaliação profissional entrega DCF sozinho. Um
múltiplo de pares — EV/EBITDA, P/L, P/VP setorial — dá uma segunda leitura e,
principalmente, um teste de sanidade sobre o nível que hoje só a §2.8 discute em
prosa.» Até esta rodada não havia modelo por múltiplos.

## Decisão

**A triangulação entra, e não entra no preço.**

1. **Três múltiplos, com a aplicabilidade declarada.** P/L, P/VP e EV/EBITDA,
   cada um com a razão de não se aplicar quando não se aplica: prejuízo tira o
   P/L e **não o inverte**; patrimônio negativo tira o P/VP; instituição
   financeira não usa EV/EBITDA, porque depósito e captação são insumo e não
   financiamento (decisão 102); ponte que deixa o acionista não positivo é
   recusada.
2. **A mediana é do universo, e vem de pacote versionado.** O núcleo avalia um
   ativo por vez e não pode calcular mediana de bolsa sem deixar de ser puro:
   quem mede é `tool/multiplos_empacotar.dart`, quem carrega é o aplicativo. É o
   arranjo do prior do beta (decisão 40) e do registro da B3 (decisão 82). **Sem
   pacote, a avaliação sai como sempre saiu** — a segunda leitura é acréscimo, e
   a falta dela não derruba a primeira.
3. **O grupo de pares é escolhido por múltiplo**, na ordem subsetor → setor →
   mercado, com mínimo de **cinco pares**. Abaixo disso a mediana é do próprio
   ativo e mais alguns, e o múltiplo deixa de ser de pares para ser de vizinhos.
   **O grupo usado viaja com a leitura** e aparece na tela.
4. **O divisor é o da ponte, dos dois lados.** Comparar duas leituras que
   dividem por contagens diferentes mediria a ponte, e não o modelo (decisão
   83).
5. **O consolidado é a mediana das que se aplicaram**, e não a média: com três
   leituras, uma muito fora tem de ser a que o consolidado ignora, e não a que o
   arrasta.
6. **Acima de 50% de divergência, a avaliação declara** — com os múltiplos que
   produziram cada leitura e de quantos pares saíram. **Nada é reconciliado**:
   escolher uma média entre DCF e múltiplos seria propor um terceiro modelo que
   ninguém validou.
7. **O preço justo continua sendo o do fluxo descontado** (decisão 103). A
   medição confere isso ativo a ativo contra o gabarito: se a triangulação
   vazasse para o cálculo, a conferência reprovaria.

## O que foi medido

Sobre a entrada congelada, com preço justo idêntico ao do gabarito em todos os
avaliados ([multiplos.md](../validacao/multiplos.md)).

**93 dos 97 avaliados recebem alguma leitura**, 66 deles as três.

| divergência (múltiplos ÷ DCF − 1) | p25 | mediana | p75 |
|---|---:|---:|---:|
| | +28,1% | **+78,2%** | +211,6% |

**61 dos 93 passam do limite de 50%**, e o DCF fica acima dos pares em **apenas
13 de 93**. O potencial mediano é de −48,4% pelo fluxo descontado e de −2,3%
pelos múltiplos; a correlação de postos entre os dois é de **0,470**, com o
mesmo sinal em 63 de 93.

## O que a medição estabelece, e o que não

**O potencial de −2,3% pelos múltiplos é quase mecânico**, e não é evidência: as
medianas saem dos preços dos pares, e avaliação relativa tende a devolver o preço
de mercado por construção. Ler isso como «os múltiplos dão razão ao mercado»
seria tomar tautologia por prova.

**O que fica estabelecido:**

- **O desacordo de nível do motor não é com o mercado — é com qualquer leitura
  relativa.** A §2.8 discutia isso em prosa; agora é +78,2% na mediana.
- **O teste por ativo funciona, e concorda com o que o motor já dizia.** A EMBJ3
  vale R$ 0,22 pelo DCF e R$ 34,30 pelos pares — e o diagnóstico dela já trazia
  excedente terminal de −3.653% do preço justo. A divergência não é ruído da
  triangulação: é o mesmo fato por outro caminho.
- **A explicação já foi achada nesta rodada.** A
  [decisão 116](116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md)
  descartou o prêmio de risco, e a
  [decisão 112](112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
  mostrou onde o desacordo mora: a rentabilidade brasileira vive abaixo do custo
  de capital, e o terminal neutro carrega o déficit para sempre. **Os múltiplos
  não carregam premissa sobre perpetuidade**, e é por isso que as duas leituras
  se afastam.

## Consequências aceitas

**Entra um item novo: B22.** Postos de 0,470 entre as duas ordenações dizem que
o múltiplo relativo é **sinal distinto**, e não cópia do DCF. Se ele ordena
melhor é pergunta de coorte, depende do item C5, e passa a ser candidato a
ordenação na regra que a decisão 103 já fixou — o prêmio do retorno esperado sai
da primeira ordenação que passar no critério.

**As medianas são de uma data só.** O pacote é de 14/09/2026, como os demais;
múltiplo setorial se move com o ciclo, e ele precisa ser regerado junto com os
outros pacotes versionados.

**Grupo pequeno vira grupo largo sem destaque.** Quando o subsetor não reúne
cinco pares, a mediana vem do setor; quando nem ele, do mercado. O grupo usado
aparece na tela ao lado do múltiplo, mas quem só olha o número não vê que ele
veio de um grupo mais largo do que o nome do setor sugere.

**O múltiplo é do exercício-base, e não normalizado.** O DCF normaliza a base
pela Saída 1; o P/L e o EV/EBITDA usam o exercício como publicado. Numa
companhia cíclica no fundo do ciclo, o múltiplo fica alto e a leitura parece cara
— é limitação conhecida do método, e é parte do porquê de a divergência ser
declarada em vez de reconciliada.
