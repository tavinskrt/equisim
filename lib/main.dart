//import 'dart:convert';
import 'package:flutter/material.dart';
//import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/stock.dart';
import 'services/stock_service.dart';


Future<void> main() async {
  // Garante que o Flutter esteja pronto para carregar o .env
  WidgetsFlutterBinding.ensureInitialized();    
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('✅ .env carregado com sucesso');
  } catch (e) {
    debugPrint('⚠️ Aviso ao carregar .env: $e');
  }
  runApp(const MyApp());
}



class MyApp extends StatelessWidget {
  //Mantendo o padrão de construtor com super.key(identidade do widget passada pro pai, sem 
  //super.key as keys não fazem nada) para compatibilidade futura e melhores práticas. 
  const MyApp({super.key});
  //@override não faz o código funcionar — ele evita que você escreva código errado sem perceber. 
  //Ele é uma anotação que indica que o método build() está sobrescrevendo um método da classe pai (StatelessWidget).
  @override
  Widget build(BuildContext context) {
    // O MaterialApp é o widget raiz da aplicação, que configura temas, rotas e a tela inicial.
    return MaterialApp(
      title: 'Stocks App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const StockPage(),
    );
  }
}



class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  // O createState é um método obrigatório para StatefulWidgets, que cria a instância do estado associado a este widget.
  State<StockPage> createState() => _StockPageState();
}



class _StockPageState extends State<StockPage> {
  List<Stock> stocks = [];
  bool isLoading = false;
  String? errorMessage;
  // 'late' indica que a variável será inicializada posteriormente, mas antes de ser usada.
  // O TextEditingController é usado para controlar o texto de um TextField.
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

  Future<void> fetchStocks() async {
    final ticker = _tickerController.text.trim().toUpperCase();
    if (ticker.isEmpty) {
      setState(() {
        errorMessage = 'Por favor, digite um ticker';
      });
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final stockServices = StockService();
    try {
      final loadedStocks = await stockServices.fetchStocks(ticker);
      setState(() {
        stocks = loadedStocks;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Ações'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _tickerController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Digite o ticker da ação',
                    hintText: 'Ex: PETR4, VALE3, ITUB4',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.trending_up),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : fetchStocks,
                    icon: const Icon(Icons.search),
                    label: const Text('Simular'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error, size: 50, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      )
                    : stocks.isEmpty
                        ? const Center(child: Text('Digite um ticker e clique em Simular'))
                        : ListView.builder(
                            itemCount: stocks.length,
                            itemBuilder: (context, index) {
                              final stock = stocks[index];
                              return ListTile(
                                title: Text(stock.date),
                                subtitle: Text('Preço: R\$ ${stock.close.toStringAsFixed(2)}'),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}