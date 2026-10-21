#!/usr/bin/env python3
"""
Genera dischetto.stl e provino.stl SENZA OpenSCAD (solo Python 3, nessuna libreria).

Legge i parametri dalla sezione PARAMETRI di dischetto.scad (stessa cartella),
quindi c'e' un solo posto dove cambiare i numeri. Costruisce la stessa geometria
del file .scad, controlla che le mesh siano chiuse (manifold) e stampa le quote
utili per la stampa (layer della pausa, cambio colore, grammi).

Uso:  python3 genera_stl.py
"""
import ast
import math
import os
import re
import struct
import sys

QUI = os.path.dirname(os.path.abspath(__file__))
DENSITA_PLA = 1.24  # g/cm^3


# ----------------------------------------------------------------------------
# Parametri
# ----------------------------------------------------------------------------
def leggi_parametri(percorso):
    """Legge le righe 'nome = valore;' prima di 'FINE PARAMETRI' nel file .scad."""
    with open(percorso, encoding="utf-8") as f:
        testo = f.read().split("FINE PARAMETRI")[0]
    p = {}
    for riga in testo.splitlines():
        riga = riga.split("//")[0].strip()
        m = re.match(r"^(\$?\w+)\s*=\s*(.+?)\s*;$", riga)
        if not m:
            continue
        nome, valore = m.groups()
        valore = re.sub(r"\btrue\b", "True", valore)
        valore = re.sub(r"\bfalse\b", "False", valore)
        p[nome] = ast.literal_eval(valore)
    return p


def calcola(p):
    """Valori derivati: identici a quelli del file .scad."""
    L = p["layer_h"]
    d = {}
    d["cav_d"] = p["tag_d"] + p["gioco_d"]
    n_cav = math.ceil((p["tag_t"] + p["gioco_t"]) / L - 0.001)
    n_cop = math.ceil(p["copertura"] / L - 0.001)
    n_disco = round(p["disco_h"] / L)
    n_icona = round(p["icona_h"] / L) if p["icona"] else 0
    # il provino si alza da solo per lasciare almeno pavimento_min sotto il tag
    n_prov = max(round(p["provino_h"] / L), n_cav + n_cop + math.ceil(p["pavimento_min"] / L - 0.001))
    q = lambda n: round(n * L, 6)  # quota Z di fine del layer n
    d.update(
        n_cav=n_cav, n_cop=n_cop, n_disco=n_disco, n_icona=n_icona, n_prov=n_prov,
        cav_h=q(n_cav), H=q(n_disco), H_icona=q(n_disco + n_icona),
        z_cav_top=q(n_disco - n_cop), z_cav_bot=q(n_disco - n_cop - n_cav),
        Hp=q(n_prov), z_prov_top=q(n_prov - n_cop), z_prov_bot=q(n_prov - n_cop - n_cav),
        pausa_dischetto=n_disco - n_cop + 1, pausa_provino=n_prov - n_cop + 1,
        cambio_colore=n_disco + 1, q=q,
    )
    d["pavimento"] = round(d["z_cav_bot"] - (p["incavo_h"] if p["incavo_adesivo"] else 0), 6)

    def multiplo(nome):
        x = p[nome] / L
        if abs(x - round(x)) > 0.001:
            sys.exit(f"ERRORE: {nome} = {p[nome]} deve essere un multiplo di layer_h = {L}")
    for nome in ("disco_h", "icona_h", "incavo_h", "provino_h"):
        multiplo(nome)
    if d["pavimento"] < p["pavimento_min"] - 0.001:
        sys.exit("ERRORE: tag troppo spesso, aumenta disco_h (o togli incavo_adesivo)")
    if d["z_prov_bot"] < p["pavimento_min"] - 0.001:
        sys.exit("ERRORE: tag troppo spesso per il provino, aumenta provino_h")
    if p["icona_tratto"] < 1.2:
        sys.exit("ERRORE: icona_tratto troppo sottile per un ugello da 0.4")
    if d["cav_d"] > p["disco_d"] - 6:
        sys.exit("ERRORE: tag troppo largo per il dischetto")
    return d


# ----------------------------------------------------------------------------
# Geometria di base
# ----------------------------------------------------------------------------
def cos_sin(k, n):
    t = 2 * math.pi * (k % n) / n
    c, s = math.cos(t), math.sin(t)
    return (0.0 if abs(c) < 1e-12 else c), (0.0 if abs(s) < 1e-12 else s)


def punto_anello(r, z, k, n):
    if r == 0:
        return (0.0, 0.0, z)
    c, s = cos_sin(k, n)
    return (r * c, r * s, z)


def rivoluzione(tris, profilo, n):
    """Ruota un profilo [(r, z), ...] antiorario attorno all'asse Z (normali verso l'esterno)."""
    for (r0, z0), (r1, z1) in zip(profilo, profilo[1:]):
        for k in range(n):
            A = punto_anello(r0, z0, k, n)
            B = punto_anello(r1, z1, k, n)
            C = punto_anello(r1, z1, k + 1, n)
            D = punto_anello(r0, z0, k + 1, n)
            if r1 != 0:
                tris.append((A, C, B))
            if r0 != 0:
                tris.append((A, D, C))


def area2(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def area_poligono(poly):
    return 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))


def triangola(poly):
    """Ear clipping di un poligono semplice antiorario -> terne di indici."""
    idx = list(range(len(poly)))
    out = []
    i = 0
    tentativi = 0
    while len(idx) > 3:
        m = len(idx)
        i %= m
        ia, ib, ic = idx[i - 1], idx[i], idx[(i + 1) % m]
        a, b, c = poly[ia], poly[ib], poly[ic]
        ok = area2(a, b, c) > 1e-12
        if ok:
            for j in idx:
                if j in (ia, ib, ic):
                    continue
                q = poly[j]
                if area2(a, b, q) >= -1e-12 and area2(b, c, q) >= -1e-12 and area2(c, a, q) >= -1e-12:
                    ok = False
                    break
        if ok:
            out.append((ia, ib, ic))
            idx.pop(i)
            tentativi = 0
        else:
            i += 1
            tentativi += 1
            if tentativi > m:
                raise RuntimeError("triangolazione fallita")
    if area2(*(poly[j] for j in idx)) > 1e-12:
        out.append(tuple(idx))
    return out


def faccia(tris, poly2d, z, verso_alto=True):
    for a, b, c in triangola(poly2d):
        A, B, C = ((*poly2d[a], z), (*poly2d[b], z), (*poly2d[c], z))
        tris.append((A, B, C) if verso_alto else (A, C, B))


def pareti(tris, poly2d, z0, z1):
    """Pareti verticali di un poligono antiorario tra z0 e z1 (normali verso l'esterno)."""
    for a, b in zip(poly2d, poly2d[1:] + poly2d[:1]):
        a0, b0, a1, b1 = (*a, z0), (*b, z0), (*a, z1), (*b, z1)
        tris.append((a0, b0, b1))
        tris.append((a0, b1, a1))


def cavita(tris, d_cav, z0, z1, n):
    """Cilindro chiuso con le normali verso l'interno: e' un vuoto sigillato."""
    r = d_cav / 2
    tmp = []
    rivoluzione(tmp, [(0, z0), (r, z0), (r, z1), (0, z1)], n)
    tris.extend((a, c, b) for a, b, c in tmp)


# ----------------------------------------------------------------------------
# Icona NFC (tre onde)
# ----------------------------------------------------------------------------
def onde(p):
    """Per ogni arco: (contorno antiorario completo, meta' superiore, meta' inferiore).

    Le meta' sono i pezzi di contorno da percorrere nella faccia superiore del
    dischetto (che e' tagliata lungo y = 0 in due poligoni senza buchi).
    """
    w = p["icona_tratto"]
    a = math.radians(p["icona_angolo"])
    raggi = p["icona_raggi"]
    N = 2 * math.ceil(p["icona_angolo"] * p["$fn"] / 360)
    M = 16  # segmenti di ogni testa arrotondata (mezzo cerchio, come circle($fn=32))
    xmin = raggi[0] * math.cos(a) - w / 2
    xmax = raggi[-1] + w / 2
    x0 = -(xmin + xmax) / 2
    risultato = []
    for r in raggi:
        ang = [a * (2 * i - N) / N for i in range(N + 1)]
        est = [(x0 + (r + w / 2) * math.cos(t), (r + w / 2) * math.sin(t)) for t in ang]
        intr = [(x0 + (r - w / 2) * math.cos(t), (r - w / 2) * math.sin(t)) for t in ang]
        # testa a +a: da est[N] a intr[N] passando per la punta
        u, t = (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))
        E = (x0 + r * u[0], r * u[1])
        testa_su = [(E[0] + w / 2 * (math.cos(s) * u[0] + math.sin(s) * t[0]),
                     E[1] + w / 2 * (math.cos(s) * u[1] + math.sin(s) * t[1]))
                    for s in (math.pi * j / M for j in range(1, M))]
        # testa a -a: da intr[0] a est[0] passando per la punta
        u, t = (math.cos(a), -math.sin(a)), (-math.sin(a), -math.cos(a))
        E = (x0 + r * u[0], r * u[1])
        testa_giu = [(E[0] + w / 2 * (-math.cos(s) * u[0] + math.sin(s) * t[0]),
                      E[1] + w / 2 * (-math.cos(s) * u[1] + math.sin(s) * t[1]))
                     for s in (math.pi * j / M for j in range(1, M))]
        h = N // 2
        contorno = est + testa_su + intr[::-1] + testa_giu
        meta_su = intr[h:] + testa_su[::-1] + est[h:][::-1]
        meta_giu = est[:h + 1][::-1] + testa_giu[::-1] + intr[:h + 1]
        assert area_poligono(contorno) > 0
        risultato.append((contorno, meta_su, meta_giu))
    return risultato


# ----------------------------------------------------------------------------
# Pezzi
# ----------------------------------------------------------------------------
def mesh_dischetto(p, d):
    n = p["$fn"]
    R = p["disco_d"] / 2
    H = d["H"]
    f = p["raccordo_sopra"]
    c = p["smusso_sotto"]
    Rt = R - f  # raggio della parte piatta in cima
    tris = []

    # Corpo (ruotato) senza la faccia superiore
    if p["incavo_adesivo"]:
        ri, hi = p["incavo_d"] / 2, p["incavo_h"]
        profilo = [(0, hi), (ri, hi), (ri, 0), (R - c, 0), (R, c)]
    else:
        profilo = [(0, 0), (R - c, 0), (R, c)]
    profilo.append((R, H - f))
    for i in range(1, 8):
        a = math.radians(i * 90 / 8)
        profilo.append((R - f + f * math.cos(a), H - f + f * math.sin(a)))
    profilo.append((Rt, H))
    rivoluzione(tris, profilo, n)

    # Faccia superiore (con i buchi delle onde), divisa in due lungo y = 0
    anello = [punto_anello(Rt, H, k, n)[:2] for k in range(n)]
    archi = onde(p) if p["icona"] else []
    h = n // 2
    sopra = [anello[h]]
    for _, meta_su, _ in archi:
        sopra += meta_su
    sopra += anello[0:h]
    sotto = anello[h:n] + [anello[0]]
    for _, _, meta_giu in reversed(archi):
        sotto += meta_giu
    faccia(tris, sopra, H)
    faccia(tris, sotto, H)

    # Rilievo delle onde
    for contorno, _, _ in archi:
        pareti(tris, contorno, H, d["H_icona"])
        faccia(tris, contorno, d["H_icona"])

    # Cavita' per il tag
    cavita(tris, d["cav_d"], d["z_cav_bot"], d["z_cav_top"], n)
    return tris


def mesh_provino(p, d):
    n = p["$fn"]
    s = p["provino_lato"] / 2 - p["provino_raggio"]
    rr = p["provino_raggio"]
    q = n // 4
    contorno = []
    for cx, cy, k0 in ((s, s, 0), (-s, s, q), (-s, -s, 2 * q), (s, -s, 3 * q)):
        for j in range(q + 1):
            cc, ss = cos_sin(k0 + j, n)
            contorno.append((cx + rr * cc, cy + rr * ss))
    tris = []
    faccia(tris, contorno, 0.0, verso_alto=False)
    faccia(tris, contorno, d["Hp"])
    pareti(tris, contorno, 0.0, d["Hp"])
    cavita(tris, d["cav_d"], d["z_prov_bot"], d["z_prov_top"], n)
    return tris


# ----------------------------------------------------------------------------
# STL e controlli
# ----------------------------------------------------------------------------
def normale(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    nx, ny, nz = u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]
    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return nx / l, ny / l, nz / l


def scrivi_stl(percorso, tris, nome):
    with open(percorso, "wb") as f:
        f.write(f"SvegliaNFC {nome} (binario, mm)".encode().ljust(80, b" ")[:80])
        f.write(struct.pack("<I", len(tris)))
        for a, b, c in tris:
            f.write(struct.pack("<12fH", *normale(a, b, c), *a, *b, *c, 0))


def leggi_stl(percorso):
    with open(percorso, "rb") as f:
        dati = f.read()
    n = struct.unpack_from("<I", dati, 80)[0]
    assert len(dati) == 84 + 50 * n, "dimensione file STL non coerente"
    tris = []
    for i in range(n):
        v = struct.unpack_from("<12f", dati, 84 + 50 * i)
        tris.append((v[3:6], v[6:9], v[9:12]))
    return tris


def controlla(tris):
    """Verifica che la mesh sia chiusa e orientata; ritorna statistiche."""
    vid = {}
    facce = []
    for t in tris:
        facce.append(tuple(vid.setdefault(v, len(vid)) for v in t))
    spigoli = {}
    degeneri = 0
    for a, b, c in facce:
        if len({a, b, c}) < 3:
            degeneri += 1
        for e in ((a, b), (b, c), (c, a)):
            spigoli[e] = spigoli.get(e, 0) + 1
    errori = sum(1 for e, k in spigoli.items() if k != 1 or spigoli.get((e[1], e[0]), 0) != 1)
    # gusci (componenti connesse)
    padre = list(range(len(vid)))

    def radice(x):
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x
    for a, b, c in facce:
        for u, v in ((a, b), (b, c)):
            ru, rv = radice(u), radice(v)
            if ru != rv:
                padre[ru] = rv
    gusci = len({radice(v) for v in range(len(vid))})
    V, E, F = len(vid), len(spigoli) // 2, len(facce)
    vol = sum(
        (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0]))
        for a, b, c in tris) / 6.0
    xs = [v[0] for t in tris for v in t]
    ys = [v[1] for t in tris for v in t]
    zs = [v[2] for t in tris for v in t]
    return dict(triangoli=F, vertici=V, spigoli_errati=errori, degeneri=degeneri, gusci=gusci,
                eulero=V - E + F, volume=vol,
                bbox=(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)),
                zmin=min(zs), zmax=max(zs))


def main():
    p = leggi_parametri(os.path.join(QUI, "dischetto.scad"))
    d = calcola(p)
    L = p["layer_h"]
    q = d["q"]
    pezzi = [("dischetto", mesh_dischetto(p, d)), ("provino", mesh_provino(p, d))]
    tutto_ok = True
    for nome, tris in pezzi:
        percorso = os.path.join(QUI, f"{nome}.stl")
        scrivi_stl(percorso, tris, nome)
        s = controlla(leggi_stl(percorso))  # ricontrolla il file scritto (float32)
        ok = s["spigoli_errati"] == 0 and s["degeneri"] == 0 and s["eulero"] == 2 * s["gusci"]
        tutto_ok &= ok
        g = s["volume"] / 1000 * DENSITA_PLA
        print(f"{nome}.stl: {s['triangoli']} triangoli, {s['gusci']} gusci "
              f"(esterno + cavita'), {'CHIUSO/manifold OK' if ok else 'ERRORI NELLA MESH'}")
        print(f"   ingombro {s['bbox'][0]:.2f} x {s['bbox'][1]:.2f} x {s['bbox'][2]:.2f} mm, "
              f"volume pieno {s['volume'] / 1000:.2f} cm3 = {g:.1f} g di PLA al 100%")
    print()
    print(f"Cavita' tag: diametro {d['cav_d']} mm, profonda {d['cav_h']} mm ({d['n_cav']} layer)")
    print(f"DISCHETTO: cavita' da Z {d['z_cav_bot']} a Z {d['z_cav_top']} mm; "
          f"sotto {d['pavimento']} mm di plastica (oltre l'incavo), sopra {q(d['n_cop'])} mm")
    pd = d["pausa_dischetto"]
    print(f"  ultimo layer con la cavita' aperta: {pd - 1} (finisce a Z {q(pd - 1)})")
    print(f"  >>> PAUSA in Bambu Studio sul layer {pd} (Z {q(pd)}) <<<  (si ferma prima di stamparlo)")
    if p["icona"]:
        cc = d["cambio_colore"]
        print(f"  cambio colore facoltativo per l'icona: layer {cc} (Z {q(cc)})")
    print(f"  layer totali: {d['n_disco'] + d['n_icona']} (altezza {d['H_icona']} mm)")
    pp = d["pausa_provino"]
    print(f"PROVINO: cavita' da Z {d['z_prov_bot']} a Z {d['z_prov_top']} mm; ultimo layer aperto {pp - 1} "
          f"(Z {q(pp - 1)}); >>> PAUSA sul layer {pp} (Z {q(pp)}) <<<; layer totali {d['n_prov']}")
    if not tutto_ok:
        sys.exit("ATTENZIONE: una mesh non e' chiusa, non stampare")


if __name__ == "__main__":
    main()
