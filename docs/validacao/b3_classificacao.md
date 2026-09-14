# A classificação setorial oficial da B3 — item A5

Medido em 14/09/2026. Ferramentas: `tool/b3_complemento_baixar.py`,
`tool/b3_empacotar.dart` e `tool/padrao_ligar.dart`.
[Decisão 87](../decisoes/087-o-setor-e-o-da-b3-por-emissor.md).

## 1. O que estava errado

A fonte de preços classifica **papel a papel**, e deixa buracos. As
[limitações §2.14](limitacoes.md) registravam três bancos sem setor — BRSR6,
PINE4 e SANB4 — que escapavam da Porta 1. A medição mostrou que o buraco é maior:
**51 tickers do universo** mudam de porta quando o setor passa a vir da B3, e
quase todos chegavam **sem setor nenhum** da fonte — classes secundárias de
emissores que a fonte classifica na classe principal (KLBN4, BRAP4, USIM6, TAEE4,
ENGI4, SANB4), e emissores inteiros sem perfil.

## 2. A fonte

O `GetDetail` do portal de empresas listadas devolve, por emissor, o texto
`Setor / Subsetor / Segmento`. Baixado para os 297 emissores do universo:
**297 de 297 classificados**, em 11 setores econômicos.

| setor econômico | emissores |
|---|---:|
| Consumo Cíclico | 78 |
| Bens Industriais | 42 |
| Financeiro | 41 |
| Utilidade Pública | 35 |
| Materiais Básicos | 27 |
| Consumo não Cíclico | 22 |
| Saúde | 20 |
| Petróleo. Gás e Biocombustíveis | 12 |
| Tecnologia da Informação | 12 |
| Comunicações | 6 |
| Outros | 1 |

## 3. A Porta 1 não pode pegar o setor Financeiro inteiro

A B3 põe em **Financeiro** 11 emissores de exploração de imóveis — shopping
centers como ALOS3 e MULT3 — e 4 holdings diversificadas, como ITSA4. Nenhum
deles capta depósito, e o passivo deles é financiamento de verdade. A Porta 1
entra por subsetor: **Intermediários Financeiros** (18), **Previdência e Seguros**
(5) e **Serviços Financeiros Diversos** (2). A taxonomia da fonte continua
valendo no recuo, para emissor que a B3 não classifica.

## 4. As portas que mudam

Das 51 mudanças, todas no sentido de ganhar uma porta que faltava:

| porta | tickers | exemplos |
|---|---:|---|
| financeira | 11 | ABCB10, BRSR5, BRSR6, PINE4, SANB4, BMIN4, BPAC5 |
| cíclica | 23 | BRAP4, UNIP6, FESA4, KLBN4, USIM6, RANI3, RAIZ4, LUPA3 |
| concessão | 17 | TAEE4, ENGI4, ALUP11, SAPR11, AXIA7, EQPA5, ENMT4 |

**Seis casos saem de uma taxonomia para outra, e não do vazio:** HAGA3
(`construcao-e-imobiliario` → Siderurgia e Metalurgia), RAIZ4
(`consumo-nao-ciclico` → Exploração, Refino e Distribuição), RANI3 (`materiais`
→ Embalagens) e três prestadoras de serviço de petróleo — LUPA3, OPCT3, OSXB3 —,
de `bens-industriais` para Petróleo, Gás e Biocombustíveis. As seis ganham a
precedência do ciclo.

## 5. O efeito, na mesma execução

Sobre os 128 avaliados, montagem do aplicativo antes e depois, na medição final
da Fase 1 ([fase1_padrao.md](fase1_padrao.md)):

| | antes | com o setor da B3 |
|---|---:|---:|
| potencial mediano | −47,7% | **−45,5%** |
| mediana do `\|Δ\|` | | 0,0% |
| `\|Δ\|` > 10 p.p. | | 3 |
| correlação de postos | | 0,967 |

Os três que se movem são classes que ganharam a precedência do ciclo, e passam a
ter a base normalizada pelo ciclo em vez da tendência:

| ativo | antes | depois |
|---|---:|---:|
| UNIP6 | −77,5% | −7,2% |
| BRAP4 | −70,7% | −12,3% |
| FESA4 | −60,6% | −43,5% |

**Os três bancos não se movem.** BRSR6, PINE4 e SANB4 passam pela Porta 1 — o
teste de integração confere o aviso —, mas o preço justo sai idêntico. A Porta 3
já os mandava à via do acionista, e a outra diferença da Porta 1, a isenção da
realavancagem, só age com o beta desalavancado, que o aplicativo não resolve
(item B11 do plano). O defeito era de roteamento; o efeito, na montagem do
aplicativo, é nulo.

## 6. O que fica

- A classificação é de 14/09/2026. Mudança de setor de emissor exige baixar e
  empacotar de novo.
- **O prior setorial do beta passa a agrupar por setor econômico da B3** onde
  ele é calculado — nas ferramentas de diagnóstico, porque o aplicativo não o
  calcula (B11).
- `Outros` (1 emissor) não entra em porta nenhuma.
