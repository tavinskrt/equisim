# Ingestão da CVM — itens A1.1 a A1.6

Executado em 11/09/2026. Este documento registra o que foi **construído** e o
que a construção mediu; a conferência de campos que a antecedeu está em
[cvm_conferencia.md](cvm_conferencia.md).

```bash
python tool/cvm_baixar.py --de 2010 --ate 2025   # ~750 MB, em data/cvm
dart run tool/cvm_ponte.dart data/cvm            # grava ponte_cvm.json
dart run tool/cvm_ingerir.dart data/cvm          # grava data/cvm_exercicios.json
dart run tool/cvm_conferir.dart data/cvm         # identidades sobre um ano
```

---

## 0. Onde cada peça mora, e por quê

O núcleo é Dart puro, sem I/O e sem dependência — travado por
`purity_test.dart`. A CVM, por outro lado, **não é API de tempo real**: é
publicação anual em massa, de 750 MB. As duas coisas juntas definem a divisão:

| peça | onde | por quê |
|---|---|---|
| `CvmBridge` — ticker↔CNPJ | **núcleo** | é regra, e regra errada avalia a empresa trocada |
| `CvmChart` — plano de contas | **núcleo** | é onde se erra em silêncio; precisa de teste |
| `receiptDate`, `treasuryShares`, `totalAssets` | **núcleo** | são campos do domínio |
| download, descompactação, CSV | **ferramenta** | I/O, e roda quando se atualiza a base, não a cada avaliação |

A base bruta e o JSON de saída ficam **fora do git** (`data/cvm/`,
`data/cvm_exercicios.json`): são dado de terceiro, reproduzíveis pelo
baixador, e 750 MB não pertencem ao histórico deste repositório.

---

## 1. A1.1 — a ponte, 98,9%

`CvmBridge` resolve em quatro regras, parando na primeira que responde:
código do FCA com formato de ticker, propagação pela raiz, nome idêntico, e a
tabela declarada. Sobre 6.676 linhas de sete anos de FCA:

| | |
|---|---:|
| linhas de FCA | 6.676 |
| em branco | 2.720 (**40,7%**) |
| descartadas pelo formato (`25585`, `000000`, `ADR`) | 433 |
| códigos com CNPJ único | 647 |
| **ambíguos** | **0** |
| **universo resolvido** | **371 / 375 = 98,9%** |
| companhias distintas | 293 |
| conflitos de raiz | **0** |

Restam quatro, todos declarados em `CvmBridge.semPonte`: `FASA3`, `LUXM4`,
`OBTC3` — sem companhia correspondente em 2024, prováveis deslistagens que a
carga histórica deve alcançar — e `MAPT3`, que fica de fora **de propósito**.

### Dois defeitos que os testes pegaram

**`B3SA3` tem dígito na raiz.** A primeira versão do filtro exigia
`^[A-Z]{4}[0-9]{1,2}$` e descartava a própria B3 como se fosse lixo de
preenchimento — a raiz dela é `B3SA`. O que separa ticker de código CVM é
**começar por letra**, não ser todo de letras. Foi por causa disso que a
conferência anterior mediu 95,7% e a implementação mede 98,9%.

**O veto era comentário.** `semPonte` documentava que `MAPT3` não deveria ser
resolvido — o nome dele na fonte de preços é "CIA MARCOPOLO", que casa com
`MARCOPOLO S.A.`, **mas a Marcopolo negocia como POMO3 e POMO4**. A lista
existia e o código não a consultava: na primeira execução o `MAPT3` foi para
o CNPJ da Marcopolo, ao lado de `POMO3` e `POMO4`. Agora é veto, antes de
qualquer regra.

E ganhou a **regra geral** que o teria pego sozinho:
`CvmBridge.conflitosDeRaiz` denuncia companhia alcançada por duas raízes
distintas. Ela não remove nada — a Natura mudou de `NATU` para `NTCO`
legitimamente —, devolve o conflito para quem carrega decidir. Hoje: **zero**.

---

## 2. A1.2 — o leitor do plano de contas

`CvmChart` detecta o layout e resolve conta por **evidência**, não por tabela
de códigos. Onde o layout não tem o conceito, devolve `null`.

**Validado em dois níveis.** Dezenove testes sobre linhas sintéticas, com os
casos exatos que a conferência expôs; e a execução sobre **5.838 exercícios de
822 companhias** (DFP e ITR de 2022 e 2023):

| medida | resultado |
|---|---|
| sem ativo total | **0** |
| sem lucro líquido | **0** |
| sem patrimônio líquido | **0** |
| EBIT indevido em banco ou seguradora | **0** |
| corporativo sem EBIT | **0** |
| **identidade ativo = passivo** | **5.818 / 5.820 = 99,97%** |

A identidade de balanço é a **conferência analítica que a §2.17 registrava
como impossível**. Ela valida o leitor, não a companhia: se a soma do plano
não fechasse, seria porque a leitura pegou a conta errada.

Layouts encontrados na amostra: 5.538 corporativo, 295 intermediação
financeira, 5 seguradora.

---

## 3. A1.3 — consolidado com recuo para individual

Companhia sem controlada arquiva **só individual** — Sanepar, Comgás, Coelba,
Elektro. Sobre os dois anos ingeridos, **2.107 exercícios** vieram por recuo, e
**nenhum** ficou sem DRE.

---

## 4. A1.4 — publicidade observada

`PointInTimeView.isPublished` passa a preferir `FundamentalsSnapshot.
receiptDate`. Sem ela, recua para a presunção de 90 dias, que continua
configurável.

A diferença é material e não é cosmética. O Banco do Brasil entregou o DFP de
2024 em **19/02/2025**; a presunção só o admitiria em **31/03**. Numa coorte de
março, isso é a diferença entre avaliar com o exercício mais recente e avaliar
com o anterior.

E corrige nos dois sentidos: a defasagem máxima medida é de **472 dias**, e
nesses casos a presunção dava por público um documento que ainda não existia.

**Reapresentação: 12,2%** dos 5.838 documentos têm `VERSAO > 1`.

> **Decisão de carga, e ela é uma escolha.** A ingestão adota a **última
> versão** de cada documento, que é o número correto conhecido hoje. Isso
> injeta conhecimento futuro numa avaliação datada. A data de recebimento de
> cada versão fica gravada, de modo que uma carga *point-in-time* estrita —
> a versão vigente na data da coorte — é possível e não foi feita.

---

## 5. A1.5 — contagem líquida de tesouraria

`FundamentalsSnapshot.sharesNetOfTreasury` subtrai a tesouraria da contagem
integralizada. Ação em tesouraria não recebe dividendo e não vota; dividir o
capital próprio pela contagem bruta atribui valor a papel que não o tem.

Na amostra de dois anos, **1.677 exercícios** têm tesouraria maior que zero.

O método nunca devolve resultado não positivo: tesouraria maior que a base é
dado corrompido, e devolver zero produziria divisão por zero adiante.

**O que ainda não foi feito:** ligar essa contagem ao divisor da ponte por
papel. Isso depende do A3 — a contagem que forma o preço vem do valor de
mercado, e cruzá-la com a da CVM é o que fecha a §1.7.

---

## 6. A1.6 — todos os anos, e o viés de sobrevivência

O baixador cobre 2010 até o ano corrente, e pula ano não publicado sem falhar.
Baixa apenas o que o motor consome — DMPL e DVA somam 400 MB por ano e nada
os usa.

**A medida que importa**, sobre os dois anos já ingeridos:

| | |
|---|---:|
| exercícios | 5.838 |
| companhias distintas | **822** |
| com ticker no universo de hoje | 2.301 (39,4%) |
| **fora do universo de hoje** | **3.537 (60,6%)** |

Sessenta por cento dos exercícios são de companhias que o universo atual não
lista. **É exatamente o viés de sobrevivência da §1.3**, e ele sai da amostra
quando a validação passar a usar esta base em vez do universo vivo.

---

## 7. O que o gate pegou

Três rodadas de auditoria, **cinco defeitos** no código desta rodada. Todos em
código novo, e nenhum deles apareceu nos números — os totais da §2 são
idênticos antes e depois das correções, o que é a assinatura de defeito de
precisão: ele não erra hoje, erra quando a entrada mudar.

| defeito | consequência |
|---|---|
| `soma += l.value` no CapEx | acúmulo em ponto flutuante numa conta que alimenta a taxa de reinvestimento |
| `(value * 100).round()` como correção | converter de volta a partir de `double` presume que ele esteja limpo |
| **escala depois do arredondamento** | `1.0005` em escala MIL são R$ 1.000,50; arredondar antes dava R$ 1.000,00 |
| `at != 0` | ativo total de 1e-14 estouraria a razão relativa e inventaria balanço que não fecha |
| `DateTime.utc` só de um lado | comparar instante UTC com data local faz a publicidade depender do fuso da máquina |

A conversão final vai **do texto do CSV ao inteiro**, sem ponto flutuante:
`CvmAccountLine.doTexto` aplica a escala antes de arredondar, em `BigInt`, e
recusa o que não couber em `int`. O construtor que aceita `double` passou a
se chamar `CvmAccountLine.aproximada`, porque é o que ele é.

E a publicidade compara **dia civil** — ano, mês e dia —, nunca instantes: as
datas chegam de origens diferentes e um `DateTime` local e um UTC do mesmo dia
são instantes distintos.

## 8. O que fica em aberto

- **A ponte é de hoje.** `ponte_cvm.json` mapeia os 375 tickers vivos. Os 3.537
  exercícios de companhias deslistadas **não têm ticker**, e sem ele não há
  série de preços para confrontar. Usá-los na validação exige uma fonte de
  preço histórico dessas companhias — trabalho do A3.
- **A ingestão não substitui a brapi ainda.** Ela produz um JSON paralelo; o
  motor continua lendo o que sempre leu. Ligar as duas exige o D2, a camada
  multi-fonte com procedência, que não foi feita nesta rodada.
- **CapEx segue aproximado.** O leitor soma as linhas de `6.02.*` que
  mencionem imobilizado ou intangível — a única parte de `CvmChart` que
  depende de texto livre, e por isso a única com cobertura de 86% em vez de
  100%.
- **Duas identidades de balanço não fecham** em 5.820. Não investigadas.
