---
numero: 134
titulo: A mudança de base apaga do cache o ativo inteiro, e é vista no primeiro pregão em comum
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Ao executar mudanças no código, realize a execução das lentes e correção dos
  problemas apontados por elas.
afeta:
  - lib/data/repositories/market_repositories.dart
  - lib/data/datasources/local/cache_database.dart
  - test/data/cache_repository_test.dart
  - test/data/brapi_datasource_test.dart
  - scripts/qa/advisor/lentes.ts
substitui: []
---

## Contexto

A fonte de cotações devolve o fechamento já ajustado por todo evento
societário até hoje, numa janela de dez anos. O cache guarda a união do que já
viu. Quando um desdobramento ou grupamento acontece entre duas buscas, o disco
tem a base de antes e a resposta tem a de agora. Misturar as duas deixa um
degrau que ninguém vê na série: é o mesmo defeito que a decisão 97 mediu nas
coortes, só que entrando pelo cache.

O repositório já tratava isso desde 21/09/2026 (lente `risco`). A lente
`dados` desta rodada achou um furo no tratamento, e conferi no código que
havia um segundo:

1. **Só saía o que vinha antes da resposta.** Na mudança de base, o repositório
   apagava do disco as cotações anteriores ao primeiro pregão da resposta e
   gravava a resposta por cima. Um pregão que o disco tinha **dentro** da
   janela e que a resposta omitia não era apagado nem sobrescrito, e ficava no
   meio da série nova na escala velha. A fixture gravada da fonte tem um
   buraco desses, em 18/08/2026.
2. **A mudança só era vista no primeiro dia da resposta.** Quando esse dia
   faltava no disco, a comparação dava "sem evento", e o histórico em outra
   base ficava inteiro.

## Decisão

1. **Na mudança de base sai o ativo inteiro do cache**, e fica só a resposta.
   Perder profundidade já era o preço aceito. O que muda é que agora não sobra
   nenhum pregão da base velha, nem antes da janela nem dentro dela.
2. **A comparação é no primeiro pregão que o disco e a resposta têm em
   comum.** Um evento entre duas buscas reajusta todo pregão anterior a ele,
   então o primeiro dia em comum basta para enxergá-lo.
3. **Dois testes, um para cada caso**, sobre a fixture real: o pregão da base
   velha dentro da janela sai, e a mudança é vista quando o primeiro dia da
   resposta falta no disco. Sem a correção, os dois falham.

## Os outros achados da rodada

**Recusados, com o motivo conferido no código:**

- **Os campos "de hoje" dos fundamentos ficam velhos nos exercícios que só o
  disco tem** (lente `dados`). É verdade, mas a cascata não lê esses campos
  ali. A contagem corrente, o valor de mercado e o EV/EBITDA são lidos só do
  exercício mais recente publicado (`latest`, `publicados.last`), e esse é o
  exercício que a resposta renova.
- **O volume das cotações com mais de dez anos fica vazio para sempre**
  (lente `dados`). O volume só é lido na janela de liquidez recente
  (`EligibilityGate.medianTradedValue`), que a fonte renova. E volume ausente
  faz o teste ser omitido, não reprovar a avaliação. A simulação não aborta,
  ao contrário do que a lente afirmou.
- **`AuditJson` converte `NaN` em texto dentro do núcleo** (lente `nucleo`). A
  conversão está só no `toJson`, que é o contrato de serialização do próprio
  tipo. O valor em memória, que é o que o cálculo lê, não muda.
- **`viaMigrada`, o construtor sem validação, `CalendarDate` e o sufixo
  `AsOf`** (lente `nucleo`). São estruturas que já existiam, com razão
  registrada (decisão 102 e as leituras de dado gravado), e nenhuma é
  regressão. Ficam inventariadas.

**A disciplina das duas lentes ganha a conferência que faltou**: na `dados`,
afirmar que um dado velho contamina o cálculo exige citar quem o lê, e os dois
casos acima ficam registrados como já conferidos. Na `nucleo`, uma conversão no
`toJson` não é conversão em memória.

**Aceito sem mudança de código:** a lente `risco` apontou que o teste de
resposta malformada da fonte de demonstrativos deixava de fora as duas rotas de
estatística, justamente as que trazem a contagem de ações e o valor de mercado.
O laço agora cobre as cinco rotas e confere também esses quatro campos. O
código já tolerava todos os corpos quebrados sem inventar número.

## Consequências aceitas

**A comparação lê do disco a janela inteira da resposta**, até dez anos, e não
um dia só. É uma leitura local por ativo a cada renovação, que acontece a cada
doze horas.
