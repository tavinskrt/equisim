import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../audit/audit_bus.dart';
import '../../audit/audit_export_stub.dart'
    if (dart.library.js_interop) '../../audit/audit_export_web.dart' as export_impl;

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
    return event.calculations
        .any((c) => c.formulaName.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final theme = _ConsoleTheme(_dark);
    final events = _visible;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
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
      'totalDeCalculos':
          events.fold<int>(0, (sum, e) => sum + e.calculations.length),
      'filtroAplicado': _filter.name,
      'eventos': [for (final e in events) e.toJson()],
    });

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final saved =
        export_impl.downloadJson('equisim-auditoria-$stamp.json', document);

    if (!saved) {
      // Fora do navegador não há download; a área de transferência entrega o
      // mesmo conteúdo sem inventar um caminho de arquivo.
      Clipboard.setData(ClipboardData(text: document));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? 'Auditoria exportada: ${events.length} eventos.'
          : 'Auditoria copiada para a área de transferência '
              '(${events.length} eventos).'),
      behavior: SnackBarBehavior.floating,
    ));
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

  final _ConsoleTheme theme;
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
                  Text(
                    'Painel de Auditoria de Cálculos',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
                label: autoScroll ? 'Pausar Auto-scroll' : 'Retomar Auto-scroll',
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
                icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

  final _ConsoleTheme theme;
  final AuditBus bus;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                      'backtest. Cada requisição à API e cada fórmula avaliada '
                      'aparece aqui no instante em que acontece.'
                  : 'Use a aplicação normalmente: as execuções aparecem aqui '
                      'assim que ocorrerem.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.dim, fontSize: 13, height: 1.5),
            ),
          ],
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
  final _ConsoleTheme theme;

  bool get _isNetwork => event.calculations.isEmpty;

  @override
  Widget build(BuildContext context) {
    final status = event.outputPayload['status'];
    final failed = status == 'falha';
    final accent =
        failed ? theme.danger : (_isNetwork ? theme.network : theme.accent);

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

  final _ConsoleTheme theme;
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

  final _ConsoleTheme theme;
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

  final _ConsoleTheme theme;
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
                  for (var i = 0;
                      i < trace.mappedVariables.length;
                      i++)
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
                        style: theme.mono(color: theme.text, size: 11.5)
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
        border: last
            ? null
            : Border(bottom: BorderSide(color: theme.border)),
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

// ------------------------------------------------------------- Visualizador JSON --

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({
    required this.theme,
    required this.label,
    required this.value,
  });

  final _ConsoleTheme theme;
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
                  onTap: () => Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(value),
                  )),
                  child: Icon(Icons.copy_all_outlined,
                      size: 14, color: theme.dim),
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

  final _ConsoleTheme theme;
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
        TextSpan(children: [
          if (widget.name != null)
            TextSpan(
              text: '${widget.name}: ',
              style: theme.mono(color: theme.jsonKey, size: 11.5),
            ),
          TextSpan(
            text: _scalarText(value),
            style: theme.mono(color: _scalarColor(theme, value), size: 11.5),
          ),
        ]),
      ),
    );
  }

  Widget _branch({
    required _ConsoleTheme theme,
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
                Text(
                  summary,
                  style: theme.mono(color: theme.dim, size: 10),
                ),
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
            child: Text(
              close,
              style: theme.mono(color: theme.dim, size: 11.5),
            ),
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

  static Color _scalarColor(_ConsoleTheme theme, Object? value) {
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

  final _ConsoleTheme theme;
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
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.theme, required this.color, required this.label});

  final _ConsoleTheme theme;
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

  final _ConsoleTheme theme;
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
            Text(label, style: TextStyle(color: color, fontSize: 11.5)),
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

  final _ConsoleTheme theme;
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
          border: Border.all(
            color: selected ? theme.accent : theme.border,
          ),
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

/// Paleta do console.
///
/// Independente do tema da aplicação de propósito: a janela de auditoria é uma
/// instância separada, sem sessão e sem preferências carregadas, e o painel
/// costuma ser projetado num telão — onde ora o escuro, ora o claro é o
/// legível. O alternador local resolve isso sem arrastar o controlador de tema
/// e sua dependência de Firebase para dentro do painel.
class _ConsoleTheme {
  const _ConsoleTheme(this.dark);

  final bool dark;

  Color get background =>
      dark ? const Color(0xFF0B1020) : const Color(0xFFF4F6FB);
  Color get panel => dark ? const Color(0xFF121A33) : Colors.white;
  Color get border =>
      dark ? const Color(0xFF25314F) : const Color(0xFFDDE3F0);
  Color get text => dark ? const Color(0xFFE6ECFA) : const Color(0xFF0B1E4B);
  Color get dim => dark ? const Color(0xFF8494B8) : const Color(0xFF7A88A6);

  Color get accent => const Color(0xFF00B37E);
  Color get network => const Color(0xFF4C8DFF);
  Color get warning => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get danger => const Color(0xFFEF4444);

  Color get jsonKey => dark ? const Color(0xFF7FD1FF) : const Color(0xFF0A6C9E);
  Color get jsonString =>
      dark ? const Color(0xFFB6E3A8) : const Color(0xFF2E7D32);
  Color get jsonNumber =>
      dark ? const Color(0xFFFFC48A) : const Color(0xFFB45309);
  Color get jsonBool =>
      dark ? const Color(0xFFD8A6FF) : const Color(0xFF7B1FA2);

  /// Estilo monoespaçado com cadeia de reserva.
  ///
  /// O alvo web não embarca fonte monoespaçada; a lista cobre Windows, macOS e
  /// Linux para que o alinhamento das colunas de números não dependa de qual
  /// máquina abrir o painel na apresentação.
  TextStyle mono({
    required Color color,
    double size = 12,
    bool bold = false,
  }) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontFamily: 'monospace',
        fontFamilyFallback: const [
          'Consolas',
          'Menlo',
          'DejaVu Sans Mono',
          'Courier New',
          'monospace',
        ],
      );
}

/// Formata número para leitura, sem notação científica em valores grandes.
String _formatNumber(double value) {
  if (!value.isFinite) return '$value';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
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
