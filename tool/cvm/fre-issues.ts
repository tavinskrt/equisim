// As emissões de ações por valor do Formulário de Referência, com a data em
// que cada uma ficou pública (item B28).
//
// O quadro «aumentos do capital social» do FRE declara, emissão a emissão, a
// data da deliberação e da emissão, o valor total, a quantidade de ações, o
// preço, o tipo de subscrição e a forma de integralização. **É o valor que
// entrou**, e não uma inferência pela contagem: a CMIG de 2018 aparece com R$
// 1,31 bilhão em dinheiro, a Fleury de 2023 com R$ 2,16 bilhões pela
// incorporação da Pardini.
//
// **Três coisas saem**, porque não trazem valor à companhia: a capitalização
// sem emissão de ações, a emissão sem quantidade ou sem valor, e a bonificação
// — que o FRE registra como «subscrição particular» com o valor da reserva
// capitalizada: a SHUL4 de 2021 tem 89 milhões de ações por R$ 22,9 milhões, a
// R$ 0,26 cada, com a forma «Ações Bonificadas»; a SLCE3 de 2023 tem 21
// milhões por R$ 500 milhões, com preço de emissão zero e forma em branco — a
// bonificação de 10% de 05/05/2023. **Emissão por valor tem preço de emissão
// positivo**, e a que não tem sai.
//
// **Cada versão do formulário conta a partir do dia em que foi recebida**
// (`DT_RECEB`): a coorte de uma data só vê a emissão que já estava num
// formulário público, e com os números daquele formulário — a primeira versão
// da CMIG de 2018 tinha R$ 1,0 bilhão, a subscrição ainda em curso.
//
// **Vale o formulário mais recente, inteiro, e não a soma dos formulários.**
// Cada versão relista os aumentos dos exercícios anteriores com um
// identificador novo — a ALPA4 de 2019 aparece em cinco documentos com cinco
// identificadores —, e juntar por identificador somaria a mesma emissão cinco
// vezes. O quadro de cada versão é completo para os três últimos exercícios,
// que cobrem com folga o intervalo entre o balanço e a coorte.
//
// **O quadro de aumentos parou em 2023** — o formulário novo da CVM não o tem,
// nem o de desdobramentos: o último aumento lido é de maio de 2023. Dali em
// diante a segunda fonte é o quadro de **capital social**, que continua: cada
// versão diz o capital integralizado em reais e a contagem. A variação entre
// duas versões é o capital que entrou — a Minerva de 2026, R$ 1,46 bilhão com
// 393 milhões de ações novas; a Casas Bahia, R$ 1,68 bilhão com a conversão da
// dívida. **É um piso**: o ágio da subscrição pode ir para reserva de capital,
// e aí não aparece. E **não distingue bonificação**, que também aumenta o
// capital, por capitalização de reserva: quem a separa é o preço, e por isso
// quem usa esta fonte descarta a variação que um evento de ações explica
// ([byCapitalChange]).
import { existsSync } from 'node:fs';

import { compareStr, DateTime, Money, round, ShareIssue, str, tryParseDouble } from '../../src/core';
import { filesIn } from '../lib/files';
import { readCvmCsv } from './csv';

interface IssueRecord {
  readonly document: string;
  readonly date: DateTime;
  readonly value: number;
  readonly shares: number;
}

/**
 * Uma versão do quadro de capital social: o capital integralizado e a
 * contagem, com a aprovação que a produziu.
 */
interface CapitalVersion {
  readonly received: DateTime;
  readonly approval: DateTime;
  readonly value: number;
  readonly shares: number;
  readonly document: string;
}

/** Dia `AAAA-MM-DD` da CVM como meia-noite UTC, ou `null`. */
const utcDay = (raw: string | undefined) => DateTime.tryParse(`${raw}T00:00:00Z`);

const push = <K, V>(map: Map<K, V[]>, key: K, value: V) => {
  const list = map.get(key);
  if (list === undefined) map.set(key, [value]);
  else list.push(value);
};

/** As emissões por valor do FRE, por CNPJ. */
export class FreIssuances {
  /**
   * Desde quando vale a variação do capital: o quadro de aumentos cobre até
   * aqui, e somar as duas fontes antes disso contaria a emissão duas vezes.
   */
  static readonly capitalStart = DateTime.utc(2023, 7, 1);

  /** Forma de integralização que é bonificação ou capitalização de reserva. */
  private static readonly noValue = /bonific|reserva|lucros? acumulad|lucros? retid/i;

  private constructor(
    /** Emissões com valor, por CNPJ, de todas as versões. */
    private readonly byCnpj: Map<string, IssueRecord[]>,
    /**
     * Toda versão com o quadro preenchido — inclusive só com capitalização sem
     * ação nova —, por CNPJ, com o recebimento.
     */
    private readonly documents: Map<string, Map<string, DateTime>>,
    /** Versões do quadro de capital integralizado, por CNPJ. */
    private readonly capital: Map<string, CapitalVersion[]>,
  ) {}

  /** Lê os formulários de [folder], ou devolve `null` sem eles. */
  static read(folder = 'data/cvm/fre'): FreIssuances | null {
    if (!existsSync(folder)) return null;
    const receivedInputs = new Map<string, DateTime>();
    for (const f of filesIn(folder, /^fre_cia_aberta_\d{4}\.csv$/)) {
      for (const r of readCvmCsv(f)) {
        const id = r['ID_DOC'];
        const day = utcDay(r['DT_RECEB']);
        if (id !== undefined && day !== null) receivedInputs.set(id, day);
      }
    }
    const capital = new Map<string, CapitalVersion[]>();
    for (const f of filesIn(folder, /^fre_cia_aberta_capital_social_\d{4}\.csv$/)) {
      for (const r of readCvmCsv(f)) {
        if (r['Tipo_Capital'] !== 'Capital Integralizado') continue;
        const cnpj = r['CNPJ_Companhia'];
        const document = r['ID_Documento'];
        const received = receivedInputs.get(document ?? '');
        const approval = utcDay(r['Data_Autorizacao_Aprovacao']);
        const value = tryParseDouble(r['Valor_Capital'] ?? '');
        const shares = tryParseDouble(r['Quantidade_Total_Acoes'] ?? '');
        if (cnpj === undefined || document === undefined || received === undefined) continue;
        if (approval === null || value === null || shares === null) continue;
        if (!(value > 0) || !(shares > 0)) continue;
        push(capital, cnpj, { received, approval, value, shares, document });
      }
    }
    for (const v of capital.values()) {
      v.sort((a, b) => {
        const c = a.received.compareTo(b.received);
        return c !== 0 ? c : compareStr(a.document, b.document);
      });
    }
    const byCnpj = new Map<string, IssueRecord[]>();
    const documents = new Map<string, Map<string, DateTime>>();
    for (const f of filesIn(folder, /^fre_cia_aberta_capital_social_aumento_\d{4}\.csv$/)) {
      for (const r of readCvmCsv(f)) {
        const cnpj = r['CNPJ_Companhia'];
        const document = r['ID_Documento'];
        const received = receivedInputs.get(document ?? '');
        if (cnpj === undefined || document === undefined || received === undefined) continue;
        let docs = documents.get(cnpj);
        if (docs === undefined) documents.set(cnpj, (docs = new Map()));
        docs.set(document, received);
        if ((r['Tipo_Subscricao'] ?? '').toLowerCase().includes('sem emiss')) continue;
        if (FreIssuances.noValue.test(r['Forma_Integralizacao'] ?? '') || FreIssuances.noValue.test(r['Tipo_Subscricao'] ?? '')) {
          continue;
        }
        const value = tryParseDouble(r['Valor_Total_Emissao'] ?? '');
        const shares = tryParseDouble(r['Quantidade_Total_Acoes'] ?? '');
        const price = tryParseDouble(r['Preco_Emissao'] ?? '');
        if (value === null || shares === null || !(value > 0) || !(shares > 0)) continue;
        if (price === null || !(price > 0)) continue;
        const date = utcDay(r['Data_Emissao']) ?? utcDay(r['Data_Deliberacao']);
        if (date === null) continue;
        push(byCnpj, cnpj, { document, date, value, shares });
      }
    }
    return new FreIssuances(byCnpj, documents, capital);
  }

  /**
   * As emissões de [cnpj] no formulário mais recente recebido até [t] que
   * tem o quadro de aumentos preenchido.
   *
   * Dentro do mesmo formulário, a mesma emissão repetida — mesma data, mesma
   * quantidade — entra uma vez.
   */
  known(cnpj: string, t: DateTime): ShareIssue[] {
    const day = DateTime.utc(t.year, t.month, t.day);
    let last: string | null = null;
    let asOfDate: DateTime | null = null;
    for (const [document, received] of this.documents.get(cnpj) ?? new Map<string, DateTime>()) {
      if (received.isAfter(day)) continue;
      if (asOfDate === null || received.isAfter(asOfDate) || (!received.isBefore(asOfDate) && compareStr(document, last!) > 0)) {
        last = document;
        asOfDate = received;
      }
    }
    if (last === null) return [];
    const seen = new Set<string>();
    const out: ShareIssue[] = [];
    const records = (this.byCnpj.get(cnpj) ?? []).filter((r) => r.document === last).sort((a, b) => a.date.compareTo(b.date));
    for (const r of records) {
      const key = `${r.date.toIso8601String()}|${str(r.shares)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(new ShareIssue({ date: r.date, amount: Money.fromReais(r.value), shares: round(r.shares) }));
    }
    return out;
  }

  /**
   * As variações do capital integralizado entre versões do FRE recebidas até
   * [t], com a aprovação a partir de [capitalStart]: cada aumento de
   * contagem de 1% ou mais com capital maior sai como emissão pelo capital
   * que entrou, e com a razão entre as contagens.
   *
   * **Quem usa descarta a que um evento de ações explica** — a bonificação
   * também aumenta o capital —, pela razão e pela data. Ver o comentário do
   * arquivo.
   */
  byCapitalChange(cnpj: string, t: DateTime): { issuance: ShareIssue; ratio: number }[] {
    const day = DateTime.utc(t.year, t.month, t.day);
    const versions = (this.capital.get(cnpj) ?? []).filter((c) => !c.received.isAfter(day));
    const out: { issuance: ShareIssue; ratio: number }[] = [];
    for (let i = 1; i < versions.length; i++) {
      const a = versions[i - 1]!;
      const b = versions[i]!;
      if (b.approval.isBefore(FreIssuances.capitalStart)) continue;
      if (!b.approval.isAfter(a.approval)) continue;
      const ratio = b.shares / a.shares;
      const inflow = Money.fromReais(b.value).minus(Money.fromReais(a.value));
      if (Math.log(ratio) < Math.log(1.01) || !inflow.isPositive) continue;
      out.push({
        issuance: new ShareIssue({ date: b.approval, amount: inflow, shares: round(b.shares - a.shares) }),
        ratio,
      });
    }
    return out;
  }
}
