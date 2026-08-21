import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../utils/app_colors.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import 'study_notifier.dart';

/// Abre o seletor de ativos.
Future<void> showAssetPicker(
  BuildContext context, {
  required bool toPrincipal,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssetPickerSheet(toPrincipal: toPrincipal),
    );

class _AssetPickerSheet extends ConsumerStatefulWidget {
  final bool toPrincipal;
  const _AssetPickerSheet({required this.toPrincipal});

  @override
  ConsumerState<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends ConsumerState<_AssetPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(isLightModeProvider);
    final universe = ref.watch(universeProvider);
    final study = ref.watch(studyProvider).study;

    final already = <Ticker>{
      ...study.principal.tickers,
      ...study.reserva.tickers,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF0F2148),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted(isLight),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            SectionHeader(
              isLight: isLight,
              title: widget.toPrincipal
                  ? 'Adicionar à Principal'
                  : 'Adicionar à Reserva',
              subtitle: 'Ações da B3 — fundos imobiliários estão fora do escopo',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toUpperCase()),
              style: TextStyle(color: AppColors.textPrimary(isLight)),
              decoration: InputDecoration(
                hintText: 'Buscar ticker (ex.: PETR4)',
                hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                prefixIcon: Icon(Icons.search,
                    size: 19, color: AppColors.textSecondary(isLight)),
                filled: true,
                fillColor: AppColors.inputBackground(isLight),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: universe.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  isLight: isLight,
                  icon: Icons.cloud_off,
                  title: 'Universo indisponível',
                  message: 'Não foi possível carregar a lista de ações da B3.',
                ),
                data: (tickers) {
                  final filtered = tickers
                      .where((t) =>
                          _query.isEmpty || t.value.startsWith(_query))
                      .take(200)
                      .toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      isLight: isLight,
                      icon: Icons.search_off,
                      title: 'Nada encontrado',
                      message: 'Nenhuma ação corresponde a "$_query".',
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final ticker = filtered[index];
                      final isUsed = already.contains(ticker);
                      return _AssetOption(
                        ticker: ticker,
                        isUsed: isUsed,
                        isLight: isLight,
                        onTap: isUsed ? null : () => _add(ticker),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Busca o perfil antes de inserir: sem a classificação setorial, o alerta
  /// de concentração — requisito funcional — não teria como operar.
  Future<void> _add(Ticker ticker) async {
    final asset = await ref.read(assetProfileProvider(ticker).future);
    if (!mounted) return;

    ref.read(studyProvider.notifier).addAsset(
          asset ?? Asset(ticker: ticker, name: ticker.value),
          toPrincipal: widget.toPrincipal,
        );
    if (mounted) Navigator.pop(context);
  }
}

class _AssetOption extends StatelessWidget {
  final Ticker ticker;
  final bool isUsed;
  final bool isLight;
  final VoidCallback? onTap;

  const _AssetOption({
    required this.ticker,
    required this.isUsed,
    required this.isLight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      enabled: !isUsed,
      title: Text(
        ticker.value,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: isUsed
              ? AppColors.textMuted(isLight)
              : AppColors.textPrimary(isLight),
        ),
      ),
      subtitle: isUsed
          ? Text(
              'Já está no estudo',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted(isLight),
              ),
            )
          : null,
      trailing: Icon(
        isUsed ? Icons.check : Icons.add,
        size: 17,
        color: isUsed ? AppColors.textMuted(isLight) : AppColors.primary,
      ),
    );
  }
}
