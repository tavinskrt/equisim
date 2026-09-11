# O vale do ciclo, e a normalização que só funcionava no pico

Medido em 11/09/2026.

```bash
dart run tool/base_negativa.dart   # grava base_negativa.json
dart run tool/recusas.dart         # a composição das recusas
```

---

## 0. O defeito

O motor normaliza o exercício-base contra a mediana do ciclo quando ele destoa
— é a Guarda 1, e ela existe porque **um exercício não descreve a empresa**.

O fator é `ciclo ÷ atual`, e ele exige denominador positivo:

```dart
final normaliza = ... && retornoAtual != null && retornoAtual > 0;
```

De modo que a correção **funciona no pico e desliga no vale**. Numa siderúrgica,
o vale é metade do ciclo — e ali o fluxo-base sai negativo, a cascata recusa, e
a empresa é descartada por causa de um ano.

A composição das recusas mostrou o tamanho: sete ativos elegíveis saíam por "os
dados não sustentam nenhuma das duas vias", e em quase todos a causa era essa.

## 1. A correção é a mesma conta, escrita de outro jeito

```
fluxo-base = retorno do ciclo × capital de hoje
```

É exatamente o que o fator faz — o próprio código já dizia isso, em
[`_baseProfitFor`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart):
*"multiplicar o lucro observado pelo fator equivale a partir do retorno do ciclo
aplicado à base de capital corrente"*. A diferença é que esta forma sobrevive a
um denominador não positivo.

E o retorno que governa o freio de reinvestimento já era o do ciclo nesse caso:
`retornoDaBase` recua para `retornoCiclo` quando o corrente não é utilizável. As
duas pontas passam a falar do mesmo ano.

## 2. As três condições, e cada uma prende em alguém

| Condição | Por quê | Quem ela barra |
|---|---|---|
| ciclo positivo e medível | sem isso não há a que voltar | AMER3, BHIA3, DASA3 |
| ao menos 60% da janela positiva | separa vale de declínio | HBSA3 |
| a trava de saúde não reprovar | quem mudou de patamar não volta | RAPT4 |

**Nenhum guarda é decorativo** — cada um é o único que barra ao menos um ativo.

O corte de 60% não é parâmetro novo: é o
`ValuationParameters.minPositiveFlow` com que a Porta 3 já decide se um fluxo
operacional se sustenta.

### 2.1 A trava de saúde foi retirada e reposta

O argumento para tirá-la era de ordenação, e ele é verdadeiro: a trava compara o
exercício com o de três anos antes e **devolve nulo quando a referência também
era prejuízo**. Ela dispara em quem perdeu agora e cala em quem já perdia. Medido:

| Ativo | queda no triênio | janela positiva | com a trava |
|---|---:|---:|---|
| RAPT4 | **109,0%** | **100,0%** | barrado |
| AZEV4 | não medível | 62,5% | passa |

Ordenação invertida: a empresa com oito de oito exercícios positivos e um ano
ruim fica de fora, e a que perde dinheiro há anos entra.

**E ainda assim a trava fica.** Sem ela, a RAPT4 entra a **+311,7% de
potencial** — fluxo-base reconstruído sobre um retorno de ciclo de 17,6% que a
empresa acabou de deixar de ter. Reconstruir a base **erra para cima**, o risco
é assimétrico, e é esse risco que a trava controla. A ordenação imperfeita é o
preço, e ele é menor.

A AZEV4 entra e sai a **−93,1%**: o guarda a admitiu e a conta disse que o
capital próprio dela não vale quase nada. Admitir não é resgatar.

## 3. O efeito

| | antes | depois |
|---|---:|---:|
| ativos avaliados | 120 | **127** |
| potencial mediano | −31,8% | −31,8% |
| potencial p75 | +10,7% | **+11,4%** |
| potenciais positivos | 37 | **40** |
| **preços dos que já existiam alterados** | — | **0** |

A mudança é estritamente aditiva, que é a forma certa: nada do que já era
avaliado se move.

| Ativo | via | preço justo | potencial |
|---|---|---:|---:|
| CSNA3 | acionista | 10,16 | **+59,7%** |
| MRVE3 | acionista | 8,60 | +55,0% |
| PCAR3 | firma | 3,24 | +14,5% |
| USIM3 | firma | 3,20 | −55,1% |
| USIM5 | firma | 3,14 | −58,8% |
| CSAN3 | firma | 1,33 | −65,0% |
| AZEV4 | acionista | 0,10 | −93,1% |

Quatro dos sete saem **abaixo** do preço de mercado. A reconstrução não é uma
máquina de gerar potencial — é a remoção de um viés de sobrevivência que
descartava a empresa no ano ruim e a mantinha no ano bom.

## 4. O que fica declarado

**A ressalva `baseReconstruida` é a mais forte da lista.** O preço justo desses
sete não repousa em nenhum exercício observado recente: repousa na afirmação de
que a empresa volta ao que já foi. O aviso diz isso com essas palavras, com o
retorno do vale, o do ciclo e a fração positiva da janela.

**O motor não distingue o primeiro ano de um declínio de um vale de ciclo.** A
trava de saúde é o que tenta, e ela tem o buraco da §2.1. Um declínio que
começou no último exercício, em empresa cuja referência de três anos atrás já
era fraca, atravessa. O que limita o estrago é a frequência: dois anos de
prejuízo derrubam a janela abaixo do corte, e o ativo sai.
