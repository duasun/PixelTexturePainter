# Plan, arhitektura i izvori

## Implementirano

1. Glavni prozor, komponente i UI scene; File/Edit/View; ravne kontrole, Verdana, SVG ikonice.
2. Dokument sa retkim blokovima, lokalni undo/redo, snimanje i recovery.
3. 2D/3D prikaz, BVH biranje površine i diskretni kursor sa obrisom četkice.
4. Brush sa 20 ugrađenih i uvozivih PNG maski, spray sa Opacity/Strength i preview tačkicama, clone, smudge, blur, stamp, picker i Alt+klik, oblici, selekcije, maske i slojevi sa okom i preimenovanjem.
5. Fill režimi Color, Texture, šest ugrađenih patterna i korisnički piksel-kanvas; rotacija i skala patterna, gradijent sa dužinom u texelima i razvijanjem preko susednih trouglova.
6. Auto UV ugaonim projekcijama, provera preklapanja, MaxRects pakovanje i osnovno uređivanje ostrva.
7. Efekti uživo, geometrijske ivice, PNG, GLB/glTF sa naslikanom teksturom i OBJ export.
8. Funkcionalne provere, Godot render test i 4K merenje na lokalnom GPU-u.

9. Učitavanje PNG/Lospec paleta, dva označena uzorka, flood fill po boji, skrivanje UV panela, compact toolbar u dve kolone i rast/sužavanje selekcije.
10. Tab wireframe, hover površine u Select režimu, stabilni paneli sa pamtljivim razdelnicima i izbor mape nad radnom površinom.
11. Albedo, Roughness, Metallic, Normal, Height, AO i Emission na odvojenim slojevima; PNG izvoz svih mapa i podržane PBR mape u GLB/glTF.
12. Ikonice za komande prikaza i četkice, File meniji bez duplih gornjih dugmadi, podrazumevani dvokolonski Compact, korisnički config sa poslednjim projektom i podešavanjima.
13. Pregled linije, pravougaonika i elipse u 3D shaderu i 2D Canvas crtanju do puštanja miša; pregled ne menja slojeve.
14. Izmena palete kroz ColorPicker, globalni Replace color i flood fill sa tolerancijom/povezanošću.
15. UV reprojekcija postojeće boje, pregled Apply/Cancel i Undo; promena rezolucije celog projekta, UV dijagnostika i padding na izvozu.
16. Prenos postojećih GLB/glTF materijalnih mapa pri uvozu, izmenjivi pattern fill sloj, AO/ivice kao maske i osvetljeni PBR pregled.
17. 3D simetrija po X/Y/Z osama za slobodno crtanje, sa markerima na ogledanoj površini.

Sledeći koraci traže zasebnu implementaciju: kamera-projektovan stencil, LSCM za organske modele, više materijalnih atlasa, pun tangent-space materijalni prikaz sa više svetala i simetrija oblika/klona. Ne uključivati neproverenu native UV biblioteku kao obaveznu zavisnost.

Palete do 1024 boje koriste balansirano RGB stablo za prikaz i CPU izvoz, sa istim pravilom za jednake udaljenosti. Flood fill čita kompozit preko zasebnih keševa, koristi scanline unutar blokova 64×64 i brzi put za jednobojne blokove. Vraća pre/posle blokove kao ostali paint poslovi. GLB/glTF izvoz koristi ugrađeni [GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html). Selekcija je zaseban shader mesh i ne ulazi u izvezenu sliku ili geometriju.

## Granice komponenti

- `core/PaintDocument`: podaci projekta; `PaintLayer`: blokovi i cache kompozicije; `PaintHistory`: reverzibilne komande.
- `core/PaintChannels`: identitet i podrazumevane vrednosti mapa; aktivna mapa određena je aktivnim slojem. Kompozicija filtrira slojeve po kanalu. Color efekti važe samo za Albedo. Svaki efekat ima imenovani gornji sloj sa sopstvenim `effect_settings`; stariji globalni efekti se pri otvaranju prebacuju u te slojeve. Projektni format 2 čuva kanale i čita prethodni format 1.
- `paint/PaintEngine`: jedan potez, zamrznuta podešavanja, interpolacija, lokalni mask cache i raspoređivanje rada kroz frejmove.
- `paint/TileDisplay`: CPU kompozicija izmenjenih blokova i parcijalno osvežavanje GPU texture-array stranica.
- `paint/PaintOperations`: veće operacije vraćaju komandu; ne menjaju aktivni dokument tokom rada.
- `paint/ProjectTransforms`: promene UV, rezolucije, boja i prenos uvezenih tekstura nad kopijom dokumenta; `paint/PBRPreview`: ograničene slike za osvetljeni viewport.
- `core/BackgroundJob`: jedna pozadinska nit, mutex za napredak/otkazivanje; rezultat se primenjuje na glavnoj niti.
- `core/ModelGeometry`: eksplicitni uglovi trouglova, topološke veze, UV lookup i BVH. Ne vezuje UV šavove za identitet geometrijskog verteksa.
- `uv/`: samostalna implementacija projekcije i MaxRects pakovanja.
- `io/`: runtime GLB/glTF i OBJ, verzionisana ZIP arhiva i izvoz.
- `scenes/`: raspored i kontrole. `ui/`: ponašanje tih komponenti.
- `ui/MainWindow`: jedino mesto koje spaja dokument, servise i UI. Dete emituje signal naviše; roditelj poziva metodu naniže. Komponente ne traže roditelja preko `get_parent()` da bi menjale njegovo stanje.
- `ui/PainterConfig`: korisnički ConfigFile za poslednji projekat, alat, sprej, toolbar i raspored. Izmene se odloženo snimaju da povlačenje numeričkih polja ne piše fajl na svaki korak; zadnja putanja se upisuje odmah po uspešnom otvaranju/snimanju.

## Performanse

Jedna 4K RGBA slika zauzima 64 MiB. Puno kopiranje takve slike na svakom događaju miša ili svakom undo koraku nije prihvatljiva osnova. Zato su istorija i CPU slojevi podeljeni na 64×64 blokove, sa implicitnom osnovnom bojom i implicitno belim maskama.

Godot `ImageTexture.update()` osvežava celu sliku. Prikaz koristi `Texture2DArray`, stranice 256×256 i `update_layer()` samo za prljave stranice. Shader bira stranicu iz UV koordinata i koristi nearest uzorkovanje. Na 4K jedan prikaz zauzima približno 64 MiB GPU podataka plus CPU staging. Nekoliko promenjenih texela ne zahteva slanje celog atlasa.

Maske za 3D četkicu rasterizuju samo potrebne 64×64 blokove pogođenog ostrva. UV prostorne ćelije prethodno smanjuju listu kandidata. Cache je ograničen na 256 blokova. Clone koristi lenje kompozitne kopije izvora i copy-on-write, da izbegne punu kopiju 4K projekta na početku poteza.

Smudge i Blur uzorkuju lokalne CPU blokove trenutne mape, bez GPU readback-a, sa četkicom do 64 px. Blur koristi premultiplied alpha i izvorni Image resize za lokalni filter. Spray akumulira coverage samo na pogođenim blokovima; Opacity ograničava ceo potez, a Strength zajedno određuje internu gustinu i nakupljanje čestica. Preview i sledeći nalet koriste isti seed i ograničenja selekcije/ostrva. Brush maska se skalira i tonira jednom na početku poteza; 3D/UV preview se kešira za izabranu veličinu i boju. Wireframe se gradi pri promeni geometrije, a hover samo pri promeni ciljne grupe. Preview markeri ne ulaze u eksport.

Panel palete i inspektor imaju Control omotače koji odvajaju minimalne veličine sadržaja od SplitContainer razdelnika. Raspored je definisan scenama; kod čuva samo korisničke split offset vrednosti. GPU prikaz drži trenutno izabranu mapu. Osvetljeni pregled pravi šest privremenih mapa do 1024 px u pozadinskoj niti, bez šest stalnih 4K GPU kopija.

Undo ima ciljnu granicu 192 MiB i 256 komandi. Jedna pojedinačna veća komanda ostaje sačuvana i ako premaši memorijski cilj, kako upravo izvršena operacija ne bi postala neponištiva. Najskuplji delovi koji još zahtevaju profilisanje na većim slučajevima su Multiply/Add, vrlo veliki UV chartovi, velike četkice i pune operacije sa maskama.

## Istraživanje i odluke

- [Pixel8r2](https://actiondawg.itch.io/pixel8r2) je Substance filter, sa pixelizacijom, kvantizacijom, ditheringom i paletama. Poslužio je kao referenca za efekte, ne kao osnova samostalnog paint engine-a.
- [Union Bytes Painter](https://www.unionbytes.de/apps/ubpainter/) i [Blockbench](https://www.blockbench.net/) su reference za brz 2D/3D rad i retro teksture.
- [ArmorPaint manual](https://armorpaint.org/manual) je referenca za brush/fill/clone/layer tok rada.
- [Jukka Jylänki — RectangleBinPack / MaxRects](https://github.com/juj/RectangleBinPack) opisuje pakovanje pravougaonika. Ovde je algoritam implementiran direktno u GDScriptu, bez binarne zavisnosti.
- [Blender UV dokumentacija](https://docs.blender.org/manual/en/latest/modeling/meshes/editing/uv.html) daje kontekst za razdvajanje po uglovima i projekcije.
- [Lévy i saradnici — Least Squares Conformal Maps](https://brunolevy.github.io/papers/LSCM_SIGGRAPH_2002.pdf) je smer za kasniji kvalitetniji unwrap; LSCM nije implementiran u ovoj verziji.
- [Godot runtime file loading](https://docs.godotengine.org/en/4.7/tutorials/io/runtime_file_loading_and_saving.html) i [ImageTexture](https://docs.godotengine.org/en/4.7/classes/class_imagetexture.html) određuju podržani import i strategiju osvežavanja teksture.

Nijedan referentni program niti njegova grafička sredstva nisu kopirani u projekat.
