# Pixel texture painter

Samostalni alat za bojenje low-poly modela. Projekat koristi Godot 4.7, GDScript i Compatibility renderer. Razvijen i testiran postojećim Godotom sa ovog računara; ne zahteva dodatne biblioteke ili GDExtension.

## Pokretanje

- Dvoklik na **Pokreni Painter.cmd**. Ako postoji izvezeni program u `build`, pokreće njega; u suprotnom koristi postojeći Godot.
- Za uređivanje: otvori **project.godot** u Godotu, zatim F6 za pojedinačnu scenu ili F5 za program.
- Izvoz u `build/PixelTexturePainter.exe` je za Windows ARM64, za ovaj Snapdragon računar. Za x64 računar promeni arhitekturu export preseta i izvezi odgovarajući build.

UI je u `.tscn` scenama. Font je instalirana **Verdana**, preko SystemFont resursa. Font nije kopiran iz Windowsa u projekat.

## Brz početak

1. Program pri pokretanju otvara poslednji uspešno otvoren ili snimljen projekat. Ako ga nema, prikazuje primer obojenog sanduka. **File → New project**: izaberi rezoluciju ili posebno širinu i visinu, od 16 do 4096 px. Novi projekat dobija praznu teksturu i kocku kao početni model.
2. **File → Import model** učitava GLB, glTF ili OBJ. Novi model zamenjuje prethodnu geometriju, UV mrežu i stare slojeve boje; **Undo** ih vraća. Postojeće UV koordinate iz GLB/glTF se koriste bez novog odmotavanja (sitne greške zaokruživanja na ivici 0–1 se poravnaju sa ivicom). Albedo, Roughness, Metallic, Normal, AO i Emission materijalne teksture prenose se na te koordinate kao slojevi koje možeš dalje da slikaš; novi prazan Paint sloj je iznad njih. Ako različiti materijali koriste ista UV polja, program čuva prvu teksturu na preklopljenim pikselima i prijavljuje broj preklopa. OBJ učitava geometriju i UV, ali trenutno ne čita MTL teksture. Model bez UV pripremi u tabu **UV → Generate UV layout**. UV Info pokazuje broj sitnih/nepokrivenih trouglova i preklapanja.
3. **S / Select**: klik na model ili UV teksturu bira UV ostrvo; u Layers izaberi Face, Object ili Material za drugačiji izbor. Shift dodaje, Ctrl oduzima, Esc čisti izbor. **Ctrl+.** dodaje jedan prsten susednih trouglova preko zajedničkih ivica; **Ctrl+,** vraća po jedan korak do početnog izbora. Novi ručni izbor postavlja novu početnu selekciju. Žuta ivica sa tamnim obrisom i obojena površina pokazuju izbor u oba prikaza.
4. **B / Brush** crta direktno na modelu ili UV teksturi. Na modelu potez ostaje unutar pogođenog UV ostrva i ručnog izbora. U 2D možeš crtati i u praznim delovima atlasa.
5. **File → Save / Save as** čuva `.rtpaint` projekat. **Export current map PNG** izvozi izabranu mapu, a **Export all maps PNG** sve napravljene mape. **Export model** nudi **GLB**, **glTF** i OBJ; po uspešnom izvozu otvara odredišni folder u Windows Exploreru. GLB čuva geometriju, trenutni UV, Albedo sa efektima i podržane materijalne mape u jednom fajlu. Uz glTF sačuvaj i prateće `.bin`/slikovne fajlove koje izvoz napravi. Materijal koristi nearest filtriranje; projekat samo sa Albedom izvozi se kao unshaded, a sa dodatnim podržanim mapama kao PBR materijal. OBJ čuva geometriju i UV; teksture za njega izvezi posebno.

**UV view** uz izbor mape dole desno u prozoru modela, ili **View → Show / hide UV panel**, skriva i vraća ceo UV panel. UV podaci ostaju u projektu. **Compact** na bočnom toolbaru slaže ikonice u **dve kolone**; naziv i prečica alata vide se u tooltipu. Ponovni klik vraća tekst. Model, UV, paleta i inspektor imaju odvojene sive panele. Inspektor zauzima celu desnu visinu radnog prostora, a paleta je ispod prikaza levo. Visina palete i širina inspektora menjaju se povlačenjem njihovih razdelnika i pamte se između pokretanja. U Layers tabu razdelnik između liste i svojstava menja visinu liste slojeva i pamti se između pokretanja. Promena alata, sadržaja i taba ne menja njihovu veličinu.

**Tab**, **Wires** iznad modela ili **View → Toggle model wireframe** uključuje/isključuje ivice modela. Select automatski uključuje wireframe i svetloplavom bojom pokazuje površinu pod kursorom; žuta označava već izabrane površine. **Light** uključuje osvetljeni materijalni pregled koji kombinuje Albedo, Roughness, Metallic, Normal, AO i Emission. Pregled se osvežava u pozadini posle poteza i za 4K koristi najviše 1024 px po mapi; izvoz i sačuvane mape ostaju u punoj rezoluciji. Ovi markeri i pregled ne ulaze u izvoz.

Gore su **File / Edit / View / Help** meniji i naziv projekta. Novi/otvori/snimi/import/undo/export/exit su u menijima sa postojećim prečicama. **Help → About** otvara opis programa, koji se dopunjava u sceni `main_window.tscn`. Obe boje (1 i 2) ostaju označene u donjoj paleti. **Undo** i **Redo** su stalno vidljive ikonice levo od **Frame** iznad modela; omogućene su kada istorija ima odgovarajuću radnju. **Frame, Wires, Ortho, Light** uz model, kao i **Round, Dither, Mirror UV** uz podešavanja četkice, prikazani su ikonicama sa tooltipovima. Narandžasta boja dugmeta pokazuje uključeno stanje. Bočna traka se pri prvom pokretanju otvara u Compact režimu sa dve kolone.

Ispod menija je razmak, zatim podešavanja izabranog alata u jednom redu neposredno iznad prikaza, uključujući sva Spray polja. Prikazuju se samo podešavanja koja taj alat koristi. Veličinu četkice biraš u **Size**; njen obris i žuti marker na modelu/UV prikazu pokazuju ciljani texel. Obris odgovara kvadratnoj ili diskretnoj kružnoj četkici i prilagođava se zumu. **Soft edge** od 0% (oštar pixel brush) do 100% (mek rub) umanjuje jačinu ka ivici četkice. Radi i za Eraser, Clone, Smudge, Blur i oblike; meki potezi su korisni za Metallic, Roughness i druge mape. Mek rub računa se jednom za otisak poteza, a ne ponovo za svaki dodir. Selekcija i prozirnost mogu dodatno smanjiti efekat unutar obrisa.

## Alati i prečice

| Prečica | Radnja |
|---|---|
| B | Brush: veličina, opacity, square/round, dither, UV mirror |
| A | Spray: pojedinačni pikseli, kontinuirano prskanje dok držiš klik |
| E | Eraser |
| I | Eyedropper |
| Alt + levi klik | Brzi eyedropper uz zadržavanje izabranog alata |
| Ctrl + levi klik i vodoravno povlačenje | Menja Size trenutnog alata, uključujući širinu gradijenta; 3 px pomeraja miša po koraku |
| Alt + levi klik i vodoravno povlačenje | Menja opacity trenutnog alata, 2 px pomeraja miša po procentu |
| C | Clone; Ctrl + klik postavlja izvor |
| U / V | Smudge / Blur |
| F | Fill izabranih faces; bez selekcije flood fill povezane oblasti iste boje |
| P | Fill with Texture |
| G | Gradijent tačne dužine u pikselima |
| T | Stamp iz učitane slike |
| L / R / O | Linija / pravougaonik / elipsa |
| S | Izbor površina |
| Tab | Uključi / isključi wireframe modela |
| F2 | Preimenuj fokusirani sloj |
| Ctrl+. / Ctrl+, | Proširi selekciju / vrati prethodni prsten |
| [ / ] | Smanji / povećaj veličinu četkice |
| Ctrl+N / Ctrl+O | Novi / otvori projekat |
| Ctrl+S / Ctrl+Shift+S | Save / Save as |
| Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y | Undo / redo |
| Ctrl+E | Export PNG |

Prečice sa povlačenjem rade u 3D i UV prikazu. Pomeraj od najmanje 4 px razdvaja povlačenje od kratkog klika; Alt+klik i dalje uzima boju, a Ctrl+klik zadržava radnje kao što su clone izvor i oduzimanje selekcije. Podešavanje samo menja vrednost, bez poteza boje ili Undo stavke. U 3D prikazu drži desni klik i koristi **WASD** za kretanje, **E/Q** za gore/dole i **Shift** za brže kretanje. Dok držiš desni klik, pokret miša okreće kameru; srednji klik je pomera, a točkić sporije zumira ka površini ispod kursora i dopušta veoma blizak pregled bez prolaska kroz tu površinu. Prečice alata, uključujući A i E, rade čim pustiš desni klik. U UV prikazu srednji/desni klik pomera sliku. Numerička polja podržavaju unos klikom, horizontalno povlačenje, Shift za finije korake i točkić; šira polja van trake imaju i dugmad +/−.

Linija, pravougaonik, elipsa i gradijent prikazuju svetli pregled dok držiš levi klik i vučeš. Pregled se istovremeno vidi na modelu i u UV prikazu, a potez ulazi u aktivni sloj tek kada pustiš miš. Potez i dalje poštuje izbor površina i Undo.

**Sym X/Y/Z** u podešavanjima alata ogledaju 3D potez oko centra modela. Markeri na suprotnoj površini pokazuju gde će se crtati; jedan potez na svim uključenim osama ostaje jedna Undo radnja. Radi za Brush, Eraser, Stamp, Spray, Smudge i Blur kada se crta direktno na modelu. **Mirror UV** je zasebno ogledanje u atlasu.

### Palete i trenutne boje

**Load palette…** u dnu učitava PNG (po jedan piksel za boju, mrežu ili uvećane swatcheve), HEX, GIMP GPL, JASC PAL, Paint.NET TXT, RGB/grayscale ASE i Lospec JSON/CSV. Podržano je do 1024 boje. Providni PNG pikseli se preskaču; ponovljene boje PNG slike se objedinjuju. Tekstualni formati zadržavaju redosled iz fajla. Lospec preuzimanja su proverena na [Endesga 32](https://lospec.com/palette-list/endesga-32); [JSON/CSV API](https://lospec.com/palettes/api) koristi istu listu boja.

Levi klik bira **1**, desni **2**. Okvir i broj obeležavaju izabrane swatcheve. Dva stalna uzorka sa HEX vrednostima pokazuju trenutne boje i kada su uzete eyedropperom van palete. Dugme **+** ispod palete otvara birač i dodaje novu boju. **Edit selected color…** ili dvoklik na swatch menja boju, a **Remove color** je briše. Sve tri radnje podržavaju Undo/Redo. Paleta i obe boje čuvaju se u projektu; efekat Palette koristi celu paletu.

**Edit → Replace color** menja odgovarajuće piksele u slojevima trenutno prikazane mape, sa podesivom tolerancijom i jednom Undo radnjom. Za lokalno bojenje koristi Fill sa Tolerance i Contiguous.

### Fill i stamp

Bez selekcije **F** popunjava oblast vidljive boje povezanu preko horizontalnih/vertikalnih suseda, do granice druge boje. **Tolerance** određuje koliko susedna boja sme da odstupa; isključeni **Contiguous** menja sve odgovarajuće piksele u pogođenom UV ostrvu, ili u celoj teksturi iz UV prikaza. Sa izabranim faces, fill boji ceo izbor. Veliki fill radi u pozadini, može da se otkaže i ima jednu Undo akciju.

**File → Import stamp image…** učitava PNG/JPG/WebP do 4096×4096 i aktivira **Stamp / T**. Otvara se **Stamp** tab u desnom inspektoru: prevuci pravougaonik preko slike da koristiš samo taj deo. Točkić zumira oko kursora, a srednji klik i povlačenje pomeraju uvećanu sliku; levi klik i dalje precizno bira izvorne piksele. Prikaz ispod pokazuje izabrani otisak; **Use full image** vraća celu sliku. **Rotation** okreće otisak. PNG sa providnom pozadinom je pogodan za otiske. **Size** određuje veličinu otiska u texelima, **Opacity** jačinu. Možeš i da izabereš T pa klikneš na model ako slika još nije učitana. Slika i izabrana oblast čuvaju se u projektu, a promena oblasti podržava Undo. Ovo je slikovna četkica; kamera-projektovan stencil koji pomeraš preko ekrana još nije implementiran.

### Fill with Texture

Izaberi površine, otvori **Pattern**, učitaj sliku i podesi **Direction**, **Scale** i **Offset**. Klikni **Create pattern fill layer**, ili alatom P klikni površinu modela. Bez ručne selekcije klik bira pogođeno UV ostrvo. Dobijaš zaseban sloj: kasnije ga izaberi, promeni rotaciju, skalu ili pomeraj i pregled se ponovo proračunava; ručno slikanje po istom sloju ostaje iznad uzorka. Izvorna slika, izabrane površine i transformacija čuvaju se u projektu. Tekstura se ponavlja u prostoru UV atlasa; ovo nije triplanar projekcija.

### Spray

Skraćeni natpisi u traci su **Op** (Opacity), **Dots** (Density), **Step** (Spacing) i **Dist** (Distance); potpuni opisi su u tooltipovima.

- **Size** određuje prečnik na udaljenosti 100%; stvarni otisak vidi se kao obris na modelu i UV prikazu.
- **Density** je broj pokušaja nanošenja piksela po naletu; čestice mogu pasti na isti piksel.
- **Spacing** je razmak u texelima duž poteza.
- **Rate** je broj naleta u sekundi dok miš miruje.
- **Opacity** ograničava ukupnu jačinu jednog držanja klika: na 20% ni dugo prskanje u istom potezu ne prelazi 20% prema boji pre poteza. Novi potez može dodatno pojačati boju.
- **Flow** određuje koliko svaka čestica doprinosi dostizanju tog ograničenja.
- **Distance** je relativna udaljenost mlaznice: 200% udvostručuje prečnik i deli Flow sa četiri. Nije mera u metrima modela. Maksimalni efektivni prečnik je 256 texela.

Svetle tačkice unutar kursora pokazuju položaje **sledećeg naleta** u oba prikaza, uz ograničenje selekcijom i pogođenim UV ostrvom. Posle naleta prikaz prelazi na naredni raspored; svetlina markera ne predstavlja jačinu boje. Jedno držanje klika je jedna undo akcija. Redo vraća iste čestice, bez novog nasumičnog rasporeda. Podešavanja izmenjena tokom poteza važe za sledeći potez.

### Smudge i Blur

**U / Smudge** preuzima boju na početku poteza i razmazuje je povlačenjem. **V / Blur** lokalno omekšava postojeće texele. Oba alata čitaju kompozit trenutne mape, pišu u aktivni sloj i podržavaju selekciju i Undo/Redo. **Opacity** određuje jačinu; maksimalna veličina je 64 px radi odziva na 4K teksturama. Uzorkovanje je u UV prostoru; smudge prekida prenos boje pri prelasku na drugo UV ostrvo.

### Gradijent od tačno 7 px

Izaberi površinu/povezane površine, G, boju A i B, **Length = 7 px**, pa povuci u željenom smeru. **Size** određuje širinu obojene trake oko povučene linije: 4 px i 12 px sada daju različit rezultat. Vodič tokom prevlačenja pokazuje tu širinu u oba prikaza. Boje A i B zauzimaju prvi i sedmi uzorak; između njih je pet uzoraka. Izvan tog intervala ostaje krajnja boja. Dither daje prelaz sa samo te dve boje. Na susednim izabranim trouglovima gradijent se razvija preko fizički zajedničkih ivica, pa razmak između UV ostrva ne ulazi u dužinu. Mera koristi texel gustinu početnog trougla; različite gustine UV ostrva ne mogu istovremeno predstavljati istu fizičku dužinu i isti broj piksela.

### Clone i efekti

Ctrl+klik postavlja clone izvor u bilo kom prikazu. Svaki potez čita kompozit pre početka tog poteza, tako da preklapanje izvora i odredišta ne razmazuje uzorak. Novi potez ponovo polazi od postavljenog izvora.

**Wrap** u podešavanjima alata prenosi deo otiska koji dodiruje 3D ivicu na susednu vidljivu površinu, čak i kada između njih postoji UV šav. Ako su površine selektovane, boja ostaje unutar te selekcije. Važi za četkicu, gumicu, Clone, Stamp, Spray, Smudge, Blur i geometrijske poteze Line/Rectangle/Ellipse. Fill i Texture fill već koriste izabrane površine, a Gradient razvija prelaz preko njihovih zajedničkih ivica. Prekidač se pamti u configu.

Layers: dodavanje, kopiranje, brisanje, redosled, vidljivost, zaključavanje, opacity i Normal/Multiply/Add. **Oko i katanac su u svakom redu sloja**; oko menja vidljivost, katanac zabranjuje crtanje po tom sloju. Dvoklik na naziv, F2 na fokusiranom sloju ili polje Name menja naziv; vidljivost, zaključavanje i preimenovanje podržavaju Undo. **Reset current map** u Layers ili Edit meniju briše sadržaj svih slojeva izabrane mape, uz jedan Undo korak; struktura i druge mape ostaju.

Tab **Effects** radi sa sklopivim sekcijama. Na početku su sve zatvorene; program pamti koje otvoriš. Brightness, contrast, saturation, **Pixel Noise** i ograničenje na paletu odmah prikazuju efekat na Albedu. Pixel Noise ima Amount, Coverage, Grain size, Tone i Pattern seed; isti deterministički uzorak ulazi u PNG/GLB izvoz. Za geometrijske ivice i ambient occlusion, promena numeričkog polja i puštanje miša računa **privremeni pregled** u pozadini. Dugmad Generate/Bake prihvataju prikaz u jednom Undo koraku. Rasipanje Geometry Edges ostaje neprekidno preko trouglova istog UV ostrva. AO uzorkuje zaklanjanje poluloptastim zracima iz površine, uključujući odvojene delove modela. Strength određuje jačinu, Ray reach domet u texelima, Contact focus težište bliskih kontakata, a Falloff oblik opadanja. Uzorci se interpoliraju između tačaka na svakom UV trouglu i beleže u novom Albedo sloju. Za 4K AO se računa na internom atlasu do 1024 px po dužoj strani, pa se rezultat uvećava na punu rezoluciju radi bržeg pregleda i bake operacije. Ovi Albedo efekti ne menjaju druge mape.

**Blur selected layer** u Effects omekšava celu izabranu boju sloja, sa Radius 1–32 px. Puštanje kontrole ili **Preview blur** prikazuje rezultat bez izmene istorije; **Apply blur to layer** snima ga kao jedan Undo korak, a **Cancel preview** vraća original. Računanje ide u pozadini i zahvata samo naslikane tileove i njihove susede; crtanje je privremeno zaključano dok se pregled računa.

### Dodatne mape

Izbor **Map** dole desno u prozoru modela nudi **Albedo, Roughness, Metallic, Normal, Height, AO i Emission**. Prvi izbor nove mape pravi njen sloj; naredni slojevi pripadaju trenutno izabranoj mapi. Oznaka pored naziva sloja pokazuje kojoj mapi pripada, a izbor sloja automatski prikazuje tu mapu. Sve dele iste UV koordinate i rezoluciju, sa najviše 32 sloja ukupno.

Roughness, Metallic, Height i AO su grayscale podaci. Normal je RGB mapa u OpenGL +Y konvenciji, sa neutralnom bojom (128, 128, 255). Nacrtaj Height, otvori **Effects → Normal from Height**, podesi **Height strength** i klikni **Generate Normal map**. Generator čita razlike susednih texela i dodaje novi Normal sloj koji možeš dalje ručno da slikaš ili Undo vratiš. Ravne oblasti ostaju neutralne; na UV granicama može se pojaviti prelaz ako susedni delovi atlasa imaju različite visine.

GLB/glTF uključuje Albedo, Roughness, Metallic, Normal, AO i Emission kada njihove slojeve napraviš. **Height se izvozi kao PNG**, jer nije deo osnovnog glTF materijala. **Export all maps PNG** pravi fajlove oblika `ime_albedo.png`, `ime_roughness.png` itd.

## Snimanje i oporavak

`.rtpaint` sadrži geometriju, UV, slojeve svih mapa, paletu, efekte i izvorne slike za pattern/stamp. Stariji projekti koji imaju maske zadržavaju njihove podatke i izgled pri učitavanju. Novi format je verzija 2; učitavanje prethodnog formata verzije 1 ostaje podržano. Snimanje prvo pravi privremenu arhivu, a prethodna verzija ostaje u `.bak`. Undo istorija važi za otvorenu sesiju i ne čuva se u fajlu.

Posle izmena, automatski recovery se pravi približno svaka dva minuta kada nema aktivnog poteza/posla. **File → Recover autosave** otvara poslednju kopiju. To je jedna zajednička recovery kopija, nije istorija projekata. Exit i zamena nesnimljenog projekta traže potvrdu odbacivanja. Koristi Save pre potvrde ako želiš da sačuvaš izmene.

Korisnički `user://painter.cfg` pamti putanju poslednjeg projekta, alat, veličinu/oblik/opacity/soft edge četkice, Dither, Mirror UV, Wrap, podešavanja spreja, Compact, aktivni tab inspektora, otvorene sekcije Effects, podešavanja AO/ivica/Normal/Blur/UV kontrola, zum i položaj Stamp pregleda poslednjeg projekta, vidljivost prikaza i veličine panela. Podešavanja se snimaju kratko posle promene i pri izlasku. **File → Open last project** otvara zapamćeni fajl; **File → Reopen last project on startup** uključuje/isključuje automatsko otvaranje. Kada fajl više nije dostupan, program se vraća početnom primeru. Starije vrednosti razdelnika iz `user://workspace_layout.cfg` preuzimaju se pri prvom pravljenju novog configa. Stamp slika i crop, Pattern slika i transformacija, boje i slojevi čuvaju se u sačuvanom `.rtpaint` fajlu.

## Performanse i trenutni obim

CPU tekstura koristi retke blokove 64×64; GPU prikaz koristi stranice 256×256. Potez kopira samo promenjene blokove za undo, umesto cele 4K teksture. Obrada poteza ima budžet oko 3,5 ms po frejmu; prikaz ažurira samo prljave stranice. Velike operacije rade u pozadinskoj niti. Pojedinačan veliki dab, složeni blend režimi i mnogo slojeva mogu premašiti budžet; podrška za 4K nije obećanje istog FPS-a za svaki model i podešavanje.

Na ovom računaru sa Adreno X1-45, raniji test četkice od 16 px, teksture 4096×4096 i dva sloja davao je oko 60 FPS. U aktuelnom sintetičkom testu sa dva trougla, gradijent širine 12 px na 4K atlasu obrađen je za oko 78 ms uz 19 izmenjenih blokova, a ray AO dometa 64 px za oko 1,8 s uz 78 blokova. Na test modelu sa 96 trouglova i atlasom 1024×1024 AO traje oko 6,7 s. Geometry Edges sa velikim rasipanjem 31 px i 100% noise na tom modelu traje oko 10 s na 1024², odnosno 50 s na 4K; efekat se računa u pozadini, ali treba smanjiti domet za brz pregled. Trajanje zavisi od broja trouglova i rezolucije. Tačna merenja ranijeg prikaza su u `test_output/render_results.json`. Core i UI provere se nalaze u `tests`; rezultati u `test_output`. Screenshot test uključuje čitanje GPU slike, koje namerno zastaje i nije deo merenja poteza.

Na istom računaru gradnja šest mapa za osvetljeni pregled projekta 4096×4096 trajala je oko 0,76 s u pozadinskoj niti. Sam potez je i dalje ograničen budžetom rada po frejmu; pregled može kratko da kasni za poslednjim potezom.

Za Smudge, Blur i Spray sa veličinom 64 px na 4K atlasu, uz osvežavanje kursora i spray preview, poslednje merenje dalo je oko 16,7 ms po frejmu na 95. percentilu i 2,7–3,1 ms za CPU paint/kompoziciju. Rezultati su u `test_output/workflow_render_results.json`; to je konkretan scenario sa dva sloja, ne garancija za sve kombinacije podešavanja.

Ova verzija radi jedan UV atlas sa sedam opcionih mapa i do 32 sloja ukupno. UDIM, animacije, kamera-projektovan stencil i napredni conformal/LSCM unwrap još nisu implementirani. **Stamp** je slikovna četkica. Auto UV koristi projekciju ugaonih grupa i MaxRects, pogodno za retro tvrde površine; nije zamena za napredno odmotavanje organskih modela. Ručno pomeranje UV ostrva i automatski novi raspored prikazuju pregled sa prenetom bojom; Apply potvrđuje, Cancel vraća prethodni izgled, Undo vraća prethodne UV i slojeve. Prenos je po texelima i kod ekstremno sitnih ili preklopljenih UV ostrva može izgubiti detalj. **Edit → Resize texture** menja rezoluciju celog projekta do 4096×4096 sa nearest-neighbor skaliranjem i Undo. **UV → Inspect** prikazuje sitne, nepokrivene i preklopljene faceove. **Export padding** širi boju nekoliko texela van UV ivica na izvozu i smanjuje vidljive šavove.

## Provere

Sa postojećim Godot console izvršnim fajlom:

```powershell
$engine = 'D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $engine --headless --editor --path . --import --quit
& $engine --headless --path . --script res://tests/run_core.gd
& $engine --headless --path . --script res://tests/run_ui.gd
& $engine --headless --path . --script res://tests/run_features.gd
& $engine --headless --path . --script res://tests/run_workflow.gd
& $engine --headless --path . --script res://tests/run_preferences.gd
& $engine --headless --path . --script res://tests/run_transforms.gd
& $engine --path . --script res://tests/render_smoke.gd
& $engine --path . --script res://tests/render_features.gd
& $engine --path . --script res://tests/render_workflow.gd
& $engine --headless --path . --export-release 'Windows ARM64' build/PixelTexturePainter.exe
```

Arhitektura, plan i izvori: [docs/architecture.md](docs/architecture.md). Planirane funkcije: [TODO.md](TODO.md).
