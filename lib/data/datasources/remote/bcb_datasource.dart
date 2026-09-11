import 'package:equisim_core/equisim_core.dart';

import '../../dtos/brapi_dtos.dart' show BrapiJson;
import '../../network/api_client.dart';

/// Séries do Sistema Gerenciador de Séries Temporais do Banco Central.
///
/// API aberta: sem token, sem cadastro, sem limite relevante. Preferida à
/// brapi para dados macro por ser fonte oficial e citável na monografia.
class BcbDatasource {
  /// Cliente HTTP compartilhado, já com interceptors de auditoria.
  final ApiClient client;

  /// Declara o datasource sobre um [ApiClient] configurado.
  BcbDatasource(this.client);

  /// CDI diário (SGS 12) — taxa livre de risco do CAPM e do índice de Sharpe.
  static const int seriesCdiDaily = 12;

  /// IPCA mensal (SGS 433) — usado para a taxa real e para o crescimento
  /// nominal da perpetuidade.
  static const int seriesIpcaMonthly = 433;

  /// IBC-Br **dessazonalizado** (SGS 24364) — proxy mensal do produto real.
  ///
  /// É a parcela real do teto da perpetuidade, que até a decisão 25 era a
  /// constante de 3% em `GrowthEstimator`. Medido sobre 10 anos, o índice dá
  /// 1,45% ao ano.
  ///
  /// **Dessazonalizado, e não a série bruta (24363):** aquela oscila entre 103 e
  /// 118 dentro do mesmo ano, e a razão entre duas pontas mediria sazonalidade,
  /// não crescimento.
  ///
  /// É **índice**, não taxa. [series] divide por 100 como faz com as demais, o
  /// que não atrapalha: só razões entre pontos são usadas, e o fator cancela.
  static const int seriesIbcBrMonthly = 24364;

  /// Frequência de cada série do SGS.
  ///
  /// **A série carrega a própria base desde a decisão 59**, e o mapeamento
  /// mora aqui porque é aqui que se sabe qual código do SGS foi pedido: 12 é
  /// CDI diário em dias úteis, 433 e 24364 são mensais.
  static TimeBasis basisOf(int seriesId) =>
      seriesId == seriesCdiDaily ? TimeBasis.businessDaily : TimeBasis.monthly;

  /// Busca uma série no intervalo informado.
  ///
  /// A API devolve `{"data":"02/01/2024","valor":"0.043739"}`, com a data em
  /// `dd/MM/yyyy` e o valor em **percentual do período**, como texto. Aqui vira
  /// fração, que é a unidade usada em todo o domínio.
  Future<Result<RateSeries>> series(int seriesId, DateRange range) async {
    final response = await client.getJson(
      '${client.config.bcbBaseUrl}/bcdata.sgs.$seriesId/dados',
      query: {
        'formato': 'json',
        'dataInicial': _brDate(range.start),
        'dataFinal': _brDate(range.end),
      },
      heavy: true, // dez anos de CDI diário passam de 2.500 pontos
    );

    return response.flatMap((body) {
      if (body is! List) {
        return Err(ComputationFailure(
          'Resposta inesperada da série SGS $seriesId.',
        ));
      }

      final pontos = <RatePoint>[];
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;
        final date = _parseBrDate(BrapiJson.asString(item['data']));
        final percent = BrapiJson.asDouble(item['valor']);
        if (date == null || percent == null) continue;
        pontos.add(RatePoint(date: date, rate: percent / 100.0));
      }

      if (pontos.isEmpty) {
        return Err(InsufficientData(
          'Série SGS $seriesId sem dados no período solicitado.',
        ));
      }
      return Ok(RateSeries(pontos, basis: basisOf(seriesId)));
    });
  }

  /// Atalho para a série do CDI no intervalo.
  ///
  /// A taxa vem **diária em base 252 dias úteis**; anualizar exige composição
  /// por `RateSeries.annualized()`, nunca multiplicação.
  ///
  /// Nenhum caminho de produção passa por aqui — `MarketMacroRepository` chama
  /// [series] com [seriesCdiDaily] direto, para aplicar cache na mesma etapa.
  /// Preservado como API legível do datasource e exercitado pelos testes.
  Future<Result<RateSeries>> cdi(DateRange range) =>
      series(seriesCdiDaily, range);

  /// Atalho para a série do IPCA no intervalo.
  ///
  /// A taxa vem **mensal**: anualizar exige `annualized(periodsPerYear: 12)`.
  /// Como [cdi], é contornado em produção pelo repositório.
  Future<Result<RateSeries>> ipca(DateRange range) =>
      series(seriesIpcaMonthly, range);

  static String _brDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  static DateTime? _parseBrDate(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }
}
