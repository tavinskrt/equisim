---
numero: 154
titulo: A logo da empresa acompanha o ticker, vinda da brapi, com as iniciais no lugar quando falta
status: aceita
origem: voce
data: 2026-10-28
citacao: >
  Existe alguma chance da gente conseguir colocar a logo das empresas dos
  tickers como ícone de cada um, pra ficar mais bonito na UI?
afeta:
  - src/ui/ticker-logo.tsx
  - src/ui/sheet.tsx
  - src/features/study/portfolio-column.tsx
  - src/features/study/asset-picker-sheet.tsx
  - src/features/shell/command-palette.tsx
  - src/features/asset/asset-xray.tsx
  - src/features/backtest/per-asset-card.tsx
  - src/features/valuations/valuations-page.tsx
  - src/features/manual/manual-page.tsx
  - scripts/capture-screens.ts
  - scripts/qa/advisor/rules.ts
  - docs/motor/07-aplicativo.md
  - test/ui/ticker-logo.test.tsx
substitui: []
---

## Contexto

O ticker aparecia só como texto em todas as telas. O pedido foi pôr a logo da
empresa ao lado dele. A logo não entra em conta nenhuma: é identificação
visual, e o que precisava ser decidido era **de onde ela vem** e **o que a tela
mostra quando ela não vem**.

A brapi, fonte de mercado do projeto desde a decisão 0, já publica as logos: o
`/v2/stocks/profile` devolve `logoUrl`, e o endereço segue o padrão
`https://icons.brapi.dev/icons/<TICKER>.svg` (ver
`test/fixtures/brapi_profile_petr4.json`). A FAQ da brapi diz que o recurso
está em todos os planos, inclusive o gratuito, "sem custo adicional", e que as
logos "são fornecidas para uso em contexto financeiro".

## Decisão

**Cada ticker da interface leva a logo da empresa, carregada da brapi pelo
navegador, e as duas primeiras letras da raiz do ticker no lugar dela quando a
imagem não carrega.**

1. O endereço é montado a partir do ticker, e não lido do perfil: ler do perfil
   gastaria uma requisição da cota da brapi por ativo listado, e a busca e o
   seletor listam centenas.
2. A imagem é carregada pelo `<img>` do navegador, preguiçosa (`loading="lazy"`)
   e sem `Referer`: a brapi recebe o ticker pedido, e não a página do Equisim.
3. Falhou uma vez, o ticker fica nas iniciais pelo resto da sessão.
4. A marca é decorativa (`aria-hidden`): o ticker continua escrito ao lado.
5. Aparece no Estudo, no seletor de ativos, na busca (Ctrl/⌘ + K), no título
   do Raio-X, no desempenho por ativo do Backtest, em Meus valuations e no
   cabeçalho de Simular minhas premissas.

## Consequências aceitas

- **Dependência nova de rede, em tempo de execução**, de um domínio da brapi
  (`icons.brapi.dev`) que não passa pelo proxy nem pelo cliente HTTP do
  aplicativo: não conta cota, não entra no painel de logs e não tem cache
  próprio além do HTTP do navegador. Fora do ar, a tela mostra as iniciais e
  nada mais muda.
- **Logo é marca registrada da empresa.** O uso é o de identificação nominativa
  do emissor, ao lado do próprio ticker, num contexto financeiro — o uso que a
  brapi declara. Nenhuma logo é copiada para o repositório.
- **Empacotar as logos no build foi descartado**: faria do repositório
  redistribuidor de marcas de terceiros, envelheceria a cada troca de
  identidade visual e acrescentaria centenas de arquivos para um ganho só de
  disponibilidade sem rede.
- **Outras fontes foram descartadas**: a Logo API gratuita da Clearbit foi
  desligada pela HubSpot em dezembro de 2025. A sucessora que ela indica, a
  logo.dev, tem chave publicável feita para o navegador e busca por ticker com
  sufixo de bolsa, mas exige cadastro, impõe limite por minuto e por IP e, em
  projeto comercial no plano gratuito, um link de atribuição na tela — tudo
  isso por uma cobertura da B3 que a documentação não declara, contra uma
  fonte que o projeto já usa. Os sites de análise brasileiros não oferecem
  API nem licença.
- **As iniciais repetem entre empresas** (`BBAS3` e `BBDC4` são ambas `BB`):
  servem de lugar reservado, e o ticker ao lado é que identifica.
- **A captura de tela usa logos sintéticas**, e `TAEE11` responde 404 de
  propósito para mostrar as iniciais; o prompt da lente `tela` registra isso.
