<p align="center">
  <img src="assets/branocesta.png" width="96" alt="Ikona aplikace Bránocesta">
</p>

<h1 align="center">Bránocesta</h1>

<p align="center">
  Jedna ikona na ploše místo tří. Brána ke <a href="https://github.com/JohnyLeeJohnes/spac">Spáči</a>,
  <a href="https://github.com/JohnyLeeJohnes/sluzbak">Službákovi</a> a
  <a href="https://github.com/JohnyLeeJohnes/mesec">Měšci</a>: tady je nainstaluješ, aktualizuješ, odinstaluješ i spustíš.
</p>

<p align="center">
  <img src="docs/prehled.png" width="760" alt="Okno brány se třemi kartami: Spáč, Službák a Měšec">
</p>

Otevřeš bránu, klikneš na **Spustit** a jsi v aplikaci. Brána se přitom zavře, dál už vidíš jen to, co sis vybral.
Tlačítkem **Bránocesta** v aplikaci se do brány zase vrátíš.

- **Vybereš si, co chceš.** Na začátku není nainstalované nic. **Nainstalovat** stáhne z GitHubu nejnovější
  vydání aplikace; nic neklonuješ, nic nerozbaluješ. **Odinstalovat** ji zase odebere a tvoje data nechá být.
- **Hlídá nová vydání.** Při každém otevření se podívá, jestli nevyšlo něco novějšího, a nabídne ti
  **Aktualizovat**: u každé aplikace i u sebe samé. Sama od sebe nic nepřepisuje.
- **Všechno na jednom místě.** Aplikace se instalují do jedné společné složky. **Složka aplikací** ti ji otevře.
- **Nezdržuje.** Co už je nainstalované, jde spustit hned, i když kontrola ještě běží nebo nejsi na internetu.
- **Nic se nekompiluje.** Dva skripty v PowerShellu a jedno okno v XAML, stejně jako aplikace za bránou.

## Instalace

1. Stáhni **[Branocesta.zip](https://github.com/JohnyLeeJohnes/branocesta/releases/latest/download/Branocesta.zip)**.
   Odkaz vede vždycky na nejnovější vydání.
2. Klikni na stažený ZIP pravým tlačítkem, zvol **Vlastnosti**, dole zaškrtni **Odblokovat** a potvrď.
3. Rozbal ho tam, kde má brána zůstat, třeba do Dokumentů.
4. Ve složce `Branocesta` poklepej na **`install.cmd`**. Vytvoří zástupce **Bránocesta** s ikonou v nabídce
   Start, na ploše a přímo ve složce. Přes něj se brána spouští jako každá jiná aplikace, bez okna konzole.
5. Otevři bránu a u aplikací, které chceš, klikni na **Nainstalovat**.

> **Proč odblokovat?** Windows si soubory stažené z internetu označí a skripty s tímhle označením nemusí
> spustit. Když ZIP odblokuješ ještě před rozbalením, označení se na rozbalené soubory nepřenese.
> `install.cmd` ho ze souborů sundá i sám, jenže k tomu ho Windows nejdřív musí nechat spustit.

- **Jen vyzkoušet:** poklepej na `Branocesta.cmd`, spustí bránu bez vytváření zástupců.
- **Nová verze brány:** brána ji nabídne dole v okně tlačítkem **Aktualizovat bránu**, viz níže. Ručně to jde
  rozbalením nového ZIPu přes starý. Nainstalované aplikace zůstanou.
- **Přesunutí složky:** zástupce ukazuje tam, kde brána leží. Po přesunutí spusť `install.cmd` znovu.
- **Odebrání:** smaž zástupce z plochy a z nabídky Start, složku s bránou a `%LOCALAPPDATA%\Branocesta`
  (tam jsou nainstalované aplikace). Jejich data zůstanou, kde byla, viz níže.
- **Z gitu:** `git clone https://github.com/JohnyLeeJohnes/branocesta.git` a pak rovnou krok 4. Klonování
  označení z internetu nepřidává, takže odblokování odpadá. Naklonovanou bránu aktualizuješ přes `git pull`;
  tlačítko pro aktualizaci se u ní neukazuje, aby ti nezahodila rozdělané úpravy.

Potřebuješ Windows 10 nebo 11 (Windows PowerShell 5.1 je jejich součástí) a pro stahování internet.
Vyzkoušeno na Windows 11.

## Jak to funguje

1. Brána se u každé aplikace zeptá GitHubu na nejnovější vydání (`/releases/latest`).
2. **Nainstalovat** ho stáhne a rozbalí do společné složky. Bere ZIP přiložený k vydání; když u vydání
   žádný není, archiv zdrojáků, který GitHub dělá ke každému tagu.
3. Když později vyjde novější vydání, objeví se na kartě **Aktualizovat**. Samo se nic nepřepisuje.
4. **Spustit** pustí aplikaci stejně jako její vlastní zástupce (bez okna konzole). Brána počká, až se okno
   aplikace ukáže, pošle ho dopředu a zavře se.
5. Aplikace spuštěná z brány má tlačítko **Bránocesta**: zavře ji a bránu znovu otevře. Brána jí k tomu při
   spuštění předá, kde leží (proměnná prostředí `BRANOCESTA`). Když aplikaci pustíš jejím vlastním zástupcem,
   tlačítko v ní není.
6. **Odinstalovat** smaže složku aplikace. Data, která si aplikace drží jinde, zůstanou.
7. Stejně se brána zeptá i na své vlastní vydání. Když vyšlo novější, napíše to dole v okně a nabídne
   **Aktualizovat bránu**. Po kliknutí si stáhne nové soubory, přepíše jimi své a otevře se znovu, už v nové verzi.

Na kartě vidíš, kterou verzi máš a co se právě děje. **Zkontrolovat vydání** nebo klávesa F5 se podívá znovu.

## Dobré vědět

- **Kde aplikace jsou.** Všechny na jednom místě: v `%LOCALAPPDATA%\Branocesta\apps`, každá ve své složce
  (`Spac`, `Sluzbak`, `Mesec`), ať je brána nainstalovaná kdekoli. Otevře ji tlačítko **Složka aplikací**.
  Aktualizace brány na ni nesahá.
- **Tvoje data aktualizace ani odinstalování nesmaže.** Aplikace si je drží jinde: Službák v `%APPDATA%\Sluzbak`,
  Měšec v `%APPDATA%\Mesec`, Spáč v `%LOCALAPPDATA%\Spac`. Brána na ně nesahá.
- **Po zavření nic neběží.** Brána i aplikace jsou každá jedno okno a s ním skončí. Na pozadí nezůstává nic,
  co by hlídalo vydání nebo čekalo na spuštění.
- **Běžící aplikaci nepřepisuje ani nemaže.** Když chceš aktualizovat nebo odinstalovat něco, co máš zrovna
  otevřené, brána ti napíše, ať to nejdřív zavřeš.
- **Nepovedená instalace nic nerozbije.** Nové soubory se chystají vedle a složky se vymění až nakonec.
  Když se stahování nebo rozbalení nepovede, zůstane ti verze, kterou jsi měl.
- **Vlastní zástupce aplikacím nedělá.** Pokud máš některou aplikaci nainstalovanou i samostatně, brána
  o ní neví a nijak jí nepřekáží; má svoji kopii.
- **Bez přihlášení.** Repozitáře aplikací jsou veřejné. GitHub dovolí bez přihlášení 60 dotazů za hodinu
  z jedné adresy; jedno otevření brány potřebuje čtyři a každá instalace nebo aktualizace jeden další.
- **Proč skript, a ne `.exe`.** Nepodepsaný `.exe` umí Windows 11 (Smart App Control) zablokovat. Skript
  běží bez podpisu a před spuštěním si ho můžeš celý přečíst.
- **Proč není instalace jedním příkazem.** Příkaz, který skript stáhne z internetu a rovnou ho spustí,
  hlásí Microsoft Defender jako trojského koně, ať je ve skriptu cokoli. Proto se brána instaluje ze ZIPu.

## Úpravy

| Soubor | Obsah |
| --- | --- |
| `Branocesta.ps1` | Okno: karty aplikací, úlohy na pozadí, spuštění aplikace, vytvoření zástupců. |
| `Branocesta.xaml` | Vzhled okna: barvy, styly, karty. |
| `Apps.ps1` | Seznam aplikací, dotaz na nejnovější vydání, instalace a odinstalování, aktualizace brány. O okně nic neví. |
| `Branocesta.cmd`, `install.cmd` | Spuštění bez instalace a vytvoření zástupců. |
| `tools/make-icon.ps1` | Vygeneruje ikonu do `assets/`. |
| `tools/make-release.ps1` | Sestaví `dist/Branocesta.zip` pro GitHub Release. |
| `tests/test.ps1` | Zkouška instalace vydání a průchod oknem. |

**Další aplikace za bránu:** přidej řádek do `$apps` na začátku `Apps.ps1` (repozitář a skript, kterým se
spouští) a do `Branocesta.xaml` kartu s prvky `<Id>Icon`, `<Id>Version`, `<Id>Status`, `<Id>Busy` a tlačítky
`<Id>Launch`, `<Id>Install`, `<Id>Update` a `<Id>Remove`; nejsnáz zkopírováním jedné z těch tří.
Vydání musí mít spouštěcí skript buď přímo v ZIPu, nebo v jedné společné složce.

Jiné barvy? Paleta je na začátku `Branocesta.xaml`. Změny se projeví při dalším spuštění, nic se nesestavuje.
Co se ve které verzi změnilo, je v [CHANGELOG.md](CHANGELOG.md).

Test se pouští takhle:

```
powershell -ExecutionPolicy Bypass -File tests/test.ps1
```

Na GitHub nesahá a tvých nainstalovaných aplikací se nedotkne: vydání má vymyšlená a všechno dělá
v dočasné složce. Několikrát přitom na chvíli otevře okno brány.

Obrázek v `docs/` vzniká takhle. Ukáže, co je ve složce, kterou zadáš; sám nic neinstaluje:

```
powershell -ExecutionPolicy Bypass -File Branocesta.ps1 -AppsPath <složka> -Screenshot docs\prehled.png
```

---

**In English:** Bránocesta ("gate-way") is a small launcher for three sibling Windows apps: Spáč (shutdown
timer), Službák (Prague open-data dashboard) and Měšec (budget tracker). On start it asks GitHub for the
latest release of each app. Nothing is installed by default: each card lets you install, update, uninstall
or launch its app, and everything is installed into one folder, `%LOCALAPPDATA%\Branocesta\apps`. Launching
an app closes the gateway, and a button in each app brings it back. The gateway offers to update itself the same way. It is a PowerShell script with a WPF
window: download `Branocesta.zip` from the latest release, unblock and extract it, and run `install.cmd` to
get a desktop shortcut. Nothing to compile. The interface is in Czech.
