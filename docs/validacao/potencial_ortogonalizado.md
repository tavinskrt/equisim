# O potencial ortogonalizado — item B2

> **Métrica de acompanhamento.** Ela sai de
> `tool/regressao_condicional.dart` em toda execução que remede as coortes, e
> este documento é onde ela fica registrada rodada a rodada. A última leitura é
> de **21/09/2026**, sobre o motor da Fase 3: o item C5 restaurou a base bruta e
> o backtest foi reexecutado.
>
> ```bash
> dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas --trimestral
> dart run tool/regressao_condicional.dart --trimestral
> ```

## 0. Por que uma grandeza própria

A §0 do [plano](../plano-motor-de-referencia.md) mediu que o potencial do DCF
ordena menos que o book-to-market e, condicionado a ele, não acrescenta. Isso é
uma acusação, e acusação não se acompanha. **O resíduo do potencial depois de
pagar o que o P/B já dá de graça é uma grandeza**, e medi-la a cada rodada
transforma a §0 em métrica: ela sobe quando o motor melhora, e fica onde está
quando não melhora.

É o que o item B2 pede, e é o que este documento registra.

## 1. As duas ortogonalizações, e por que as duas

| | tira do potencial |
|---|---|
| **IC ortogonalizado ao P/B** (o do B2) | o que o **book-to-market** explica |
| IC incremental | o que o **P/B e o L/P** explicam |

O item B2 nomeia o book-to-market, que é o fator contra o qual a §0 mediu o
motor. O IC incremental é mais exigente e já existia. **Os dois ficam**: publicar
só um deles deixaria a grandeza de acompanhamento mudar de definição entre
rodadas sem ninguém notar.

Em cada coorte, o potencial em posto padronizado é regredido contra o do fator —
ou dos fatores —, e o **resíduo** tem a correlação de ordem medida contra o
retorno realizado. A média entre coortes recebe o mesmo tratamento inferencial de
todo o resto: `t` corrigido pela sobreposição contra o crítico simulado dela, e
Newey-West ao lado ([decisão 96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).

## 2. A leitura de hoje

**36 meses, coortes trimestrais, com as deslistadas** — 2.165 observações, 22
coortes, sobre o **motor da Fase 3**:

| | média | `t` | Newey-West | `t` corrigido / crítico | coortes positivas |
|---|---:|---:|---:|---:|---:|
| **IC ortogonalizado ao P/B** | **+0,025** | +0,64 | +0,40 | **+0,16 / 2,70** | 10 de 22 |
| IC incremental (P/B e L/P) | +0,013 | +0,33 | +0,19 | +0,08 / 2,70 | 10 de 22 |
| IC do potencial, sozinho | +0,089 | +2,18 | +1,26 | +0,53 / 2,70 | 13 de 22 |
| IC do book-to-market | +0,157 | +8,16 | +4,26 | +1,98 / 2,70 | 20 de 22 |

**12 meses**, 2.943 observações, 30 coortes: IC ortogonalizado ao P/B de
**+0,044**, `t` corrigido de 0,76 contra 2,24, positivo em 18 de 30.

**O resíduo é indistinguível de zero.** Ele é positivo, é pequeno, e está
positivo em menos da metade das coortes — que é a assinatura de ruído, não de
sinal fraco.

## 3. O histórico

A grandeza mudou de instrumento três vezes, e o registro precisa dizer qual
instrumento produziu cada número.

| medido em | montagem | 12 meses | 36 meses |
|---|---|---:|---:|
| 11/09/2026 | 8 coortes anuais, base de ações de hoje, sem deslistadas | +0,0066 | +0,0394 |
| 16/09/2026 | 22 coortes trimestrais, base da data, com deslistadas, motor da decisão 102 | +0,015 | +0,016 |
| 21/09/2026 | mesma montagem, **motor da Fase 3**, base bruta restaurada (item C5) | **+0,044** | **+0,025** |

**A subida de 0,016 para 0,025 é o motor, e desta vez o instrumento não mudou.**
Entre 16/09 e 21/09 a montagem é a mesma — 22 coortes trimestrais, base da data,
com as deslistadas —, e o que mudou foram as **doze decisões** de método das
rodadas 4 a 6 e a **reexecução das coortes** sobre a base bruta restaurada. É a
primeira vez que a série mede duas vezes o mesmo instrumento, e por isso a
primeira vez que a diferença é atribuível ao motor.

**Continua indistinguível de zero**: `t` corrigido de 0,16 contra o crítico de
2,70, positivo em 10 de 22 coortes. Subiu 0,009 num intervalo cuja largura é da
ordem de 0,4.

**A queda de 0,039 para 0,016 não é o motor piorando.** Entre as duas leituras o
instrumento mudou de coortes anuais para trimestrais, o preço das coortes foi
para a base da data — o defeito que inflava os dois sinais de valor (C3, decisão
97) —, as deslistadas entraram e a cascata trocou de via. O número de 11/09 media
outro instrumento sobre outro motor. **É a partir de 16/09 que a série começa.**

## 4. O que a métrica decide, e o que não decide

**Não decide o prêmio do retorno esperado.** Isso é o B1, e a
[decisão 103](../decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md)
já o resolveu pela regra fixada antes de medir: o prêmio sai da primeira
ordenação que passar no critério, e nenhuma passa.

**Não é o R3.** O veredito da habilidade é o coeficiente do potencial
condicionado ao P/B numa regressão conjunta, medido no C1 da Fase 4. O IC
ortogonalizado é a mesma pergunta por outro caminho — o mais fácil de ler — e
serve para acompanhar, não para decidir.

**Decide o que a próxima rodada tem de bater.** Qualquer mudança de método que
se proponha a fazer o DCF acrescentar ao P/B tem aqui o número contra o qual ela
será medida: **+0,025 em 36 meses**, com `t` corrigido de 0,16.
