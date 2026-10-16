# TODO

Ovo su planirane funkcije; još nisu implementirane. Prečice su rezervisane kao predlog i treba ih proveriti u aplikaciji pre objave.

- [ ] **Directional Blur.** Dodati zaseban efekat za aktivni sloj/izabranu oblast: ugao, dužina u texelima i jačina. Promena vrednosti prikazuje privremeni rezultat; Apply je jedna Undo radnja, Cancel vraća prethodni prikaz. Obrada treba da ostane u pozadini i da ne blokira crtanje na 4K teksturi.
- [ ] **Referentna slika u radnom prostoru.** Učitati sliku kao pomerljiv i skalabilan prikaz pored ili preko 3D modela, sa podešavanjem opacity i zaključavanjem položaja. Taster **H** prikazuje/sakriva sliku jednim pritiskom bez gubitka položaja i podešavanja. Slika i njen raspored čuvaju se u `.rtpaint` projektu, ali ne ulaze u teksturu ni GLB/PNG izvoz.
- [ ] **Fokus kamere na predmet jednim tasterom.** Taster **Z** približava i centrira kameru na izabrane površine; bez selekcije koristi površinu pod kursorom, a ako je nema, ceo model. Sačuvati postojeći **Frame whole model** kao poseban brzi povratak. Fokus treba da radi i u perspektivnom i u ortografskom prikazu bez prolaska kroz geometriju.
- [ ] **Klikabilne ose u 3D pregledu.** Mali orijentacioni widget u uglu prikaza sa +X/−X, +Y/−Y i +Z/−Z. Klik postavlja pogled tačno duž izabrane ose i uključuje ortografski pogled; trenutno središte fokusa ostaje isto. Jasno označiti aktivnu osu i omogućiti povratak na slobodno orbitiranje desnim klikom.
