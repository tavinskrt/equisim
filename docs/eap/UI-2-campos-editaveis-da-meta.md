---
pacote: UI-2
titulo: Os campos de valor da Meta parecem editáveis
decisao: 22
origem: lente `tela`, execução de 390 dp claro
escopo:
  - lib/presentation/goals/goal_page.dart
fora_de_escopo:
  - lib/presentation/theme
criterio_de_pronto: >
  Na captura `meta@390.png`, os três campos monetários do plano patrimonial se
  distinguem visualmente de um bloco de exibição — por borda, sublinhado ou
  marca de edição. Conferível sem tocar na tela.
---

## O achado

Citação literal da lente:

> Na captura `meta@390.png`, sob "PLANO PATRIMONIAL", os blocos contendo
> "R$ 10000", "R$ 1000" e "R$ 500000" são retângulos cinza-claros uniformes sem
> qualquer indicação visual de que aceitam digitação.

O custo que ela apontou: quem usa pode concluir que os valores são calculados
pelo sistema, interagir só com o controle de prazo, e nunca personalizar o
plano. A funcionalidade existe e fica invisível.

## Por que é LOCAL e não ESTRUTURAL

Resolve-se num ponto, sem mover nada de lugar. Não há nada de errado na
organização da tela — só na afordância de três campos.

Isso o coloca **depois** de UI-1 na ordem de trabalho. Uma rodada endereça as
estruturais primeiro, e este pacote não bloqueia aquele.

## Caminhos que a lente ofereceu

1. **Borda ativa ou marca de edição** ao lado dos valores, sinalizando que são
   campos. Custo: acrescenta peso visual a uma tela que já tem muitos blocos.

2. **Estilo padrão de entrada do Material** — contorno ou sublinhado — para
   separar campo de contêiner. Custo: aproxima a tela do visual genérico do
   Material, que o sistema de design da decisão 21 evitou de propósito.

## Atenção ao corrigir

`lib/presentation/theme/` está fora do escopo deste pacote. Se a correção
parecer pedir um token novo, isso é sinal de que ela cresceu além do pacote —
pare e registre, em vez de mexer no sistema por dentro de uma correção de
afordância.
