---
numero: 141
titulo: A documentação do motor e do aplicativo é refeita do zero contra o código, e o guia de estudo passa a ser documento do projeto
status: aceita
origem: voce
data: 2026-09-28
citacao: >
  Descarte (realmente, apague) todos os documentos que dizem cobrir funções do
  motor/aplicação e refaça eles do absoluto zero conferindo cada linha
  disponível no código. [...] precisamos de um documento que mostre isso e
  consiga provar que o que está sendo mostrado faz sentido e tem base teórica.
  [...] precisamos estudar toda a teoria que cobre o motor e não temos
  conhecimento prévio de finanças nem estatística.
afeta:
  - README.md
  - docs/validacao/limitacoes.md
  - docs/AUDITORIA_DE_CALCULOS.md
  - web/ASSETS.md
  - docs/motor/README.md
  - docs/estudo/README.md
  - tool/casos_de_estudo.dart
  - tool/tabelas_casos.py
  - tool/figuras_estudo.py
retira:
  - docs/refinamento-do-valuation.md
substitui: []
---

## Contexto

Os documentos que diziam descrever o motor e o aplicativo tinham envelhecido
por partes. Cada decisão atualizava o que tocava, e nenhuma reconciliava o
conjunto: o README descrevia a reconstrução das Fases 0 a 5 como estado atual;
as limitações listavam como abertas coisas resolvidas havia semanas (a
estrutura a termo "linear e de dois pontos", a migração de via, a tesouraria "não
tratada em lugar nenhum", os bancos sem setor); o documento de refinamento, com
2.315 linhas, misturava o método de 07/09/2026 com o de hoje. E a linguagem
estava, nas palavras do usuário, tão difícil que o orientador não conseguia ler.

## Decisão

1. **Os documentos que descrevem função são refeitos do zero, conferindo cada
   afirmação no código de 28/09/2026:** `README.md`,
   `docs/validacao/limitacoes.md`, `docs/AUDITORIA_DE_CALCULOS.md` (o guia do
   painel de logs) e `web/ASSETS.md`, nos mesmos caminhos, para que as
   referências de fora continuem válidas.
2. **Nasce `docs/motor/`**, a documentação que prova cada regra: para cada uma,
   o arquivo e a função que a executam, a fórmula, a base teórica e a evidência
   do registro.
3. **Nasce `docs/estudo/`**, o guia para quem não sabe finanças nem
   estatística: sete capítulos, glossário, roteiro de estudo, perguntas do
   orientador e cinco casos calculados passo a passo com os números do motor.
   Os números vêm de `tool/casos_de_estudo.dart` (entrada congelada; os dados
   ficam em `docs/estudo/casos/dados/`), as tabelas são reconferidas por
   `tool/tabelas_casos.py`, e as figuras saem de `tool/figuras_estudo.py`.
4. **`docs/refinamento-do-valuation.md` é apagado** (campo `retira`). Ele
   estava no `afeta` das decisões 25, 27, 28 e 30, que perdem esse objeto sem
   ser editadas; o conteúdo está no git, commit `6827219`. As referências de
   código e de medição a ele passam a apontar para o commit e para
   `docs/motor/`.
5. **As medições de `docs/validacao/` não são reescritas.** Cada uma é registro
   datado do que se mediu, e é citada pelas decisões; reescrever mudaria a
   evidência de decisões aceitas.

## Consequências aceitas

**Conferir cada linha achou sete defeitos**, registrados no plano como B35 a
B41: o rastro da via da firma descrevia outra conta (B35); o cenário de desconto
não alcançava o caminho de Ke resolvido (B36); a taxa dos bancos não seguia a
curva ano a ano (B37); o rótulo "Otimista" num cenário que pode valer menos
(B38, que depende de decisão); um aviso e um rastro citavam uma trava retirada
pela decisão 36 (B39); o aviso das contagens nomeava a contagem errada (B40); a
mediana dos pares incluía a própria companhia (B41). Seis foram corrigidos na
mesma rodada. A documentação descreve o código depois das correções.

**A documentação volta a poder envelhecer.** O guia e os casos dependem dos
números do motor; quando o motor mudar, `tool/casos_de_estudo.dart` refaz os
dados, e os documentos precisam ser relidos. A lente `registro` é quem aponta a
defasagem; ela não bloqueia nada.

**Quem procurar uma seção antiga do refinamento** (as decisões 25 a 30 citam
seções dele) precisa do histórico do git.
