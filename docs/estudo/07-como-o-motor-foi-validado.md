# 7. Como sabemos se o motor funciona

> **Para que serve este capítulo.** "O motor funciona?" tem três respostas
> diferentes, porque "funcionar" quer dizer três coisas. Este capítulo explica
> cada uma, o que foi medido, e o que se pode (e o que não se pode) afirmar ao
> orientador e no artigo.
>
> Tempo de leitura: 40 minutos. Pré-requisitos: capítulos 4 e 6.

---

## 7.1 Dois objetivos que não são o mesmo

O projeto persegue dois objetivos, definidos no
[plano do motor de referência](../plano-motor-de-referencia.md):

- **Valuation exemplar**: o preço justo de **um** ativo é defensável linha a
  linha — cada número tem fonte, cada premissa é observada ou declarada, e o
  resultado se move na direção que a teoria diz quando o mundo muda.
- **Motor de referência**: a **ordenação** de todas as ações é confiável, e o
  motor sabe o quanto não sabe.

Um DCF pode ser impecável sobre uma empresa e ainda assim ordenar mal o mercado
inteiro. São perguntas diferentes, medidas de formas diferentes.

---

## 7.2 As três condições do motor de referência

| | Condição | Pergunta em português | Onde está |
|---|---|---|---|
| **R1** | Nenhum defeito conhecido | Há alguma conta errada que já sabemos? | nenhum item de defeito aberto no plano |
| **R2** | Incerteza calibrada | A faixa de "8 em 10" acerta 8 em 10? | faixa calibrada, medida fora da amostra |
| **R3** | Habilidade testada, com o poder declarado | O motor ordena melhor que o acaso? E o teste enxergaria se ordenasse? | teste pré-registrado, com o poder medido |

### R1 — nenhum defeito conhecido

Todo defeito achado vira item no plano (letra B, numerado), com o critério de
"pronto". A condição é que nenhum defeito conhecido esteja aberto.

**Como os defeitos são caçados:** a auditoria automática a cada envio
(`npm run qa:gemini`), as sete lentes do conselheiro (capítulo 8 da
[documentação do motor](../motor/README.md)), o gabarito da cascata (a saída
completa de 376 ativos congelada, conferida ao bit a cada mudança), e as
leituras humanas — como a desta documentação.

**Um exemplo honesto:** ao reescrever esta documentação conferindo cada linha
de código, foram achados cinco defeitos (itens B35 a B39): o rastro do painel
de logs descrevia uma conta diferente da feita na via da firma; o cenário de
desconto não alcançava todos os anos em um caso; a taxa dos bancos não seguia a
curva ano a ano; e dois textos (um aviso e um rastro) diziam que uma regra
retirada ainda valia. Quatro foram corrigidos na mesma rodada; o B38 (o nome
"Otimista" num cenário que pode valer menos) depende de decisão.

### R2 — incerteza calibrada

A faixa calibrada da tela promete: "em 8 de cada 10 avaliações passadas, o preço
mais os proventos terminaram nesta faixa". Medida **fora da amostra** (em
coortes que não foram usadas para ajustá-la):

| Horizonte | Prometido | Medido | Critério (±5 pontos) |
|---|---:|---:|---|
| 12 meses | 80% | 79,7% | cumprido |
| 36 meses | 80% | 79,6% | cumprido |

A faixa sai da volatilidade do papel e do preço de hoje, e o preço justo entra
com o peso pequeno que a evidência deu (capítulo 4, seção 4.12). **R2 está
atingido** (decisões 100 e 124).

### R3 — habilidade testada, com o poder declarado

A pergunta: **as ações com maior upside no motor renderam mais nos 36 meses
seguintes?**, controlando pelo book-to-market (a razão patrimônio ÷ valor de
mercado, um fator de valor conhecido na literatura — Fama e French, 1992).

O teste foi **fixado antes de medir** (decisão 96): regressão em cada coorte
trimestral de 2018 a 2023, média das inclinações (Fama-MacBeth), `t` corrigido
pela sobreposição das janelas, contra um limiar de 2,70, e Newey-West acima de
2. Fixar antes impede o erro mais comum de validação: testar vários critérios e
relatar o que passou.

**Resultado (remedição de 01/10/2026, com o prêmio de mercado novo):** inclinação
de 0,032, com `t` corrigido de 0,18 contra 2,70. **Não passou.** (Com o prêmio de
5,5%, em 28/09/2026, era 0,069, com `t` de 0,40.)

**Nem o book-to-market sozinho passou**: na mesma remedição, o IC dele em 36
meses é 0,17, com `t` corrigido de 2,27 contra 2,70 (era 2,03 em 28/09). Pela
regra fixada antes de medir (decisão 103), sem ordenação que passe, o retorno
esperado da tela de metas fica só no custo do capital próprio.

**E o poder:** com a série brasileira disponível, o menor efeito que o teste
detectaria com 80% de chance é 0,65 — vinte vezes o medido. O próprio
book-to-market só teria esse poder no efeito dele com 54 coortes, em 2034. Ou seja, o teste
**não teria como** confirmar uma habilidade do tamanho que a literatura costuma
achar.

Diante disso, o usuário decidiu (decisão 140) que o critério é **"habilidade
testada, com o poder declarado"**: o teste foi feito como combinado, o resultado
está registrado, e o registro diz até onde o teste enxerga. **R3 está
atingido nessa definição.** "Habilidade comprovada" **não** está.

---

## 7.3 A réplica selada (C7)

O único caminho para "comprovada" é evidência que ninguém podia ter ajustado:
previsões feitas **antes** do resultado existir. O projeto sela, a cada
trimestre, as previsões do motor daquele dia, com o código de então e o hash do
git de cada arquivo (decisões 133 e 138). As três primeiras coortes seladas são
de 31/12/2025, 31/03/2026 e 30/06/2026. A leitura só é permitida quando os 36
meses passarem — a ferramenta `tool/c7_leitura.dart` recusa ler antes. As
leituras previstas são em 2029 e 2031.

---

## 7.4 O que dizer ao orientador (e o que não dizer)

**Pode-se afirmar:**

- cada número do preço justo tem fonte, fórmula, referência teórica e rastro no
  painel de logs, e a soma das parcelas do rastro fecha com o preço mostrado;
- a incerteza declarada na tela está calibrada fora da amostra (R2);
- a habilidade de ordenação foi testada por um critério fixado antes, e o
  registro declara que o teste não passou e por que ele não teria poder para
  passar (R3);
- o motor é determinístico: a mesma entrada dá o mesmo resultado, hoje e daqui
  a um ano, e o gabarito confere isso ao bit.

**Não se pode afirmar:**

- que o preço justo prevê o preço futuro (a faixa mostra o contrário: o preço
  converge pouco ao justo);
- que comprar os de maior upside dá retorno maior (não comprovado);
- que o nível do preço justo está "certo": ele é sistematicamente mais baixo que
  o mercado (upside mediano de −37% com os dados de 14/09/2026), e isso está declarado nas
  [limitações](../validacao/limitacoes.md).

A frase da decisão 140 resume a posição do projeto: o motor "não atinge nossos
critérios de poder tomar a decisão por si só" e "serve para uso pessoal na
maioria dos casos". É uma ferramenta de **análise**, e não um oráculo.

## Para estudar mais

- **Fama e French (1992)**, "The cross-section of expected stock returns",
  *Journal of Finance* — o artigo do book-to-market.
- **Harvey, Liu e Zhu (2016)**, "…and the cross-section of expected returns",
  *Review of Financial Studies* — por que testar muitos critérios e relatar o
  que passou produz descobertas falsas, e por que pré-registrar.
- **López de Prado, *Advances in Financial Machine Learning*** (Wiley),
  capítulos sobre backtest — os erros clássicos de validação.
