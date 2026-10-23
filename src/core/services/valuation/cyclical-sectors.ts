/** Quais setores têm a reversão ao ciclo com precedência sobre a tendência. */

const ACCENTS: ReadonlyMap<string, string> = new Map([
  ['á', 'a'],
  ['à', 'a'],
  ['â', 'a'],
  ['ã', 'a'],
  ['ä', 'a'],
  ['é', 'e'],
  ['è', 'e'],
  ['ê', 'e'],
  ['ë', 'e'],
  ['í', 'i'],
  ['ì', 'i'],
  ['î', 'i'],
  ['ï', 'i'],
  ['ó', 'o'],
  ['ò', 'o'],
  ['ô', 'o'],
  ['õ', 'o'],
  ['ö', 'o'],
  ['ú', 'u'],
  ['ù', 'u'],
  ['û', 'u'],
  ['ü', 'u'],
  ['ç', 'c'],
  ['ñ', 'n'],
]);

/**
 * Devolve a letra sem acento, o dígito como está, ou `null` para qualquer
 * outro caractere — que o chamador trata como separador.
 */
function fold(ch: string): string | null {
  const unaccented = ACCENTS.get(ch) ?? ch;
  if (unaccented.length !== 1) return null;
  const code = unaccented.charCodeAt(0);
  const isLetter = code >= 0x61 && code <= 0x7a;
  const isDigit = code >= 0x30 && code <= 0x39;
  return isLetter || isDigit ? unaccented : null;
}

/**
 * Setores de commodity e cíclicos pesados.
 *
 * **Por que existe.** A Guarda 1 pergunta se a tendência do retorno domina a
 * reversão à média, e mantém a base como observada quando domina. Numa empresa
 * de crescimento isso está certo: o nível corrente é o novo patamar. Numa
 * commodity, não — a perna de alta do ciclo tem exatamente a forma de uma
 * tendência, e o teste a lê como estrutural.
 *
 * Foi o que aconteceu com a SUZB3: retorno corrente de 41,5% contra 18,4% de
 * mediana do ciclo, com `t` significante e deriva maior que a correção. A base
 * ficou travada no pico de celulose e câmbio, e o preço justo saiu a
 * +259,1% do de mercado. A medição estava na §13.2 do documento de
 * refinamento, que a decisão 141 apagou (no git, commit `6827219`); a regra de
 * hoje está em `docs/motor/03-base-e-crescimento.md`.
 *
 * Aqui a determinação é setorial e vem de fora do dado: **em commodity, preço
 * reverte à média por definição do produto**, e nenhuma quantidade de anos
 * consecutivos de alta muda isso. A lista é declarada, não inferida.
 */
export const CyclicalSectors = {
  /**
   * Chave de setor cujo conteúdo é inteiramente de commodity ou cíclico
   * pesado: papel e celulose, siderurgia, mineração, petroquímicos,
   * fertilizantes, madeira e artefatos de metal.
   */
  heavySectorKey: 'materiais-basicos',

  /**
   * Subsetores cíclicos que **não** vivem sob [heavySectorKey].
   *
   * Existem porque a chave `energia` mistura duas coisas de natureza oposta:
   * exploração e refino de petróleo, que é commodity pura, e energia elétrica,
   * que é concessão regulada de fluxo estável. Classificar `energia` inteira
   * como cíclica jogaria EGIE3, EQTL3 e as outras 28 elétricas na mesma regra
   * de reversão — o oposto do que a natureza delas pede.
   *
   * A comparação é sobre o subsetor **normalizado**, sem acento e sem
   * pontuação, porque a fonte publica variantes do mesmo rótulo: aparecem
   * tanto `Exploração, Refino e Distribuição` quanto
   * `Exploração. Refino e Distribuição`.
   */
  heavyIndustryTerms: [
    'petroleo',
    'refino',
    'mineracao',
    'minerais metalicos',
    'siderurgia',
    'papel e celulose',
    'petroquimicos',
  ] as readonly string[],

  /**
   * `true` quando a reversão ao ciclo tem precedência sobre a tendência.
   *
   * - [sectorKey]: chave setorial da fonte, já em minúsculas.
   * - [industry]: subsetor da fonte, com acentuação e pontuação originais.
   *
   * Os termos de [heavyIndustryTerms] valem **independentemente do setor**:
   * mineração e siderurgia aparecem sob `materiais-basicos` hoje, mas um papel
   * reclassificado pela fonte não deveria mudar de regime de normalização por
   * causa disso.
   */
  hasCyclePrecedence(args: { sectorKey?: string | null; industry?: string | null } = {}): boolean {
    // Os dois lados normalizados: a chave da taxonomia usa hífen, que o
    // normalizador converte em espaço. Comparar a chave crua contra o resultado
    // normalizado nunca casaria, e a falha seria silenciosa.
    if (CyclicalSectors.normalize(args.sectorKey) === CyclicalSectors.normalize(CyclicalSectors.heavySectorKey)) {
      return true;
    }
    const sub = CyclicalSectors.normalize(args.industry);
    if (sub.length === 0) return false;
    for (const term of CyclicalSectors.heavyIndustryTerms) {
      if (sub.includes(term)) return true;
    }
    return false;
  },

  /**
   * Minúsculas, sem acento e sem pontuação, com espaços colapsados.
   *
   * Escrito à mão porque o núcleo não carrega pacote de normalização — ver a
   * restrição em `CLAUDE.md`. Cobre o que a fonte usa em português; qualquer
   * caractere fora disso vira espaço, o que é o comportamento seguro para
   * comparação por termo.
   */
  normalize(raw: string | null | undefined): string {
    if (raw === null || raw === undefined) return '';
    let buffer = '';
    let pendingSpace = false;
    for (const unit of raw.toLowerCase()) {
      const ch = fold(unit);
      if (ch === null) {
        pendingSpace = buffer.length > 0;
        continue;
      }
      if (pendingSpace) {
        buffer += ' ';
        pendingSpace = false;
      }
      buffer += ch;
    }
    return buffer;
  },
};
