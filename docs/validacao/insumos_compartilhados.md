# A1 — a discordância entre as vias vem do medidor ou da estrutura?

Medido em 10/09/2026, sobre os 96 ativos em que as duas vias são avaliáveis.

```bash
dart run tool/insumos_compartilhados.dart   # grava insumos_compartilhados.json
```

---

## 0. A pergunta

[`vias.md`](vias.md) mediu que as duas vias discordam além de 1,5× em 55 de 92
ativos. A [decisão 38](../decisoes/038-transicao-continua-entre-as-vias.md)
removeu o **degrau** que essa discordância produzia — e não a discordância.

Antes de decidir se conciliá-las exige reconstruir a Porta 2, cabia testar a
explicação mais barata: **uma empresa tem um crescimento e uma posição no
ciclo**, e as duas vias os medem separadamente — sobre capital investido de um
lado e patrimônio do outro. Se a discordância colapsar ao impor os mesmos dois
insumos, ela é do medidor, e o conserto é amarrá-los.

**O que não se compartilha, e é deliberado.** O retorno sobre o capital difere
legitimamente entre as vias — ROE excede ROIC quando há alavancagem — e a taxa
também: WACC e Ke descontam fluxos diferentes. Impor esses apagaria a economia
do problema em vez de medi-la.

**O empréstimo roda nos dois sentidos**, para não confundir "a discordância
colapsa" com "a via da firma tem razão".

---

## 1. O quanto os insumos divergem

| | mediana | dispersão |
|---|---:|---|
| crescimento (firma − acionista) | 0,00 p.p. | \|dif\| > 3 p.p. em **44 de 96** |
| fator de base (firma ÷ acionista) | 1,00× | fora de [0,8; 1,25] em **35 de 96** |

Há o que compartilhar: quase metade do universo mede o crescimento de forma
materialmente diferente nas duas vias.

## 2. E compartilhar não resolve

Dispersão medida pela **mediana de `|ln razão|`** — razão é grandeza
multiplicativa, e 0,5× e 2,0× são a mesma discordância em direções opostas.

| Insumos | mediana \|ln r\| | fora de 1,5× | fora de 2× |
|---|---:|---:|---:|
| como está hoje | **0,554** | 59/96 | 36/96 |
| só o crescimento da firma | 0,559 | 56/96 | 32/96 |
| só o fator da firma | 0,473 | 54/96 | 37/96 |
| **ambos, da firma** | **0,468** | 52/96 | 34/96 |
| ambos, do acionista | 0,491 | 46/85 | 29/85 |

**O colapso é de 15,5% no melhor sentido e 11,3% no outro.** Compartilhar os
dois insumos deixa **52 dos 96 ainda além de 1,5×**, e só **13** passam a
concordar dentro de 1,1×.

**Em 39 dos 96 compartilhar piorou.** O crescimento sozinho não move nada — a
dispersão sobe de 0,554 para 0,559.

### Os casos que encerram a questão

| Ativo | razão antes | depois | `g` firma / acionista | fator firma / acionista |
|---|---:|---:|---|---|
| **POSI3** | 28,15× | **28,15×** | 5,0% / 5,0% | 1,00 / 1,00 |
| **PRIO3** | 0,17× | **0,17×** | 5,0% / 5,0% | 3,00 / 3,00 |
| LOGG3 | 0,04× | 0,03× | 5,0% / 5,0% | 0,62 / 0,50 |

POSI3 e PRIO3 já usavam **crescimento idêntico e fator idêntico** nas duas
vias, e mesmo assim os preços justos diferem por 28× e 5,9×. Não há o que
amarrar ali: os insumos já estão amarrados.

---

## 3. O que isso diz, e é estrutural

**As duas vias não são dois olhares sobre um modelo. São dois modelos
independentes**, e a identidade teórica que se esperava delas nunca foi
construída:

1. **Os fluxos não derivam um do outro.** O da firma é `NOPAT = EBIT × (1 − t)`,
   montado de umas linhas; o do acionista é o LPA **publicado**, de outras.
   Não existe em lugar nenhum a ponte `FCFE = FCFF − juros × (1 − t) + ΔDívida`
   que ligaria os dois — nem o termo de variação de dívida.
2. **`Ke` e `WACC` não estão ligados pela alavancagem.** O beta é regressão
   crua contra o Ibovespa e o peso da dívida vem do mercado; não há beta
   desalavancado ligando um ao outro. `FCFF/WACC ≡ FCFE/Ke` só vale quando
   estão, e aqui não estão.

Por isso 85% da dispersão sobrevive a compartilhar crescimento e ciclo: o que
resta não está nos insumos que as guardas medem, está na **definição do fluxo e
da taxa**.

---

## 4. O que isto autoriza decidir

**Autoriza descartar o caminho barato.** Amarrar crescimento e fator de base
entre as vias fecha 15,5% da discordância e piora 39 dos 96 casos. Não é o
conserto, e adotá-lo teria dado a impressão de que era.

**Autoriza nomear o conserto que resta.** Conciliar exige derivar uma via da
outra — `FCFE = FCFF − juros × (1 − t) + ΔDívida` — e ligar `Ke` a `WACC` por
um beta desalavancado. São duas reconstruções, não uma: a Porta 2 **e** o custo
de capital.

**E reordena a fila.** O beta *bottom-up* estava na Fase C do roteiro, depois da
ingestão da CVM. Ele é **pré-requisito** da conciliação, não sucessor: sem beta
desalavancado não há como amarrar as duas taxas, e sem as taxas amarradas a
identidade continua quebrada por construção.

**Não autoriza** tratar a divergência como limitação declarável. Dois modelos
que a teoria diz serem idênticos e que na prática diferem por 28× não são uma
escolha de método — é o motor se contradizendo, e continua sendo defeito
conhecido até ser fechado ou substituído por um caminho único.

---

## 5. O que fica em aberto

1. **A via do acionista para instituição financeira é caso à parte.** Ali não
   há valor da firma nem dívida líquida com sentido econômico, e a via do
   acionista **deve** permanecer um modelo independente — declarado como tal,
   sem pretensão de identidade.
2. **A ponte continua numericamente frágil** onde o capital próprio é fino, e
   é o problema que a pós-condição existe para conter. Um `FCFE` derivado
   corretamente o resolve por construção: é a mesma avaliação por uma rota que
   não passa pela subtração `EV − D`.
3. **O termo `ΔDívida` não existe hoje em lugar nenhum do motor**, e sem ele o
   `FCFE` derivado não fecha.
