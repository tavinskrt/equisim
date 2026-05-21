import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HomeController extends ChangeNotifier {
  List<String> acoes = [''];
  List<String> fiis = [''];
  DateTime? startDate;
  DateTime? endDate;
  String aporte = '';
  String valuation = 'graham';
  String margem = '';

  void addAcao() {
    if (acoes.length < 6) {
      acoes.add('');
      notifyListeners();
    }
  }

  void removeAcao(int index) {
    if (acoes.length > 1) {
      acoes.removeAt(index);
      notifyListeners();
    }
  }

  void updateAcao(int index, String value) {
    acoes[index] = value.toUpperCase();
    notifyListeners();
  }

  void addFii() {
    if (fiis.length < 6) {
      fiis.add('');
      notifyListeners();
    }
  }

  void removeFii(int index) {
    if (fiis.length > 1) {
      fiis.removeAt(index);
      notifyListeners();
    }
  }

  void updateFii(int index, String value) {
    fiis[index] = value.toUpperCase();
    notifyListeners();
  }

  void setStartDate(DateTime date) {
    startDate = date;
    notifyListeners();
  }

  void setEndDate(DateTime date) {
    endDate = date;
    notifyListeners();
  }

  void setAporte(String value) {
    String num = value.replaceAll(RegExp(r'\D'), '');
    if (num.isEmpty) {
      aporte = '';
    } else {
      int cents = int.parse(num);
      double val = cents / 100;
      final formatCurrency = NumberFormat.currency(locale: "pt_BR", symbol: "");
      aporte = formatCurrency.format(val).trim();
    }
    notifyListeners();
  }

  void setValuation(String methodId) {
    valuation = methodId;
    notifyListeners();
  }

  void setMargem(String value) {
    String raw = value.replaceAll(RegExp(r'\D'), '');
    if (raw.isNotEmpty) {
      int m = int.parse(raw);
      if (m > 100) return;
      margem = m.toString();
    } else {
      margem = '';
    }
    notifyListeners();
  }
}
