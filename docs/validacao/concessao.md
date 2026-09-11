# D8 — a perpetuidade sobre um contrato que acaba

Medido em 10/09/2026.

```bash
dart run tool/concessao.dart   # grava concessao.json
```

---

## 0. A pergunta

O valor terminal do motor é perpétuo para todo ativo. Uma concessão —
transmissão, distribuição, saneamento, rodovia, ferrovia, aeroporto — tem prazo,
e no fim dele o ativo reverte ao poder concedente ou vai a nova licitação.
Descontar fluxo perpétuo de um contrato que acaba não é aproximação: é outra
empresa.

## 1. O estimador que parecia servir, e não serve

A fonte não publica prazo de concessão, e não haveria como publicar: uma
concessionária tem dezenas de contratos com vencimentos diferentes.

O que ela publica é a base de ativos e a amortização. Numa concessão o direito
de operar é registrado como intangível e amortizado **ao longo do prazo do
contrato** — de modo que `(imobilizado + intangível) ÷ D&A` parecia ser a vida
remanescente.

**Não é.** Medido:

| | mediana | p10 | p90 |
|---|---:|---:|---:|
| concessionárias (n=15) | 15,8 anos | 6,3 | 24,4 |
| as demais (n=92) | 9,2 anos | 3,7 | 19,5 |

A separação existe em agregado e desaparece no caso a caso — três das quinze
caem dentro do miolo das demais, e os exemplos individuais matam o estimador:

| Ativo | vida medida | o que se sabe do contrato |
|---|---:|---|
| **TAEE11** | **6,3 anos** | outorgas de transmissão até 2042 |
| WEGE3 | 14,3 anos | não tem concessão alguma |
| CMIG4 | 14,8 anos | distribuição até 2045 |
| ABEV3 | 12,5 anos | não tem concessão alguma |

A TAEE11 é o caso que fecha a questão: transmissão contabiliza a outorga como
**ativo financeiro**, não intangível amortizável, e a razão mede então o giro do
imobilizado operacional. **O indicador mede giro da base de ativos, não
vencimento de contrato.**

Sem prazo, não há como truncar a perpetuidade. Isso não é escolha: é ausência
de dado, e o registro dela vale mais que um número inventado.

## 2. O tamanho do que não se pode corrigir

Truncar uma perpetuidade em `L` anos remove a cauda, que vale
`((1+g)/(1+r))^L` do valor terminal. Com as taxas e os pesos terminais que o
motor produz para os quinze expostos:

| Se o contrato acabasse em | preço justo mediano ficaria em |
|---|---:|
| 10 anos | **0,80×** |
| 20 anos | 0,90× |
| 30 anos | 0,95× |

**O erro é de 5% a 20%, e não de ordem de grandeza.** A razão é aritmética: a
taxa de equilíbrio dos expostos está entre 9% e 13%, e a essa taxa a cauda além
do vigésimo ano já vale pouco. Uma concessão renovável de trinta anos é, para
efeito de desconto, quase uma perpetuidade.

Esse resultado é o que impede a correção de ser urgente — e é também o que
justifica declarar em vez de arbitrar.

## 3. O que o contrato nega de frente, e isso se corrige

A perpetuidade é uma afirmação sobre **quanto tempo** o fluxo dura. Há outra,
mais forte, que o motor fazia sobre os mesmos ativos: a de que o **retorno
excedente sobrevive para sempre**.

Cinco dos quinze recebiam essa exceção:

| Ativo | λ preservado | peso do terminal | subsetor |
|---|---:|---:|---|
| **CPFE3** | **0,2610** | 50,5% | Energia Elétrica |
| CMIG4 | 0,0008 | 40,6% | Energia Elétrica |
| MOTV3 | 0,0000 | 45,9% | Exploração de Rodovias |
| SBSP3 | 0,0000 | 45,0% | Água e Saneamento |
| TAEE11 | 0,0000 | 57,7% | Energia Elétrica |

A CPFE3 é o caso com conteúdo: **26% do excedente de retorno preservado para
sempre**, numa distribuidora cuja concessão será relicitada e cuja tarifa é
fixada por regulador para remunerar o capital **ao custo dele**, não acima.

O terminal neutro da
[decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) —
`ROIC_∞ = WACC` — é exatamente o modelo certo para esse negócio, e a exceção de
vantagem competitiva é exatamente o errado.

**Contrato de prazo determinado passa a ser bloqueio nomeado do excedente
perpétuo.** Não trunca nada, não inventa horizonte: recusa a única afirmação que
o contrato contradiz diretamente.

### O efeito

| | antes | depois |
|---|---:|---:|
| potencial mediano | −31,8% | −31,8% |
| potenciais positivos | 37 | 37 |
| **preços justos alterados** | — | **2** |

CPFE3 −5,8% e TAEE11 −2,5%. Os outros três já tinham `λ` nulo — a bandeira
estava ligada e não preservava nada, o que é a diferença entre
`moatApplied` e `λ` que a [decisão 36](../decisoes/036-decaimento-medido-do-excedente-na-perpetuidade.md)
criou justamente para expor.

## 4. A classificação é declarada, não inferida

Como a de [`CyclicalSectors`](../../packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart),
e pela mesma razão: **quem tem concessão é fato do contrato, não do dado.**

| Onde | O quê |
|---|---|
| chave de setor | `saneamento`, `infraestrutura` |
| termo de subsetor | `energia eletrica`, `agua e saneamento`, `exploracao de rodovias`, `transporte ferroviario`, `aeroportu`, `concessao` |

A comparação é sobre o rótulo normalizado, sem acento nem pontuação, porque a
fonte publica variantes do mesmo texto. `Exploração. Refino e Distribuição`
**não** entra: petróleo é concessão de exploração, e não de serviço público com
tarifa — o negócio não é relicitado, a reserva se esgota. É outro problema.

## 5. O que fica em aberto

1. **O horizonte continua infinito**, e é a maior premissa não verificada que
   sobra no terminal. Fechá-la exige o prazo médio ponderado das outorgas, que
   só existe em nota explicativa e em formulário de referência da CVM — dado da
   Fase B, não da brapi.
2. **A reversão indenizada não é modelada.** Ao fim da concessão o investimento
   não amortizado costuma ser indenizado, e isso é valor terminal positivo que
   o truncamento simples ignoraria. Modelar o prazo sem modelar a indenização
   trocaria um viés por outro.
3. **Geradora com concessão renovável em regime de cotas** não é a mesma coisa
   que transmissora com receita anual permitida, e a classificação atual trata
   as duas igual. Separá-las exige subsetor mais fino que o publicado.
