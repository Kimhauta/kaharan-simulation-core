# Kehityspäiväkirja (Development Log) – Kaharan Simulation Core

Tämä dokumentti kokoaa yhteen **Kaharan Simulation Core** -arkkitehtuurin, GDExtension-sillan ja Godot 4 -mittausympäristön keskeiset kehitysvaiheet, tekniset ratkaisut ja suorituskykyhavainnot.

---

## Vaihe 1: Projektin pystytys ja arkkitehtuurijako (17.10.2026)

### Toteutus ja arkkitehtuurimuutokset
* Pystytettiin projektin perusrakenne ja Git-versionhallinta.
* Eriytettiin lähdekoodi kolmeen tiukasti rajattuun kerrokseen:
  * `core/`: pelimoottorista riippumaton C++20-simulaatioydin.
  * `bridge/`: Godot 4 GDExtension -siltakerros.
  * `godot_project/`: moottorin esityskerros, testiskenet ja käyttöliittymä.
* Määriteltiin juuren `CMakeLists.txt` C++20-standardille (`CMAKE_CXX_STANDARD 20`).

### Havainnot ja ratkaisut
* Simulaatioydin päätettiin toteuttaa täysin päättömänä (*headless*) ilman yhtäkään riippuvuutta Godot-moottorin otsikkotiedostoihin, jotta ydintä voidaan testata ja mitata myös itsenäisenä komentoriviohjelmana.

---

## Vaihe 2: GDExtension-sillan rakentaminen (19.10.2026)

### Toteutus ja arkkitehtuurimuutokset
* Liitettiin `godot-cpp` (v4.6) projektiin Git-alimoduulina (`external/godot-cpp`).
* Toteutettiin `SimulationBridge`-luokka ja kirjaston alustuspiste (`kaharan_bridge_init`).
* Luotiin `.gdextension`-määritystiedosto Godot 4 -projektille.

### Havainnot ja ratkaisut
* **Linkitysristiriitojen ratkaisu:** MSVC-linkittäjä ilmoitti puuttuvasta `godot_project/bin`-kohdekansiosta sekä ajonaikaisen C-kirjaston ristiriidasta (`MD_DynamicRelease` vs. `MT_StaticRelease`).
* Ongelma ratkaistiin automatisoimalla kohdekansion luonti CMake-skriptissä ja pakottamalla koko käännösputkelle staattinen ajonaikainen kirjasto (`/MT`).
* Varmistettiin, että Godot 4 lataa dynaamisen `simulation_bridge.dll`-kirjaston ja rekisteröi `SimulationBridge`-solmun luokkatietokantaan.

---

## Vaihe 3: Structure-of-Arrays (SoA) -ydin ja mikromittaukset (20.10.2026)

### Toteutus ja arkkitehtuurimuutokset
* Määriteltiin 12-tavuinen muistiin kohdistettu `Vec3`-tietue (`alignas(4)`).
* Toteutettiin dataorientoitunut `EntityRegistry`-rekisteri, joka tallentaa entiteettien tunnisteet, sijainnit, nopeudet ja LOD-tilat yhtenäisiin peräkkäisiin `std::vector`-taulukoihin (Structure of Arrays, SoA).
* Kirjoitettiin lineaarinen `tick()`-päivityssilmukka `__restrict`-osoitinmääreillä kääntäjän SIMD-autovektoroinnin mahdollistamiseksi.
* Toteutettiin itsenäinen komentorivipohjainen mikromittausohjelma (`benchmark/src/main_bench.cpp`).

### Havainnot ja mittaustulokset
* Optimoidun Release-käännöksen (`/O2`) todettiin nopeuttavan laskentaa noin viisinkertaisesti Debug-käännökseen verrattuna.
* 5 000 entiteetin päivitys vei komentorivimittauksessa keskimäärin **8,3 µs** (~1,66 ns / entiteetti), ja laskenta-aika skaalautui lineaarisesti entiteettimäärän kasvaessa.

---

## Vaihe 4: MultiMesh-visualisointi ja integrointi Godotiin (20.10.2026)

### Toteutus ja arkkitehtuurimuutokset
* Kytkettiin `SimulationWorld`-luokka osaksi Godotin `SimulationBridge`-solmua.
* Toteutettiin ensimmäinen `sync_to_multimesh()`-synkronointimetodi, joka välittää SoA-sijaintitiedot Godotin `MultiMesh`-instanssipuskuriin ilman GDScript-silmukkaa.
* Lisättiin entiteeteille symmetrinen kimpoamislogiikka testialueen rajoille ($\pm 50{,}0\text{ m}$).

### Havainnot ja mittaustulokset
* 5 000 kuutiota piirtyi ruudulle vakaalla 60 FPS -nopeudella yhdellä näytönohjaimen piirtokutsulla (*Draw Call*).
* Moottorin sisäinen C++-simulaatioaskel kesti vain **10–48 µs** (alle 0,3 % 60 Hz:n ruutubudjetista).
* Lähdekoodi dokumentoitiin Doxygen-kommentein ja arkistoon lisättiin arkkitehtuurikuvaus (`README.md`).

---

## Vaihe 5: Zero-Copy-synkronointi, A/B-testipenkki ja päävalikko (21.–22.10.2026)

### Toteutus ja arkkitehtuurimuutokset
* **Zero-Copy ja 48 tavun tietosopimus (`Transform3DData`):** Muistipuskurin rakenne sovitettiin vastaamaan suoraan Godot 4:n `MultiMesh`-renderöijän odottamaa rivijärjestettyä $3 \times 4$ -muunnosmatriisia (`alignas(16)`, 12 liukulukua / 48 tavua). Ratkaisu poisti kehyksen aikaisen matriisimuunnoksen kokonaan.
* **Suora muistikopio (`std::memcpy`):** Entiteettikohtainen `set_instance_transform()`-silmukka korvattiin yhdellä `std::memcpy`-kutsulla ja `MultiMesh::set_buffer()`-päivityksellä. Lisäksi toteutettiin `sync_to_multimesh_range()` muistipuskurin viipalointiin usealle eri `MultiMeshInstance3D`-solmulle.
* **Automaattinen A/B-testipenkki ja käyttöliittymä:** Rakennettiin ensimmäinen automatisoitu testiskene (1-Mesh DOD, 5-Mesh DOD ja 5-Mesh OOP kuormilla 1k, 5k ja 10k) sekä päävalikko ja `GameSettings`-asetustenhallinta.
* **Paikallinen tiedonhallinta:** Ohjattiin mittaustulokset erilliseen kansioon ja suljettiin ajonaikaiset datatiedostot pois Git-seurannasta (`.gitignore`).

### Havainnot ja mittaustulokset
* 10 000 entiteetin `MultiMesh`-synkronointiaika laski **~300–380 mikrosekuntiin** ja C++-fysiikkalaskenta vei vain **~25–30 µs**.
* V-Sync OFF -tilassa 10 000 entiteetin DOD-malli saavutti editoriajossa **607 FPS**, kun vastaava GDScript/Node3D OOP-malli jäi **45 FPS** -tasolle.

---

## Vaihe 6: Modulaarinen Benchmark Suite, dynaaminen saturaatioemitteri ja sessiotelemetria (10.11.2026)

### Toteutus ja arkkitehtuurimuutokset
* **Inkrementaalinen agenttien lisäys (`add_test_agents`):** Laajennettiin `SimulationWorld`-luokkaa pysyvällä satunnaislukugeneraattorilla (`m_rng`) ja `add_test_agents(size_t count)` -metodilla (`SimulationBridge::add_agents`). Tämä mahdollistaa uusien entiteettien lisäämisen suoraan SoA-puskurin jatkoksi ilman aiemman tilan tyhjennystä.
* **Modulaarinen skenerakenne:** Jaettiin suorituskykytestit erikoistuneisiin skeneihin:
  * `bench_synthetic_render.tscn` ja `bench_synthetic_headless.tscn`: 12-vaiheinen A/B-vertailumatriisi kiinteillä kuormilla (renderöitynä ja päättömänä).
  * `bench_ramp_up_render.tscn` ja `bench_ramp_up_headless.tscn`: jatkuva saturaatio- ja murtumispistekoe.
* **Kiihtyvä emitteri ja hystereesivahti:** Toteutettiin aikapohjainen emitteri ($R(t) = R_0 + \alpha t$) kehyskohtaisella leikkurilla (`MAX_SPAWN_PER_FRAME = 250`). Saturaatiopiste sidottiin 60 Hz:n ruutubudjettiin (`17,5 ms` toleranssiraja) 5,0 sekunnin yhtäjaksoisella ylitysvaatimuksella.
* **Aikaleimatut ajokansiot ja tulosnäkymä:** `GameSettings` luo jokaiselle ajolle oman kansion (`run_YYYY-MM-DD_.../`), johon tallentuvat `manifest.json`, `summary.csv` sekä kehyskohtaiset CSV-aikasarjat. Toteutettiin `benchmark_results.gd`-näkymä 2D-käyräpiirturilla ja tilastollisilla vakausmittareilla (`StdDev`, `1% Low FPS`, `0.1% Low FPS`).

### Havainnot ja mittaustulokset (`run_2026-11-10_18-20-52_full_suite`)
* **Synteettinen 10 000 entiteetin kuorma:**
  * *Rendered (1-Mesh):* DOD **535,63 FPS** (`31,38 µs` logiikka) vs. OOP **39,46 FPS** (`12 751,24 µs` logiikka) $\rightarrow$ **13,6× FPS** ja **406× logiikkanopeutus**.
  * *Headless (Pure CPU):* DOD **747,95 FPS** (`28,99 µs` logiikka) vs. OOP **63,33 FPS** (`12 157,19 µs` logiikka) $\rightarrow$ **419× logiikkanopeutus**.
* **Havainto geometrisesta pullonkaulasta 5-Mesh-tilassa:** Alkuperäisessä 5-Mesh-testissä käytetyt oletusarvoiset `SphereMesh`- ja `CapsuleMesh`-primitiivit sisälsivät moninkertaisesti enemmän kolmioita kuin `BoxMesh`, mikä rajoitti renderöidyn 5-Mesh DOD -ajon ~158 FPS:ään ja ~35 000 entiteetin saturaatiopisteeseen. Tämä havainto johti geometrian vakiointiin Vaiheessa 7.

---

## Vaihe 7: Etäisyyspohjainen Simulation LOD, 3-huoneen tuotantotesti ja Release-verifiointi (12.11.2026)

### Toteutus ja arkkitehtuurimuutokset
* **Etäisyyspohjainen Simulation LOD (`SimulationLOD`) ja kaartoliike:** Toteutettiin C++-ytimeen kolmiportainen etäisyysluokittelu ja porrastettu aikaviipalointi:
  * `LOD0_Full` (`< 25 m`): täysi liike- ja ohjauspäivitys joka kehyksessä ($1\times \Delta t$).
  * `LOD1_Amortized` (`25–55 m`): porrastettu päivitys joka 4. kehys ($4\times \Delta t$) bittimaskilla `((i + frame_tick) & 3u) == 0u`.
  * `LOD2_Dormant` (`> 55 m`): harvennettu taustapäivitys joka 16. kehys ($16\times \Delta t$) bittimaskilla `((i + frame_tick) & 15u) == 0u`.
  * Lisättiin trigonometrinen suunnanmuutos (`set_steering_enabled`) sekä C++- että GDScript-toteutukseen realistisen agenttikohtaisen ohjauslaskennan mallintamiseksi.
* **Metodologinen vakiointi (5 värikoodattua kuutiota):** Kaikki viisi entiteettiarkkityyppiä vakioitiin käyttämään identtisiä $0{,}55 \times 0{,}55 \times 0{,}55\text{ m}$ kuutioita (`BoxMesh`, 12 kolmiota / entiteetti) viidellä eri materiaalilla ja ilman agenttikohtaista dynaamista varjonheittoa (`SHADOW_CASTING_SETTING_OFF`). Näin mittaukset eristävät puhtaasti muistirakenteen, piirtokutsujen niputuksen ja simulaatioarkkitehtuurin vaikutuksen.
* **3-huoneen Greybox-kenttä (`greybox_level.gd`) ja koodipohjainen UI:** Rakennettiin $100 \times 100\text{ m}$ kokoinen kolmen huoneen ja kahden yhdyskäytävän testikenttä, joka toimii sekä vapaasti pelattavana hiekkalaatikkona että 4-vaiheisena tuotantotestinä (`OOP Base`, `OOP + LOD`, `DOD Base`, `DOD + LOD`, 45 s / kierros). Lisäksi `main_menu.gd`, `settings_menu.gd` ja `benchmark_hub.gd` yhtenäistettiin koodipohjaisiksi käyttöliittymiksi.
* **Käyttöjärjestelmätason muistimittaus (`GetProcessMemoryInfo`):** Korvattiin Godotin vain Debug-käännöksissä toimiva `MEMORY_STATIC`-laskuri Win32 API:n `GetProcessMemoryInfo` (`WorkingSetSize`) -kyselyllä (`SimulationBridge::get_process_memory_mb()`), joka mittaa prosessin todellisen fyysisen muistinkulutuksen myös itsenäisessä Release-käännöksessä.

### Havainnot ja mittaustulokset (`run_2026-11-12_22-58-26_full_suite_release`)
* **Synteettinen 10 000 entiteetin A/B-vertailu (Release `.exe`):**
  * *Rendered (5-Mesh):* DOD saavutti **668,96 FPS** (`23,92 µs` logiikka, `330,92 MB` alkumuisti, 20 solmua) vs. OOP **54,92 FPS** (`8 207,26 µs` logiikka, `382,83 MB` alkumuisti, 10 020 solmua) $\rightarrow$ **343,1× logiikkanopeutus**, **12,2× FPS** ja **~52 MB** pienempi muistinkulutus.
  * *Headless (5-Mesh):* DOD **886,58 FPS** (`27,14 µs` logiikka) vs. OOP **106,67 FPS** (`7 119,63 µs` logiikka) $\rightarrow$ **262,3× logiikkanopeutus**.
* **Dynaaminen Ramp-Up (60 FPS saturaatiopisteet):**
  * *Rendered (5-Mesh):* DOD kesti **326 667 entiteettiä** (`408,70 MB`) vs. OOP **17 391 entiteettiä** (`477,58 MB`) $\rightarrow$ **18,8× kapasiteetti**.
  * *Headless (Pure CPU):* DOD kesti **968 903 entiteettiä** (`500,63 µs` logiikka, `417,12 MB`) vs. OOP **30 379 entiteettiä** (`470,00 MB`) $\rightarrow$ **31,9× kapasiteetti**.
* **3-huoneen Fly-Through ja Simulation LOD (10 000 entiteettiä, kaartoliike):**
  * `OOP Base`: **40,44 FPS** (`14 434,18 µs` logiikka, `StdDev 1,721 ms`).
  * `OOP + LOD`: **65,68 FPS** (`9 515,93 µs` logiikka, **-34,1 %** laskenta-aika, `StdDev 1,263 ms`).
  * `DOD Base`: **396,72 FPS** (`212,39 µs` logiikka, `StdDev 0,091 ms`, **68,0× nopeampi** kuin OOP Base).
  * `DOD + LOD`: **394,20 FPS** (`153,31 µs` logiikka, **-27,8 %** laskenta-aika vs. DOD Base ja **94,1× nopeampi** kuin OOP Base, `StdDev 0,081 ms`).