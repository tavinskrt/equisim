import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ThemeController extends ChangeNotifier {
  bool _isLightMode = false;
  bool get isLightMode => _isLightMode;

  ThemeController() {
    _loadThemeFromPrefs();
  }

  Future<void> _loadThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isLightMode = prefs.getBool('isLightMode') ?? false; // default escuro
    notifyListeners();
  }

  Future<void> toggleTheme(String? uid) async {
    _isLightMode = !_isLightMode;
    notifyListeners();

    // Salvar localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLightMode', _isLightMode);

    // Salvar na nuvem se o usuário estiver logado
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'isLightMode': _isLightMode,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Erro ao salvar tema no Firestore: $e');
      }
    }
  }

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
        // Se não tem no firebase, salva a preferência atual
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'isLightMode': _isLightMode,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar tema com o Firestore: $e');
    }
  }
}
