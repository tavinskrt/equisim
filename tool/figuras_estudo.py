"""Figuras SVG do guia de estudo (docs/estudo/img/).

Uso, da raiz do repositório, depois de `dart run tool/casos_de_estudo.dart`:

    python tool/figuras_estudo.py

Sem biblioteca externa: SVG escrito à mão, com os valores tirados dos dados
dos casos (docs/estudo/casos/dados/) ou de contas explícitas aqui.
Cores: paleta de referência validada (azul, laranja, aqua), com modo escuro
selecionado dentro do próprio SVG.
"""
import json
import math
import os

SAIDA = 'docs/estudo/img/'
os.makedirs(SAIDA, exist_ok=True)

ESTILO = """<style>
  .fundo{fill:#fcfcfb}
  .t1{fill:#0b0b0b;font:600 15px system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
  .t2{fill:#52514e;font:12px system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
  .t3{fill:#0b0b0b;font:12px system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
  .tb{fill:#0b0b0b;font:600 12px system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
  .grade{stroke:#e4e3de;stroke-width:1}
  .eixo{stroke:#b9b8b1;stroke-width:1}
  .s1{stroke:#2a78d6;fill:#2a78d6}
  .s2{stroke:#eb6834;fill:#eb6834}
  .s3{stroke:#1baf7a;fill:#1baf7a}
  .neutro{stroke:#8f8e87;fill:#8f8e87}
  .caixa{fill:#f3f2ee;stroke:#c9c8c1;stroke-width:1}
  .caixa2{fill:#e7f0fb;stroke:#2a78d6;stroke-width:1.5}
  .caixa3{fill:#fdeee7;stroke:#eb6834;stroke-width:1.5}
  .caixa4{fill:#f3f2ee;stroke:#8f8e87;stroke-width:1;stroke-dasharray:0}
  .seta{stroke:#52514e;stroke-width:1.5;fill:none}
  .anel{stroke:#fcfcfb;stroke-width:2}
  @media (prefers-color-scheme: dark){
    .fundo{fill:#1a1a19}
    .t1,.t3,.tb{fill:#ffffff}
    .t2{fill:#c3c2b7}
    .grade{stroke:#33332f}
    .eixo{stroke:#5a5953}
    .s1{stroke:#3987e5;fill:#3987e5}
    .s2{stroke:#d95926;fill:#d95926}
    .s3{stroke:#199e70;fill:#199e70}
    .caixa{fill:#262624;stroke:#4a4944}
    .caixa2{fill:#16283f;stroke:#3987e5}
    .caixa3{fill:#3a2016;stroke:#d95926}
    .caixa4{fill:#262624;stroke:#6d6c66}
    .seta{stroke:#c3c2b7}
    .anel{stroke:#1a1a19}
  }
</style>"""


def br(x, casas=0):
    s = f'{x:,.{casas}f}'
    return s.replace(',', 'X').replace('.', ',').replace('X', '.')


def svg(nome, largura, altura, titulo, desc, corpo):
    texto = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {largura} {altura}" '
             f'width="{largura}" height="{altura}" role="img" aria-labelledby="t d">'
             f'<title id="t">{titulo}</title><desc id="d">{desc}</desc>{ESTILO}'
             f'<rect class="fundo" width="{largura}" height="{altura}" rx="8"/>{corpo}</svg>\n')
    with open(SAIDA + nome, 'w', encoding='utf-8', newline='\n') as f:
        f.write(texto)
    print('gravado', nome)


def barra(x, y0, y1, w, classe, raio=4):
    """Coluna com topo arredondado de 4px e base reta, de y0 (base) a y1 (topo)."""
    topo, base = min(y0, y1), max(y0, y1)
    h = base - topo
    r = min(raio, h / 2, w / 2)
    if y1 <= y0:  # para cima
        d = (f'M{x},{base} L{x},{topo + r} Q{x},{topo} {x + r},{topo} '
             f'L{x + w - r},{topo} Q{x + w},{topo} {x + w},{topo + r} L{x + w},{base} Z')
    else:  # para baixo: ponta arredondada embaixo
        d = (f'M{x},{topo} L{x},{base - r} Q{x},{base} {x + r},{base} '
             f'L{x + w - r},{base} Q{x + w},{base} {x + w},{base - r} L{x + w},{topo} Z')
    return f'<path class="{classe}" d="{d}" stroke="none"/>'


# ---------------------------------------------------------------- 1 -------
def valor_presente():
    W, H = 720, 400
    x0, x1, y0, y1 = 70, 580, 340, 96
    taxas = [(0.08, 's1', '8% a.a.'), (0.12, 's2', '12% a.a.'), (0.16, 's3', '16% a.a.')]

    def X(t): return x0 + (x1 - x0) * t / 10
    def Y(v): return y0 - (y0 - y1) * v / 1000
    c = ['<text class="t1" x="24" y="32">Quanto valem hoje R$ 1.000 recebidos no ano t</text>',
         '<text class="t2" x="24" y="52">Valor presente = 1.000 ÷ (1 + taxa)^t</text>']
    for v in range(0, 1001, 250):
        c.append(f'<line class="grade" x1="{x0}" x2="{x1}" y1="{Y(v)}" y2="{Y(v)}"/>')
        c.append(f'<text class="t2" x="{x0 - 8}" y="{Y(v) + 4}" text-anchor="end">{br(v)}</text>')
    for t in range(0, 11, 2):
        c.append(f'<text class="t2" x="{X(t)}" y="{y0 + 20}" text-anchor="middle">{t}</text>')
    c.append(f'<text class="t2" x="{(x0 + x1) / 2}" y="{y0 + 40}" text-anchor="middle">anos até receber</text>')
    c.append(f'<line class="eixo" x1="{x0}" x2="{x1}" y1="{y0}" y2="{y0}"/>')
    for i, (r, cl, rot) in enumerate(taxas):
        pts = ' '.join(f'{X(t):.1f},{Y(1000 / (1 + r) ** t):.1f}' for t in range(11))
        c.append(f'<polyline class="{cl}" points="{pts}" style="fill:none" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>')
        v10 = 1000 / (1 + r) ** 10
        c.append(f'<circle class="{cl} anel" cx="{X(10)}" cy="{Y(v10)}" r="4.5"/>')
        c.append(f'<text class="t3" x="{X(10) + 10}" y="{Y(v10) + 4}">{rot}: R$ {br(v10, 2)}</text>')
    # legenda
    lx = 24
    for i, (r, cl, rot) in enumerate(taxas):
        c.append(f'<line class="{cl}" x1="{lx + i * 100}" x2="{lx + i * 100 + 18}" y1="70" y2="70" stroke-width="3"/>')
        c.append(f'<text class="t2" x="{lx + i * 100 + 24}" y="74">{rot}</text>')
    svg('valor-presente.svg', W, H, 'Valor presente de R$ 1.000 por ano e taxa',
        'Três curvas decrescentes: a 8%, 12% e 16% ao ano, R$ 1.000 no ano 10 valem hoje R$ 463,19, R$ 321,97 e R$ 226,68.',
        ''.join(c))


# ---------------------------------------------------------------- 2 -------
def curva():
    d = json.load(open('docs/estudo/casos/dados/WEGE3.json', encoding='utf-8'))
    fw = d['curva']['forwards']
    term = d['curva']['terminal']
    cdi = d['capm']['rf']
    W, H = 720, 380
    x0, x1, y0, y1 = 70, 640, 310, 80
    lo, hi = 0.13, 0.15

    def X(i): return x0 + (x1 - x0) * i / 11
    def Y(v): return y0 - (y0 - y1) * (v - lo) / (hi - lo)
    c = ['<text class="t1" x="24" y="32">Taxa livre de risco de cada ano: forwards da curva do Tesouro</text>',
         '<text class="t2" x="24" y="52">Prefixados de 10/09/2026, usados na avaliação de 14/09/2026</text>']
    for k in range(5):
        v = lo + (hi - lo) * k / 4
        c.append(f'<line class="grade" x1="{x0}" x2="{x1}" y1="{Y(v):.1f}" y2="{Y(v):.1f}"/>')
        c.append(f'<text class="t2" x="{x0 - 8}" y="{Y(v) + 4:.1f}" text-anchor="end">{br(v * 100, 1)}%</text>')
    pts = [(X(i + 1), Y(v)) for i, v in enumerate(fw)] + [(X(11), Y(term))]
    rot = [str(i + 1) for i in range(10)] + ['∞']
    for (x, _), r in zip(pts, rot):
        c.append(f'<text class="t2" x="{x:.1f}" y="{y0 + 20}" text-anchor="middle">{r}</text>')
    c.append(f'<text class="t2" x="{(x0 + x1) / 2}" y="{y0 + 40}" text-anchor="middle">ano da projeção (∞ = perpetuidade)</text>')
    c.append(f'<line class="neutro" x1="{x0}" x2="{x1}" y1="{Y(cdi):.1f}" y2="{Y(cdi):.1f}" stroke-width="1.5"/>')
    c.append(f'<text class="t2" x="{x1}" y="{Y(cdi) + 16:.1f}" text-anchor="end">CDI de hoje: {br(cdi * 100, 2)}% (a taxa do ano 1 se não houvesse curva)</text>')
    c.append('<polyline class="s1" style="fill:none" stroke-width="2" stroke-linejoin="round" points="'
             + ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts) + '"/>')
    for (x, y) in pts:
        c.append(f'<circle class="s1 anel" cx="{x:.1f}" cy="{y:.1f}" r="4.5"/>')
    for i in (0, 4, 10):
        x, y = pts[i]
        v = fw[i] if i < 10 else term
        c.append(f'<text class="t3" x="{x:.1f}" y="{y - 12:.1f}" text-anchor="middle">{br(v * 100, 2)}%</text>')
    svg('curva-forwards.svg', W, H, 'Forwards anuais da curva prefixada',
        'A taxa sobe de 13,62% no ano 1 para 14,63% no ano 5 e fica em 14,29% no ano 10 e na perpetuidade; o CDI de hoje é 14,09%.',
        ''.join(c))


# ---------------------------------------------------------------- 3 -------
def beta():
    # Ilustração com pontos gerados por conta fixa (sem aleatoriedade): retorno
    # do mercado em [-3%, 3%] e o da ação = 0,7 × mercado + desvio periódico.
    W, H = 560, 420
    x0, x1, y0, y1 = 70, 520, 360, 70

    def X(v): return x0 + (x1 - x0) * (v + 0.04) / 0.08
    def Y(v): return y1 + (y0 - y1) * (0.04 - v) / 0.08
    c = ['<text class="t1" x="24" y="32">Beta é a inclinação da reta</text>',
         '<text class="t2" x="24" y="52">Ilustração: cada ponto é um dia (pontos fictícios, β = 0,7)</text>']
    for k in (-0.04, -0.02, 0, 0.02, 0.04):
        c.append(f'<line class="grade" x1="{x0}" x2="{x1}" y1="{Y(k):.1f}" y2="{Y(k):.1f}"/>')
        c.append(f'<line class="grade" x1="{X(k):.1f}" x2="{X(k):.1f}" y1="{y1}" y2="{y0}"/>')
        c.append(f'<text class="t2" x="{x0 - 8}" y="{Y(k) + 4:.1f}" text-anchor="end">{br(k * 100, 0)}%</text>')
        c.append(f'<text class="t2" x="{X(k):.1f}" y="{y0 + 18}" text-anchor="middle">{br(k * 100, 0)}%</text>')
    c.append(f'<text class="t2" x="{(x0 + x1) / 2}" y="{y0 + 38}" text-anchor="middle">retorno do Ibovespa no dia</text>')
    c.append(f'<text class="t2" transform="translate(18,{(y0 + y1) / 2}) rotate(-90)" text-anchor="middle">retorno da ação no dia</text>')
    for i in range(80):
        m = 0.03 * math.sin(i * 1.7) * math.cos(i * 0.37)
        a = 0.7 * m + 0.009 * math.sin(i * 2.9 + 1.3)
        c.append(f'<circle class="s1" cx="{X(m):.1f}" cy="{Y(a):.1f}" r="3.2" fill-opacity="0.55" stroke="none"/>')
    c.append(f'<line class="s2" x1="{X(-0.035):.1f}" y1="{Y(-0.0245):.1f}" x2="{X(0.035):.1f}" y2="{Y(0.0245):.1f}" stroke-width="2.5"/>')
    c.append(f'<text class="t3" x="{X(0.012):.1f}" y="{Y(0.03):.1f}">reta: ação = 0,7 × Ibovespa</text>')
    svg('beta-regressao.svg', W, H, 'Beta como inclinação da regressão',
        'Nuvem de pontos com uma reta de inclinação 0,7: quando o mercado sobe 1%, a ação sobe em média 0,7%.',
        ''.join(c))


# ---------------------------------------------------------------- 4 -------
def triangular():
    W, H = 560, 300
    x0, x1, y0, y1 = 60, 500, 230, 70
    c = ['<text class="t1" x="24" y="32">Distribuição triangular de uma premissa</text>',
         '<text class="t2" x="24" y="52">Exemplo: crescimento sorteado entre g − 4 p.p. e g + 4 p.p., mais provável em g</text>']
    xm = (x0 + x1) / 2
    c.append(f'<path class="s1" d="M{x0},{y0} L{xm},{y1} L{x1},{y0} Z" fill-opacity="0.12" stroke-width="2" stroke-linejoin="round"/>')
    c.append(f'<line class="eixo" x1="{x0 - 10}" x2="{x1 + 10}" y1="{y0}" y2="{y0}"/>')
    for x, r in ((x0, 'g − 4 p.p.\n(mínimo)'), (xm, 'g do motor\n(mais provável)'), (x1, 'g + 4 p.p.\n(máximo)')):
        a, b = r.split('\n')
        c.append(f'<text class="t3" x="{x}" y="{y0 + 20}" text-anchor="middle">{a}</text>')
        c.append(f'<text class="t2" x="{x}" y="{y0 + 36}" text-anchor="middle">{b}</text>')
    c.append(f'<line class="grade" x1="{xm}" x2="{xm}" y1="{y1}" y2="{y0}"/>')
    c.append(f'<text class="t2" x="{xm + 14}" y="{y1 + 18}">chance maior</text>')
    svg('triangular.svg', W, H, 'Distribuição triangular',
        'Triângulo com base do mínimo ao máximo e pico no valor do motor.', ''.join(c))


# ---------------------------------------------------------------- 5 -------
def cascata():
    W, H = 760, 560
    c = ['<text class="t1" x="24" y="32">A cascata de avaliação do Equisim</text>',
         '<text class="t2" x="24" y="52">Cada ativo passa pelas portas, em ordem; a via escolhida não muda depois</text>']

    def caixa(x, y, w, h, titulo, sub, cl='caixa'):
        s = f'<rect class="{cl}" x="{x}" y="{y}" width="{w}" height="{h}" rx="8"/>'
        s += f'<text class="tb" x="{x + w / 2}" y="{y + 22}" text-anchor="middle">{titulo}</text>'
        for i, linha in enumerate(sub):
            s += f'<text class="t2" x="{x + w / 2}" y="{y + 40 + i * 16}" text-anchor="middle">{linha}</text>'
        return s

    def seta(x1_, y1_, x2_, y2_, rot=None, lado='right'):
        s = f'<path class="seta" d="M{x1_},{y1_} L{x2_},{y2_}" marker-end="url(#ponta)"/>'
        if rot:
            mx, my = (x1_ + x2_) / 2, (y1_ + y2_) / 2
            if y1_ == y2_:  # horizontal: rótulo centrado acima da linha
                s += f'<text class="t2" x="{mx}" y="{my - 7}" text-anchor="middle">{rot}</text>'
            else:
                anc = 'start' if lado == 'right' else 'end'
                dx = 8 if lado == 'right' else -8
                s += f'<text class="t2" x="{mx + dx}" y="{my + 4}" text-anchor="{anc}">{rot}</text>'
        return s

    c.append('<defs><marker id="ponta" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 Z" class="neutro" stroke="none"/></marker></defs>')
    c.append(caixa(250, 72, 260, 64, 'Dados na data da avaliação', ['exercícios já publicados, preço, curva, beta']))
    c.append(seta(380, 136, 380, 166))
    c.append(caixa(250, 166, 260, 74, 'Porta 0 — elegibilidade', ['liquidez ≥ R$ 2 mi/dia; ≥ 8 exercícios;', 'PL positivo; sem recuperação judicial']))
    c.append(caixa(560, 172, 170, 60, 'Recusa', ['com o motivo'], 'caixa4'))
    c.append(seta(510, 203, 558, 203, 'não', 'right'))
    c.append(seta(380, 240, 380, 270, 'sim'))
    c.append(caixa(250, 270, 260, 64, 'Porta 1 — é financeira?', ['banco, seguradora, bolsa…']))
    c.append(seta(380, 334, 380, 364, 'não'))
    c.append(caixa(250, 364, 260, 64, 'Porta 3 — NOPAT positivo', ['em ≥ 60% dos exercícios?']))
    c.append(caixa(24, 364, 190, 64, 'Via do acionista', ['lucro por papel, ao Ke'], 'caixa3'))
    c.append(seta(250, 302, 120, 362, 'sim', 'left'))
    c.append(seta(250, 396, 216, 396, 'não', 'left'))
    c.append(caixa(546, 364, 190, 64, 'Via da firma', ['NOPAT → fluxo do acionista'], 'caixa2'))
    c.append(seta(510, 396, 544, 396, 'sim'))
    c.append(caixa(160, 462, 440, 74, 'Porta 2 — premissas', ['base (normalização pelo ciclo) e crescimento;', 'desconto; perpetuidade; preço justo e ressalvas']))
    c.append(seta(120, 428, 250, 460))
    c.append(seta(640, 428, 510, 460))
    svg('cascata.svg', W, H, 'Cascata de avaliação',
        'Dados, Porta 0 (elegibilidade, ou recusa), Porta 1 (financeira vai à via do acionista), Porta 3 (NOPAT positivo vai à via da firma, senão acionista), e Porta 2 (premissas e preço justo).',
        ''.join(c))


# ---------------------------------------------------------------- 6 -------
def wege3():
    d = json.load(open('docs/estudo/casos/dados/WEGE3.json', encoding='utf-8'))
    passo = next(x for x in d['rastro']['calculations'] if x['formulaName'].startswith('Fluxo do acionista'))
    import re
    rx = re.compile(r'fluxo do acionista ([\d.\-e]+); .* valor presente ([\d.\-e]+)')
    fl, vp = [], []
    for s in passo['intermediateSteps']:
        m = rx.search(s)
        if m:
            fl.append(float(m.group(1)) / 1e9)
            vp.append(float(m.group(2)) / 1e9)
    W, H = 760, 420
    x0, x1, y0, y1 = 70, 730, 340, 104
    top = 12.0

    def Y(v): return y0 - (y0 - y1) * v / top
    c = ['<text class="t1" x="24" y="32">WEGE3: fluxo do acionista e valor presente, ano a ano (R$ bi)</text>',
         '<text class="t2" x="24" y="52">O fluxo cresce; o valor de hoje cai, porque o desconto (17,6% a 18,6%) supera o crescimento</text>']
    for v in range(0, 13, 3):
        c.append(f'<line class="grade" x1="{x0}" x2="{x1}" y1="{Y(v):.1f}" y2="{Y(v):.1f}"/>')
        c.append(f'<text class="t2" x="{x0 - 8}" y="{Y(v) + 4:.1f}" text-anchor="end">{v}</text>')
    banda = (x1 - x0) / 10
    w = 22
    for i in range(10):
        xc = x0 + banda * (i + 0.5)
        c.append(barra(xc - w - 1, y0, Y(fl[i]), w, 's1'))
        c.append(barra(xc + 1, y0, Y(vp[i]), w, 's2'))
        c.append(f'<text class="t2" x="{xc:.1f}" y="{y0 + 18}" text-anchor="middle">{i + 1}</text>')
    c.append(f'<line class="eixo" x1="{x0}" x2="{x1}" y1="{y0}" y2="{y0}"/>')
    c.append(f'<text class="t2" x="{(x0 + x1) / 2}" y="{y0 + 38}" text-anchor="middle">ano da projeção</text>')
    # rótulos seletivos: ano 1 e ano 10
    for i in (0, 9):
        xc = x0 + banda * (i + 0.5)
        c.append(f'<text class="t3" x="{xc - w / 2 - 1:.1f}" y="{Y(fl[i]) - 6:.1f}" text-anchor="middle">{br(fl[i], 1)}</text>')
        c.append(f'<text class="t3" x="{xc + w / 2 + 1:.1f}" y="{Y(vp[i]) - 6:.1f}" text-anchor="middle">{br(vp[i], 1)}</text>')
    c.append('<rect class="s1" x="24" y="64" width="12" height="12" rx="2" stroke="none"/><text class="t2" x="42" y="75">fluxo do acionista</text>')
    c.append('<rect class="s2" x="174" y="64" width="12" height="12" rx="2" stroke="none"/><text class="t2" x="192" y="75">valor presente</text>')
    svg('wege3-fluxos.svg', W, H, 'WEGE3, fluxo e valor presente por ano',
        f'Fluxo do acionista de R$ {br(fl[0], 1)} bi no ano 1 a R$ {br(fl[9], 1)} bi no ano 10; valor presente de R$ {br(vp[0], 1)} bi a R$ {br(vp[9], 1)} bi.',
        ''.join(c))

    # composição (cascata de valores)
    ponte = next(x for x in d['rastro']['calculations'] if x['formulaName'].startswith('Capital próprio'))
    v = ponte['mappedVariables']
    exp_ = v['VP do fluxo explícito do acionista (R$)'] / 1e9
    ter = v['VP do terminal do acionista (R$)'] / 1e9
    mino = v['minoritários M (R$)'] / 1e9
    tot = exp_ + ter - mino
    W, H = 720, 380
    x0, x1, y0, y1 = 70, 680, 310, 80
    top = 60.0

    def Y2(val): return y0 - (y0 - y1) * val / top
    c = ['<text class="t1" x="24" y="32">WEGE3: de onde vem o preço justo (R$ bi)</text>',
         f'<text class="t2" x="24" y="52">R$ {br(tot, 2)} bi ÷ 4,196 bi de papéis = R$ 12,53 por papel</text>']
    for k in range(0, 61, 20):
        c.append(f'<line class="grade" x1="{x0}" x2="{x1}" y1="{Y2(k):.1f}" y2="{Y2(k):.1f}"/>')
        c.append(f'<text class="t2" x="{x0 - 8}" y="{Y2(k) + 4:.1f}" text-anchor="end">{k}</text>')
    etapas = [('VP dos 10 anos', 0, exp_, 's1'), ('VP do terminal', exp_, exp_ + ter, 's1'),
              ('Minoritários', exp_ + ter, tot, 's2'), ('Capital próprio', 0, tot, 'neutro')]
    banda = (x1 - x0) / 4
    w = 24 * 2
    for i, (rot, a, b, cl) in enumerate(etapas):
        xc = x0 + banda * (i + 0.5)
        if b >= a:
            c.append(barra(xc - w / 2, Y2(a), Y2(b), w, cl))
        else:
            c.append(barra(xc - w / 2, Y2(a), Y2(b), w, cl))
        val = b - a if i < 3 else tot
        c.append(f'<text class="t3" x="{xc:.1f}" y="{Y2(max(a, b)) - 8:.1f}" text-anchor="middle">{"−" if val < 0 else ("+" if 0 < i < 3 else "")}{br(abs(val), 2)}</text>')
        c.append(f'<text class="t2" x="{xc:.1f}" y="{y0 + 20}" text-anchor="middle">{rot}</text>')
    c.append(f'<line class="eixo" x1="{x0}" x2="{x1}" y1="{y0}" y2="{y0}"/>')
    svg('wege3-composicao.svg', W, H, 'Composição do preço justo da WEGE3',
        f'VP explícito {br(exp_, 2)} bi, mais VP terminal {br(ter, 2)} bi, menos minoritários {br(mino, 2)} bi, igual a capital próprio de {br(tot, 2)} bi.',
        ''.join(c))


valor_presente()
curva()
beta()
triangular()
cascata()
wege3()
