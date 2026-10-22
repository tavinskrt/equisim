---
numero: 132
titulo: A cópia dos insumos da avaliação passa por um lugar só, e nenhum campo se perde
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Ao executar mudanças no código, realize a execução das lentes e correção dos
  problemas apontados por elas.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_inputs_copy_test.dart
  - tool/backtest_valuation.dart
  - tool/gabarito_cascata.dart
  - tool/multiplos.dart
  - docs/validacao/multiplos.json
  - docs/validacao/backtest_trimestral.json
  - docs/validacao/habilidade_trimestral.md
  - docs/validacao/recusas_custo.md
substitui: []
---

## Contexto

Achado ao conferir a integridade do rastro (decisão 131): para dizer no evento
com que insumos a cascata rodou, era preciso saber que os insumos chegavam à
cascata inteiros — e não chegavam.

`ValuationInputs` tem 34 campos e **nenhuma cópia genérica**, por escolha
registrada no gabarito: as imposições de diagnóstico não são do aplicativo.
Cada cópia repetia a lista de campos à mão, e **os campos acrescentados nas
rodadas recentes não foram lembrados em todas**:

- **`withProjectionYears`**, que a concessão que acaba dentro da projeção usa
  **em produção** (decisão 88), perdia os múltiplos de pares, o valor do
  minoritário e a tradução do cenário. **As concessionárias ficavam sem a
  segunda leitura por múltiplos na tela do aplicativo**;
- **`withRiskFreeShift`**, da varredura do nível da curva, perdia os mesmos três;
- **`_comFundamentos` e `_semSerie`**, do backtest, e **`_impor`**, do gabarito,
  perdiam a composição declarada da unit (decisão 106), a taxa de referência do
  crédito (item B10) e a janela do beta (decisão 111). A leitura ancorada do
  backtest e as montagens de diagnóstico do gabarito rodavam outro divisor nas
  units, e sem o aviso de janela curta do beta.

## Decisão

1. **Uma cópia só, `_copy`, lista todo campo uma vez**, e os métodos públicos
   passam por ela: `withProjectionYears`, `withRiskFreeShift`,
   `withFundamentals`, `withoutPrices`, `withPeerMultiples`, `withContextNotes`
   e `withOverrides` — este para as imposições de diagnóstico, que continuam
   fora do aplicativo.
2. **Um teste preenche os 34 campos com valores fora do padrão** e confere que
   cada método preserva todos os que não troca. Ao acrescentar um campo, ele é
   acrescentado em `_copy` e no teste.
3. **As ferramentas que produzem medição versionada usam os métodos do núcleo**:
   o backtest, o gabarito e a medição dos múltiplos.

## O que foi medido

- **Em produção, quatro concessionárias ganham a segunda leitura** que perdiam:
  EGIE3, EQTL3, TAEE11 e TAEE4. Na medição do B5 a triangulação vai de 93 para
  97 ativos. **Nenhum preço justo muda**: os três campos perdidos não entram no
  preço.
- **No gabarito, nenhum preço justo muda** em nenhuma montagem. Nas de
  diagnóstico — via da firma, via do acionista, imposições —, os avisos mudam em
  5, 10 e 7 ativos: a ALUP11 passa a ser descrita pela composição declarada, e a
  CYRE4 ganha o aviso de janela curta do beta. Nos casos medidos, a razão
  inferida coincidia com a declarada, e por isso o preço não se moveu.
- **No backtest, as leituras secundárias mudam muito**, e ele foi reexecutado.
  A leitura ancorada e o contrafactual sem o corte de liquidez passavam pelas
  cópias com defeito. Em 393 e 1.159 observações o potencial muda, e em várias
  o erro era o divisor da unit aplicado à espécie: a SAPR4 de 30/06/2021 tinha
  justo ancorado de R$ 5,94 contra R$ 30,15 do anual, e agora tem R$ 29,69.
  **Nenhum veredito muda.** A ancorada continua fora do padrão pela regra da
  decisão 98 (diferença de IC de +0,021, `t` corrigido de 0,27 contra 2,70). A
  recusa por liquidez fica pela razão da decisão 95 (soltos em −28,1% contra
  −54,3%). O critério do R3 não passa por essas cópias e fica em 0,052 com
  0,30.

## Consequências aceitas

**O teste lista os campos, e depende de quem acrescenta um lembrar dele.** A
alternativa — reflexão — não existe no Dart puro. A diferença para antes é que
agora há **um** lugar a lembrar, e um teste que falha se a cópia esquecer um
campo que ele conhece.

**Outras ferramentas de diagnóstico ainda copiam à mão** (`dcf_reverso`,
`minoritario` e afins). Elas produzem medições pontuais já registradas, e
migram quando forem reexecutadas.
