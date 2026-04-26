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

  Future<void> fetchStocks() async {
  setState(() {
    isLoading = true;
    errorMessage = null;
  });

  final stockServices = StockService();
  try {
    final loadedStocks = await stockServices.fetchStocks('PETR4');

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
  void initState() {
    super.initState();
    fetchStocks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Ações'),
      ),
      body: isLoading
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
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: fetchStocks,
                          child: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : stocks.isEmpty
                  ? const Center(child: Text('Nenhum dado disponível'))
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
    );
  }
}