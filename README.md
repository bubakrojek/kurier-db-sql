Baza danych firmy kurierskiej
Projekt studencki polegający na zaprojektowaniu relacyjnej bazy danych dla firmy kurierskiej. Projekt wykonany w ramach zajęć z baz danych.

Technologie
    MySQL
    SQL

Pliki
    db_schema.sql – zawiera pełną definicję struktury bazy danych

Opis bazy danych
    Baza danych opisuje firmę kurierską i zawiera wszystkie potrzebne tabele, widoki, procedury i funkcje do zarządzania przesyłkami.

Tabele

    klient – dane klientów (imię, nazwisko, adres, e-mail)

    kurier – lista kurierów (imię, nazwisko, numer prawa jazdy)

    auto – pojazdy kurierów (kolor, marka, model, numer rejestracyjny)

    karta_pojazdu – powiązania aut z kurierami przez numery prawa jazdy

    magazyn – adresy i numery magazynów

    paczka – informacje o paczkach (data przyjęcia, wydania, magazyn)

    produkt – lista produktów do wysyłki (nazwa, cena)

    zamowienie – zamówienia (kurier, paczka, nadawca, odbiorca, rozmiar, waga, data)

    zamowienie_produkt – produkty w zamówieniu

    cennik – ceny przesyłek wg rozmiaru paczki

    aktualny_status_zamowienia – status zamówienia (czy opłacone, data, godzina)

    statystyki_produktow – ile razy dany produkt był zamawiany i za jaką kwotę

Widoki

    analiza_zamowien_miesieczna – miesięczne zestawienie zamówień, liczby klientów, średniej wagi, wartości produktów, procentu opłaconych przesyłek

    statystyki_klientow – podsumowanie dla każdego klienta: liczba zamówień, suma wartości, średnia cena produktu, liczba różnych produktów, daty pierwszego i ostatniego zamówienia

Procedury i funkcje

    Dodawanie zamówienia

    Aktualizacja statystyk produktów

    Wysyłanie powiadomień do klientów

    Wysyłka zamówienia

    Przenoszenie paczki do innego magazynu

    Sprawdzanie statusu zamówienia po imieniu i nazwisku

    Planowanie trasy kuriera

Triggery

    Blokada usunięcia klienta z aktywnymi zamówieniami

    Sprawdzanie wagi paczki przy dodawaniu zamówienia

    Sprawdzanie, czy kurier ma prawo jazdy przy przypisywaniu auta

W bazie znajdują się także przykładowe dane do każdej z tabel, więc od razu po imporcie można testować działanie zapytań i procedur.