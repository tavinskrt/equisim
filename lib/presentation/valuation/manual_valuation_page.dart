import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/fin_amount.dart';
import '../shared/domain_copy.dart';
import '../shared/ui_kit.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'manual_copy.dart';
import 'normalization_panel.dart';

/// Largura a partir da qual os campos e o resultado ficam lado a lado, em dp.
///
/// Abaixo dela o resultado desce para depois dos campos, e o preço justo do
/// usuário fica numa barra fixa no rodapé: quem edita um campo no celular
/// precisa ver o número mudar sem rolar a tela.
const double _larguraDeDuasColunas = 960;

/// **Editar valuation: o cálculo do usuário** (decisão 147).
///
/// Os campos abrem com os números do motor para o ativo — o lucro de partida,
/// o crescimento, a taxa de desconto, a perpetuidade, o reinvestimento —, e o
/// usuário troca o que discordar. A conta é a do motor, congelada em
/// [ValuationResult.manual]: sem troca, o preço é o do motor ao centavo; com
/// troca, muda só o que foi trocado.
///
/// **O preço do usuário não herda a validação.** A faixa calibrada e a
/// habilidade medida são do preço do motor, e a tela diz isso no rodapé.
class ManualValuationPage extends StatefulWidget {
  /// A avaliação do motor, com a conta congelada.
  final ValuationResult result;

  /// Premissas com que a tela abre. **O aplicativo não o usa** — a tela abre
  /// nos números do motor —; existe para o teste e para a captura da lente
  /// `tela`, que precisam mostrar a tela já editada.
  final ManualPremises? inicial;

  /// Declara a tela. [result] precisa trazer [ValuationResult.manual].
  const ManualValuationPage({super.key, required this.result, this.inicial});

  @override
  State<ManualValuationPage> createState() => _ManualValuationPageState();
}

class _ManualValuationPageState extends State<ManualValuationPage> {
  late ManualPremises _p;

  /// O campo que "o que o preço de hoje supõe" resolve.
  ManualField _alvo = ManualField.discountRate;

  /// A última resposta de "o que o preço de hoje supõe", ou `null`. Qualquer
  /// troca de campo a apaga: ela respondia às premissas de antes.
  ManualSolution? _resposta;

  ManualValuation get _m => widget.result.manual!;

  @override
  void initState() {
    super.initState();
    _p = widget.inicial ?? _m.motorPremises;
  }

  void _trocar(ManualPremises p) => setState(() {
        _p = p;
        _resposta = null;
      });

  void _resolver() =>
      setState(() => _resposta = _m.solve(_alvo, _p));

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final avaliacao = m.evaluate(_p);
    final degraus = m.attribution(_p);
    final alterado = degraus.isNotEmpty;
    final largo = MediaQuery.sizeOf(context).width >= _larguraDeDuasColunas;
    final saida = avaliacao.valueOrNull;
    final falha = avaliacao.failureOrNull;

    final campos = _Campos(
      m: m,
      p: _p,
      falha: falha,
      saida: saida,
      alterado: alterado,
      normalizacao: widget.result.diagnostics?.baseNormalization,
      onChanged: _trocar,
    );
    final resultado = <Widget>[
      _ResumoCard(m: m, saida: saida, falha: falha, alterado: alterado),
      const Gap.md(),
      if (saida != null) ...[
        _ContaCard(m: m, saida: saida),
        const Gap.md(),
      ],
      _DiscordanciaCard(m: m, degraus: degraus),
      const Gap.md(),
      _ReversoCard(
        m: m,
        p: _p,
        alvo: _alvo,
        resposta: _resposta,
        onAlvo: (f) => setState(() {
          _alvo = f;
          _resposta = null;
        }),
        onResolver: _resolver,
        onUsar: (f, v) => _trocar(_p.withValue(f, v)),
      ),
      if (saida != null) ...[
        const Gap.md(),
        _AnosCard(m: m, p: _p, saida: saida),
      ],
      if (saida != null && saida.notices.isNotEmpty) ...[
        const Gap.md(),
        for (final n in saida.notices)
          Padding(
            padding: const EdgeInsets.only(bottom: FinSpace.sm),
            child: NoticeBanner(message: ManualCopy.aviso(n)),
          ),
      ],
      const Gap.md(),
      Text(
        'A faixa calibrada e a habilidade medida do Equisim são do preço '
        'justo do motor, porque foi ele que as avaliações passadas testaram. '
        'O preço desta tela é a conta do motor com os seus números: o '
        'resultado da sua opinião, sem validação própria.',
        style: context.finType.caption.copyWith(
          color: context.fin.textTertiary,
        ),
      ),
    ];

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          bottom: largo,
          child: Column(
            children: [
              _Cabecalho(
                ticker: widget.result.ticker,
                alterado: alterado,
                onVoltarAoMotor: () => _trocar(m.motorPremises),
              ),
              Expanded(
                child: largo
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 11,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                FinSpace.lg,
                                FinSpace.lg,
                                FinSpace.sm,
                                FinSpace.xl,
                              ),
                              children: [campos],
                            ),
                          ),
                          Expanded(
                            flex: 9,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                FinSpace.sm,
                                FinSpace.lg,
                                FinSpace.lg,
                                FinSpace.xl,
                              ),
                              children: resultado,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(FinSpace.lg),
                        children: [
                          campos,
                          const Gap.lg(),
                          ...resultado,
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: largo
          ? null
          : _BarraDoResultado(m: m, saida: saida, alterado: alterado),
    );
  }
}

// ---------------------------------------------------------------- Cabeçalho --

class _Cabecalho extends StatelessWidget {
  final Ticker ticker;
  final bool alterado;
  final VoidCallback onVoltarAoMotor;

  const _Cabecalho({
    required this.ticker,
    required this.alterado,
    required this.onVoltarAoMotor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return AppHeader(
      leading: IconButton(
        tooltip: 'Voltar à avaliação',
        icon: Icon(Icons.arrow_back, size: 20, color: c.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: 'Editar valuation',
      subtitle: '${ticker.value} · seu cálculo',
      // Ícone, e não botão com texto: em 320 dp o rótulo estourava o
      // cabeçalho. O botão com texto mora no cartão "Seus números".
      actions: [
        IconButton(
          tooltip: 'Voltar aos números do motor',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: alterado ? onVoltarAoMotor : null,
          icon: Icon(
            Icons.restart_alt,
            size: 20,
            color: alterado ? c.positive : c.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Campos --

/// Como o valor de um campo se escreve e se lê.
enum _Unidade {
  /// Reais, escritos em milhões com uma casa.
  reais,

  /// Taxa ao ano, em percentual com duas casas.
  taxa,

  /// Parcela do lucro, em percentual com uma casa.
  parcela;

  String mostrar(double v) => switch (this) {
        _Unidade.reais => Fmt.ratio(v / 1e6, decimals: 1),
        _Unidade.taxa => Fmt.ratio(v * 100, decimals: 2),
        _Unidade.parcela => Fmt.ratio(v * 100, decimals: 1),
      };

  /// O valor escrito como o motor o lê na referência: `R$ 1.234,5 mi`,
  /// `14,09%`.
  String referencia(double v) => switch (this) {
        _Unidade.reais => 'R\$ ${mostrar(v)} mi',
        _Unidade.taxa || _Unidade.parcela => '${mostrar(v)}%',
      };

  /// Lê o que o usuário digitou, na convenção brasileira, ou `null` quando
  /// não é número.
  ///
  /// Vírgula é decimal. Sem vírgula, o ponto é decimal — exceto em reais,
  /// onde `1.234` com três dígitos depois do ponto é milhar.
  double? ler(String texto) {
    var s = texto
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('R\$', '')
        .replaceAll('%', '')
        .replaceAll('−', '-');
    if (s.isEmpty || s == '-') return null;
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (this == _Unidade.reais &&
        RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    }
    final n = double.tryParse(s);
    if (n == null || !n.isFinite) return null;
    return switch (this) {
      _Unidade.reais => n * 1e6,
      _Unidade.taxa || _Unidade.parcela => n / 100,
    };
  }

  /// Diferença abaixo da qual o campo continua "igual ao do motor": metade
  /// da última casa exibida.
  double get tolerancia => switch (this) {
        _Unidade.reais => 0.05e6,
        _Unidade.taxa => 0.00005,
        _Unidade.parcela => 0.0005,
      };
}

/// Os cartões dos campos, na ordem em que a conta os usa.
class _Campos extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final Failure? falha;
  final ManualOutcome? saida;
  final bool alterado;

  /// Por que o motor normalizou o lucro de partida — o painel do cartão dele.
  final BaseNormalization? normalizacao;
  final ValueChanged<ManualPremises> onChanged;

  const _Campos({
    required this.m,
    required this.p,
    required this.falha,
    required this.saida,
    required this.alterado,
    required this.normalizacao,
    required this.onChanged,
  });

  /// O campo que a recusa nomeia, quando ela nomeia um.
  ManualField? get _recusado {
    final f = falha;
    if (f is! InvalidInput) return null;
    return ManualField.values.asNameMap()[f.field];
  }

  String? _erro(ManualField campo) {
    final r = _recusado;
    final f = falha;
    if (r == null || f == null) return null;
    // A margem da perpetuidade é relação entre a taxa e o crescimento perpétuo:
    // os dois campos a mostram.
    final nomeia = r == campo ||
        (r == ManualField.perpetualGrowth && campo == ManualField.discountRate);
    return nomeia ? ManualCopy.recusa(f) : null;
  }

  @override
  Widget build(BuildContext context) {
    final motor = m.motorPremises;
    final via = m.lane;
    final c = context.fin;
    final t = context.finType;

    final publicado = m.publishedBase;
    final String refBase;
    if (m.rebuiltBase) {
      refBase = 'Motor: ${_Unidade.reais.referencia(motor.baseProfit)} — '
          'reconstruído do retorno do ciclo, porque o último exercício veio no '
          'prejuízo.';
    } else if (publicado != null && (m.baseFactor - 1).abs() > 0.005) {
      refBase = 'Motor: ${_Unidade.reais.referencia(motor.baseProfit)} — o '
          'último exercício, ${_Unidade.reais.referencia(publicado)}, '
          'normalizado ${m.baseFactor > 1 ? 'para cima' : 'para baixo'} pelo '
          'ciclo (×${Fmt.ratio(m.baseFactor, decimals: 2)}).';
    } else {
      refBase = 'Motor: ${_Unidade.reais.referencia(motor.baseProfit)} — o '
          'último exercício publicado.';
    }

    final taxaTerminalDoMotor = m.motorTerminalRate;
    final refTaxa = 'Motor: ${_Unidade.taxa.referencia(motor.discountRate)} '
        'no ano 1 e ${_Unidade.taxa.referencia(taxaTerminalDoMotor)} na '
        'perpetuidade — a curva de juros do Tesouro mais o beta vezes o prêmio '
        'de mercado.';
    final wacc = saida?.capitalCostRates;
    final notaDaFirma = via == ValuationLane.firm && wacc != null
        ? 'Na via da firma, o custo médio do capital do motor '
            '(${_Unidade.taxa.referencia(wacc.first)} no ano 1) continua '
            'guiando o retorno e a perpetuidade da operação: a taxa daqui só '
            'desconta.'
        : null;

    final motorNeutro = motor.terminalReturn == null;
    final refCapitalNovo = motorNeutro
        ? 'Motor: igual à taxa (${_Unidade.taxa.referencia(taxaTerminalDoMotor)}).'
        : 'Motor: ${_Unidade.taxa.referencia(motor.terminalReturn!)} — vantagem '
            'competitiva medida no histórico da empresa.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Seus números',
                subtitle: 'Os campos abrem com os números do motor. Troque o '
                    'que discordar: o preço muda enquanto você digita.',
              ),
              const Gap.sm(),
              Text(
                via == ValuationLane.firm
                    ? 'Este ativo é avaliado pela via da firma: a conta parte do '
                        'lucro da operação, desconta o que sobra ao acionista '
                        'depois da dívida e divide pelas ações.'
                    : 'Este ativo é avaliado pela via do acionista: a conta parte '
                        'do lucro líquido, desconta o que sobra depois de '
                        'reinvestir e divide pelas ações.',
                style: t.bodySm.copyWith(color: c.textSecondary),
              ),
              if (alterado) ...[
                const Gap.xs(),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Acao(
                    texto: 'Voltar aos números do motor',
                    icone: Icons.restart_alt,
                    onPressed: () => onChanged(motor),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Gap.md(),
        _CampoNumerico(
          campo: ManualField.baseProfit,
          rotulo: ManualCopy.rotulo(ManualField.baseProfit, via),
          explicacao: ManualCopy.explicacao(ManualField.baseProfit, via),
          referencia: refBase,
          valor: p.baseProfit,
          valorDoMotor: motor.baseProfit,
          unidade: _Unidade.reais,
          passo: (motor.baseProfit * 0.05).abs(),
          grade: 1e5,
          minimo: 0,
          maximo: motor.baseProfit * 3,
          erro: _erro(ManualField.baseProfit),
          onChanged: (v) => onChanged(p.copyWith(baseProfit: v)),
          extras: [
            if (publicado != null &&
                publicado > 0 &&
                (publicado - p.baseProfit).abs() > _Unidade.reais.tolerancia)
              _Acao(
                texto:
                    'Usar o último exercício (${_Unidade.reais.referencia(publicado)})',
                onPressed: () => onChanged(p.copyWith(baseProfit: publicado)),
              ),
          ],
          detalhe: normalizacao == null
              ? null
              : NormalizationPanel(normalization: normalizacao!),
        ),
        const Gap.md(),
        _CampoNumerico(
          campo: ManualField.growth,
          rotulo: ManualCopy.rotulo(ManualField.growth, via),
          explicacao: ManualCopy.explicacao(ManualField.growth, via),
          referencia: 'Motor: ${_Unidade.taxa.referencia(motor.growth)} no ano 1, '
              'caindo em linha reta até o crescimento da perpetuidade.',
          valor: p.growth,
          valorDoMotor: motor.growth,
          unidade: _Unidade.taxa,
          passo: 0.0025,
          grade: 0.0025,
          minimo: -0.20,
          maximo: 0.40,
          erro: _erro(ManualField.growth),
          onChanged: (v) => onChanged(p.copyWith(growth: v)),
          alteradoForcado: p.growthPath != motor.growthPath,
          onVoltarAoMotor: () => onChanged(
            p.copyWith(growth: motor.growth, growthPath: motor.growthPath),
          ),
          modos: _Modos<ManualGrowthPath>(
            valor: p.growthPath,
            opcoes: const {
              ManualGrowthPath.decai: 'Cai até a perpetuidade',
              ManualGrowthPath.constante: 'Constante nos 10 anos',
            },
            onChanged: (v) => onChanged(p.copyWith(growthPath: v)),
          ),
        ),
        const Gap.md(),
        _CampoNumerico(
          campo: ManualField.perpetualGrowth,
          rotulo: ManualCopy.rotulo(ManualField.perpetualGrowth, via),
          explicacao: ManualCopy.explicacao(ManualField.perpetualGrowth, via),
          referencia: 'Motor: '
              '${_Unidade.taxa.referencia(motor.perpetualGrowth)}.',
          valor: p.perpetualGrowth,
          valorDoMotor: motor.perpetualGrowth,
          unidade: _Unidade.taxa,
          passo: 0.0025,
          grade: 0.0025,
          minimo: -0.02,
          maximo: 0.12,
          erro: _erro(ManualField.perpetualGrowth),
          onChanged: (v) => onChanged(p.copyWith(perpetualGrowth: v)),
        ),
        const Gap.md(),
        _CampoNumerico(
          campo: ManualField.discountRate,
          rotulo: ManualCopy.rotulo(ManualField.discountRate, via),
          explicacao: ManualCopy.explicacao(ManualField.discountRate, via),
          referencia: refTaxa,
          nota: notaDaFirma,
          valor: p.discountRate,
          valorDoMotor: motor.discountRate,
          unidade: _Unidade.taxa,
          passo: 0.0025,
          grade: 0.0025,
          minimo: 0.04,
          maximo: 0.30,
          erro: _erro(ManualField.discountRate),
          onChanged: (v) => onChanged(p.copyWith(discountRate: v)),
          alteradoForcado: p.ratePath != motor.ratePath,
          onVoltarAoMotor: () => onChanged(
            p.copyWith(discountRate: motor.discountRate, ratePath: motor.ratePath),
          ),
          modos: _Modos<ManualRatePath>(
            valor: p.ratePath,
            opcoes: const {
              ManualRatePath.motor: 'Segue a curva, como no motor',
              ManualRatePath.constante: 'Uma taxa só, em todos os anos',
            },
            onChanged: (v) => onChanged(p.copyWith(ratePath: v)),
          ),
        ),
        const Gap.md(),
        _ReinvestimentoCard(
          m: m,
          p: p,
          motor: motor,
          erro: _erro,
          onChanged: onChanged,
        ),
        if (p.reinvestment == ManualReinvestment.peloRetorno) ...[
          const Gap.md(),
          _CapitalNovoCard(
            m: m,
            p: p,
            motor: motor,
            referencia: refCapitalNovo,
            erro: _erro(ManualField.terminalReturn),
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// O reinvestimento: pelo retorno sobre o capital, como o motor, ou uma
/// parcela fixa do lucro.
class _ReinvestimentoCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualPremises motor;
  final String? Function(ManualField) erro;
  final ValueChanged<ManualPremises> onChanged;

  const _ReinvestimentoCard({
    required this.m,
    required this.p,
    required this.motor,
    required this.erro,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final via = m.lane;
    final modos = _Modos<ManualReinvestment>(
      valor: p.reinvestment,
      opcoes: const {
        ManualReinvestment.peloRetorno: 'Pelo retorno, como no motor',
        ManualReinvestment.parcelaFixa: 'Uma parcela fixa do lucro',
      },
      onChanged: (v) => onChanged(p.copyWith(reinvestment: v)),
    );
    if (p.reinvestment == ManualReinvestment.parcelaFixa) {
      return _CampoNumerico(
        campo: ManualField.retention,
        rotulo: ManualCopy.rotulo(ManualField.retention, via),
        explicacao: ManualCopy.explicacao(ManualField.retention, via),
        referencia: 'Ponto de partida: a parcela do ano 1 no motor, '
            '${_Unidade.parcela.referencia(motor.retention)}. Com ela fixa, o '
            'crescimento deixa de depender do retorno, e a perpetuidade é '
            'Gordon com a mesma parcela.',
        valor: p.retention,
        valorDoMotor: motor.retention,
        unidade: _Unidade.parcela,
        passo: 0.01,
        grade: 0.01,
        minimo: 0,
        maximo: 0.95,
        erro: erro(ManualField.retention),
        onChanged: (v) => onChanged(p.copyWith(retention: v)),
        modos: modos,
        // A parcela é do usuário, e o motor não a usa: o selo de alterado é o
        // do modo, e não o do valor — e voltar ao motor é voltar ao modo dele.
        alteradoForcado: true,
        onVoltarAoMotor: () => onChanged(p.copyWith(
          reinvestment: motor.reinvestment,
          returnOnCapital: motor.returnOnCapital,
          retention: motor.retention,
        )),
      );
    }
    return _CampoNumerico(
      campo: ManualField.returnOnCapital,
      rotulo: ManualCopy.rotulo(ManualField.returnOnCapital, via),
      explicacao: ManualCopy.explicacao(ManualField.returnOnCapital, via),
      referencia: motor.returnOnCapital > 0
          ? 'Motor: ${_Unidade.taxa.referencia(motor.returnOnCapital)} no ano 1.'
          : 'Motor: sem retorno medido — o motor não reinveste nada para '
              'crescer, e o resultado declara isso.',
      valor: p.returnOnCapital,
      valorDoMotor: motor.returnOnCapital,
      unidade: _Unidade.taxa,
      passo: 0.0025,
      grade: 0.0025,
      minimo: 0,
      maximo: 0.60,
      erro: erro(ManualField.returnOnCapital),
      onChanged: (v) => onChanged(p.copyWith(returnOnCapital: v)),
      modos: modos,
    );
  }
}

/// O retorno do capital novo na perpetuidade: igual à taxa, como o motor sem
/// vantagem competitiva, ou o que o usuário disser.
class _CapitalNovoCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualPremises motor;
  final String referencia;
  final String? erro;
  final ValueChanged<ManualPremises> onChanged;

  const _CapitalNovoCard({
    required this.m,
    required this.p,
    required this.motor,
    required this.referencia,
    required this.erro,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final via = m.lane;
    final proprio = p.terminalReturn != null;
    // Quem sai do "igual à taxa" parte do retorno do motor, quando há, ou da
    // taxa da perpetuidade mais cinco pontos — um número que já muda a conta.
    final partida = motor.terminalReturn ?? (m.motorTerminalRate + 0.05);
    final modos = _Modos<bool>(
      valor: proprio,
      opcoes: const {
        false: 'Igual à taxa: crescer não cria valor',
        true: 'Outro retorno',
      },
      onChanged: (v) =>
          onChanged(p.copyWith(terminalReturn: v ? partida : null)),
    );
    if (!proprio) {
      return _CartaoDeCampo(
        rotulo: ManualCopy.rotulo(ManualField.terminalReturn, via),
        explicacao: ManualCopy.explicacao(ManualField.terminalReturn, via),
        alterado: motor.terminalReturn != null,
        erro: erro,
        onVoltarAoMotor: motor.terminalReturn == null
            ? null
            : () => onChanged(p.copyWith(terminalReturn: motor.terminalReturn)),
        children: [
          modos,
          const Gap.sm(),
          Text(
            referencia,
            style: context.finType.caption.copyWith(
              color: context.fin.textSecondary,
            ),
          ),
        ],
      );
    }
    return _CampoNumerico(
      campo: ManualField.terminalReturn,
      rotulo: ManualCopy.rotulo(ManualField.terminalReturn, via),
      explicacao: ManualCopy.explicacao(ManualField.terminalReturn, via),
      referencia: referencia,
      valor: p.terminalReturn!,
      valorDoMotor: motor.terminalReturn ?? double.nan,
      unidade: _Unidade.taxa,
      passo: 0.0025,
      grade: 0.0025,
      minimo: 0.02,
      maximo: 0.50,
      erro: erro,
      onChanged: (v) => onChanged(p.copyWith(terminalReturn: v)),
      onVoltarAoMotor: () =>
          onChanged(p.copyWith(terminalReturn: motor.terminalReturn)),
      modos: modos,
    );
  }
}

/// O cartão de um campo: título, explicação, selo de alterado e o conteúdo.
///
/// **Cada campo tem cartão próprio**, e é o ponto: a tela existe para ser
/// editada, e um campo agrupado com outros num cartão só se lia como resumo.
/// A borda passa à cor da marca quando o valor deixa o do motor — é o que diz,
/// de longe, onde o usuário discorda.
class _CartaoDeCampo extends StatelessWidget {
  final String rotulo;
  final String explicacao;
  final bool alterado;
  final String? erro;
  final VoidCallback? onVoltarAoMotor;
  final List<Widget> children;

  const _CartaoDeCampo({
    required this.rotulo,
    required this.explicacao,
    required this.alterado,
    required this.erro,
    required this.onVoltarAoMotor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    return GlassCard(
      borderColor: erro != null
          ? c.negative
          : alterado
              ? c.brand
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  style: t.titleSm.copyWith(color: c.textPrimary),
                ),
              ),
              if (alterado) ...[
                const Gap.sm(axis: Axis.horizontal),
                _Selo(texto: 'Seu número'),
              ],
            ],
          ),
          const Gap.xs(),
          Text(explicacao, style: t.caption.copyWith(color: c.textSecondary)),
          const Gap.md(),
          ...children,
          if (alterado && onVoltarAoMotor != null) ...[
            const Gap.xs(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Acao(
                texto: 'Usar o do motor',
                icone: Icons.undo,
                onPressed: onVoltarAoMotor!,
              ),
            ),
          ],
          if (erro != null) ...[
            const Gap.sm(),
            Text(erro!, style: t.bodySm.copyWith(color: c.negative)),
          ],
        ],
      ),
    );
  }
}

/// Um campo numérico em destaque: valor grande, menos e mais, controle
/// deslizante e a referência do motor.
///
/// Segue a afordância do campo da Meta — preenchimento rebaixado, borda, lápis
/// e foco na cor da marca —, maior, porque aqui o campo é o assunto da tela.
class _CampoNumerico extends StatefulWidget {
  /// O campo, que dá a chave do texto para os testes.
  final ManualField campo;
  final String rotulo;
  final String explicacao;
  final String referencia;
  final String? nota;
  final double valor;
  final double valorDoMotor;
  final _Unidade unidade;
  final double passo;
  final double grade;
  final double minimo;
  final double maximo;
  final String? erro;
  final ValueChanged<double> onChanged;
  final VoidCallback? onVoltarAoMotor;
  final Widget? modos;
  final List<Widget> extras;

  /// Conteúdo a mais no pé do cartão — o porquê da normalização, no do lucro.
  final Widget? detalhe;
  final bool alteradoForcado;

  const _CampoNumerico({
    required this.campo,
    required this.rotulo,
    required this.explicacao,
    required this.referencia,
    this.nota,
    required this.valor,
    required this.valorDoMotor,
    required this.unidade,
    required this.passo,
    required this.grade,
    required this.minimo,
    required this.maximo,
    required this.erro,
    required this.onChanged,
    this.onVoltarAoMotor,
    this.modos,
    this.extras = const [],
    this.detalhe,
    this.alteradoForcado = false,
  });

  @override
  State<_CampoNumerico> createState() => _CampoNumericoState();
}

class _CampoNumericoState extends State<_CampoNumerico> {
  late final TextEditingController _texto;
  final FocusNode _foco = FocusNode();

  /// `true` enquanto o texto digitado não é número.
  bool _ilegivel = false;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.unidade.mostrar(widget.valor));
    _foco.addListener(() {
      // Ao sair do campo, o texto volta à forma canônica do valor que valeu.
      if (!_foco.hasFocus) {
        setState(() => _ilegivel = false);
        _texto.text = widget.unidade.mostrar(widget.valor);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CampoNumerico antigo) {
    super.didUpdateWidget(antigo);
    // O valor mudou por fora — menos e mais, controle deslizante, "usar o do
    // motor", a resposta do cálculo reverso. Enquanto o usuário digita, o
    // texto é dele: reescrevê-lo moveria o cursor no meio da digitação.
    final lido = widget.unidade.ler(_texto.text);
    final mudou = lido == null ||
        (lido - widget.valor).abs() > widget.unidade.tolerancia / 10;
    if (mudou && !_foco.hasFocus) {
      _texto.text = widget.unidade.mostrar(widget.valor);
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  double _naGrade(double v) =>
      widget.grade > 0 ? (v / widget.grade).roundToDouble() * widget.grade : v;

  void _passo(int sentido) {
    final v = _naGrade(widget.valor + sentido * widget.passo);
    _texto.text = widget.unidade.mostrar(v);
    widget.onChanged(v);
  }

  bool get _alterado =>
      widget.alteradoForcado ||
      !widget.valorDoMotor.isFinite ||
      (widget.valor - widget.valorDoMotor).abs() > widget.unidade.tolerancia;

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final u = widget.unidade;
    // A faixa do controle deslizante sempre contém o valor do motor e o
    // corrente; o campo de texto aceita qualquer número.
    final lo = [
      widget.minimo,
      widget.valor,
      if (widget.valorDoMotor.isFinite) widget.valorDoMotor,
    ].reduce((a, b) => a < b ? a : b);
    var hi = [
      widget.maximo,
      widget.valor,
      if (widget.valorDoMotor.isFinite) widget.valorDoMotor,
    ].reduce((a, b) => a > b ? a : b);
    if (hi <= lo) hi = lo + (widget.passo > 0 ? widget.passo * 10 : 1);

    OutlineInputBorder contorno(Color cor, {double espessura = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cor, width: espessura),
        );
    final erro = widget.erro != null || _ilegivel;

    return _CartaoDeCampo(
      rotulo: widget.rotulo,
      explicacao: widget.explicacao,
      alterado: _alterado,
      erro: widget.erro ??
          (_ilegivel ? 'Escreva um número, como 12,5.' : null),
      onVoltarAoMotor: widget.valorDoMotor.isFinite
          ? (widget.onVoltarAoMotor ??
              () {
                _texto.text = u.mostrar(widget.valorDoMotor);
                widget.onChanged(widget.valorDoMotor);
              })
          : widget.onVoltarAoMotor,
      children: [
        if (widget.modos != null) ...[widget.modos!, const Gap.md()],
        Row(
          children: [
            _BotaoPasso(
              icone: Icons.remove,
              dica: 'Diminuir ${widget.rotulo.toLowerCase()}',
              onPressed: () => _passo(-1),
            ),
            const Gap.sm(axis: Axis.horizontal),
            Expanded(
              child: TextField(
                key: ValueKey('campo-${widget.campo.name}'),
                controller: _texto,
                focusNode: _foco,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-−]')),
                ],
                style: t.numLg.copyWith(color: c.textPrimary),
                onChanged: (s) {
                  final v = u.ler(s);
                  setState(() => _ilegivel = v == null);
                  if (v != null) widget.onChanged(v);
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.surfaceSunken,
                  prefixText: u == _Unidade.reais ? 'R\$ ' : null,
                  prefixStyle: t.bodySm.copyWith(color: c.textSecondary),
                  suffixText: switch (u) {
                    _Unidade.reais => 'mi',
                    _Unidade.taxa => '% a.a.',
                    _Unidade.parcela => '%',
                  },
                  suffixStyle: t.bodySm.copyWith(color: c.textSecondary),
                  // O lápis é a marca de edição, como no campo da Meta: o
                  // campo inteiro já é o alvo do toque.
                  prefixIcon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: c.textTertiary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FinSpace.sm,
                    vertical: FinSpace.md,
                  ),
                  border: contorno(c.border),
                  enabledBorder: contorno(erro ? c.negative : c.border),
                  focusedBorder:
                      contorno(erro ? c.negative : c.brand, espessura: 2),
                ),
              ),
            ),
            const Gap.sm(axis: Axis.horizontal),
            _BotaoPasso(
              icone: Icons.add,
              dica: 'Aumentar ${widget.rotulo.toLowerCase()}',
              onPressed: () => _passo(1),
            ),
          ],
        ),
        // `Material` transparente pelo mesmo motivo do alternador de Monte
        // Carlo: o controle pinta o respingo no `Material` mais próximo, e o
        // `GlassCard` interpõe um fundo próprio entre os dois.
        Material(
          type: MaterialType.transparency,
          child: Slider(
            value: widget.valor.clamp(lo, hi),
            min: lo,
            max: hi,
            activeColor: c.brand,
            inactiveColor: c.border,
            semanticFormatterCallback: u.referencia,
            onChanged: (v) {
              final r = _naGrade(v);
              _texto.text = u.mostrar(r);
              widget.onChanged(r);
            },
          ),
        ),
        Text(
          widget.referencia,
          style: t.caption.copyWith(color: c.textSecondary),
        ),
        if (widget.nota != null) ...[
          const Gap.xs(),
          Text(widget.nota!, style: t.caption.copyWith(color: c.textTertiary)),
        ],
        if (widget.extras.isNotEmpty) ...[
          const Gap.xs(),
          Wrap(spacing: FinSpace.sm, children: widget.extras),
        ],
        if (widget.detalhe != null) ...[
          const Gap.md(),
          widget.detalhe!,
        ],
      ],
    );
  }
}

/// Botão de menos e mais, com alvo de 48 dp.
class _BotaoPasso extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback onPressed;

  const _BotaoPasso({
    required this.icone,
    required this.dica,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return IconButton(
      tooltip: dica,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        backgroundColor: c.surfaceSunken,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icone, size: 20, color: c.textPrimary),
    );
  }
}

/// Uma ação de texto pequena, na cor de texto positiva.
class _Acao extends StatelessWidget {
  final String texto;
  final IconData? icone;
  final VoidCallback onPressed;

  const _Acao({required this.texto, required this.onPressed, this.icone});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final rotulo = Text(
      texto,
      style: context.finType.bodySm.copyWith(color: c.positive),
    );
    // `positive`, e não `brand`: é texto, e a cor de marca não tem contraste
    // garantido para texto.
    return icone == null
        ? TextButton(onPressed: onPressed, child: rotulo)
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icone, size: 16, color: c.positive),
            label: rotulo,
          );
  }
}

/// O selo de campo alterado.
class _Selo extends StatelessWidget {
  final String texto;
  const _Selo({required this.texto});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.sm,
        vertical: FinSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.brandSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.brand),
      ),
      child: Text(
        texto,
        style: context.finType.caption.copyWith(
          color: c.positive,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// As opções de modo de um campo, como fichas — as mesmas da escolha de ativo
/// na aba Valuation.
class _Modos<T> extends StatelessWidget {
  final T valor;
  final Map<T, String> opcoes;
  final ValueChanged<T> onChanged;

  const _Modos({
    required this.valor,
    required this.opcoes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: FinSpace.sm,
        runSpacing: FinSpace.sm,
        children: [
          for (final MapEntry(key: k, value: rotulo) in opcoes.entries)
            ChoiceChip(
              label: Text(rotulo),
              selected: k == valor,
              onSelected: (_) => onChanged(k),
              labelStyle: context.finType.bodySm.copyWith(
                color: k == valor ? c.textOnBrand : c.textSecondary,
              ),
              selectedColor: c.brand,
              backgroundColor: c.surfaceSunken,
              side: BorderSide(color: c.border),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Resultado --

/// O preço do usuário contra o do motor e o de mercado.
class _ResumoCard extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome? saida;
  final Failure? falha;
  final bool alterado;

  const _ResumoCard({
    required this.m,
    required this.saida,
    required this.falha,
    required this.alterado,
  });

  /// Largura por coluna abaixo da qual as três métricas se empilham, em dp.
  static const double larguraPorColuna = 120;

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final seu = saida?.fairValuePerShare;
    final delta = seu == null ? null : seu - m.motorFairValue;
    final potencial = seu == null ? null : seu / m.marketPrice - 1;
    final tiles = [
      MetricTile(
        label: 'Preço justo do motor',
        value: Fmt.money(m.motorFairValue),
      ),
      MetricTile(label: 'Preço de mercado', value: Fmt.money(m.marketPrice)),
      MetricTile(
        label: 'Seu potencial',
        value: potencial == null
            ? '—'
            : Fmt.percent(potencial, decimals: 1, signed: true),
        hint: 'total, sem prazo',
        trend: FinAmount.trendOf(potencial),
      ),
    ];
    return GlassCard(
      borderColor: alterado ? c.brand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Seu preço justo',
            subtitle: alterado
                ? 'A conta do motor com os seus números'
                : 'Igual ao do motor: nenhum campo foi trocado',
          ),
          const Gap.md(),
          // O `Align` não é decorativo: `FinAmount` embrulha o texto num
          // `AnimatedSwitcher`, que centraliza o filho na caixa recebida, e a
          // coluna estica a caixa — sem ele o número flutuava no meio do
          // cartão, longe do título que o nomeia (ver `MetricTileRow`).
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FinAmount(
              text: seu == null ? '—' : Fmt.money(seu),
              style: t.numHero,
              align: TextAlign.left,
            ),
          ),
          if (delta != null && alterado) ...[
            const Gap.xs(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FinAmount(
                text: '${delta >= 0 ? '+' : '−'}${Fmt.money(delta.abs())} '
                    '(${Fmt.percent(delta / m.motorFairValue, decimals: 1, signed: true)}) '
                    'contra o motor',
                style: t.numSm,
                trend: FinAmount.trendOf(delta),
                align: TextAlign.left,
                maxLines: 2,
              ),
            ),
          ],
          const Gap.lg(),
          LayoutBuilder(
            builder: (context, constraints) {
              final escala = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth <
                  larguraPorColuna * escala * tiles.length) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tile) in tiles.indexed) ...[
                      if (i > 0) const Gap.sm(),
                      tile,
                    ],
                  ],
                );
              }
              return MetricTileRow(tiles: tiles);
            },
          ),
          if (falha != null) ...[
            const Gap.md(),
            NoticeBanner(
              trend: FinTrend.negative,
              icon: Icons.error_outline,
              message: ManualCopy.recusa(falha!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A barra fixa do rodapé, no celular: o preço do usuário sempre à vista.
class _BarraDoResultado extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome? saida;
  final bool alterado;

  const _BarraDoResultado({
    required this.m,
    required this.saida,
    required this.alterado,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final seu = saida?.fairValuePerShare;
    final potencial = seu == null ? null : seu / m.marketPrice - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(
          top: BorderSide(color: alterado ? c.brand : c.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FinSpace.lg,
            vertical: FinSpace.sm,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FinSpace.md,
            runSpacing: FinSpace.xs,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seu preço justo',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  FinAmount(
                    text: seu == null ? '—' : Fmt.money(seu),
                    style: t.numLg,
                    align: TextAlign.left,
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motor ${Fmt.money(m.motorFairValue)} · mercado '
                    '${Fmt.money(m.marketPrice)}',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  FinAmount(
                    text: potencial == null
                        ? '—'
                        : '${Fmt.percent(potencial, decimals: 1, signed: true)} '
                            'de potencial',
                    style: t.numSm,
                    trend: FinAmount.trendOf(potencial),
                    align: TextAlign.left,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reais em milhões, para as linhas da conta.
String _milhoes(double v) =>
    '${v < 0 ? '−' : ''}R\$ ${Fmt.ratio(v.abs() / 1e6, decimals: 1)} mi';

/// A conta inteira: o valor presente dos anos, o da perpetuidade, a ponte e o
/// preço por ação.
class _ContaCard extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome saida;

  const _ContaCard({required this.m, required this.saida});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final s = saida;
    final explicito = s.explicitPresentValue;
    final perpetuo = s.terminalPresentValue;
    final total = explicito.abs() + perpetuo.abs();
    final pesoExplicito = total > 0 ? explicito.abs() / total : 0.5;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'A conta',
            subtitle: m.lane == ValuationLane.firm
                ? 'O valor presente do que sobra ao acionista depois da dívida, '
                    'dividido pelas ações'
                : 'O valor presente do que sobra ao acionista depois de '
                    'reinvestir, dividido pelas ações',
          ),
          const Gap.md(),
          LabelValueRow(
            label: 'Valor presente dos 10 anos',
            value: _milhoes(explicito),
          ),
          const Gap.xs(),
          LabelValueRow(
            label: 'Valor presente da perpetuidade',
            value: _milhoes(perpetuo),
          ),
          if (s.minorityInterest > 0) ...[
            const Gap.xs(),
            LabelValueRow(
              label: '− Parte dos acionistas minoritários das controladas',
              value: _milhoes(-s.minorityInterest),
            ),
          ],
          if (s.postStatementCapital > 0) ...[
            const Gap.xs(),
            LabelValueRow(
              label: '+ Ações emitidas depois do balanço',
              value: _milhoes(s.postStatementCapital),
            ),
          ],
          const Divider(height: FinSpace.lg),
          LabelValueRow(
            label: 'Valor do patrimônio (VPL)',
            value: _milhoes(s.equityValue),
          ),
          const Gap.xs(),
          LabelValueRow(
            label: '÷ Ações',
            value: '${Fmt.ratio(m.shares / 1e6, decimals: 1)} mi',
          ),
          const Gap.xs(),
          LabelValueRow(
            label: '= Seu preço justo por ação',
            value: Fmt.money(s.fairValuePerShare),
            trend: FinTrend.positive,
          ),
          const Gap.lg(),
          Text(
            'De onde vem o valor',
            style: t.caption.copyWith(color: c.textSecondary),
          ),
          const Gap.xs(),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (pesoExplicito * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: c.brand),
                  ),
                  Expanded(
                    flex: ((1 - pesoExplicito) * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: c.borderStrong),
                  ),
                ],
              ),
            ),
          ),
          const Gap.xs(),
          Wrap(
            spacing: FinSpace.md,
            runSpacing: FinSpace.xs,
            children: [
              _Legenda(
                cor: c.brand,
                texto: '10 anos: ${Fmt.percent(pesoExplicito, decimals: 0)}',
              ),
              _Legenda(
                cor: c.borderStrong,
                texto: 'Perpetuidade: '
                    '${Fmt.percent(1 - pesoExplicito, decimals: 0)} — '
                    '${s.terminalKind.rotulo}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  final Color cor;
  final String texto;
  const _Legenda({required this.cor, required this.texto});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Gap.xs(axis: Axis.horizontal),
          Flexible(
            child: Text(
              texto,
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ),
        ],
      );
}

/// "Onde você discorda do motor": do preço do motor ao do usuário, um grupo
/// de premissas de cada vez.
class _DiscordanciaCard extends StatelessWidget {
  final ManualValuation m;
  final List<ManualStep> degraus;

  const _DiscordanciaCard({required this.m, required this.degraus});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final valores = [
      m.motorFairValue,
      for (final d in degraus) ...[d.from, if (d.to != null) d.to!],
    ].where((v) => v.isFinite).toList();
    final lo = valores.fold(0.0, (a, b) => a < b ? a : b);
    final hi = valores.fold(lo + 1e-9, (a, b) => a > b ? a : b) * 1.05;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    Widget barra(double de, double para, Color cor) => LayoutBuilder(
          builder: (context, k) {
            final a = pos(de < para ? de : para) * k.maxWidth;
            final b = pos(de < para ? para : de) * k.maxWidth;
            return SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: a,
                    width: (b - a).clamp(2.0, k.maxWidth),
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

    Widget linha(String rotulo, String valor, FinTrend tendencia, Widget b) =>
        Padding(
          padding: const EdgeInsets.only(bottom: FinSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabelValueRow(label: rotulo, value: valor, trend: tendencia),
              const Gap.xs(),
              b,
            ],
          ),
        );

    final ultimo = degraus.isEmpty ? null : degraus.last.to;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Onde você discorda do motor',
            subtitle: 'Quanto cada troca move o preço, na ordem em que a conta '
                'as usa',
          ),
          const Gap.md(),
          linha(
            'Preço justo do motor',
            Fmt.money(m.motorFairValue),
            FinTrend.neutral,
            barra(lo, m.motorFairValue, c.borderStrong),
          ),
          if (degraus.isEmpty)
            Text(
              'Troque um campo para ver quanto cada discordância move o preço.',
              style: t.bodySm.copyWith(color: c.textSecondary),
            ),
          for (final d in degraus)
            if (d.to == null)
              linha(
                d.groups.map((g) => g.rotulo).join(' e '),
                'sem valor finito',
                FinTrend.blocked,
                barra(d.from, d.from, c.negative),
              )
            else
              linha(
                d.groups.map((g) => g.rotulo).join(' e '),
                '${d.delta! >= 0 ? '+' : '−'}${Fmt.money(d.delta!.abs())}',
                FinAmount.trendOf(d.delta),
                barra(d.from, d.to!, d.delta! >= 0 ? c.positive : c.negative),
              ),
          if (ultimo != null) ...[
            const Divider(height: FinSpace.lg),
            linha(
              'Seu preço justo',
              Fmt.money(ultimo),
              FinTrend.neutral,
              barra(lo, ultimo, c.brand),
            ),
          ],
        ],
      ),
    );
  }
}

/// "O que o preço de hoje supõe?": o valor de um campo que leva o preço justo
/// ao de mercado, com os outros como estão.
class _ReversoCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualField alvo;
  final ManualSolution? resposta;
  final ValueChanged<ManualField> onAlvo;
  final VoidCallback onResolver;
  final void Function(ManualField, double) onUsar;

  const _ReversoCard({
    required this.m,
    required this.p,
    required this.alvo,
    required this.resposta,
    required this.onAlvo,
    required this.onResolver,
    required this.onUsar,
  });

  static _Unidade _unidade(ManualField f) => switch (f) {
        ManualField.baseProfit => _Unidade.reais,
        ManualField.retention => _Unidade.parcela,
        _ => _Unidade.taxa,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final opcoes = <ManualField>[
      ManualField.discountRate,
      ManualField.growth,
      ManualField.baseProfit,
      if (p.reinvestment == ManualReinvestment.peloRetorno)
        ManualField.returnOnCapital
      else
        ManualField.retention,
      if (p.terminalReturn != null) ManualField.terminalReturn,
    ];
    final escolhido = opcoes.contains(alvo) ? alvo : opcoes.first;
    final r = resposta;
    final nome = ManualCopy.rotulo(escolhido, m.lane).toLowerCase();
    final u = _unidade(escolhido);
    String? frase;
    if (r != null && r.field == escolhido) {
      final v = r.value;
      if (v != null) {
        frase = 'Para valer ${Fmt.money(r.target)}, com os outros campos como '
            'estão, $nome teria de ser ${u.referencia(v)}. Hoje está em '
            '${u.referencia(p.valueOf(escolhido) ?? double.nan)}.';
      } else if (r.closestValue != null && r.closestPrice != null) {
        frase = 'Com os outros campos como estão, nenhum valor de $nome leva o '
            'preço justo a ${Fmt.money(r.target)}: o mais perto é '
            '${Fmt.money(r.closestPrice!)}, com ${u.referencia(r.closestValue!)}.';
      } else {
        frase = 'Com os outros campos como estão, a conta não fecha para '
            'nenhum valor de $nome.';
      }
    }
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'O que o preço de hoje supõe?',
            subtitle: 'O valor de um campo que faz o preço justo bater com o de '
                'mercado (${Fmt.money(m.marketPrice)})',
          ),
          const Gap.md(),
          _Modos<ManualField>(
            valor: escolhido,
            opcoes: {for (final f in opcoes) f: ManualCopy.rotulo(f, m.lane)},
            onChanged: onAlvo,
          ),
          const Gap.md(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: onResolver,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.textOnBrand,
              ),
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Calcular'),
            ),
          ),
          if (frase != null) ...[
            const Gap.md(),
            Text(frase, style: t.bodySm.copyWith(color: c.textPrimary)),
            if (r?.value != null) ...[
              const Gap.xs(),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Acao(
                  texto: 'Usar este valor',
                  icone: Icons.check,
                  onPressed: () => onUsar(escolhido, r!.value!),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Ano a ano: a projeção que a conta fez, em milhões de reais.
class _AnosCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualOutcome saida;

  const _AnosCard({required this.m, required this.p, required this.saida});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final firma = m.lane == ValuationLane.firm;
    final cab = <String>[
      'Ano',
      'Crescimento',
      firma ? 'Lucro operacional' : 'Lucro líquido',
      'Reinvestido',
      if (firma) ...['Fluxo da firma', 'Dívida'],
      firma ? 'Fluxo do acionista' : 'Fluxo',
      'Taxa',
      'Fator',
      'Valor presente',
    ];
    String mi(double? v) => v == null || !v.isFinite
        ? '—'
        : '${v < 0 ? '−' : ''}${Fmt.ratio(v.abs() / 1e6, decimals: 1)}';
    final linhas = <List<String>>[
      for (final y in saida.years)
        [
          '${y.year}',
          Fmt.percent(y.growth, decimals: 1),
          mi(y.profit),
          Fmt.percent(y.retention, decimals: 0),
          if (firma) ...[mi(y.firmFlow), mi(y.debtService)],
          mi(y.flow),
          Fmt.percent(y.rate, decimals: 2),
          Fmt.ratio(y.discountFactor, decimals: 3),
          mi(y.presentValue),
        ],
      [
        'Perpetuidade',
        Fmt.percent(p.perpetualGrowth, decimals: 1),
        '',
        '',
        if (firma) ...['', ''],
        '${mi(saida.terminalValue)} no ano 10',
        Fmt.percent(saida.terminalRate, decimals: 2),
        Fmt.ratio(saida.years.last.discountFactor, decimals: 3),
        mi(saida.terminalPresentValue),
      ],
    ];
    final estiloCab = t.caption.copyWith(color: c.textSecondary);
    final estilo = t.captionNum.copyWith(color: c.textPrimary);
    TableRow fila(List<String> celulas, TextStyle s, {Color? fundo}) =>
        TableRow(
          decoration: fundo == null ? null : BoxDecoration(color: fundo),
          children: [
            for (final (i, v) in celulas.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FinSpace.sm,
                  vertical: FinSpace.xs + 2,
                ),
                child: Text(
                  v,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: s,
                ),
              ),
          ],
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Ano a ano',
            subtitle: 'Em milhões de reais. O fluxo de cada ano chega no meio '
                'dele, como no motor: valor presente = fluxo ÷ fator',
          ),
          const Gap.md(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: c.divider),
              ),
              children: [
                fila(cab, estiloCab),
                for (final (i, l) in linhas.indexed)
                  fila(
                    l,
                    estilo,
                    fundo: i == linhas.length - 1 ? c.surfaceSunken : null,
                  ),
                fila([
                  'VPL',
                  for (var i = 1; i < cab.length - 1; i++) '',
                  mi(saida.explicitPresentValue + saida.terminalPresentValue),
                ], estilo.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Gap.sm(),
          Text(
            firma
                ? 'Fluxo do acionista = fluxo da firma − serviço da dívida '
                    '(juros depois do imposto, menos o rendimento do caixa, '
                    'menos a dívida nova que acompanha o crescimento).'
                : 'Fluxo = lucro × (1 − parcela reinvestida).',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}
