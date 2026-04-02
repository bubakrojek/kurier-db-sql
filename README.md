#  firmakurierska — Baza danych firmy kurierskiej

Relacyjna baza danych stworzona w **MariaDB 10.4** (kompatybilna z MySQL), modelująca system zarządzania zamówieniami, magazynami, kurierami, klientami i flotą pojazdów dla firmy kurierskiej.

***

##  Spis treści

- [Opis projektu](#opis-projektu)
- [Struktura bazy danych](#struktura-bazy-danych)
  - [Tabele](#tabele)
  - [Widoki](#widoki)
  - [Procedury składowane](#procedury-składowane)
  - [Funkcje](#funkcje)
  - [Wyzwalacze (Triggery)](#wyzwalacze-triggery)
- [Instalacja i import](#instalacja-i-import)

***

## Opis projektu

Baza `firmakurierska` obsługuje cały cykl życia przesyłki — od momentu złożenia zamówienia przez klienta, przez przypisanie kuriera i pojazdu, przechowywanie paczki w magazynie, aż po dostarczenie do odbiorcy. System zawiera również mechanizmy analityczne (widoki, statystyki) oraz logikę biznesową zaimplementowaną w procedurach, funkcjach i wyzwalaczach.

***

## Struktura bazy danych

### Tabele

| Tabela | Opis | Klucz główny |
|--------|------|--------------|
| `klient` | Dane klientów (nadawcy i odbiorcy) | `IDklienta` |
| `kurier` | Dane kurierów wraz z nr prawa jazdy | `IDkuriera` |
| `auto` | Flota pojazdów firmowych | `IDauta` |
| `kartapojazdu` | Powiązanie kurierów z pojazdami (wiele-do-wielu) | `(idauta, nrprawajazdykierowcy)` |
| `magazyn` | Dane magazynów (adres) | `IDmagazynu` |
| `paczka` | Stan magazynowy paczki — daty przyjęcia i wydania | `idpaczki` |
| `zamowienie` | Główna tabela zamówień | `IDzamowienia` |
| `zamowienieprodukt` | Przypisanie produktów do zamówień (wiele-do-wielu) | `(IDproduktu, IDzamowienia)` |
| `produkt` | Katalog produktów z cenami | `IDproduktu` |
| `cennik` | Ceny przesyłek według rozmiaru paczki | `rozmiar` |
| `aktualnystatuszamowienia` | Status płatności zamówienia z datą i godziną | `IDzamowienia` |
| `statystykiproduktow` | Tabela agregująca statystyki sprzedaży produktów | `IDproduktu` |

***

#### Szczegóły tabel

**`klient`**
```sql
IDklienta INT (PK, AUTO_INCREMENT)
imie        VARCHAR(45) NOT NULL
nazwisko    VARCHAR(45) NOT NULL
email       VARCHAR(30)
nrdomu      INT NOT NULL
ulica       VARCHAR(20) NOT NULL
miasto      VARCHAR(45) NOT NULL
```

**`kurier`**
```sql
IDkuriera    INT (PK, AUTO_INCREMENT)
imie         VARCHAR(45) NOT NULL
nazwisko     VARCHAR(45) NOT NULL
nrprawajazdy VARCHAR(20) UNIQUE
```

**`auto`**
```sql
IDauta  INT (PK, AUTO_INCREMENT)
kolor   VARCHAR(45) NOT NULL
marka   VARCHAR(45) NOT NULL
model   VARCHAR(45) NOT NULL
nrrej   VARCHAR(20) NOT NULL UNIQUE
```

**`kartapojazdu`** — tabela łącząca kurierów z pojazdami
```sql
idauta                INT (FK → auto.IDauta)
nrprawajazdykierowcy  VARCHAR(20) (FK → kurier.nrprawajazdy)
PK: (idauta, nrprawajazdykierowcy)
```

**`magazyn`**
```sql
IDmagazynu  INT (PK, AUTO_INCREMENT)
nrdomu      INT NOT NULL
ulica       VARCHAR(20) NOT NULL
miasto      VARCHAR(45) NOT NULL
```

**`paczka`**
```sql
idpaczki      INT (PK, AUTO_INCREMENT)
dataprzyjecia DATE
datawydania   DATE          -- NULL = paczka wciąż w magazynie
IDmagazynu    INT (FK → magazyn.IDmagazynu)
```
> Jeśli `dataprzyjecia` i `datawydania` są `NULL` — zamówienie anulowane.

**`zamowienie`**
```sql
IDzamowienia  INT (PK, AUTO_INCREMENT)
IDkuriera     INT (FK → kurier.IDkuriera)
nrmagazynowy  INT (FK → paczka.idpaczki)
IDodbiorcy    INT (FK → klient.IDklienta)
IDnadawcy     INT (FK → klient.IDklienta)
rozmiar       VARCHAR(45) (FK → cennik.rozmiar)
waga          FLOAT        -- 0–30 kg (kontrolowane triggerem)
datazlozenia  DATE
```

**`cennik`**
```sql
rozmiar  VARCHAR(45) (PK)  -- XS, S, M, L, XL, XXL
cena     DECIMAL(10,2)
```

***

### Widoki

#### `statystykiklientow`
Zagregowane dane o aktywności klientów jako odbiorców:

| Kolumna | Opis |
|---------|------|
| `IDklienta`, `imie`, `nazwisko` | Dane klienta |
| `lacznailosczamowien` | Łączna liczba zamówień |
| `lacznakwotazamowienia` | Suma wartości zamówionych produktów |
| `sredniakwotaproduktow` | Średnia wartość produktu |
| `liczbaunikalnychproduktow` | Liczba różnych zamawianych produktów |
| `najnowszezamowienie` | Data ostatniego zamówienia |
| `najstarszezamowienie` | Data pierwszego zamówienia |
| `iloscmiesiecywspolpracy` | Okres współpracy w miesiącach |

#### `analizazamowienmiesieczna`
Miesięczne zestawienie zamówień:

| Kolumna | Opis |
|---------|------|
| `miesiac` | Miesiąc w formacie `YYYY-MM` |
| `liczbazamowien` | Liczba zamówień w miesiącu |
| `liczbaunikalnychklientow` | Unikalni odbiorcy |
| `sredniawaga` | Średnia waga paczki |
| `lacznawartoscproduktow` | Łączna wartość produktów |
| `liczbaoplaconych` | Liczba opłaconych zamówień |
| `procentoplaconych` | % opłaconych zamówień |

***

### Procedury składowane

#### `dodajzamowienie(pIDodbiorcy, pIDnadawcy, pwaga, plistaproduktow OUT pstatus)`
Główna procedura transakcyjna do składania nowego zamówienia:
1. Tworzy rekord w `paczka`
2. Losowo przypisuje kuriera
3. Tworzy wpis w `zamowienie`
4. Ustawia status płatności na `NIE`
5. Przypisuje produkt z listy do zamówienia
6. Automatycznie oblicza rozmiar paczki na podstawie wagi

#### `aktualizujstatystykiproduktow()`
Czyści i odświeża tabelę `statystykiproduktow` na podstawie aktualnych danych z `zamowienieprodukt`.

#### `wyslijzamowienie(OUT wynik)`
Wysyła najstarsze oczekujące zamówienie (FIFO):
- Pobiera zamówienie z `datawydania IS NULL`
- Wyświetla dane odbiorcy i listę produktów
- Aktualizuje `datawydania` w tabeli `paczka`

#### `wyslijpowiadomieniaklientom()`
Wysyła powiadomienia (do tabeli tymczasowej) do klientów z nieopłaconymi zamówieniami.

***

### Funkcje

#### `przeniespaczke(pidpaczki, pnowymagazynid) → VARCHAR(100)`
Przenosi paczkę do innego magazynu. Waliduje:
- Czy paczka nie została już wydana
- Czy paczka nie jest anulowana
- Czy docelowy magazyn istnieje
- Czy paczka nie jest już w tym magazynie

#### `wyswietlstan(pimie, pnazwisko) → VARCHAR(15)`
Zwraca status płatności (`Oplacone` / `Nie oplacone` / `Nie znaleziono`) dla najnowszego zamówienia klienta.

#### `zaplanujtrasekuriera(pidkuriera) → TEXT`
Generuje posortowaną trasę dostaw dla danego kuriera — listę adresów niezrealizowanych zamówień, posortowaną wg miasta i ulicy.

***

### Wyzwalacze (Triggery)

| Wyzwalacz | Tabela | Kiedy | Działanie |
|-----------|--------|-------|-----------|
| `sprawdzwagepaczki` | `zamowienie` | BEFORE INSERT | Odrzuca zamówienie, jeśli waga poza zakresem 0–30 kg |
| `trpreventdeleteklientwithorders` | `klient` | BEFORE DELETE | Blokuje usunięcie klienta, który ma aktywne zamówienia |
| `trcheckkartapojazdu` | `kartapojazdu` | BEFORE INSERT | Sprawdza, czy kurier posiada ważne prawo jazdy |

***

## Instalacja i import

### Wymagania
- MariaDB 10.4+ lub MySQL 8.0+
- phpMyAdmin (opcjonalnie) lub klient MySQL CLI

### Import przez CLI

```bash
mysql -u root -p < firmakurierska.sql
```

### Import przez phpMyAdmin

1. Otwórz phpMyAdmin
2. Przejdź do zakładki **Import**
3. Wybierz plik `firmakurierska.sql`
4. Kliknij **Wykonaj**

***

## Dane testowe

Baza zawiera przykładowe dane testowe:
- **51 klientów** (polskich i zagranicznych)
- **21 kurierów** z przypisanymi prawami jazdy
- **20 pojazdów** (Citroën, Renault, Mercedes, Iveco, Ford, VW, Fiat, Peugeot)
- **10 magazynów** w różnych miastach Polski
- **55 zamówień** z lat 2014–2026
- **50 produktów** (elektronika, artykuły biurowe)

***

*Baza danych wygenerowana: 05.02.2025 | MariaDB 10.4.32 | PHP 8.2.12*
