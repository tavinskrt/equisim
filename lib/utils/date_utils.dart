class BrazilianDateUtils {
  BrazilianDateUtils._(); // Construtor privado para evitar instanciação

  /// Verifica se é fim de semana (sábado ou domingo)
  static bool isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Verifica se é um feriado nacional brasileiro
  /// 
  /// Incluí os principais feriados fixos. Feriados móveis (Carnaval, Páscoa, etc)
  /// precisariam de cálculo mais complexo.
  static bool isBrazilianHoliday(DateTime date) {
    final month = date.month;
    final day = date.day;

    // Feriados fixos brasileiros
    const fixedHolidays = {
      '1/1': 'Ano Novo',
      '4/21': 'Tiradentes',
      '5/1': 'Dia do Trabalho',
      '9/7': 'Independência',
      '10/12': 'Nossa Senhora Aparecida',
      '11/2': 'Finados',
      '11/15': 'Proclamação da República',
      '11/20': 'Consciência Negra',
      '12/25': 'Natal',
    };

    final dateKey = '$month/$day';
    return fixedHolidays.containsKey(dateKey);
  }

  /// Verifica se é um dia útil (não é feriado nem fim de semana)
  /// 
  /// Nota: Para feriados móveis complexos, você pode passar uma lista customizada
  static bool isBusinessDay(DateTime date, {List<DateTime>? customHolidays}) {
    if (isWeekend(date)) return false;
    if (isBrazilianHoliday(date)) return false;

    if (customHolidays != null) {
      for (final holiday in customHolidays) {
        if (date.year == holiday.year &&
            date.month == holiday.month &&
            date.day == holiday.day) {
          return false;
        }
      }
    }

    return true;
  }

  /// Retorna o próximo dia útil a partir de uma data
  /// 
  /// Se a data já for um dia útil, retorna a própria data.
  /// Avança até encontrar um dia útil válido.
  static DateTime getNextBusinessDay(
    DateTime date, {
    List<DateTime>? customHolidays,
    int maxDaysToSearch = 365,
  }) {
    DateTime current = date;

    for (int i = 0; i < maxDaysToSearch; i++) {
      if (isBusinessDay(current, customHolidays: customHolidays)) {
        return current;
      }
      current = current.add(const Duration(days: 1));
    }

    return current; // Fallback se não encontrar em 365 dias
  }

  /// Retorna o dia 20 de cada mês ou o próximo dia útil se não for possível
  /// 
  /// Este é o dia de "compra" padrão do backtest.
  /// 
  /// Exemplo: se 20/03/2024 for feriado, retorna o próximo dia útil.
  static DateTime getMonthly20thOrNextBusinessDay(
    int year,
    int month, {
    List<DateTime>? customHolidays,
  }) {
    DateTime date20th = DateTime(year, month, 20);

    // Se for dia útil, retorna
    if (isBusinessDay(date20th, customHolidays: customHolidays)) {
      return date20th;
    }

    // Caso contrário, retorna próximo dia útil
    return getNextBusinessDay(date20th, customHolidays: customHolidays);
  }

  /// Gera todas as datas de compra mensal entre duas datas
  /// 
  /// Retorna um mapa com: {DateTime (dia 20 ou próximo útil), ano, mês}
  static List<DateTime> generateMonthlyPurchaseDates(
    DateTime startDate,
    DateTime endDate, {
    List<DateTime>? customHolidays,
  }) {
    final purchaseDates = <DateTime>[];

    // Começa do primeiro mês após startDate
    DateTime current = DateTime(startDate.year, startDate.month);

    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      final purchaseDate = getMonthly20thOrNextBusinessDay(
        current.year,
        current.month,
        customHolidays: customHolidays,
      );

      // Adiciona se estiver dentro do período
      if (!purchaseDate.isAfter(endDate)) {
        purchaseDates.add(purchaseDate);
      }

      // Avança para o próximo mês
      if (current.month == 12) {
        current = DateTime(current.year + 1, 1);
      } else {
        current = DateTime(current.year, current.month + 1);
      }
    }

    return purchaseDates;
  }

  /// Retorna a data do último dia útil do período
  static DateTime getLastBusinessDay(DateTime date, {List<DateTime>? customHolidays}) {
    DateTime current = date;

    // Se já for dia útil, retorna
    if (isBusinessDay(current, customHolidays: customHolidays)) {
      return current;
    }

    // Volta dias até encontrar um dia útil
    for (int i = 0; i < 365; i++) {
      current = current.subtract(const Duration(days: 1));
      if (isBusinessDay(current, customHolidays: customHolidays)) {
        return current;
      }
    }

    return current; // Fallback
  }

  /// Calcula o número de dias úteis entre duas datas
  static int countBusinessDaysBetween(
    DateTime startDate,
    DateTime endDate, {
    List<DateTime>? customHolidays,
  }) {
    int count = 0;
    DateTime current = startDate;

    while (!current.isAfter(endDate)) {
      if (isBusinessDay(current, customHolidays: customHolidays)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }

    return count;
  }

  /// Formata uma data no padrão brasileiro
  /// 
  /// Exemplo: "20/03/2024"
  static String formatBR(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  /// Formata uma data com mês por extenso
  /// 
  /// Exemplo: "20 de março de 2024"
  static String formatBRVerbose(DateTime date) {
    const months = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];

    return "${date.day} de ${months[date.month - 1]} de ${date.year}";
  }

  /// Retorna o trimestre de uma data
  /// 
  /// Retorna: "Q1", "Q2", "Q3" ou "Q4"
  static String getQuarter(DateTime date) {
    if (date.month <= 3) return 'Q1';
    if (date.month <= 6) return 'Q2';
    if (date.month <= 9) return 'Q3';
    return 'Q4';
  }

  /// Retorna a data de início do trimestre
  static DateTime getQuarterStart(DateTime date) {
    if (date.month <= 3) return DateTime(date.year, 1, 1);
    if (date.month <= 6) return DateTime(date.year, 4, 1);
    if (date.month <= 9) return DateTime(date.year, 7, 1);
    return DateTime(date.year, 10, 1);
  }

  /// Retorna a data de fim do trimestre
  static DateTime getQuarterEnd(DateTime date) {
    if (date.month <= 3) return DateTime(date.year, 3, 31);
    if (date.month <= 6) return DateTime(date.year, 6, 30);
    if (date.month <= 9) return DateTime(date.year, 9, 30);
    return DateTime(date.year, 12, 31);
  }
}
