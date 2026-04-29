import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'controllers/stock_controller.dart';
import 'views/stock_page.dart';


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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StockController()),
      ],
      child: MaterialApp(
        title: 'Simulainvest',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: const StockPage(),
      ),
    );
  }
}