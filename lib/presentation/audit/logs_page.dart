import 'dart:convert';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';

import 'console_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../audit/audit_bus.dart';
import '../../audit/audit_export_stub.dart'
    if (dart.library.js_interop) '../../audit/audit_export_web.dart'
    as export_impl;

/// Aplicação mínima da janela paralela de auditoria.
///
/// Deliberadamente separada de `EquisimApp`: o painel não autentica ninguém,
/// não lê carteira e não dispara cálculo. Se ele subisse dentro da aplicação
/// inteira, os cálculos da própria janela de inspeção apareceriam na lista
/// misturados aos da janela sob análise — uma auditoria observando a si mesma.
class AuditLogsApp extends StatelessWidget {
  const AuditLogsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equisim — Auditoria de Cálculos',
      debugShowCheckedModeBanner: false,
      // A guia é aberta em '#/logs', e a rota da plataforma **vence**
      // `initialRoute` — é assim que o `WidgetsApp` resolve o conflito. Esta
      // instância não tem tabela de rotas (ela *é* o painel), então o Navigator
      // procuraria '/logs', não acharia e reportaria "Could not navigate to
      // initial route" a cada abertura, antes de voltar à raiz por conta
      // própria. A pilha aqui tem um item por definição: o painel não navega
      // para lugar nenhum.
      // `onGenerateRoute` também é obrigatório: sem uma das entradas da tabela
      // de rotas, o `WidgetsApp` conclui que a aplicação não usa navegação e
      // não monta Navigator nenhum — a janela subiria em branco.
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => const LogsPage(),
      ),
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(builder: (_) => const LogsPage()),
      ],
    );
  }
}

/// Console de inspeção dos cálculos, em tempo real.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

enum _Filter { todos, calculos, rede }

class _LogsPageState extends State<LogsPage> {
  final AuditBus _bus = AuditBus.instance;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  bool _autoScroll = true;
  bool _dark = true;
  _Filter _filter = _Filter.todos;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _bus.addListener(_onBusChanged);
    _lastCount = _bus.history.length;
  }

  @override
  void dispose() {
    _bus.removeListener(_onBusChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onBusChanged() {
    if (!mounted) return;
    final grew = _bus.history.length > _lastCount;
    _lastCount = _bus.history.length;
    setState(() {});
    if (grew && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  List<AuditEvent> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final event in _bus.history)
        if (_matchesFilter(event) && _matchesQuery(event, query)) event,
    ];
  }

  bool _matchesFilter(AuditEvent event) => switch (_filter) {
    _Filter.todos => true,
    // A separação é estrutural, não um rótulo à parte: evento sem fórmula
    // decomposta é ida à rede; com fórmula, é cálculo do núcleo.
    _Filter.calculos => event.calculations.isNotEmpty,
    _Filter.rede => event.calculations.isEmpty,
  };

  bool _matchesQuery(AuditEvent event, String query) {
    if (query.isEmpty) return true;
    if (event.endpoint.toLowerCase().contains(query)) return true;
    if (event.transactionId.toLowerCase().contains(query)) return true;
    return event.calculations.any(
      (c) => c.formulaName.toLowerCase().contains(query),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ConsoleTheme(_dark);
    final events = _visible;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            // O cabeçalho fica com metade da tela, no máximo, e rola por
            // dentro acima disso.
            //
            // Ele é uma faixa de rótulos longos que quebra em mais linhas
            // conforme a tela estreita ou a fonte cresce. Medido numa tela de
            // 320×568 com a Roboto real: 282 px em escala 1,0, mas 696 px em
            // escala 2,0 — mais alto que a tela inteira. Sem o teto, esta
            // `Column` estourava 128 px por baixo e a lista de eventos sumia,
            // que é o oposto do que o painel existe para fazer.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                child: _Header(
                  theme: theme,
                  bus: _bus,
                  total: _bus.history.length,
                  showing: events.length,
                  autoScroll: _autoScroll,
                  filter: _filter,
                  search: _search,
                  dark: _dark,
                  onToggleAutoScroll: () =>
                      setState(() => _autoScroll = !_autoScroll),
                  onToggleTheme: () => setState(() => _dark = !_dark),
                  onFilter: (f) => setState(() => _filter = f),
                  onSearch: () => setState(() {}),
                  onClear: _bus.clear,
                  onExport: _export,
                  onReconnect: _bus.requestReplay,
                ),
              ),
            ),
            Expanded(
              child: events.isEmpty
                  ? _EmptyState(theme: theme, bus: _bus)
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _EventCard(
                        key: ValueKey(events[index].transactionId),
                        event: events[index],
                        ordinal: index + 1,
                        theme: theme,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _export() {
    final events = _visible;
    final document = const JsonEncoder.withIndent('  ').convert({
      'aplicacao': 'Equisim',
      'documento': 'Auditoria de cálculos',
      'exportadoEm': DateTime.now().toIso8601String(),
      'totalDeEventos': events.length,
      'totalDeCalculos': events.fold<int>(
        0,
        (sum, e) => sum + e.calculations.length,
      ),
      'filtroAplicado': _filter.name,
      'eventos': [for (final e in events) e.toJson()],
    });

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final saved = export_impl.downloadJson(
      'equisim-auditoria-$stamp.json',
      document,
    );

    if (!saved) {
      // Fora do navegador não há download; a área de transferência entrega o
      // mesmo conteúdo sem inventar um caminho de arquivo.
      Clipboard.setData(ClipboardData(text: document));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Auditoria exportada: ${events.length} eventos.'
              : 'Auditoria copiada para a área de transferência '
                    '(${events.length} eventos).',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ------------------------------------------------------------------ Cabeçalho --

class _Header extends StatelessWidget {
  const _Header({
    required this.theme,
    required this.bus,
    required this.total,
    required this.showing,
    required this.autoScroll,
    required this.filter,
    required this.search,
    required this.dark,
    required this.onToggleAutoScroll,
    required this.onToggleTheme,
    required this.onFilter,
    required this.onSearch,
    required this.onClear,
    required this.onExport,
    required this.onReconnect,
  });

  final ConsoleTheme theme;
  final AuditBus bus;
  final int total;
  final int showing;
  final bool autoScroll;
  final _Filter filter;
  final TextEditingController search;
  final bool dark;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onToggleTheme;
  final ValueChanged<_Filter> onFilter;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final connected = bus.crossWindow;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.functions, color: theme.accent, size: 20),
                  const SizedBox(width: 8),
                  // Em 320 dp o título sozinho é mais largo que a faixa que o
                  // Wrap tem para oferecer. Flexível, ele quebra em duas
                  // linhas; sem isso, estoura a lateral em 244 px.
                  Flexible(
                    child: Text(
                      'Painel de Auditoria de Cálculos',
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              _StatusPill(
                theme: theme,
                ok: connected,
                label: connected
                    ? 'Canal entre janelas ativo'
                    : 'Entrega local (mesma janela)',
              ),
              _StatusPill(
                theme: theme,
                ok: bus.role == AuditRole.emitter,
                neutral: bus.role != AuditRole.emitter,
                label: bus.role == AuditRole.emitter
                    ? 'Esta janela calcula'
                    : 'Modo inspeção',
              ),
              Text(
                showing == total
                    ? '$total evento(s)'
                    : '$showing de $total evento(s)',
                style: TextStyle(color: theme.dim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ConsoleButton(
                theme: theme,
                icon: Icons.delete_sweep_outlined,
                label: 'Limpar Logs',
                onTap: onClear,
              ),
              _ConsoleButton(
                theme: theme,
                icon: autoScroll ? Icons.pause : Icons.play_arrow,
                label: autoScroll
                    ? 'Pausar Auto-scroll'
                    : 'Retomar Auto-scroll',
                active: !autoScroll,
                onTap: onToggleAutoScroll,
              ),
              _ConsoleButton(
                theme: theme,
                icon: Icons.download_outlined,
                label: 'Exportar Auditoria (JSON)',
                onTap: onExport,
              ),
              if (bus.role == AuditRole.inspector)
                _ConsoleButton(
                  theme: theme,
                  icon: Icons.sync,
                  label: 'Recarregar histórico',
                  onTap: onReconnect,
                ),
              _ConsoleButton(
                theme: theme,
                icon: dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: dark ? 'Modo claro' : 'Modo escuro',
                onTap: onToggleTheme,
              ),
              const SizedBox(width: 4),
              for (final f in _Filter.values)
                _FilterChip(
                  theme: theme,
                  label: switch (f) {
                    _Filter.todos => 'Todos',
                    _Filter.calculos => 'Cálculos',
                    _Filter.rede => 'Rede',
                  },
                  selected: filter == f,
                  onTap: () => onFilter(f),
                ),
              SizedBox(
                width: 220,
                height: 34,
                child: TextField(
                  controller: search,
                  onChanged: (_) => onSearch(),
                  style: TextStyle(color: theme.text, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: theme.background,
                    hintText: 'Filtrar por ativo ou fórmula…',
                    hintStyle: TextStyle(color: theme.dim, fontSize: 12),
                    prefixIcon: Icon(Icons.search, size: 16, color: theme.dim),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: theme.accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme, required this.bus});

  final ConsoleTheme theme;
  final AuditBus bus;

  @override
  Widget build(BuildContext context) {
    // Rolável porque o parágrafo é longo e o espaço é o que sobra do
    // cabeçalho: com a fonte do sistema ampliada numa tela de 568 px, o texto
    // não cabe e a explicação de "o que o painel está esperando" some atrás
    // da listra de estouro — justamente para quem abriu o painel sem saber o
    // que fazer nele.
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, size: 36, color: theme.dim),
              const SizedBox(height: 14),
              Text(
                'Aguardando execuções',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                bus.crossWindow
                    ? 'Volte à janela principal e abra um ativo, a meta ou o '
                          'backtest. Cada requisição à API e cada fórmula '
                          'avaliada aparece aqui no instante em que acontece.'
                    : 'Use a aplicação normalmente: as execuções aparecem aqui '
                          'assim que ocorrerem.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.dim, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Cartão de evento --

class _EventCard extends StatelessWidget {
  const _EventCard({
    super.key,
    required this.event,
    required this.ordinal,
    required this.theme,
  });

  final AuditEvent event;
  final int ordinal;
  final ConsoleTheme theme;

  bool get _isNetwork => event.calculations.isEmpty;

  @override
  Widget build(BuildContext context) {
    final status = event.outputPayload['status'];
    final failed = status == 'falha';
    final accent = failed
        ? theme.danger
        : (_isNetwork ? theme.network : theme.accent);

    // Material, e não um contêiner decorado: o `ExpansionTile` pinta fundo e
    // tinta de toque no Material mais próximo, e uma caixa colorida entre os
    // dois esconderia ambos — o próprio framework acusa isso em depuração.
    return Material(
      color: theme.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: theme.dim,
          collapsedIconColor: theme.dim,
          title: _title(accent, failed),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'tx ${event.transactionId} · '
              '${_formatTimestamp(event.timestamp)} · '
              '${event.executionTimeMs} ms',
              style: theme.mono(color: theme.dim, size: 11),
            ),
          ),
          children: [
            _Section(
              theme: theme,
              letter: 'A',
              title: 'Requisição & Resposta',
              subtitle: _isNetwork
                  ? 'Payload bruto trocado com a fonte de dados.'
                  : 'Insumos resolvidos que entraram no motor e o resultado '
                        'que saiu dele.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _JsonPanel(
                    theme: theme,
                    label: 'inputPayload',
                    value: event.inputPayload,
                  ),
                  const SizedBox(height: 8),
                  _JsonPanel(
                    theme: theme,
                    label: 'outputPayload',
                    value: event.outputPayload,
                  ),
                ],
              ),
            ),
            if (!_isNetwork) ...[
              const SizedBox(height: 12),
              _Section(
                theme: theme,
                letter: 'B',
                title: 'Fórmulas e Equações',
                subtitle:
                    'Cada expressão como aparece na metodologia, na ordem em '
                    'que o motor a aplicou.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < event.calculations.length; i++)
                      _FormulaBlock(
                        theme: theme,
                        ordinal: i + 1,
                        trace: event.calculations[i],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                theme: theme,
                letter: 'C',
                title: 'Substituição de Variáveis e Decomposição',
                subtitle:
                    'O valor atribuído a cada símbolo e o resultado de cada '
                    'etapa intermediária. A numeração acompanha a seção B.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < event.calculations.length; i++)
                      _SubstitutionBlock(
                        theme: theme,
                        ordinal: i + 1,
                        trace: event.calculations[i],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(Color accent, bool failed) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '$ordinal',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            event.endpoint,
            overflow: TextOverflow.ellipsis,
            style: theme.mono(color: theme.text, size: 13, bold: true),
          ),
        ),
        const SizedBox(width: 8),
        if (failed)
          _Tag(theme: theme, color: theme.danger, label: 'sem modelo aplicável')
        else if (_isNetwork)
          _Tag(
            theme: theme,
            color: theme.network,
            label: 'HTTP ${event.outputPayload['statusCode'] ?? '—'}',
          )
        else
          _Tag(
            theme: theme,
            color: theme.accent,
            label: '${event.calculations.length} fórmula(s)',
          ),
      ],
    );
  }

  static String _formatTimestamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

class _Section extends StatelessWidget {
  const _Section({
    required this.theme,
    required this.letter,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final ConsoleTheme theme;
  final String letter;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'SEÇÃO $letter',
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: theme.dim, fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// ------------------------------------------------------------ Seção B: fórmulas --

class _FormulaBlock extends StatelessWidget {
  const _FormulaBlock({
    required this.theme,
    required this.ordinal,
    required this.trace,
  });

  final ConsoleTheme theme;
  final int ordinal;
  final CalculationTrace trace;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$ordinal. ${trace.formulaName}',
            style: TextStyle(
              color: theme.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                trace.latexRepresentation,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(color: theme.text, fontSize: 17),
                // Uma expressão que o renderizador não entenda não pode
                // derrubar o painel no meio da apresentação: cai para o TeX
                // literal, que ainda é auditável.
                onErrorFallback: (error) => SelectableText(
                  trace.latexRepresentation,
                  style: theme.mono(color: theme.warning, size: 12),
                ),
              ),
            ),
          ),
          if (trace.finalValue != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.arrow_right_alt, size: 15, color: theme.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: SelectableText(
                    '${_formatNumber(trace.finalValue!)}'
                    '${trace.unit.isEmpty ? '' : ' ${trace.unit}'}',
                    style: theme.mono(
                      color: theme.accent,
                      size: 12.5,
                      bold: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------- Seção C: substituição --

class _SubstitutionBlock extends StatelessWidget {
  const _SubstitutionBlock({
    required this.theme,
    required this.ordinal,
    required this.trace,
  });

  final ConsoleTheme theme;
  final int ordinal;
  final CalculationTrace trace;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$ordinal. ${trace.formulaName}',
            style: TextStyle(
              color: theme.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trace.sample != null && trace.sample!.points.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SampleChart(theme: theme, sample: trace.sample!),
          ],
          if (trace.mappedVariables.isNotEmpty) ...[
            const SizedBox(height: 10),
            _label('Variáveis mapeadas'),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < trace.mappedVariables.length; i++)
                    _variableRow(
                      trace.mappedVariables.keys.elementAt(i),
                      trace.mappedVariables.values.elementAt(i),
                      last: i == trace.mappedVariables.length - 1,
                    ),
                ],
              ),
            ),
          ],
          if (trace.intermediateSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _label('Decomposição'),
            const SizedBox(height: 6),
            for (final step in trace.intermediateSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: theme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SelectableText(
                        step,
                        style: theme
                            .mono(color: theme.text, size: 11.5)
                            .copyWith(height: 1.55),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (trace.finalValue != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                'Resultado: ${_formatNumber(trace.finalValue!)}'
                '${trace.unit.isEmpty ? '' : ' ${trace.unit}'}',
                style: theme.mono(color: theme.accent, size: 12, bold: true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: theme.dim,
      fontSize: 9.5,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    ),
  );

  Widget _variableRow(String symbol, Object? value, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: SelectableText(
              symbol,
              style: theme.mono(color: theme.jsonKey, size: 11.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              value == null
                  ? 'indisponível'
                  : (value is num ? _formatNumber(value.toDouble()) : '$value'),
              style: theme.mono(
                color: value == null ? theme.warning : theme.text,
                size: 11.5,
                bold: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------ Amostra por trás da mediana --

/// Desenha a amostra que sustentou uma estatística resumo.
///
/// O orientador pediu isto por um motivo prático: uma mediana isolada não
/// permite decidir se algum exercício deve ser expurgado. Com os pontos à
/// vista — cada um com seu ano, a banda de aceitação desenhada por cima e o
/// exercício central destacado — dá para ver de onde o número saiu e discutir
/// a janela.
///
/// O gráfico não recalcula nada: a mediana, a banda e a marcação do exercício
/// central vêm prontas do núcleo, do mesmo objeto que produziu o resultado.
/// Gráfico de amostra do console.
///
/// Envolvido em `RepaintBoundary` no próprio `build`: ele vive dentro de uma
/// lista longa e rolável, e sem a fronteira o `CustomPaint` recompõe os pixels
/// a cada quadro de rolagem.
class _SampleChart extends StatelessWidget {
  const _SampleChart({required this.theme, required this.sample});

  final ConsoleTheme theme;
  final TraceSample sample;

  bool get _winsorized {
    final observed = sample.points.where((p) => p.isObserved).firstOrNull;
    final selected = sample.selected;
    if (observed == null || selected == null) return false;
    return (observed.value - selected).abs() > 1e-9;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _caption(sample.title.isEmpty ? 'Amostra' : sample.title),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 12, 8),
            decoration: BoxDecoration(
              border: Border.all(color: theme.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 168,
                  child: CustomPaint(
                    painter: _SampleChartPainter(theme: theme, sample: sample),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 12),
                _legend(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _table(),
        ],
      ),
    );
  }

  Widget _legend() {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _legendItem(theme.accent, 'exercício central da amostra'),
        _legendItem(theme.dim, 'demais exercícios da janela'),
        _legendItem(
          _winsorized ? theme.danger : theme.network,
          _winsorized
              ? 'observado, fora da banda'
              : 'observado, dentro da banda',
        ),
        if (sample.lowerBound != null)
          _legendItem(
            theme.accent.withValues(alpha: 0.18),
            'banda de aceitação',
          ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      // Flexível para que a legenda quebre em vez de estourar: numa janela
      // de 320 px, "demais exercícios da janela" é mais largo que a faixa
      // que o Wrap tem para oferecer.
      Flexible(
        child: Text(label, style: theme.mono(color: theme.dim, size: 10)),
      ),
    ],
  );

  /// Os mesmos números em texto selecionável.
  ///
  /// O gráfico responde "de onde saiu a mediana"; a tabela é o que se copia
  /// para a defesa, e é o que resta quando o painel é lido numa impressão.
  Widget _table() {
    final points = sample.points;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < points.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: i == points.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: theme.border)),
              ),
              child: _row(points[i]),
            ),
        ],
      ),
    );
  }

  /// Uma linha da tabela.
  ///
  /// O painel também é aberto empilhado sobre a aplicação em telas estreitas,
  /// e a etiqueta é o texto de comprimento variável da linha. Numa única
  /// linha ela espremeria o valor até zero e estouraria a lateral, então
  /// abaixo de 380 px ela desce para a segunda linha em vez de disputar
  /// espaço com o número.
  Widget _row(TraceSamplePoint point) {
    final tag = _tagOf(point);
    final valor = SelectableText(
      _formatNumber(point.value),
      style: theme.mono(
        color: point.definesResult ? theme.accent : theme.text,
        size: 11.5,
        bold: point.definesResult,
      ),
    );
    final rotulo = SizedBox(
      width: 64,
      child: SelectableText(
        point.label,
        style: theme.mono(color: theme.jsonKey, size: 11.5),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  rotulo,
                  Expanded(child: valor),
                ],
              ),
              if (tag.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 64, top: 2),
                  child: Text(
                    tag,
                    style: theme.mono(color: theme.dim, size: 10),
                  ),
                ),
            ],
          );
        }
        // O valor fica sem `Expanded` de propósito: é um número curto, e
        // dando-lhe metade da linha a etiqueta seria cortada com espaço vazio
        // sobrando ao lado dela. Quem recebe o resto da largura é a etiqueta,
        // que é o texto de comprimento variável.
        return Row(
          children: [
            rotulo,
            valor,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tag,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: theme.mono(color: theme.dim, size: 10),
              ),
            ),
          ],
        );
      },
    );
  }

  String _tagOf(TraceSamplePoint point) {
    final tags = [
      if (point.definesResult) 'define a ${sample.summaryLabel}',
      if (point.isObserved) _winsorized ? 'observado · aparado' : 'observado',
    ];
    return tags.join(' · ');
  }

  Widget _caption(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: theme.dim,
      fontSize: 9.5,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    ),
  );
}

class _SampleChartPainter extends CustomPainter {
  _SampleChartPainter({required this.theme, required this.sample});

  final ConsoleTheme theme;
  final TraceSample sample;

  /// Faixa reservada aos rótulos de ano, abaixo do eixo.
  static const double _labelStrip = 18;

  /// Folga entre a ponta de uma barra cortada e a borda do quadro, onde entram
  /// a marca de corte e o valor real do exercício.
  static const double _clipInset = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sample.points;
    if (points.isEmpty || size.width <= 0) return;

    final plotHeight = size.height - _labelStrip;
    if (plotHeight <= 10) return;

    final (bottom, top) = _scale();
    double y(double value) =>
        plotHeight - (value - bottom) / (top - bottom) * plotHeight;

    final slot = size.width / points.length;
    final barWidth = math.min(34.0, slot * 0.52);

    // 1. Banda de aceitação, ao fundo.
    final low = sample.lowerBound, high = sample.upperBound;
    if (low != null && high != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(high), size.width, y(low)),
        Paint()..color = theme.accent.withValues(alpha: 0.12),
      );
      for (final edge in [low, high]) {
        _dashedLine(
          canvas,
          y(edge),
          size.width,
          theme.accent.withValues(alpha: 0.45),
        );
      }
      _text(
        canvas,
        _compact(high),
        0,
        y(high) - 12,
        theme.mono(color: theme.dim, size: 9),
        alignLeft: true,
      );
      _text(
        canvas,
        _compact(low),
        0,
        y(low) + 2,
        theme.mono(color: theme.dim, size: 9),
        alignLeft: true,
      );
    }

    // 2. Linha do zero, quando a série cruza o eixo.
    if (bottom < 0 && top > 0) {
      canvas.drawLine(
        Offset(0, y(0)),
        Offset(size.width, y(0)),
        Paint()
          ..color = theme.border
          ..strokeWidth = 1,
      );
    }

    // 3. Barras.
    final zero = y(0).clamp(0.0, plotHeight);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final center = slot * (i + 0.5);
      // Exercício fora da escala: a barra é cortada e o valor vai por escrito.
      // Deixar a escala ir até ele achataria os anos típicos e a banda contra
      // o eixo, que é justamente o que se precisa enxergar para decidir sobre
      // expurgo — e o valor cheio continua na tabela abaixo.
      final above = p.value > top;
      final below = p.value < bottom;
      // A barra cortada para antes da borda: o valor real é escrito acima
      // dela, e sem essa folga o texto sairia da moldura.
      final valueY = above
          ? _clipInset
          : below
          ? plotHeight - _clipInset
          : y(p.value);
      final rect = Rect.fromLTRB(
        center - barWidth / 2,
        math.min(valueY, zero),
        center + barWidth / 2,
        math.max(valueY, zero),
      );

      final winsorized =
          p.isObserved &&
          sample.selected != null &&
          (p.value - sample.selected!).abs() > 1e-9;
      final color = winsorized
          ? theme.danger
          : p.isObserved
          ? theme.network
          : p.definesResult
          ? theme.accent
          : theme.dim;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect.height < 2
              ? Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 2)
              : rect,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = color.withValues(alpha: p.definesResult ? 0.95 : 0.72),
      );

      // O exercício central ganha contorno: é ele que responde "de onde saiu
      // a mediana", e cor sozinha não sobrevive a uma impressão em cinza.
      if (p.definesResult) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = theme.accent,
        );
      }

      // 4. Marca de corte e o valor real, quando a barra não coube.
      if (above || below) {
        _breakMark(
          canvas,
          center,
          barWidth,
          above ? rect.top : rect.bottom,
          above,
          color,
        );
        _text(
          canvas,
          _compact(p.value),
          center,
          above ? rect.top - 14 : rect.bottom + 3,
          theme.mono(color: color, size: 9.5, bold: true),
        );
      }

      // 5. Onde o valor observado foi parar depois de aparado.
      if (winsorized) {
        final target = y(sample.selected!.clamp(bottom, top));
        canvas.drawLine(
          Offset(center - barWidth / 2 - 4, target),
          Offset(center + barWidth / 2 + 4, target),
          Paint()
            ..color = theme.accent
            ..strokeWidth = 2,
        );
        _arrow(canvas, center, valueY, target, theme.accent);
      }

      _text(
        canvas,
        p.label,
        center,
        plotHeight + 4,
        theme.mono(color: p.definesResult ? theme.accent : theme.dim, size: 10),
      );
    }

    // 6. A mediana, por último, para ficar legível sobre as barras.
    final summary = sample.summary;
    if (summary != null) {
      _dashedLine(canvas, y(summary), size.width, theme.accent);
      _text(
        canvas,
        '${sample.summaryLabel} ${_compact(summary)}',
        size.width,
        y(summary) - 13,
        theme.mono(color: theme.accent, size: 9.5, bold: true),
        alignRight: true,
      );
    }
  }

  /// Limites verticais do gráfico.
  ///
  /// A escala é governada pela **banda**, não pelo maior valor: no caso que
  /// motivou toda a normalização — SAPR11, exercício 9,5× a mediana — deixar
  /// o eixo alcançar o atípico comprime os quatro anos típicos e a banda
  /// inteira contra o zero, e o gráfico deixa de responder à única pergunta
  /// que precisa responder. O exercício que estoura o quadro sai cortado, com
  /// a marca de corte e o valor escrito ao lado.
  (double, double) _scale() {
    final values = [for (final p in sample.points) p.value];
    final low = sample.lowerBound, high = sample.upperBound;

    var bottom = math.min(0.0, values.reduce(math.min));
    var top = values.reduce(math.max);

    if (low != null && high != null) {
      final folga = (high - low) * 0.55;
      final limiteAlto = high + folga;
      final limiteBaixo = math.min(0.0, low - folga);
      // Só corta se houver o que cortar: com a série toda dentro da banda,
      // apertar a escala inventaria um corte que não existe.
      top = math.min(
        top,
        math.max(limiteAlto, _largestUpTo(values, limiteAlto)),
      );
      bottom = math.max(
        bottom,
        math.min(limiteBaixo, _smallestFrom(values, limiteBaixo)),
      );
    }

    if (sample.selected != null) {
      top = math.max(top, sample.selected!);
      bottom = math.min(bottom, math.min(0.0, sample.selected!));
    }

    if (top - bottom < 1e-12) {
      // Série constante: sem folga artificial, a conversão de valor para pixel
      // dividiria por zero e o gráfico sairia em branco.
      final unidade = top.abs() < 1e-12 ? 1.0 : top.abs() * 0.1;
      top += unidade;
      bottom -= unidade;
    }
    final span = top - bottom;
    return (bottom - span * 0.06, top + span * 0.14);
  }

  static double _largestUpTo(List<double> values, double limit) {
    final dentro = values.where((v) => v <= limit);
    return dentro.isEmpty ? limit : dentro.reduce(math.max);
  }

  static double _smallestFrom(List<double> values, double limit) {
    final dentro = values.where((v) => v >= limit);
    return dentro.isEmpty ? limit : dentro.reduce(math.min);
  }

  /// Zigue-zague na ponta da barra cortada — a convenção de eixo interrompido.
  void _breakMark(
    Canvas canvas,
    double center,
    double barWidth,
    double edge,
    bool atTop,
    Color color,
  ) {
    final left = center - barWidth / 2;
    final direction = atTop ? 1.0 : -1.0;
    final path = Path()..moveTo(left, edge + 2 * direction);
    for (var i = 0; i < 4; i++) {
      path.lineTo(
        left + barWidth * (i + 0.5) / 4,
        edge + (i.isEven ? 5 : 2) * direction,
      );
    }
    path.lineTo(left + barWidth, edge + 2 * direction);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
  }

  void _dashedLine(Canvas canvas, double atY, double width, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < width; x += 8) {
      canvas.drawLine(
        Offset(x, atY),
        Offset(math.min(x + 4, width), atY),
        paint,
      );
    }
  }

  void _arrow(Canvas canvas, double x, double from, double to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(x, from), Offset(x, to), paint);
    final direction = to > from ? 1.0 : -1.0;
    canvas.drawLine(Offset(x, to), Offset(x - 3, to - 4 * direction), paint);
    canvas.drawLine(Offset(x, to), Offset(x + 3, to - 4 * direction), paint);
  }

  void _text(
    Canvas canvas,
    String value,
    double x,
    double y,
    TextStyle style, {
    bool alignRight = false,
    bool alignLeft = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = alignRight
        ? x - painter.width - 2
        : alignLeft
        ? x + 2
        : x - painter.width / 2;
    painter.paint(canvas, Offset(left, y));
  }

  /// Forma curta para caber no gráfico — a tabela abaixo carrega o valor cheio.
  static String _compact(double value) {
    // `toStringAsFixed` não lança em valor não finito (devolve "NaN"), mas
    // "NaN" pendurado num eixo não informa nada a quem audita.
    if (!value.isFinite) return '—';
    final abs = value.abs();
    if (abs >= 1e9) return '${(value / 1e9).toStringAsFixed(2)} bi';
    if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(2)} mi';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(1)} mil';
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _SampleChartPainter old) =>
      old.sample != sample || old.theme.dark != theme.dark;
}

// ------------------------------------------------------------- Visualizador JSON --

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({
    required this.theme,
    required this.label,
    required this.value,
  });

  final ConsoleTheme theme;
  final String label;
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.mono(color: theme.dim, size: 10.5, bold: true),
                  ),
                ),
                InkWell(
                  onTap: () => Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert(value),
                    ),
                  ),
                  child: Icon(
                    Icons.copy_all_outlined,
                    size: 14,
                    color: theme.dim,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _JsonNode(theme: theme, value: value, depth: 0),
            ),
          ),
        ],
      ),
    );
  }
}

/// Árvore JSON expansível.
///
/// Um bloco de texto indentado bastaria para ler o payload, mas não para
/// *navegar* nele durante uma arguição: o insumo de uma avaliação traz seis
/// exercícios com uma dezena de campos cada, e rolar tudo para achar um número
/// é o oposto do que o painel existe para fazer. Os dois primeiros níveis
/// abrem sozinhos; o resto abre sob demanda.
class _JsonNode extends StatefulWidget {
  const _JsonNode({
    required this.theme,
    required this.value,
    required this.depth,
    this.name,
  });

  final ConsoleTheme theme;
  final Object? value;
  final int depth;
  final String? name;

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded = widget.depth < 2;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final value = widget.value;

    if (value is Map) {
      return _branch(
        theme: theme,
        open: '{',
        close: '}',
        summary: '${value.length} campo(s)',
        children: [
          for (final entry in value.entries)
            _JsonNode(
              theme: theme,
              value: entry.value,
              depth: widget.depth + 1,
              name: '${entry.key}',
            ),
        ],
      );
    }

    if (value is List) {
      return _branch(
        theme: theme,
        open: '[',
        close: ']',
        summary: '${value.length} item(ns)',
        children: [
          for (var i = 0; i < value.length; i++)
            _JsonNode(
              theme: theme,
              value: value[i],
              depth: widget.depth + 1,
              name: '$i',
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: SelectableText.rich(
        TextSpan(
          children: [
            if (widget.name != null)
              TextSpan(
                text: '${widget.name}: ',
                style: theme.mono(color: theme.jsonKey, size: 11.5),
              ),
            TextSpan(
              text: _scalarText(value),
              style: theme.mono(color: _scalarColor(theme, value), size: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _branch({
    required ConsoleTheme theme,
    required String open,
    required String close,
    required String summary,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: theme.dim,
                ),
                if (widget.name != null)
                  Text(
                    '${widget.name}: ',
                    style: theme.mono(color: theme.jsonKey, size: 11.5),
                  ),
                Text(
                  _expanded ? open : '$open … $close',
                  style: theme.mono(color: theme.dim, size: 11.5),
                ),
                const SizedBox(width: 6),
                Text(summary, style: theme.mono(color: theme.dim, size: 10)),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(close, style: theme.mono(color: theme.dim, size: 11.5)),
          ),
      ],
    );
  }

  static String _scalarText(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is num) return _formatNumber(value.toDouble());
    return '$value';
  }

  static Color _scalarColor(ConsoleTheme theme, Object? value) {
    if (value == null) return theme.warning;
    if (value is String) return theme.jsonString;
    if (value is num) return theme.jsonNumber;
    if (value is bool) return theme.jsonBool;
    return theme.text;
  }
}

// ---------------------------------------------------------------- Componentes --

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.theme,
    required this.ok,
    required this.label,
    this.neutral = false,
  });

  final ConsoleTheme theme;
  final bool ok;
  final bool neutral;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = neutral ? theme.dim : (ok ? theme.accent : theme.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          // "Entrega local (mesma janela)" não cabe na faixa de um Wrap de
          // 288 dp: flexível, o rótulo quebra dentro da pílula em vez de
          // estourar. Sem elipse de propósito — um estado do canal cortado
          // pela metade não informa nada.
          Flexible(
            child: Text(label, style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.theme, required this.color, required this.label});

  final ConsoleTheme theme;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: theme.mono(color: color, size: 10.5, bold: true),
      ),
    );
  }
}

class _ConsoleButton extends StatelessWidget {
  const _ConsoleButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final ConsoleTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? theme.warning : theme.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? theme.warning.withValues(alpha: 0.12)
              : theme.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? theme.warning.withValues(alpha: 0.4) : theme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            // "Exportar Auditoria (JSON)" estoura a faixa do Wrap em 320 dp.
            // O rótulo é o nome da ação: quebra em duas linhas, não corta.
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: color, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ConsoleTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? theme.accent : theme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.accent : theme.dim,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- Tema --

/// Formata número para leitura, sem notação científica em valores grandes.
String _formatNumber(double value) {
  if (!value.isFinite) return '$value';
  // Epsilon, e nao `==`: um valor que deveria ser inteiro mas passou por
  // aritmetica binaria chega como 1.0000000000000002, escapa do caminho limpo
  // e o console mostra a sujeira decimal. Com tolerancia, ele formata como o
  // inteiro que de fato representa.
  if ((value - value.roundToDouble()).abs() < 1e-9 && value.abs() < 1e15) {
    return _groupThousands(value.round().toString());
  }
  final text = value.toStringAsFixed(value.abs() < 1 ? 6 : 2);
  final parts = text.split('.');
  return '${_groupThousands(parts.first)}.${parts.last}';
}

String _groupThousands(String digits) {
  final negative = digits.startsWith('-');
  final body = negative ? digits.substring(1) : digits;
  final buffer = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    if (i > 0 && (body.length - i) % 3 == 0) buffer.write('.');
    buffer.write(body[i]);
  }
  return '${negative ? '-' : ''}$buffer';
}
