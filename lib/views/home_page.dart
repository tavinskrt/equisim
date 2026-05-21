import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../controllers/home_controller.dart';
import 'package:intl/intl.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(),
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatelessWidget {
  const _HomeScreenContent();

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<HomeController>(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B1E4B),
              Color(0xFF0F2C6A),
              Color(0xFF0D3D2F),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            /// Decorações geométricas de fundo
            Positioned(
              top: -100,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00B37E).withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00B37E).withValues(alpha: 0.05),
                ),
              ),
            ),

            /// Conteúdo Principal
            Column(
              children: [
                /// Header Fixado
                ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.only(top: 52, left: 20, right: 20, bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1E4B).withValues(alpha: 0.6),
                        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(9),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF00B37E), Color(0xFF00CC8F)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00B37E).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.show_chart, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Equisim',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.1,
                                    ),
                                  ),
                                  Text(
                                    'NOVA SIMULAÇÃO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white.withValues(alpha: 0.4),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00B37E).withValues(alpha: 0.18),
                              border: Border.all(color: const Color(0xFF00B37E).withValues(alpha: 0.35), width: 1.5),
                            ),
                            child: const Icon(Icons.person_outline, color: Color(0xFF00B37E), size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                /// Corpo expansível
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        /// 1. ATIVOS
                        _SectionCard(
                          icon: Icons.ssid_chart,
                          title: 'Ativos',
                          subtitle: 'Tickers para comparação',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AÇÕES',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(controller.acoes.length, (index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _TickerInput(
                                    value: controller.acoes[index],
                                    placeholder: 'Ex.: PETR4',
                                    onChange: (v) => controller.updateAcao(index, v),
                                    onRemove: controller.acoes.length > 1 ? () => controller.removeAcao(index) : null,
                                  ),
                                );
                              }),
                              if (controller.acoes.length < 6)
                                _AddButton(label: 'Adicionar ação', onClick: controller.addAcao),
                              
                              Container(height: 1, color: Colors.white.withValues(alpha: 0.07), margin: const EdgeInsets.symmetric(vertical: 12)),
                              
                              Text(
                                'FUNDOS IMOBILIÁRIOS',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(controller.fiis.length, (index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _TickerInput(
                                    value: controller.fiis[index],
                                    placeholder: 'Ex.: HGLG11',
                                    onChange: (v) => controller.updateFii(index, v),
                                    onRemove: controller.fiis.length > 1 ? () => controller.removeFii(index) : null,
                                  ),
                                );
                              }),
                              if (controller.fiis.length < 6)
                                _AddButton(label: 'Adicionar FII', onClick: controller.addFii),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        /// 2. PERÍODO
                        _SectionCard(
                          icon: Icons.calendar_month_outlined,
                          title: 'Período',
                          subtitle: 'Janela histórica de análise',
                          child: Row(
                            children: [
                              Expanded(
                                child: _DatePickerField(
                                  label: 'Data inicial',
                                  selectedDate: controller.startDate,
                                  onSelect: (date) => controller.setStartDate(date),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _DatePickerField(
                                  label: 'Data final',
                                  selectedDate: controller.endDate,
                                  onSelect: (date) => controller.setEndDate(date),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        /// 3. APORTE
                        _SectionCard(
                          icon: Icons.attach_money,
                          title: 'Aporte mensal',
                          subtitle: 'Valor investido por mês',
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 14, right: 8),
                                  child: Text(
                                    'R\$',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.35)),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    onChanged: controller.setAporte,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: '0,00',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                                    ),
                                    controller: TextEditingController.fromValue(
                                      TextEditingValue(
                                        text: controller.aporte,
                                        selection: TextSelection.collapsed(offset: controller.aporte.length),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        /// 4. MÉTODO DE VALUATION
                        _SectionCard(
                          icon: Icons.pie_chart_outline,
                          title: 'Método de Valuation',
                          subtitle: 'Critério de avaliação intrínseca',
                          child: GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                            childAspectRatio: 2.5,
                            children: [
                              _ValuationButton(
                                id: 'graham', label: 'Graham', desc: 'P/L e P/VP',
                                selected: controller.valuation == 'graham',
                                onTap: () => controller.setValuation('graham'),
                              ),
                              _ValuationButton(
                                id: 'bazin', label: 'Bazin', desc: 'Dividend Yield',
                                selected: controller.valuation == 'bazin',
                                onTap: () => controller.setValuation('bazin'),
                              ),
                              _ValuationButton(
                                id: 'lynch', label: 'Peter Lynch', desc: 'PEG Ratio',
                                selected: controller.valuation == 'lynch',
                                onTap: () => controller.setValuation('lynch'),
                              ),
                              _ValuationButton(
                                id: 'dcf', label: 'DCF Simplificado', desc: 'Fluxo de Caixa',
                                selected: controller.valuation == 'dcf',
                                onTap: () => controller.setValuation('dcf'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        /// 5. PARÂMETROS
                        _SectionCard(
                          icon: Icons.tune,
                          title: 'Parâmetros',
                          subtitle: 'Configurações da simulação',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Margem de Segurança', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.55))),
                                  Text('Desconto mínimo sobre o valor intrínseco', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        onChanged: controller.setMargem,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: 25',
                                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                                        ),
                                        controller: TextEditingController.fromValue(
                                          TextEditingValue(
                                            text: controller.margem,
                                            selection: TextSelection.collapsed(offset: controller.margem.length),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 14),
                                      child: Text(
                                        '%',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.35)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              if (controller.margem.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Stack(
                                  children: [
                                    Container(
                                      height: 4,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: (int.tryParse(controller.margem) ?? 0).clamp(0, 100) / 100.0,
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Color(0xFF00B37E), Color(0xFF00CC8F)]),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('0%', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.25))),
                                    Text('${controller.margem}% selecionado', style: const TextStyle(fontSize: 10, color: Color(0xFF00B37E), fontWeight: FontWeight.w600)),
                                    Text('100%', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.25))),
                                  ],
                                ),
                              ],
                              
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.3), size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'O ativo será considerado comprável somente se seu preço atual estiver pelo menos este percentual abaixo do valor intrínseco calculado.',
                                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3), height: 1.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        /// EXECUTAR
                        Container(
                          width: double.infinity,
                          height: 54,
                          margin: const EdgeInsets.only(top: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF00B37E), Color(0xFF00CC8F)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B37E).withValues(alpha: 0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Ação de Executar Simulação
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                            label: const Text(
                              'Executar Simulação',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Componentes Auxiliares
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF00B37E).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF00B37E).withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFF00B37E), size: 16),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.38))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TickerInput extends StatelessWidget {
  final String value;
  final String placeholder;
  final Function(String) onChange;
  final VoidCallback? onRemove;

  const _TickerInput({required this.value, required this.placeholder, required this.onChange, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: TextField(
              onChanged: onChange,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              controller: TextEditingController.fromValue(
                TextEditingValue(
                  text: value,
                  selection: TextSelection.collapsed(offset: value.length),
                ),
              ),
            ),
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.close, color: Color(0xFFEF4444), size: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onClick;

  const _AddButton({required this.label, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClick,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF00B37E).withValues(alpha: 0.3), style: BorderStyle.solid), // Flutter doesn't have native dashed borders easily, solid is fine for now
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Color(0xFF00B37E), size: 14),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00B37E))),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? selectedDate;
  final Function(DateTime) onSelect;

  const _DatePickerField({required this.label, required this.selectedDate, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 0.3)),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date != null) onSelect(date);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              selectedDate != null ? DateFormat('dd/MM/yyyy').format(selectedDate!) : 'Selecionar',
              style: TextStyle(
                fontSize: 12,
                color: selectedDate != null ? Colors.white : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ValuationButton extends StatelessWidget {
  final String id;
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _ValuationButton({required this.id, required this.label, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00B37E).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: selected ? const Color(0xFF00B37E).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08), width: selected ? 1.5 : 1.0),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: selected ? const Color(0xFF00CC8F) : Colors.white)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35))),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF00B37E), Color(0xFF00CC8F)]),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
