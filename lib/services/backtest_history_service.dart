import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../models/backtest.dart';

/// Modelo compacto de métricas de risco calculadas
class RiskMetrics {
  final double volatility;
  final double maxDrawdown;
  final double sharpe;

  RiskMetrics({
    required this.volatility,
    required this.maxDrawdown,
    required this.sharpe,
  });

  /// Calcula métricas de risco (Volatilidade, Max Drawdown, Sharpe)
  /// com base na curva histórica de patrimônio e no CAGR.
  static RiskMetrics calculate(List<double> values, double cagr) {
    if (values.isEmpty) {
      return RiskMetrics(volatility: 0.0, maxDrawdown: 0.0, sharpe: 0.0);
    }

    // 1. Max Drawdown (Pior queda pico a vale)
    double maxDd = 0.0;
    double peak = double.negativeInfinity;
    for (final val in values) {
      if (val > peak) {
        peak = val;
      }
      if (peak > 0) {
        final dd = (val - peak) / peak;
        if (dd < maxDd) {
          maxDd = dd;
        }
      }
    }
    final double maxDrawdownPct = maxDd * 100.0;

    // 2. Volatilidade Anualizada
    // Calcula retornos diários
    final List<double> returns = [];
    for (int i = 1; i < values.length; i++) {
      if (values[i - 1] > 0) {
        returns.add((values[i] - values[i - 1]) / values[i - 1]);
      }
    }

    double volPct = 0.0;
    if (returns.isNotEmpty) {
      final double mean = returns.reduce((a, b) => a + b) / returns.length;
      final double variance = returns.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / returns.length;
      final double dailyVol = sqrt(variance);
      // Anualização com base em 252 dias úteis
      final double annualizedVol = dailyVol * sqrt(252);
      volPct = annualizedVol * 100.0;
    }

    // 3. Índice Sharpe (Taxa livre de risco presumida de 6% a.a.)
    double sharpeRatio = 0.0;
    if (volPct > 0) {
      sharpeRatio = (cagr - 6.0) / volPct;
    }

    return RiskMetrics(
      volatility: volPct,
      maxDrawdown: maxDrawdownPct,
      sharpe: sharpeRatio,
    );
  }
}

/// Serviço responsável pelo CRUD seguro dos resultados de Backtest no Firebase Firestore.
class BacktestHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Salva um resultado de backtest de forma compacta e segura para o usuário especificado.
  Future<void> saveBacktest(String userId, BacktestResult result) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError('O ID do usuário não pode estar vazio para salvamento.');
    }

    try {
      final s1 = result.scenario1;
      final s2 = result.scenario2;
      final config = result.config;

      // Extrai as curvas de patrimônio
      final List<double> s1Values = s1.monthlyPositions.map((p) => p.getAssetValue()).toList();
      final List<double> s2Values = s2.monthlyPositions.map((p) => p.getAssetValue()).toList();
      final List<String> dates = s1.monthlyPositions.map((p) => DateFormat('dd/MM/yyyy').format(p.date)).toList();

      // Calcula as métricas de risco para ambos os cenários
      final s1Metrics = RiskMetrics.calculate(s1Values, s1.cagr);
      final s2Metrics = RiskMetrics.calculate(s2Values, s2.cagr);

      // Calcula o período em meses pré-calculado
      final int periodMonths = ((config.endDate.year - config.startDate.year) * 12) +
          config.endDate.month -
          config.startDate.month;

      // Determina o nome correto do método de valuation
      final String methodLabel = config.valuationMethod.label;

      // Determina os detalhes do parâmetro
      String paramText = '';
      if (config.valuationMethod == ValuationMethod.graham) {
        paramText = 'Margem: ${config.safetyMargin.toStringAsFixed(0)}%';
      } else if (config.valuationMethod == ValuationMethod.bazin) {
        paramText = 'Retorno: ${config.desiredRate.toStringAsFixed(1)}%';
      } else if (config.valuationMethod == ValuationMethod.dcf) {
        paramText = 'Desc: ${config.dcfDiscountRate.toStringAsFixed(0)}% | Cr: ${config.dcfGrowthRate.toStringAsFixed(0)}%';
      } else {
        paramText = 'Lynch';
      }

      final docData = {
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'executionDate': result.executionDate.toIso8601String(),
        'stockTicker': config.stockTicker,
        'fiiTicker': config.fiiTicker,
        'startDate': config.startDate.toIso8601String(),
        'endDate': config.endDate.toIso8601String(),
        'monthlyInvestment': config.monthlyInvestment,
        'totalInvested': s1.totalInvested, // Capital Aportado Acumulado
        'periodMonths': periodMonths,
        'valuationMethod': config.valuationMethod.name,
        'valuationMethodLabel': methodLabel,
        'paramText': paramText,
        'safetyMargin': config.safetyMargin,
        'desiredRate': config.desiredRate,
        'dcfDiscountRate': config.dcfDiscountRate,
        'dcfGrowthRate': config.dcfGrowthRate,
        'dcfPerpetualGrowth': config.dcfPerpetualGrowth,
        'dcfProjectionYears': config.dcfProjectionYears,
        'diaCompra': config.diaCompra,
        'considerarReinvestimento': config.considerarReinvestimento,

        // Cenário 1 (Buy & Hold)
        'finalValueBuyHold': s1.finalValue,
        'totalReturnBuyHold': s1.totalReturn,
        'cagrBuyHold': s1.cagr,
        'sharpeBuyHold': s1Metrics.sharpe,
        'maxDrawdownBuyHold': s1Metrics.maxDrawdown,
        'volatilidadeBuyHold': s1Metrics.volatility,

        // Cenário 2 (Valuation Inteligente)
        'finalValueValuation': s2.finalValue,
        'totalReturnValuation': s2.totalReturn,
        'cagrValuation': s2.cagr,
        'sharpeValuation': s2Metrics.sharpe,
        'maxDrawdownValuation': s2Metrics.maxDrawdown,
        'volatilidadeValuation': s2Metrics.volatility,

        // Curvas para o gráfico (Compactação em arrays simples)
        'monthlyValuesBuyHold': s1Values,
        'monthlyValuesValuation': s2Values,
        'monthlyDates': dates,
      };

      // Grava no Firestore com ID automático
      await _firestore.collection('backtests').add(docData);
      debugPrint('✅ Resultado do backtest salvo com sucesso no Firestore.');
    } catch (e) {
      debugPrint('❌ Erro ao salvar backtest no Firestore: $e');
      throw Exception('Erro ao persistir o histórico da simulação.');
    }
  }

  /// Recupera todos os históricos de simulações do usuário logado de forma segura.
  Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    if (userId.trim().isEmpty) {
      return [];
    }

    try {
      // Query garantida de segurança: filtra obrigatoriamente por userId e ordena por data de criação
      final QuerySnapshot querySnapshot = await _firestore
          .collection('backtests')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Adiciona o ID do documento para exclusão posterior (Delete)
        return data;
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao recuperar histórico do Firestore: $e');
      throw Exception('Erro ao carregar o histórico de simulações.');
    }
  }

  /// Exclui um histórico de simulação de forma segura.
  Future<void> deleteBacktest(String backtestId, String userId) async {
    if (backtestId.trim().isEmpty || userId.trim().isEmpty) {
      throw ArgumentError('ID do documento e ID do usuário são obrigatórios para exclusão.');
    }

    try {
      // Primeiro, busca o documento para verificar se ele pertence ao usuário
      // (Esta é uma dupla checagem local além da regra de segurança do Firestore)
      final docRef = _firestore.collection('backtests').doc(backtestId);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        throw Exception('Simulação não encontrada no banco de dados.');
      }

      final data = docSnap.data();
      if (data == null || data['userId'] != userId) {
        throw SecurityException('Você não tem permissão para excluir esta simulação.');
      }

      await docRef.delete();
      debugPrint('✅ Simulação $backtestId removida com sucesso do Firestore.');
    } catch (e) {
      debugPrint('❌ Erro ao deletar simulação no Firestore: $e');
      throw Exception('Não foi possível remover a simulação do seu histórico.');
    }
  }
}

/// Exceção de segurança customizada
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
