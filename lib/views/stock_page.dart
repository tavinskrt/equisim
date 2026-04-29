import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/stock_controller.dart';

/// Tela principal de busca de ações
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late TextEditingController _tickerController;

  @override
  void initState() {
    super.initState();
    _tickerController = TextEditingController();
  }

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulainvest'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSearchWidget(),
            const SizedBox(height: 24),
            Expanded(
              child: _buildStockListWidget(),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para buscar ações
  Widget _buildSearchWidget() {
    return Consumer<StockController>(
      builder: (context, controller, _) {
        return Column(
          children: [
            TextField(
              controller: _tickerController,
              decoration: InputDecoration(
                hintText: 'Digite o ticker (ex: PETR4)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: controller.isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              enabled: !controller.isLoading,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.isLoading
                    ? null
                    : () {
                        controller.clearStocks();
                        controller.fetchStocks(_tickerController.text);
                      },
                child: const Text('Buscar'),
              ),
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Widget para listar ações
  Widget _buildStockListWidget() {
    return Consumer<StockController>(
      builder: (context, controller, _) {
        if (controller.stocks.isEmpty && !controller.isLoading) {
          return Center(
            child: Text(
              controller.errorMessage ?? 'Nenhuma ação buscada',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        return ListView.builder(
          itemCount: controller.stocks.length,
          itemBuilder: (context, index) {
            final stock = controller.stocks[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(stock.date),
                trailing: Text(
                  'R\$ ${stock.close.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
