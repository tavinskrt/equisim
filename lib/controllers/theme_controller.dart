import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Controlador responsável pelo tema da aplicação (Modo Escuro / Modo Claro).
class ThemeController extends ChangeNotifier {
  /// Chave da preferência local. Também é o nome do campo no Firestore.
  static const String prefsKey = 'isLightMode';

  bool _isLightMode;

  /// `true` para o tema claro. Padrão `false` — a aplicação abre no escuro.
  bool get isLightMode => _isLightMode;

  /// Construtor privado: a instância só nasce com a preferência já conhecida.
  ThemeController._(this._isLightMode);

  /// Lê a preferência salva **antes** de construir o controlador.
  ///
  /// A versão anterior disparava a leitura assíncrona de dentro do construtor,
  /// sem aguardar: o controlador nascia no escuro e notificava os ouvintes
  /// quando a preferência chegava. Para quem usa o tema claro, isso era um
  /// flash escuro em toda abertura do aplicativo.
  ///
  /// Aguardar aqui custa uma ida ao disco no arranque — a mesma que o
  /// `dotenv.load` já paga em `main` — e elimina a troca visível.
  ///
  /// Falha de plataforma cai no padrão escuro em vez de impedir a partida:
  /// abrir no tema errado é incômodo, não abrir é defeito.
  static Future<ThemeController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ThemeController._(prefs.getBool(prefsKey) ?? false);
    } catch (error) {
      debugPrint('Preferência de tema indisponível; abrindo no escuro: $error');
      return ThemeController._(false);
    }
  }

  /// Alterna o tema da aplicação e salva a preferência tanto localmente quanto no Firestore.
  Future<void> toggleTheme(String? uid) async {
    _isLightMode = !_isLightMode;
    notifyListeners();

    // Salva a configuração localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, _isLightMode);

    // Salva a configuração na nuvem caso o usuário esteja autenticado
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          prefsKey: _isLightMode,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Erro ao salvar preferência de tema no Firestore: $e');
      }
    }
  }

  /// Sincroniza a preferência de tema do usuário a partir dos dados do Firestore.
  Future<void> syncWithFirebase(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey(prefsKey)) {
        final cloudIsLight = doc.data()![prefsKey] as bool;
        if (cloudIsLight != _isLightMode) {
          _isLightMode = cloudIsLight;
          notifyListeners();
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(prefsKey, _isLightMode);
        }
      } else {
        // Se o usuário não possuir configuração salva na nuvem, salva o tema atual
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          prefsKey: _isLightMode,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar preferência de tema com o Firestore: $e');
    }
  }
}
