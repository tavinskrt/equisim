import { ArrowLeft, SearchX } from 'lucide-react';
import { useNavigate, useParams } from 'react-router';

import { useProfile } from '../../app/hooks';
import { Ticker } from '../../core';
import { IconButton } from '../../ui/button';
import { Card } from '../../ui/card';
import { EmptyState } from '../../ui/feedback';
import { Reveal } from '../../ui/motion';
import { TickerLogo } from '../../ui/ticker-logo';
import { StudyMembership } from '../study/study-membership';
import { XRayBody } from './asset-xray';

/**
 * **A página do ativo** (decisão 155): o Raio-X em `/ativo/:ticker`, com a
 * largura da tela inteira, no lugar do painel lateral que abria por cima da
 * área corrente.
 */
export function AssetPage() {
  const params = useParams();
  const ticker = params['ticker'] === undefined ? null : Ticker.tryParse(params['ticker']);
  if (ticker === null) {
    return (
      <Card>
        <EmptyState icon={<SearchX aria-hidden className="size-6" />} title="Ativo não reconhecido" message={`"${params['ticker'] ?? ''}" não é um código de negociação da B3.`} />
      </Card>
    );
  }
  // A chave refaz a página ao trocar de ativo pela busca: estado nenhum passa de um ativo ao outro.
  return <AssetView key={ticker.value} ticker={ticker} />;
}

function AssetView({ ticker }: { ticker: Ticker }) {
  const navigate = useNavigate();
  const profile = useProfile(ticker);
  const name = profile.status === 'success' && profile.data !== null ? profile.data : null;

  // Quem chegou navegando volta para onde estava — o Estudo reaparece como
  // ficou —; quem abriu o link direto não tem para onde voltar, e vai ao Estudo.
  // O mesmo critério do Voltar de Simular minhas premissas.
  const back = () => {
    const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
    if (idx > 0) navigate(-1);
    else navigate('/estudo');
  };

  return (
    <div className="relative">
      {/* A aura do topo, à moda do Linear: luz da marca atrás do cabeçalho, fraca o bastante para não competir com o texto. */}
      <div aria-hidden className="asset-aura pointer-events-none absolute inset-x-0 -top-4 h-64" />
      <Reveal className="relative">
        <header className="mb-5 flex flex-wrap items-center gap-x-3 gap-y-3">
          <IconButton label="Voltar" onClick={back}>
            <ArrowLeft aria-hidden className="size-5" />
          </IconButton>
          <TickerLogo ticker={ticker} size="xl" />
          <div className="min-w-0 flex-1 basis-48">
            <p className="eyebrow">Raio-X</p>
            <h1 className="text-title font-semibold tracking-tight text-fg">{ticker.value}</h1>
            <p className="truncate text-body-sm text-fg-2">
              {name === null ? 'Avaliação pelo fluxo de caixa descontado, com as premissas à vista' : `${name.name}${name.sector.isUnknown ? '' : ` · ${name.sector.label}`}`}
            </p>
          </div>
          <StudyMembership ticker={ticker} />
        </header>
      </Reveal>
      <div className="relative">
        <XRayBody ticker={ticker} />
      </div>
    </div>
  );
}
