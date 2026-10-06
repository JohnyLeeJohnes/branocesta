# Changelog

Všechny podstatné změny v projektu. Formát vychází z [Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verze se řídí [sémantickým verzováním](https://semver.org/lang/cs/).

## [1.2.0] - 2026-10-06

### Přidáno

- Na kartě každé aplikace jsou tlačítka **Nainstalovat**, **Aktualizovat** a **Odinstalovat**. Odinstalování
  smaže jen složku aplikace; data, která si aplikace drží jinde, zůstanou.
- Tlačítko **Složka aplikací** otevře jedinou společnou složku, do které se všechny aplikace instalují
  (`%LOCALAPPDATA%\Branocesta\apps`).
- Karta ukáže, která verze je ke stažení a že vyšla novější. Ikona nenainstalované aplikace je ztlumená.

### Změněno

- Brána už aplikace neinstaluje ani neaktualizuje sama. Na začátku není nainstalované nic a o každé aplikaci
  rozhoduješ ty. Co už nainstalované máš, zůstává. Sama sebe brána aktualizuje dál.
- Když aplikace běží, brána ji nepřepíše ani nesmaže a napíše, ať ji nejdřív zavřeš.

## [1.1.1] - 2026-10-06

### Odebráno

- Instalace jedním příkazem (`install.ps1`). Příkaz, který skript stáhne z internetu a rovnou ho spustí,
  hlásí Microsoft Defender jako trojského koně a zablokuje ho. Brána se instaluje ze ZIPu a `install.cmd`.

## [1.1.0] - 2026-10-06

### Přidáno

- Brána hlídá i své vlastní vydání. Když vyjde novější, přepíše si na pozadí soubory a v zápatí okna to
  napíše; nová verze se projeví při příštím otevření. V pracovní kopii z gitu se nepřepisuje.
- Instalace jedním příkazem: `install.ps1` stáhne nejnovější vydání do `%LOCALAPPDATA%\Branocesta`, vytvoří
  zástupce s ikonou a bránu rovnou otevře.

### Změněno

- Okno si při startu načte vše, co potřebuje, do paměti (včetně ikony), takže mu výměna vlastních souborů
  za běhu nevadí.

## [1.0.0] - 2026-10-06

První vydání.

### Přidáno

- Okno se třemi kartami: Spáč, Službák a Měšec. Tlačítko **Spustit** pustí aplikaci a bránu zavře.
- Při otevření se brána u každé aplikace zeptá GitHubu na nejnovější vydání a nainstaluje ho, když chybí
  nebo je novější než to, co už máš. Bere ZIP přiložený k vydání, jinak archiv zdrojáků.
- Aplikace se instalují do `%LOCALAPPDATA%\Branocesta\apps`. Nové soubory se chystají vedle a složky se
  vymění až nakonec, takže nepovedená instalace nechá starou verzi být.
- Aplikace, která právě běží, se nepřepisuje; aktualizace se udělá při dalším otevření brány.
- Nainstalovanou aplikaci jde spustit hned, i během kontroly nebo bez internetu. Chyba u jedné aplikace
  ostatní nezastaví.
- Tlačítko **Zkontrolovat vydání** a klávesa F5.
- Tmavý vzhled včetně titulkového pruhu okna, ikona ve velikostech 16 až 256 px a `install.cmd`, který
  vytvoří zástupce v nabídce Start, na ploše a ve složce s bránou.
- Bránocesta je skript v PowerShellu s oknem ve WPF, takže se nic nekompiluje a nevadí jí Smart App Control.
- Test `tests/test.ps1`, který zkouší instalaci vymyšlených vydání a projde okno, a `tools/make-release.ps1`,
  který sestaví `Branocesta.zip` pro GitHub Release.

[1.2.0]: https://github.com/JohnyLeeJohnes/branocesta/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/JohnyLeeJohnes/branocesta/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/JohnyLeeJohnes/branocesta/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/JohnyLeeJohnes/branocesta/releases/tag/v1.0.0
