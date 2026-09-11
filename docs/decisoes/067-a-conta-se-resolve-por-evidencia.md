---
numero: 67
titulo: A conta da CVM se resolve por evidência, e a ausência do conceito é nula
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/services/cvm/cvm_chart.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_bridge.dart
  - packages/equisim_core/test/cvm_chart_test.dart
  - docs/validacao/cvm_ingestao.md
substitui: []
---

## Contexto

A CVM publica DFP e ITR com um plano de contas que **parece** padronizado.
`1 = Ativo Total` e `3.01 = Receita` valem em 467 de 467 companhias, e a
tentação é montar uma tabela de códigos.

A conferência de 11/09/2026 mostrou que a tabela estaria errada. Há **quatro
layouts** no universo, e o lucro líquido mora em código diferente em cada um:
`3.11` na não financeira, `3.09` no banco consolidado do tipo "da
Intermediação", `3.13` no individual do mesmo tipo, `3.13` na seguradora. Os
dois layouts de banco se distinguem por **uma preposição** — "da" contra "de"
— num rótulo em português.

O erro não é teórico: no individual do Itaú, `3.11` é *"Reversão dos Juros
sobre Capital Próprio"*, e casá-lo devolveria zero no lugar de R$ 37,3 bi. E
`3.05`, que é EBIT na não financeira, é "Resultado Antes dos Tributos" no
banco — R$ 47,6 bi contra R$ 42,1 bi de lucro, 13% de erro num número que a
via da firma usaria.

## Decisão

`CvmChart` resolve cada conta semântica **por padrão de descrição** entre as
linhas de nível raso, com o código servindo de desempate e de conferência. E
**devolve `null` onde o layout não tem o conceito**: banco e seguradora não
separam operação de financeiro, logo não têm EBIT, e a resposta é a ausência —
nunca um número plausível.

Três regras sustentam isso:

1. **Só nível ≤ 2.** Abaixo dele a descrição é texto livre da companhia — a
   conferência achou 26 grafias de "Caixa e Equivalentes" no nível 4.
2. **Vence o maior código.** No layout "de Intermediação" tanto `3.07`
   ("Operações Continuadas") quanto `3.11` ("Líquido Consolidado") casam com
   "lucro", e o certo é o de baixo. A comparação é numérica por segmento:
   lexicograficamente `3.9` viria depois de `3.11`.
3. **Exclusões declaradas.** "por ação", "continuada", "descontinuada",
   "reversão" e "juros sobre" saem da busca de lucro.

Na ponte, a mesma postura: `CvmBridge.semPonte` é **veto**, aplicado antes de
qualquer regra, e `conflitosDeRaiz` denuncia companhia alcançada por duas
raízes sem remover nada por conta própria.

## Consequências aceitas

**A resolução depende de texto em português da fonte.** Se a CVM reescrever um
rótulo, a leitura para de achar a conta — e para *achando nada*, que é o modo
de falha certo. Uma tabela de códigos falharia achando o número errado.

**O CapEx fica de fora dessa disciplina**, e é a única exceção: ele soma
linhas de nível 3 sob `6.02` que mencionem imobilizado ou intangível, em texto
livre, e por isso tem cobertura de 86% contra os 100% do resto.

**A validação foi em dois níveis, e o segundo é o que convence.** Dezenove
testes sobre linhas sintéticas com os casos exatos da conferência; e a
execução sobre **5.838 exercícios de 822 companhias**, com **zero** faltas de
lucro, patrimônio ou ativo total, **zero** EBIT indevido em banco, e a
identidade `ativo = passivo` fechando em **5.818 de 5.820**.

Dois defeitos meus foram pegos pelos testes antes de chegarem ao dado:
`B3SA3` tem dígito na raiz e o filtro de formato a descartava; e `semPonte`
era comentário que o código ignorava, de modo que `MAPT3` foi resolvido para a
Marcopolo — o engano que a lista existia para impedir.
