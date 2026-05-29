import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Controlador responsável pelo tema da aplicação (Modo Escuro / Modo Claro).
class ThemeController extends ChangeNotifier {
  bool _isLightMode = false; // Padrão escuro
  bool get isLightMode => _isLightMode;

  ThemeController() {
    _loadThemeFromPrefs();
  }

  /// Carrega as preferências de tema salvas localmente no dispositivo.
  Future<void> _loadThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isLightMode = prefs.getBool('isLightMode') ?? false;
    notifyListeners();
  }

  /// Alterna o tema da aplicação e salva a preferência tanto localmente quanto no Firestore.
  Future<void> toggleTheme(String? uid) async {
    _isLightMode = !_isLightMode;
    notifyListeners();

    // Salva a configuração localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLightMode', _isLightMode);

    // Salva a configuração na nuvem caso o usuário esteja autenticado
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'isLightMode': _isLightMode,
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
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('isLightMode')) {
        final cloudIsLight = doc.data()!['isLightMode'] as bool;
        if (cloudIsLight != _isLightMode) {
          _isLightMode = cloudIsLight;
          notifyListeners();
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLightMode', _isLightMode);
        }
      } else {
        // Se o usuário não possuir configuração salva na nuvem, salva o tema atual
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'isLightMode': _isLightMode,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar preferência de tema com o Firestore: $e');
    }
  }
}
