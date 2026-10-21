// =====================================================================
//  DISCHETTO NFC per SvegliaNFC
//  Disco in PLA con un tag NFC sigillato DENTRO durante la stampa
//  (pausa a meta' stampa, inserisci il tag, riprendi).
//
//  Stampante: Bambu Lab A1, ugello 0.4 mm, layer 0.2 mm
//  (anche il PRIMO layer deve essere 0.2 mm, cosi' tutte le quote
//  cadono esattamente su un cambio layer).
//  Unita': millimetri.
//
//  Come si usa:
//   - In OpenSCAD: Finestra > Customizer, cambia i numeri, F6 (Render),
//     File > Esporta > STL. Nella console trovi il layer della pausa.
//   - Senza OpenSCAD: modifica i numeri qui sotto con un editor di testo
//     e lancia  python3 genera_stl.py  (legge QUESTA sezione parametri).
//     Scrivi un valore per riga, nella forma  nome = valore;
// =====================================================================

/* [Cosa esportare] */
// "dischetto" = pezzo finale, "provino" = test veloce, "sezione" = dischetto tagliato a meta' (solo per guardare l'interno, NON stamparlo)
pezzo = "dischetto"; // [dischetto, provino, sezione]

/* [Stampa] */
// altezza layer in mm (anche il primo layer deve essere uguale)
layer_h = 0.2;

/* [Corpo del dischetto] */
// diametro del dischetto
disco_d = 55;
// spessore del corpo SENZA il rilievo dell'icona (multiplo di layer_h)
disco_h = 6.0;
// raggio dell'arrotondamento sul bordo superiore
raccordo_sopra = 0.8;
// smusso a 45 gradi sul bordo inferiore (contro la "zampa d'elefante")
smusso_sotto = 0.4;

/* [Tag NFC - MISURALO col calibro!] */
// diametro del tag
tag_d = 25;
// spessore del tag (compreso l'eventuale adesivo)
tag_t = 1.0;
// gioco sul diametro della cavita'
gioco_d = 0.5;
// gioco sullo spessore (la profondita' viene poi arrotondata in su a un multiplo di layer_h)
gioco_t = 0.2;
// plastica sopra il tag: 1.2 mm = 6 layer (abbastanza sottile per l'NFC, abbastanza spessa da sembrare piena)
copertura = 1.2;

/* [Icona NFC in rilievo] */
// true = metti l'icona delle onde sopra, false = superficie liscia
icona = true;
// altezza del rilievo (multiplo di layer_h)
icona_h = 0.6;
// larghezza del tratto delle onde (almeno 1.2 con ugello 0.4)
icona_tratto = 2.4;
// raggi (in mezzeria del tratto) dei tre archi
icona_raggi = [6, 11.5, 17];
// semi-apertura degli archi, in gradi
icona_angolo = 48;

/* [Incavo per biadesivo, sotto] */
// true = incavo tondo sotto per un tondino biadesivo, false = fondo piatto
incavo_adesivo = true;
// diametro dell'incavo
incavo_d = 40;
// profondita' dell'incavo (multiplo di layer_h)
incavo_h = 0.4;
// spessore minimo di plastica tra incavo e cavita' del tag
pavimento_min = 1.6;

/* [Provino veloce] */
// lato del quadrato
provino_lato = 32;
// altezza minima del provino (multiplo di layer_h; cresce da sola se il tag e' spesso)
provino_h = 4.0;
// raggio degli angoli
provino_raggio = 4;

/* [Qualita'] */
// segmenti per cerchio (piu' alto = piu' liscio)
$fn = 160;

// ------------------------- FINE PARAMETRI -------------------------
/* [Hidden] */

// ---- Valori calcolati (non toccare) ----
// Tutte le quote Z sono numeri interi di layer: cosi' il fondo e il
// soffitto della cavita' coincidono con un cambio layer.
cav_d   = tag_d + gioco_d;                                   // diametro cavita'
n_cav   = ceil((tag_t + gioco_t) / layer_h - 0.001);         // layer di cavita'
n_cop   = ceil(copertura / layer_h - 0.001);                 // layer sopra il tag
cav_h   = n_cav * layer_h;                                   // profondita' cavita'

n_disco = round(disco_h / layer_h);                          // layer del corpo
z_cav_top = (n_disco - n_cop) * layer_h;                     // soffitto cavita'
z_cav_bot = z_cav_top - cav_h;                               // fondo cavita'
pavimento = z_cav_bot - (incavo_adesivo ? incavo_h : 0);     // plastica sotto

// il provino si alza da solo per lasciare almeno pavimento_min sotto il tag
n_prov = max(round(provino_h / layer_h), n_cav + n_cop + ceil(pavimento_min / layer_h - 0.001));
h_prov = n_prov * layer_h;
z_prov_top = (n_prov - n_cop) * layer_h;
z_prov_bot = z_prov_top - cav_h;

// La pausa va messa sul PRIMO layer che copre la cavita':
// Bambu Studio si ferma PRIMA di stampare quel layer.
// (layer 1 = da Z 0 a Z 0.2; il layer n finisce a Z = n * layer_h)
pausa_dischetto = n_disco - n_cop + 1;
pausa_provino   = n_prov - n_cop + 1;
cambio_colore   = n_disco + 1;      // primo layer del rilievo

assert(abs(disco_h / layer_h - n_disco) < 0.001, "disco_h deve essere un multiplo di layer_h");
assert(abs(icona_h / layer_h - round(icona_h / layer_h)) < 0.001, "icona_h deve essere un multiplo di layer_h");
assert(abs(incavo_h / layer_h - round(incavo_h / layer_h)) < 0.001, "incavo_h deve essere un multiplo di layer_h");
assert(abs(provino_h / layer_h - round(provino_h / layer_h)) < 0.001, "provino_h deve essere un multiplo di layer_h");
assert(pavimento >= pavimento_min - 0.001, "Tag troppo spesso: aumenta disco_h (o togli incavo_adesivo)");
assert(z_prov_bot >= pavimento_min - 0.001, "Tag troppo spesso per il provino: aumenta provino_h");
assert(icona_tratto >= 1.2, "icona_tratto troppo sottile per un ugello da 0.4");
assert(cav_d <= disco_d - 6, "Tag troppo largo per il dischetto");

echo(str("DISCHETTO: cavita' diametro ", cav_d, " mm, da Z=", z_cav_bot, " a Z=", z_cav_top,
         " mm; plastica sotto ", pavimento, " mm, sopra ", disco_h - z_cav_top, " mm"));
echo(str("DISCHETTO: ultimo layer con cavita' aperta = ", pausa_dischetto - 1,
         " (Z=", (pausa_dischetto - 1) * layer_h, ")"));
echo(str("DISCHETTO: PAUSA sul layer ", pausa_dischetto, " (Z=", pausa_dischetto * layer_h, " mm)"));
echo(str("DISCHETTO: cambio colore (facoltativo) sul layer ", cambio_colore,
         " (Z=", cambio_colore * layer_h, " mm); layer totali ", n_disco + round(icona_h / layer_h)));
echo(str("PROVINO: alto ", h_prov, " mm, cavita' da Z=", z_prov_bot, " a Z=", z_prov_top,
         "; PAUSA sul layer ", pausa_provino, " (Z=", pausa_provino * layer_h, " mm)"));

// ---------------------------- Moduli ----------------------------

// Profilo (raggio, altezza) del corpo, da far ruotare attorno all'asse Z
module profilo_dischetto() {
    R = disco_d / 2;
    H = disco_h;
    f = raccordo_sopra;
    c = smusso_sotto;
    ri = incavo_d / 2;
    hi = incavo_h;
    raccordo = [for (i = [0:8]) let(a = i * 90 / 8) [R - f + f * cos(a), H - f + f * sin(a)]];
    base = incavo_adesivo
        ? [[0, hi], [ri, hi], [ri, 0], [R - c, 0], [R, c]]
        : [[0, 0], [R - c, 0], [R, c]];
    polygon(concat(base, raccordo, [[0, H]]));
}

// Un arco "onda": settore di corona circolare con le estremita' arrotondate
module arco_2d(r, w, a) {
    n = 2 * ceil(a * $fn / 360);
    polygon(concat(
        [for (i = [0:n]) let(t = a * (2 * i - n) / n) (r + w / 2) * [cos(t), sin(t)]],
        [for (i = [n:-1:0]) let(t = a * (2 * i - n) / n) (r - w / 2) * [cos(t), sin(t)]]
    ));
    for (s = [-1, 1])
        translate(r * [cos(s * a), sin(s * a)]) circle(d = w, $fn = 32);
}

// Simbolo NFC: tre onde che si aprono verso destra (come "wave.3.right"),
// centrate sul dischetto (centro del loro ingombro)
module icona_2d() {
    xmin = icona_raggi[0] * cos(icona_angolo) - icona_tratto / 2;
    xmax = icona_raggi[len(icona_raggi) - 1] + icona_tratto / 2;
    translate([-(xmin + xmax) / 2, 0])
        for (r = icona_raggi) arco_2d(r, icona_tratto, icona_angolo);
}

// Cavita' per il tag: vuoto chiuso, senza aperture
module cavita(z0) {
    translate([0, 0, z0]) cylinder(d = cav_d, h = cav_h);
}

module dischetto() {
    union() {
        difference() {
            rotate_extrude() profilo_dischetto();
            cavita(z_cav_bot);
        }
        if (icona)
            // parte 0.01 mm dentro il corpo per unire bene i due solidi;
            // la cima resta esattamente a disco_h + icona_h
            translate([0, 0, disco_h - 0.01])
                linear_extrude(height = icona_h + 0.01) icona_2d();
    }
}

module provino() {
    difference() {
        linear_extrude(height = h_prov)
            offset(r = provino_raggio)
                square(provino_lato - 2 * provino_raggio, center = true);
        cavita(z_prov_bot);
    }
}

// Solo per vedere l'interno: meta' dischetto (y >= 0) + il tag in trasparenza
module sezione() {
    difference() {
        dischetto();
        translate([-disco_d, -2 * disco_d, -1]) cube([2 * disco_d, 2 * disco_d, disco_h + 10]);
    }
    % translate([0, 0, z_cav_bot]) cylinder(d = tag_d, h = tag_t);
}

// ---------------------------- Uscita ----------------------------
if (pezzo == "dischetto") dischetto();
else if (pezzo == "provino") provino();
else if (pezzo == "sezione") sezione();
else echo("pezzo deve essere \"dischetto\", \"provino\" o \"sezione\"");
