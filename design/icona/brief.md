# Icona — brief e provenienza

**Scelta:** `icona.svg` ("Il dischetto all'alba"), esportata in `SvegliaNFC/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024 × 1024, senza trasparenza).

**Come è stata fatta:** disegnata a mano in SVG. Recraft, il generatore di asset previsto, non era disponibile in questa sessione.

**Brief**
- Concetto: il dischetto NFC dell'app che sorge come il sole sull'orizzonte. Svegliarsi = raggiungere il tag.
- Stile: piatto, forme geometriche semplici, leggibile fino a 40 px.
- Palette (la stessa dell'app, `Design/Theme.swift`):
  - notte `#1A1F3D` → `#07080F`;
  - alba `#FF6154` → `#FF8F3D` → `#FFC761`;
  - linee `#FFE7C2`, onde `#2A1206`.
- Elementi: sfondo notte con bagliore caldo dal basso, cerchio con gradiente alba tagliato dall'orizzonte, due onde NFC scure (come il simbolo `wave.3.right`), due linee d'orizzonte.

**Scartata:** `esplorazioni/A-pantofola.svg`, la pantofola con le onde NFC: simpatica, ma meno leggibile alle dimensioni piccole.

**Come rigenerare il PNG**
```bash
qlmanage -t -s 1024 -o /tmp design/icona/icona.svg
sips -s format jpeg -s formatOptions 100 /tmp/icona.svg.png --out /tmp/icona.jpg
sips -s format png /tmp/icona.jpg --out SvegliaNFC/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```
Il passaggio dal JPEG serve a togliere il canale alfa, che l'App Store non accetta nell'icona.
