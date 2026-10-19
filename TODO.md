# TODO

Stavke koje su zatražene za 3D pregled i efekte. Implementacija i automatske provere su u projektu.

- [x] **Directional Blur.** Zaseban efekat za aktivni sloj/izabranu oblast: ugao, dužina u texelima i jačina. Promena vrednosti prikazuje privremeni rezultat; Apply je jedna Undo radnja, Cancel vraća prethodni prikaz. Obrada radi u pozadini i koristi samo pogođene tileove i susede na 4K teksturi.
- [x] **Referentna slika u radnom prostoru.** Slika se učitava kao pomerljiv i skalabilan prikaz preko 3D modela, sa podešavanjem opacity i zaključavanjem položaja. Taster **H** je prikazuje/sakriva bez gubitka položaja i podešavanja. Slika i raspored čuvaju se u `.rtpaint` projektu, ali ne ulaze u teksturu ni GLB/PNG izvoz.
- [x] **Fokus kamere na predmet jednim tasterom.** Taster **Z** približava i centrira kameru na izabrane površine; bez selekcije koristi površinu pod kursorom, a ako je nema, ceo model. **Frame whole model** ostaje poseban brzi povratak. Fokus radi u perspektivnom i ortografskom prikazu.
- [x] **Klikabilne ose u 3D pregledu.** Mali orijentacioni widget u uglu prikaza sa +X/−X, +Y/−Y i +Z/−Z. Klik postavlja pogled tačno duž izabrane ose i uključuje ortografski pogled; trenutno središte fokusa ostaje isto. Aktivna osa je označena i desni klik nastavlja orbitiranje.
- [x] **Jednostavniji alati za bojenje.** Spray ima Size, Opacity i Strength. Fill u gornjoj traci bira Color, Texture, šest ugrađenih patterna ili sopstveni ponavljajući pixel canvas. Stamp učitavanje, crop i rotacija su u gornjoj traci. Brush ima 20 belih maski i uvoz PNG otisaka u `user://brushes`.
