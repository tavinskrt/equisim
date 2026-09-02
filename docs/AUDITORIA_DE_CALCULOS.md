# Painel de Auditoria de Cálculos

Instrumento de demonstração da apuração: uma **segunda janela do navegador** que
mostra, em tempo real, o que acontece por baixo de cada número apresentado na
tela principal — os payloads trocados com a API, as fórmulas em formatação
acadêmica e a substituição de variáveis passo a passo.

Endereço: **`/#/logs`** · Atalho: botão **LOGS** no cabeçalho, ou
**"Abrir Painel de Logs de Cálculo"** no menu do perfil.

---

## Por que não há WebSocket nem SSE

O requisito original pedia que o backend transmitisse os eventos por WebSocket
ou SSE. **Este sistema não tem backend próprio.** O motor financeiro é
`packages/equisim_core`, um pacote Dart puro que roda dentro da própria
aplicação — a pureza é verificada por `test/purity_test.dart` —, e a única API
remota é a brapi.dev, de terceiros, que não tem como emitir os cálculos que ela
não executa.

Levantar um servidor só para reemitir eventos criaria uma peça de infraestrutura
que não participa do cálculo. Pior: o que ela retransmitiria seria uma **cópia**
do que aconteceu no navegador, e uma cópia pode divergir do original — que é
exatamente o risco que a auditoria existe para eliminar.

O equivalente fiel, no alvo web, é a **`BroadcastChannel`** do próprio
navegador: canal nomeado, mesma origem, entrega por *push* entre abas, com a
mesma semântica de assinatura de um SSE — e o evento sai de dentro do cálculo,
sem intermediário. O contrato de dados transmitido é exatamente o especificado.

Em Android, iOS e desktop não existe segunda janela; lá o canal degrada para
entrega local e o painel é empilhado sobre a própria aplicação, pela rota
registrada em `MaterialApp.routes`.

---

## Arquitetura

```
┌─ Janela principal (emissora) ──────────┐   ┌─ Janela /logs (inspetora) ──┐
│                                        │   │                             │
│  ValuationCascade.evaluate()           │   │  LogsPage                   │
│    └─ AuditRecorder.begin/step         │   │    └─ AuditBus (histórico)  │
│  ApiClient (Dio)                       │   │           ▲                 │
│    └─ AuditNetworkInterceptor          │   │           │                 │
│           │                            │   │           │                 │
│           ▼                            │   │           │                 │
│      AuditBus ──── BroadcastChannel ───┼───┼───────────┘                 │
│                    'equisim-audit-v1'  │   │                             │
└────────────────────────────────────────┘   └─────────────────────────────┘
```

| Arquivo | Papel |
|---|---|
| `packages/equisim_core/lib/src/audit/calculation_trace.dart` | Contrato de dados (`AuditEvent`, `CalculationTrace`), serialização e UUID v4 |
| `packages/equisim_core/lib/src/audit/audit_recorder.dart` | Coletor ambiente; desligado, custa uma comparação com `null` |
| `lib/src/usecases/compute_valuation.dart` (seção *Auditoria*) | Rastro de cada fórmula, montado a partir dos valores **já calculados** |
| `lib/audit/audit_bus.dart` | Barramento, anel de histórico e protocolo entre janelas |
| `lib/audit/audit_channel*.dart` | Transporte (`BroadcastChannel` na web, entrega local fora dela) |
| `lib/audit/audit_network_interceptor.dart` | Captura das idas à API, com credenciais mascaradas |
| `lib/presentation/audit/logs_page.dart` | Console de inspeção |

### Custo quando desligado

`AuditRecorder.begin` devolve `null` sem consumidor acoplado, e toda a
instrumentação vira `null?.step(...)`: nenhum objeto criado, nenhuma string
formatada. É o que permite deixar a instrumentação permanentemente no caminho do
cálculo em vez de mantê-la atrás de uma bifurcação que só é exercitada na
apresentação.

A chave é `auditEnabled` (`lib/audit/audit_bus.dart`): segue `kDebugMode` por
padrão e aceita `--dart-define=EQUISIM_AUDIT=true` para uma apresentação feita a
partir de build de release.

---

## Contrato de dados

```jsonc
{
  "transactionId": "uuid-v4",
  "timestamp": "ISO-8601",
  "endpoint": "/core/valuation/PETR4",   // ou o caminho da API, em eventos de rede
  "inputPayload":  { /* insumos resolvidos, ou requisição HTTP */ },
  "outputPayload": { /* resultado, ou resposta HTTP */ },
  "executionTimeMs": 142,
  "calculations": [
    {
      "formulaName": "Custo do capital próprio (CAPM)",
      "latexRepresentation": "K_e = R_f + \\beta \\cdot (R_m - R_f)",
      "mappedVariables": { "R_f (% a.a.)": 10.65, "beta": 1.18, "R_m - R_f (% a.a.)": 5.5 },
      "intermediateSteps": [
        "Passo 1: prêmio ajustado ao risco sistemático → 1,18 × 5,5% = 6,5%",
        "Passo 2: soma à taxa livre de risco → 10,7% + 6,5% = 17,1%"
      ],
      "finalValue": 17.14,
      "unit": "% a.a."
    }
  ]
}
```

Eventos de **rede** trazem `calculations` vazio — é o que os distingue dos
eventos de **cálculo**, sem precisar de um campo de tipo à parte.

### Amostra por trás de uma agregação

Fórmulas que resumem vários períodos num único número trazem um campo `sample`
adicional. Hoje é o caso da **normalização do fluxo-base**: a mediana decide a
banda inteira, e uma mediana apresentada sozinha não permite discutir se algum
exercício deveria ser expurgado da janela.

```jsonc
"sample": {
  "title": "Exercícios da amostra (fluxo de caixa livre)",
  "unit": "R$",
  "summary": 468000000,        // a mediana
  "summaryLabel": "mediana",
  "lowerBound": 234000000,     // m·(1−τ)
  "upperBound": 702000000,     // m·(1+τ)
  "selected": 702000000,       // F₀ efetivamente adotado
  "points": [
    { "label": "2021", "value": 380000000, "definesResult": false, "isObserved": false },
    { "label": "2023", "value": 468000000, "definesResult": true,  "isObserved": false },
    { "label": "2025", "value": 4445000000, "definesResult": false, "isObserved": true  }
  ]
}
```

`definesResult` marca **exatamente** o exercício central da amostra ordenada —
ou os dois centrais, quando a contagem é par. A marcação é feita pela posição
na ordenação, não pelo valor, para que exercícios repetidos não apareçam todos
como "a mediana". Ela é produzida pelo próprio normalizador, no ponto do
cálculo: o painel desenha, não recalcula.

Na seção **C** esse campo vira um gráfico de barras com a banda de aceitação ao
fundo, o exercício central destacado, o exercício observado marcado e — quando
houve winsorização — uma seta até onde o valor foi aparado. Abaixo do gráfico,
os mesmos números em texto selecionável, porque é isso que se copia para a
defesa. Um exercício muito fora de escala é desenhado **cortado**, com a marca
de eixo interrompido e o valor escrito ao lado: deixar a escala alcançá-lo
achataria a banda contra o eixo, que é justamente o que se precisa enxergar.

A justificativa do τ e a análise da fórmula de crescimento estão em
[validacao/normalizacao_fluxo_base.md](validacao/normalizacao_fluxo_base.md) e
[validacao/crescimento_log_linear.md](validacao/crescimento_log_linear.md).

### Fórmulas instrumentadas

Razão da unidade negociada · CAPM · WACC (ou sua degeneração no Ke) ·
normalização do fluxo-base (winsorização) · crescimento por regressão log-linear
· crescimento na perpetuidade · projeção e desconto do período explícito ·
valor terminal de Gordon · ponte do valor da firma ao valor por papel ·
múltiplo EV/EBITDA · valor patrimonial · margem de segurança e potencial de
valorização.

---

## Como demonstrar

```bash
flutter run -d chrome
```

1. Entre na aplicação e clique em **LOGS** no cabeçalho — abre a guia paralela.
2. Arraste as duas janelas para telas diferentes (ou lado a lado).
3. Opere normalmente na janela principal: escolher ativo, mudar a margem de
   segurança, ligar Monte Carlo, editar a meta.
4. Cada requisição e cada avaliação aparece na guia de auditoria no instante em
   que acontece. Expanda um item para ver as três seções: **A** requisição e
   resposta, **B** fórmulas renderizadas em TeX, **C** substituição de variáveis
   e decomposição aritmética.
5. Na seção **C**, a normalização do fluxo-base traz o gráfico dos exercícios
   que formaram a mediana — é onde se discute expurgar ou manter um período.

O painel aberto **depois** das primeiras consultas não abre vazio: ele pede um
*replay* à janela emissora, que responde com o anel de histórico (200 eventos).

Controles: **Limpar Logs** (apaga nas duas janelas), **Pausar Auto-scroll**,
**Exportar Auditoria (JSON)**, filtro Cálculos/Rede e busca por ativo ou fórmula.

---

## Segurança

Nenhum cabeçalho de autorização e nenhum parâmetro `token` entra no payload: a
URL passa pelo mesmo higienizador do log de diagnóstico
(`SanitizedLogInterceptor.sanitize`). O painel é feito para ser projetado numa
tela durante a apresentação.

Respostas maiores que 4.000 caracteres entram truncadas, com o tamanho original
declarado — o histórico de dez anos de dez ativos passa de dois megabytes, e
guardar isso por requisição encheria o anel de memória para mostrar algo que
ninguém lê rolando.

---

## Testes

| Arquivo | Cobre |
|---|---|
| `packages/equisim_core/test/audit_test.dart` | Coletor ligado/desligado, contrato JSON de ida e volta, formato do UUID, e — o principal — que **instrumentar não move o número**: o preço justo com e sem auditoria é idêntico |
| `test/presentation/logs_page_test.dart` | Arranque na rota `/logs`, chegada em tempo real, as três seções, filtros, limpeza e auto-scroll |
