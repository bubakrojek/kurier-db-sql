
-- Host: 127.0.0.1:3307
-- Generation Time: Feb 05, 2025 at 09:51 PM
-- Wersja serwera: 10.4.32-MariaDB
-- Wersja PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `firma_kurierska`
--
DROP DATABASE IF EXISTS `firma_kurierska`;
CREATE DATABASE IF NOT EXISTS `firma_kurierska` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
USE `firma_kurierska`;

DELIMITER $$
--
-- Procedury
--
DROP PROCEDURE IF EXISTS `aktualizuj_statystyki_produktow`$$
CREATE DEFINER=`root`@`localhost` PROCEDURE `aktualizuj_statystyki_produktow` ()   BEGIN
    
    TRUNCATE TABLE statystyki_produktow;

  
    INSERT INTO statystyki_produktow (ID_produktu, nazwa_produktu, liczba_zamowien, laczna_kwota, cena_jednostkowa)
    SELECT 
        p.ID_produktu,
        p.nazwa_produktu,
        COUNT(zp.ID_zamowienia) AS liczba_zamowien,
        COUNT(zp.ID_zamowienia)*p.cena AS laczna_kwota,
	p.cena as cena_jednostkowa
    FROM produkt p
    LEFT JOIN zamowienie_produkt zp ON p.ID_produktu = zp.ID_produktu
    GROUP BY p.ID_produktu;
END$$

DROP PROCEDURE IF EXISTS `dodaj_zamowienie`$$
CREATE DEFINER=`root`@`localhost` PROCEDURE `dodaj_zamowienie` (IN `p_ID_odbiorcy` INT, IN `p_ID_nadawcy` INT, IN `p_waga` FLOAT, IN `p_lista_produktow` TEXT CHARSET utf8, OUT `p_status` VARCHAR(255))   BEGIN
  
    DECLARE v_nazwa VARCHAR(255) CHARSET utf8;
    DECLARE v_id_produktu INT;
    DECLARE v_paczka_id INT;
    DECLARE v_zamowienie_id INT;
    DECLARE new_id_kuriera INT;
    DECLARE v_ilosc_produktow INT;
    DECLARE v_rozmiar VARCHAR(3);
    DECLARE v_error_message VARCHAR(255);
    
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Blad dodawania zamowienia';
    END;

    IF p_lista_produktow IS NULL OR TRIM(p_lista_produktow) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lista produktów nie może być pusta!';
    END IF;
  
  
    START TRANSACTION;
   
   
    DROP TEMPORARY TABLE IF EXISTS temp_produkty;
    CREATE TEMPORARY TABLE temp_produkty (
        nazwa_produktu VARCHAR(50) 
    );
   
    INSERT INTO temp_produkty (nazwa_produktu) 
    VALUES (p_lista_produktow);
    
    INSERT INTO paczka (data_przyjecia, data_wydania, ID_magazynu)
    VALUES (CURRENT_DATE(), NULL, NULL);
    SET v_paczka_id = LAST_INSERT_ID();


    SELECT ID_kuriera INTO new_id_kuriera 
    FROM kurier 
    ORDER BY RAND() 
    LIMIT 1;
    
    
    INSERT INTO zamowienie (
        ID_kuriera, 
        nr_magazynowy, 
        ID_odbiorcy, 
        ID_nadawcy, 
        rozmiar,
        waga,
        data_zlozenia
    ) VALUES (
        new_id_kuriera, 
        v_paczka_id, 
        p_ID_odbiorcy, 
        p_ID_nadawcy,
        NULL,
        p_waga,
        CURRENT_DATE()
    );
    SET v_zamowienie_id = LAST_INSERT_ID();
    
    
    INSERT INTO aktualny_status_zamowienia (
        ID_zamowienia, 
        czy_oplacono, 
        data, 
        godzina
    ) VALUES (
        v_zamowienie_id, 
        'NIE', 
        CURRENT_DATE(), 
        CURRENT_TIME()
    );
    
   
    SELECT ID_produktu INTO v_id_produktu
    FROM produkt
    WHERE nazwa_produktu = (p_lista_produktow);
    
    
    IF v_id_produktu IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nie znaleziono produktu';
    END IF;
    
   
    INSERT INTO zamowienie_produkt (ID_zamowienia, ID_produktu)
    VALUES (v_zamowienie_id, v_id_produktu);
    
    
     CASE
        WHEN p_waga <= 2 THEN SET v_rozmiar = 'XS';
        WHEN  p_waga <= 4 THEN SET v_rozmiar = 'S';
        WHEN  p_waga <= 6 THEN SET v_rozmiar = 'M';
        WHEN  p_waga <= 8 THEN SET v_rozmiar = 'L';
        WHEN  p_waga <= 10 THEN SET v_rozmiar = 'XL';
        ELSE SET v_rozmiar = 'XXL';
    END CASE;
  
  
    UPDATE zamowienie
    SET rozmiar = v_rozmiar
    WHERE ID_zamowienia = v_zamowienie_id;


    COMMIT;

    SET p_status = 'Zamówienie dodane pomyślnie';
 
    DROP TEMPORARY TABLE IF EXISTS temp_produkty;
END$$

DROP PROCEDURE IF EXISTS `wyslij_powiadomienia_klientom`$$
CREATE DEFINER=`root`@`localhost` PROCEDURE `wyslij_powiadomienia_klientom` ()   BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_id_klienta INT;
    DECLARE v_email VARCHAR(255);
    DECLARE cur CURSOR FOR 
        SELECT DISTINCT k.ID_klienta, k.email 
        FROM klient k
        JOIN zamowienie z ON  k.ID_klienta = z.ID_odbiorcy
        JOIN aktualny_status_zamowienia a ON z.ID_zamowienia = a.ID_zamowienia
        WHERE a.czy_oplacono = 'NIE';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_powiadomienia (
        ID_klienta INT,
        email VARCHAR(255),
        wiadomosc TEXT
    );

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id_klienta, v_email;
        IF done THEN
            LEAVE read_loop;
        END IF;

       
        INSERT INTO temp_powiadomienia (ID_klienta, email, wiadomosc)
        VALUES (v_id_klienta, v_email, CONCAT('Szanowny Kliencie,\n\nMasz otwarte zamówienie, które nie zostało jeszcze opłacone. Zalecamy dokonanie płatności jak najszybciej.\n\nZ poważaniem,\nFirma Kurierska'));

    END LOOP;
    CLOSE cur;
	INSERT INTO temp_powiadomienia(ID_klienta, email,wiadomosc)
    VALUES(NULL,NULL,'Z racji braku mozliwosci wysylki realnego maila\nWstawiam "wiadomosci" do tymczaswoej tabeli\n');
    -- Wyświetlanie przykładowych powiadomień dla testowania
    SELECT * FROM temp_powiadomienia;
END$$

DROP PROCEDURE IF EXISTS `wyslij_zamowienie`$$
CREATE DEFINER=`root`@`localhost` PROCEDURE `wyslij_zamowienie` (OUT `wynik` VARCHAR(255))   BEGIN 
	DECLARE v_done INT DEFAULT 0;
	DECLARE v_id_zamowienia INT;
    DECLARE v_id_paczki INT;
    DECLARE v_id_odbiorcy INT;
    DECLARE v_data_zlozenia DATE;
    DECLARE v_nazwa_produktu VARCHAR(45);
    
    DECLARE v_imie VARCHAR(45);
    DECLARE v_nazwisko VARCHAR(45);
    DECLARE v_ulica  VARCHAR(20);
    DECLARE v_nr_domu INT;
    DECLARE v_miasto  VARCHAR(45);
    
   
    DECLARE cur CURSOR FOR
    	SELECT p.nazwa_produktu
        FROM zamowienie_produkt zp
        JOIN produkt p ON p.ID_produktu=zp.ID_produktu
        WHERE zp.ID_zamowienia=v_id_zamowienia;
        
        
   DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=1;
        
    SELECT z.ID_zamowienia, z.nr_magazynowy, z.ID_odbiorcy, z.data_zlozenia
    INTO v_id_zamowienia,v_id_paczki,v_id_odbiorcy, v_data_zlozenia
    FROM zamowienie z
    JOIN paczka p ON p.id_paczki=z.nr_magazynowy
    WHERE p.data_wydania IS NULL
    ORDER BY z.data_zlozenia ASC
    LIMIT 1;
    
    	
	IF v_id_zamowienia IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Brak zamówień do wysłania';
    END IF;
	
	SELECT k.imie,k.nazwisko,k.ulica,k.nr_domu, k.miasto
    INTO v_imie, v_nazwisko, v_ulica, v_nr_domu, v_miasto
    FROM klient k
    WHERE k.ID_klienta=v_id_odbiorcy;
		
    SELECT v_id_zamowienia AS ID_zam,
    		v_data_zlozenia AS data_zlozenia,
            CONCAT(v_imie,' ',v_nazwisko) AS dane_odbiorcy,
            CONCAT(v_ulica, ' ', v_nr_domu, ' ', v_miasto) AS adres;
            
           
    OPEN cur;
    
    read_products: LOOP
		FETCH cur INTO v_nazwa_produktu;
        IF v_done THEN 
        	LEAVE read_products;
        END IF;
        SELECT v_nazwa_produktu AS produkt;
    END LOOP read_products;
    
    CLOSE cur;

	UPDATE paczka
    SET data_wydania = CURRENT_DATE()
    WHERE id_paczki=v_id_paczki;
    
    
    SET wynik='Zaktualizawano najstarsze zamowienie';



END$$

--
-- Functions
--
DROP FUNCTION IF EXISTS `przenies_paczke`$$
CREATE DEFINER=`root`@`localhost` FUNCTION `przenies_paczke` (`p_id_paczki` INT, `p_nowy_magazyn_id` INT) RETURNS VARCHAR(100) CHARSET utf8 COLLATE utf8_general_ci MODIFIES SQL DATA BEGIN
    DECLARE v_stary_magazyn_id INT;
    DECLARE v_data_wydania DATE;
    DECLARE v_data_przyjecia DATE;
    DECLARE v_wynik VARCHAR(100);
    DECLARE czy_istnieje INT;
    DECLARE v_error BOOLEAN DEFAULT FALSE;
    
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET v_error = TRUE;
    END;
    
   -- START TRANSACTION;
    
    -- Sprawdź czy paczka istnieje i pobierz jej obecny magazyn
    SELECT ID_magazynu, data_wydania, data_przyjecia
    INTO v_stary_magazyn_id, v_data_wydania, v_data_przyjecia
    FROM paczka
    WHERE id_paczki = p_id_paczki;
    
    -- Sprawdź czy paczka nie została już wydana
    IF v_data_wydania IS NOT NULL THEN
      --  ROLLBACK;
        RETURN 'Nie można przenieść, wydano';
    ELSEIF v_data_wydania IS NULL AND v_data_przyjecia IS NULL THEN
       -- ROLLBACK;
        RETURN 'Nie mozna przeniesc, anulowano';
    END IF;
    
    SELECT  ID_magazynu INTO czy_istnieje
    FROM magazyn
    WHERE ID_magazynu = p_nowy_magazyn_id;
    
    
    IF czy_istnieje IS NULL THEN
      --  ROLLBACK;
        RETURN 'Podany magazyn nie istnieje';
    END IF;
    
    IF v_stary_magazyn_id = p_nowy_magazyn_id THEN
      --  ROLLBACK;
        RETURN 'Paczka jest już w tym magazynie';
    END IF;
    

    UPDATE paczka 
    SET ID_magazynu = p_nowy_magazyn_id
    WHERE id_paczki = p_id_paczki;
    
    IF v_error = TRUE THEN
       -- ROLLBACK;
        RETURN 'Wystąpił błąd podczas przenoszenia paczki';
    ELSE
       -- COMMIT;
        RETURN 'Paczka została przeniesiona pomyślnie';
    END IF;
    
END$$

DROP FUNCTION IF EXISTS `wyswietl_stan`$$
CREATE DEFINER=`root`@`localhost` FUNCTION `wyswietl_stan` (`p_imie` VARCHAR(45), `p_nazwisko` VARCHAR(45)) RETURNS VARCHAR(15) CHARSET utf8 COLLATE utf8_general_ci DETERMINISTIC BEGIN
	DECLARE v_stan varchar(15);
    DECLARE v_id_klienta INT;
   	DECLARE v_id_zamowienia INT;
   
    SELECT ASZ.czy_oplacono INTO v_stan
    FROM klient K
    INNER JOIN zamowienie Z ON Z.ID_odbiorcy=K.ID_klienta
    INNER JOIN aktualny_status_zamowienia ASZ ON ASZ.ID_zamowienia=Z.ID_zamowienia
    WHERE K.imie=p_imie AND k.nazwisko=p_nazwisko
     ORDER BY Z.data_zlozenia ASC
    LIMIT 1;
    

    CASE 
    WHEN v_stan IS NULL THEN
    	SET v_stan='Nie znaleziono';
    WHEN v_stan='NIE' THEN
        SET v_stan='Nie oplacone';
    ELSE SET v_stan='Oplacone';
    END CASE;


 	RETURN v_stan;
    
    
	

END$$

DROP FUNCTION IF EXISTS `zaplanuj_trase_kuriera`$$
CREATE DEFINER=`root`@`localhost` FUNCTION `zaplanuj_trase_kuriera` (`p_id_kuriera` INT) RETURNS TEXT CHARSET utf8 COLLATE utf8_general_ci READS SQL DATA BEGIN
    DECLARE v_adres TEXT;
    DECLARE v_wynik TEXT DEFAULT '';
    DECLARE v_koniec INT DEFAULT 0;
    
    DECLARE trasa_cur CURSOR FOR
        SELECT CONCAT(k.miasto, ', ', k.ulica, ' ', k.nr_domu) as adres
        FROM zamowienie z
        JOIN paczka p ON p.id_paczki = z.nr_magazynowy
        JOIN klient k ON k.ID_klienta = z.ID_odbiorcy
        WHERE z.ID_kuriera = p_id_kuriera 
        AND p.data_wydania IS NULL
        ORDER BY k.miasto ASC, k.ulica ASC;
        
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_koniec = 1;
    
    SET v_wynik = 'Trasa dostawy:\n';
    
    OPEN trasa_cur;
    
    read_loop: LOOP
        FETCH trasa_cur INTO v_adres;
        IF v_koniec THEN
            LEAVE read_loop;
        END IF;
        SET v_wynik = CONCAT(v_wynik, '-> ', v_adres, '\n');
    END LOOP;
    
    CLOSE trasa_cur;
    
    RETURN v_wynik;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `aktualny_status_zamowienia`
--

DROP TABLE IF EXISTS `aktualny_status_zamowienia`;
CREATE TABLE `aktualny_status_zamowienia` (
  `ID_zamowienia` int(11) NOT NULL,
  `czy_oplacono` varchar(3) NOT NULL,
  `data` date NOT NULL,
  `godzina` time NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='status paczki, wraz z godzina i data';

--
-- Dumping data for table `aktualny_status_zamowienia`
--

INSERT INTO `aktualny_status_zamowienia` (`ID_zamowienia`, `czy_oplacono`, `data`, `godzina`) VALUES
(1, 'NIE', '2025-01-30', '10:42:09'),
(2, 'TAK', '2025-01-30', '10:42:09'),
(3, 'NIE', '2025-01-30', '10:42:09'),
(4, 'TAK', '2025-01-30', '10:42:09'),
(5, 'NIE', '2025-01-30', '10:42:09'),
(6, 'TAK', '2025-01-30', '10:42:09'),
(7, 'NIE', '2025-01-30', '10:42:09'),
(8, 'NIE', '2025-01-30', '10:42:09'),
(9, 'NIE', '2025-01-30', '10:42:09'),
(10, 'NIE', '2025-01-30', '10:42:09'),
(11, 'TAK', '2025-01-30', '10:42:09'),
(12, 'NIE', '2025-01-30', '10:42:09'),
(13, 'NIE', '2025-01-30', '10:42:09'),
(14, 'TAK', '2025-01-30', '10:42:09'),
(15, 'NIE', '2025-01-30', '10:42:09'),
(16, 'TAK', '2025-01-30', '10:42:09'),
(17, 'NIE', '2025-01-30', '10:42:09'),
(18, 'TAK', '2025-01-30', '10:42:09'),
(19, 'NIE', '2025-01-30', '10:42:09'),
(20, 'NIE', '2025-01-30', '10:42:09'),
(21, 'NIE', '2025-01-30', '10:42:09'),
(22, 'TAK', '2025-01-30', '10:42:09'),
(23, 'TAK', '2025-01-30', '10:42:09'),
(24, 'NIE', '2025-01-30', '10:42:09'),
(25, 'NIE', '2025-01-30', '10:42:09'),
(26, 'NIE', '2025-01-30', '10:42:09'),
(27, 'NIE', '2025-01-30', '10:42:09'),
(28, 'NIE', '2025-01-30', '10:42:09'),
(29, 'NIE', '2025-01-30', '10:42:09'),
(30, 'NIE', '2025-01-30', '10:42:09'),
(31, 'NIE', '2025-01-30', '10:42:09'),
(32, 'TAK', '2025-01-30', '10:42:09'),
(33, 'TAK', '2025-01-30', '10:42:09'),
(34, 'NIE', '2025-01-30', '10:42:09'),
(35, 'TAK', '2025-01-30', '10:42:09'),
(36, 'TAK', '2025-01-30', '10:42:09'),
(37, 'NIE', '2025-01-30', '10:42:09'),
(38, 'NIE', '2025-01-30', '10:42:09'),
(39, 'NIE', '2025-01-30', '10:42:09'),
(40, 'TAK', '2025-01-30', '10:42:09'),
(41, 'NIE', '2025-01-30', '10:42:09'),
(42, 'NIE', '2025-01-30', '10:42:09'),
(43, 'NIE', '2025-01-30', '10:42:09'),
(44, 'TAK', '2025-01-30', '10:42:09'),
(45, 'NIE', '2025-01-30', '10:42:09'),
(46, 'TAK', '2025-01-30', '10:42:09'),
(47, 'NIE', '2025-01-30', '10:42:09'),
(48, 'NIE', '2025-01-30', '10:42:09'),
(49, 'NIE', '2025-01-30', '10:42:09'),
(51, 'NIE', '2025-02-04', '12:40:34'),
(52, 'NIE', '2025-02-04', '12:43:20'),
(53, 'NIE', '2025-02-04', '16:54:52'),
(54, 'NIE', '2025-02-04', '17:10:03'),
(55, 'NIE', '2025-02-04', '17:10:21');

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `analiza_zamowien_miesieczna`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `analiza_zamowien_miesieczna`;
CREATE TABLE `analiza_zamowien_miesieczna` (
`miesiac` varchar(7)
,`liczba_zamowien` bigint(21)
,`liczba_unikalnych_klientow` bigint(21)
,`srednia_waga` double(19,2)
,`laczna_wartosc_produktow` double(19,2)
,`liczba_oplaconych` decimal(22,0)
,`procent_oplaconych` decimal(28,2)
);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `auto`
--

DROP TABLE IF EXISTS `auto`;
CREATE TABLE `auto` (
  `ID_auta` int(11) NOT NULL,
  `kolor` varchar(45) NOT NULL,
  `marka` varchar(45) NOT NULL,
  `model` varchar(45) NOT NULL,
  `nr_rej` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='dane auta wykorzystywanego przez kuriera';

--
-- Dumping data for table `auto`
--

INSERT INTO `auto` (`ID_auta`, `kolor`, `marka`, `model`, `nr_rej`) VALUES
(21, 'Pomarańczowy', 'Citroen', 'Relay', 'HM80042'),
(22, 'Żółty', 'Renault', 'Master', 'AM70881'),
(23, 'Niebieski', 'Mercedes', 'Sprinter', 'PI83298'),
(24, 'Niebieski', 'Iveco', 'Daily', 'AO27734'),
(25, 'Biały', 'Ford', 'Transit', 'LB60846'),
(26, 'Biały', 'Volkswagen', 'Transporter', 'EK92851'),
(27, 'Czerwony', 'Renault', 'Master', 'ZA52156'),
(28, 'Niebieski', 'Renault', 'Master', 'ZT60056'),
(29, 'Fioletowy', 'Iveco', 'Daily', 'TH35348'),
(30, 'Biały', 'Fiat', 'Ducato', 'UL94444'),
(31, 'Żółty', 'Citroen', 'Relay', 'UZ88459'),
(32, 'Niebieski', 'Peugeot', 'Boxer', 'GD89146'),
(33, 'Fioletowy', 'Citroen', 'Relay', 'ZZ71935'),
(34, 'Żółty', 'Citroen', 'Relay', 'UI24849'),
(35, 'Zielony', 'Peugeot', 'Boxer', 'PP43408'),
(36, 'Czarny', 'Iveco', 'Daily', 'CA47275'),
(37, 'Niebieski', 'Fiat', 'Ducato', 'JJ22321'),
(38, 'Żółty', 'Citroen', 'Relay', 'NL65570'),
(39, 'Niebieski', 'Iveco', 'Daily', 'QW43425'),
(40, 'Biały', 'Mercedes', 'Sprinter', 'WK12581');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `cennik`
--

DROP TABLE IF EXISTS `cennik`;
CREATE TABLE `cennik` (
  `rozmiar` varchar(45) NOT NULL,
  `cena` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='cena przesylki za odpowiedni rozmiar paczki';

--
-- Dumping data for table `cennik`
--

INSERT INTO `cennik` (`rozmiar`, `cena`) VALUES
('L', 20.00),
('M', 15.00),
('S', 10.00),
('XL', 25.00),
('XS', 5.00),
('XXL', 30.00);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `karta_pojazdu`
--

DROP TABLE IF EXISTS `karta_pojazdu`;
CREATE TABLE `karta_pojazdu` (
  `id_auta` int(11) NOT NULL,
  `nr_prawa_jazdy_kierowcy` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

--
-- Dumping data for table `karta_pojazdu`
--

INSERT INTO `karta_pojazdu` (`id_auta`, `nr_prawa_jazdy_kierowcy`) VALUES
(21, '5KTIJ74U11'),
(22, '058AOO091W'),
(22, '9GZWW0YUA0'),
(23, 'SSWELZFZ04'),
(23, 'X1EM5UZBC3'),
(24, 'IJGAJ6OAM9'),
(25, '1LAC431RG3'),
(26, 'IJGAJ6OAM9'),
(26, 'Q7VTUCB0IX'),
(27, 'PMIM7AYW98'),
(28, 'SSWELZFZ04'),
(28, 'X1EM5UZBC3'),
(29, '9GZWW0YUA0'),
(30, '1TBQ26RQCN'),
(31, '0BP3GKNPL3'),
(31, 'PMIM7AYW98'),
(32, '0YTEBMS7H2'),
(32, '1TBQ26RQCN'),
(33, 'UFW48AV6E3'),
(34, '1LAC431RG3'),
(34, '5YFT5RSKO0'),
(35, '5FYYN5B7VF'),
(35, '5KTIJ74U11'),
(36, '058AOO091W'),
(36, 'OCLTXGA94Q'),
(37, 'IA4H84UFMK'),
(37, 'Q7VTUCB0IX'),
(38, 'Z95YCQF7L6'),
(39, 'EK6WNNHOB7'),
(40, 'TJVYDNJZPW');

--
-- Wyzwalacze `karta_pojazdu`
--
DROP TRIGGER IF EXISTS `tr_check_karta_pojazdu`;
DELIMITER $$
CREATE TRIGGER `tr_check_karta_pojazdu` BEFORE INSERT ON `karta_pojazdu` FOR EACH ROW BEGIN
   
   DECLARE licencja_exists INT;
    SELECT COUNT(*) INTO licencja_exists FROM kurier WHERE nr_prawa_jazdy = NEW.nr_prawa_jazdy_kierowcy;
    IF licencja_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kurier nie posiada prawa jazdy!';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `klient`
--

DROP TABLE IF EXISTS `klient`;
CREATE TABLE `klient` (
  `ID_klienta` int(11) NOT NULL,
  `imie` varchar(45) NOT NULL,
  `nazwisko` varchar(45) NOT NULL,
  `email` varchar(30) DEFAULT NULL,
  `nr_domu` int(100) NOT NULL,
  `ulica` varchar(20) NOT NULL,
  `miasto` varchar(45) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='dane klienta';

--
-- Dumping data for table `klient`
--

INSERT INTO `klient` (`ID_klienta`, `imie`, `nazwisko`, `email`, `nr_domu`, `ulica`, `miasto`) VALUES
(1, 'Witold', 'Kubaczyk', 'witold.kubaczyk@example.com', 852, 'Sowia', 'Krosno'),
(2, 'Emil', 'Zimoń', 'emil.zimoń@example.com', 642, 'Jesionowa', 'Chojnice'),
(3, 'Julita', 'Balik', 'julita.balik@example.com', 746, 'Żurawia', 'Świecie'),
(4, 'Jakub', 'Urynowicz', 'gianpietro42@example.com', 150, 'Morska', 'Ruda Śląska'),
(5, 'Konrad', 'Haremza', 'konrad.haremza@example.com', 245, 'Szewska', 'Zambrów'),
(6, 'Olgierd', 'Maćczak', 'gbergoglio@example.org', 183, 'Żwirowa', 'Starachowice'),
(7, 'Roksana', 'Gospodarek', 'borzomisophia@example.com', 747, 'Grabowa', 'Łaziska Górne'),
(8, 'Józef', 'Waszczyk', 'nicolettiadele@example.net', 75, 'Władysława Jagiełły', 'Wejherowo'),
(9, 'Eryk', 'Kulus', 'eryk.kulus@example.com', 718, 'Borowa', 'Ostrów Wielkopolski'),
(10, 'Wiktor', 'Rykała', 'wiktor.rykała@example.com', 820, 'Jesionowa', 'Czerwionka-Leszczyny'),
(11, 'Ewelina', 'Mierzwiak', 'ewelina.mierzwiak@example.com', 53, 'Szafirowa', 'Świecie'),
(12, 'Natan', 'Mitera', 'natan.mitera@example.com', 340, 'Nowowiejska', 'Śrem'),
(13, 'Jeremi', 'Kośnik', 'jeremi.kośnik@example.com', 130, 'Jaśminowa', 'Wałcz'),
(14, 'Emil', 'Kaszkowiak', 'qsollima@example.org', 375, 'Lipca', 'Kołobrzeg'),
(15, 'Sonia', 'Bryzek', 'sonia.bryzek@example.com', 636, 'Podwale', 'Bielsk Podlaski'),
(16, 'Ksawery', 'Sołtysek', 'hmengolo@example.com', 205, 'Waryńskiego', 'Pruszków'),
(17, 'Jerzy', 'Korta', 'jerzy.korta@example.com', 751, 'Jarzębinowa', 'Ostrów Wielkopolski'),
(18, 'Robert', 'Sajewicz', 'robert.sajewicz@example.com', 695, 'Rumiankowa', 'Bielawa'),
(19, 'Kornel', 'Patalas', 'enrico00@example.net', 727, 'Jadwigi', 'Zielona Góra'),
(20, 'Anastazja', 'Kutnik', 'angelicabodoni@example.com', 610, 'Stolarska', 'Świdnica'),
(21, 'Hasan', 'Washington', 'garzonidolores@example.com', 950, 'chemin Ramos', 'Mühlhausen'),
(22, 'Philippe', 'Kubieniec', 'philippe.kubieniec@example.com', 418, 'Heini-Geißler-Platz', 'New Curtisstad'),
(23, 'Sylwia', 'Wilkos', 'paridebuscetta@example.net', 305, 'Staszica', 'Legnica'),
(24, 'René', 'Striebitz', 'rené.striebitz@example.com', 340, 'Borgo Ivan', 'Ficuzza'),
(25, 'Alberto', 'Tagliafierro', 'alberto.tagliafierro@example.c', 858, 'Sarah Square', 'Rodriguesboeuf'),
(26, 'Biagio', 'Armata', 'biagio.armata@example.com', 226, 'Via Asprucci', 'Saint Jules-la-Forêt'),
(27, 'Monika', 'Gonzalez', 'bondumiergiacomo@example.net', 661, 'Piazza Vincentio', 'Saint Élisabeth-la-Forêt'),
(28, 'Caroline', 'Barrera', 'caroline.barrera@example.com', 303, 'Cisowa', 'Gomes'),
(29, 'Monika', 'Girard', 'monika.girard@example.com', 118, 'Powell Neck', 'Lörrach'),
(30, 'Vito', 'Maxwell', 'vito.maxwell@example.com', 111, 'Ogrodowa', 'Großenhain'),
(31, 'Costantino', 'Bertin', 'cpalombi@example.org', 818, 'Canale Federici', 'South Trevor'),
(32, 'Sarah', 'Spears', 'acerbigianfranco@example.net', 389, 'Stretto Andreotti', 'Keithchester'),
(33, 'Aldo', 'Tomei', 'aldo.tomei@example.com', 171, 'Krasickiego', 'East Justin'),
(34, 'Daniel', 'Rousset', 'daniel.rousset@example.com', 417, 'Andrea Way', 'Lake Bradley'),
(35, 'Aleks', 'Renaud', 'aleks.renaud@example.com', 368, 'Bennett Brooks', 'Ciechanów'),
(36, 'Jessica', 'Robinson', 'pergolesifabrizia@example.org', 17, 'Cedrowa', 'Precenicco'),
(37, 'Melissa', 'Mendez', 'melissa.mendez@example.com', 405, 'Canale Romolo', 'Strevi'),
(38, 'Hellmuth', 'Miller', 'osvaldopassalacqua@example.com', 326, 'Albert-Knappe-Ring', 'Pruszków'),
(39, 'Daria', 'Scholtz', 'alfiotrentin@example.com', 49, 'Salas Rest', 'Lecomtenec'),
(40, 'Agostino', 'Henry', 'agostino.henry@example.com', 853, 'Dąbrowskiego', 'Bellberg'),
(41, 'Valerio', 'Underwood', 'valerio.underwood@example.com', 171, 'Soto Station', 'Monteriggioni'),
(42, 'Christophe', 'Lemaire', 'stefanibacosi@example.org', 907, 'Borgo Sauro', 'Descamps'),
(43, 'Meryem', 'Grądziel', 'meryem.grądziel@example.com', 922, 'Złota', 'Oleśnica'),
(44, 'Margret', 'Wise', 'margret.wise@example.com', 62, 'Pavel-Wulf-Platz', 'Figueroaview'),
(45, 'Pauline', 'Pisani', 'pauline.pisani@example.com', 994, 'Jones Hill', 'Grantport'),
(46, 'Diana', 'Sornat', 'tcaironi@example.net', 953, 'Vicolo Malipiero', 'Rémy'),
(47, 'Maggie', 'Köhler', 'antonucciernesto@example.com', 540, 'Via Antonello', 'Riou-sur-Cordier'),
(48, 'Steven', 'Pizzo', 'taccoladanilo@example.com', 783, 'Hutnicza', 'Hohlen'),
(49, 'Rose-Marie', 'Mocenigo', 'domenico99@example.net', 800, 'Willie Viaduct', 'Bailly'),
(50, 'Lisa', 'Smith', 'wmurri@example.com', 693, 'Jennifer Forges', 'PrévostVille'),
(51, 'Julia', 'Szewczyk', 'julka.szewczyk@gmail.com', 15, 'Bialoleka', 'Miasto Bialoleka');

--
-- Wyzwalacze `klient`
--
DROP TRIGGER IF EXISTS `tr_prevent_delete_klient_with_orders`;
DELIMITER $$
CREATE TRIGGER `tr_prevent_delete_klient_with_orders` BEFORE DELETE ON `klient` FOR EACH ROW BEGIN
    DECLARE active_orders_count INT;

  
    SELECT COUNT(*)
    INTO active_orders_count
    FROM zamowienie
    WHERE (ID_odbiorcy = OLD.ID_klienta OR ID_nadawcy = OLD.ID_klienta);

    IF active_orders_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nie można usunąć klienta z aktywnymi zamówieniami!';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `kurier`
--

DROP TABLE IF EXISTS `kurier`;
CREATE TABLE `kurier` (
  `ID_kuriera` int(11) NOT NULL,
  `imie` varchar(45) NOT NULL,
  `nazwisko` varchar(45) NOT NULL,
  `nr_prawa_jazdy` varchar(20) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

--
-- Dumping data for table `kurier`
--

INSERT INTO `kurier` (`ID_kuriera`, `imie`, `nazwisko`, `nr_prawa_jazdy`) VALUES
(1, 'Mieszko', 'Mikusek', '5KTIJ74U11'),
(2, 'Norbert', 'Kapustka', '058AOO091W'),
(3, 'Dominik', 'Wochna', 'X1EM5UZBC3'),
(4, 'Melania', 'Zapadka', 'IJGAJ6OAM9'),
(5, 'Wojciech', 'Rode', '1LAC431RG3'),
(6, 'Konstanty', 'Durlik', 'Q7VTUCB0IX'),
(7, 'Karol', 'Koj', 'PMIM7AYW98'),
(8, 'Nikodem', 'Engel', 'SSWELZFZ04'),
(9, 'Wojciech', 'Sygut', '9GZWW0YUA0'),
(10, 'Anastazja', 'Jachimczak', '1TBQ26RQCN'),
(11, 'Dariusz', 'Szkaradek', '0BP3GKNPL3'),
(12, 'Bartek', 'Cader', '0YTEBMS7H2'),
(13, 'Mariusz', 'Bylina', 'UFW48AV6E3'),
(14, 'Iwo', 'Nowrot', '5YFT5RSKO0'),
(15, 'Ksawery', 'Falba', '5FYYN5B7VF'),
(16, 'Konstanty', 'Szabla', 'OCLTXGA94Q'),
(17, 'Fabian', 'Matyjas', 'IA4H84UFMK'),
(18, 'Blanka', 'Banachowicz', 'Z95YCQF7L6'),
(19, 'Eliza', 'Ziemkiewicz', 'EK6WNNHOB7'),
(20, 'Nicole', 'Klebba', 'TJVYDNJZPW'),
(21, 'Oliwier', 'Kasprzyk', NULL);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `magazyn`
--

DROP TABLE IF EXISTS `magazyn`;
CREATE TABLE `magazyn` (
  `ID_magazynu` int(11) NOT NULL,
  `nr_domu` int(100) NOT NULL,
  `ulica` varchar(20) NOT NULL,
  `miasto` varchar(45) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='dane magazynu';

--
-- Dumping data for table `magazyn`
--

INSERT INTO `magazyn` (`ID_magazynu`, `nr_domu`, `ulica`, `miasto`) VALUES
(1, 845, 'Ceglana', 'Pruszcz Gdański'),
(2, 104, 'Przechodnia', 'Lubartów'),
(3, 265, 'Rejtana', 'Kłodzko'),
(4, 310, 'Kasprowicza', 'Opole'),
(5, 923, 'Bema', 'Wągrowiec'),
(6, 300, 'Kasztanowa', 'Świebodzice'),
(7, 776, 'Listopada', 'Polkowice'),
(8, 748, 'Mała', 'Koszalin'),
(9, 377, 'Traugutta', 'Pruszcz Gdański'),
(10, 776, 'Wojciecha', 'Bielsk Podlaski');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `paczka`
--

DROP TABLE IF EXISTS `paczka`;
CREATE TABLE `paczka` (
  `id_paczki` int(11) NOT NULL,
  `data_przyjecia` date DEFAULT NULL,
  `data_wydania` date DEFAULT NULL,
  `ID_magazynu` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='opis stanu magazynowego paczki';

--
-- Dumping data for table `paczka`
--

INSERT INTO `paczka` (`id_paczki`, `data_przyjecia`, `data_wydania`, `ID_magazynu`) VALUES
(1, '2020-03-15', '2020-04-10', 1),
(2, '2019-07-22', '2019-08-05', 2),
(3, '2021-12-01', NULL, 4),
(4, '2018-09-10', '2018-10-20', 4),
(5, NULL, NULL, NULL),
(6, '2022-05-25', '2022-06-15', 5),
(7, '2017-01-17', '2017-02-22', 6),
(8, '2023-11-30', NULL, 7),
(9, NULL, NULL, NULL),
(10, '2024-02-10', '2024-03-12', 8),
(11, '2025-07-14', NULL, 9),
(12, '2016-05-01', '2016-06-01', 10),
(13, '2019-03-22', NULL, 2),
(14, '2020-11-11', '2021-01-05', 5),
(15, '2015-08-08', '2025-02-04', 4),
(16, '2022-04-14', '2022-05-01', 7),
(17, NULL, NULL, NULL),
(18, '2023-09-21', '2023-10-31', 9),
(19, '2014-07-19', '2025-02-04', 6),
(20, '2026-01-15', '2026-02-20', 1),
(21, '2027-06-06', NULL, 3),
(22, '2018-12-23', '2019-02-10', 2),
(23, '2021-03-09', NULL, 4),
(24, '2025-08-30', '2025-09-15', 8),
(25, NULL, NULL, NULL),
(26, '2019-06-18', NULL, 10),
(27, '2020-02-14', '2020-03-07', 7),
(28, '2023-05-01', '2023-05-28', 6),
(29, '2017-11-27', NULL, 5),
(30, '2024-10-10', '2024-11-14', 9),
(31, '2016-04-09', '2025-02-04', 1),
(32, NULL, NULL, NULL),
(33, '2022-07-12', '2022-08-22', 3),
(34, '2018-10-05', NULL, 7),
(35, '2021-01-08', '2021-02-11', 2),
(36, '2015-02-14', '2015-03-09', 4),
(37, '2023-06-19', NULL, 6),
(38, '2024-11-20', '2024-12-30', 8),
(39, NULL, NULL, NULL),
(40, '2025-09-11', NULL, 10),
(41, '2019-12-05', '2020-01-10', 9),
(42, '2020-08-29', NULL, 5),
(43, '2021-06-07', '2021-07-17', 3),
(44, '2026-02-14', NULL, 1),
(45, '2027-04-22', '2027-05-19', 7),
(46, '2028-07-09', NULL, 2),
(47, '2014-09-30', '2014-10-29', 4),
(48, '2015-11-11', '2025-02-04', 6),
(49, '2018-01-01', '2018-02-14', 8),
(51, '2025-02-04', NULL, NULL),
(52, '2025-02-04', NULL, NULL),
(53, '2025-02-04', NULL, NULL),
(54, '2025-02-04', NULL, NULL),
(55, '2025-02-04', NULL, NULL);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `produkt`
--

DROP TABLE IF EXISTS `produkt`;
CREATE TABLE `produkt` (
  `ID_produktu` int(11) NOT NULL,
  `nazwa_produktu` varchar(45) NOT NULL,
  `cena` float NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='dane produktu';

--
-- Dumping data for table `produkt`
--

INSERT INTO `produkt` (`ID_produktu`, `nazwa_produktu`, `cena`) VALUES
(1, 'Laptop', 17.45),
(2, 'Smartfon', 483.27),
(3, 'Tablet', 314.05),
(4, 'Drukarka', 185.73),
(5, 'Skaner', 461.25),
(6, 'Kamera', 54.63),
(7, 'Myszka', 324.42),
(8, 'Klawiatura', 363.14),
(9, 'Monitor', 190.6),
(10, 'Głośniki', 331.12),
(11, 'Pamięć USB', 93.8),
(12, 'Zasilacz', 484.4),
(13, 'Słuchawki', 470.71),
(14, 'Faks', 271.13),
(15, 'Koperta', 213.52),
(16, 'Długopis', 110.55),
(17, 'Ołówek', 14.43),
(18, 'Notatnik', 371.55),
(19, 'Kartridż', 27.62),
(20, 'Papier', 386.29),
(21, 'Projektor', 330.6),
(22, 'Mikrofon', 353.27),
(23, 'Router', 274.52),
(24, 'Modem', 451.34),
(25, 'Kabel HDMI', 333.86),
(26, 'Kabel USB', 270.09),
(27, 'Słuchawki bezprzewodowe', 149.27),
(28, 'Głośnik Bluetooth', 471.67),
(29, 'Powerbank', 24.67),
(30, 'Kamera internetowa', 480.25),
(31, 'Tablet graficzny', 127.07),
(32, 'Drukarka 3D', 316.52),
(33, 'Kserokopiarka', 234.52),
(34, 'Folia do laminowania', 16.14),
(35, 'Spinacz', 108.02),
(36, 'Teczka', 414.31),
(37, 'Segregator', 182.01),
(38, 'Kleje', 478.66),
(39, 'Taśma klejąca', 486.76),
(40, 'Nożyczki', 473.12),
(41, 'Zeszyt', 217.49),
(42, 'Marker', 493.8),
(43, 'Flamastry', 204.69),
(44, 'Kalkulator', 321.28),
(45, 'Tablica suchościeralna', 462.05),
(46, 'Pióro wieczne', 438.7),
(47, 'Kredki', 485.31),
(48, 'Papier kolorowy', 451.83),
(49, 'Papier ksero', 235.24),
(50, 'Papier samoprzylepny', 195.86);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `statystyki_klientow`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `statystyki_klientow`;
CREATE TABLE `statystyki_klientow` (
`ID_klienta` int(11)
,`imie` varchar(45)
,`nazwisko` varchar(45)
,`laczna_ilosc_zamowien` bigint(21)
,`laczna_kwota_zamowienia` double(19,2)
,`srednia_kwota_produktow` double(19,2)
,`liczba_unikalnych_produktow` bigint(21)
,`najnowsze_zamowienie` date
,`najstarsze_zamowienie` date
,`ilosc_miesiecy_wspolpracy` bigint(21)
);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `statystyki_produktow`
--

DROP TABLE IF EXISTS `statystyki_produktow`;
CREATE TABLE `statystyki_produktow` (
  `ID_produktu` int(11) NOT NULL,
  `nazwa_produktu` varchar(45) DEFAULT NULL,
  `liczba_zamowien` int(11) DEFAULT NULL,
  `laczna_kwota` decimal(10,2) DEFAULT NULL,
  `cena_jednostkowa` float NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

--
-- Dumping data for table `statystyki_produktow`
--

INSERT INTO `statystyki_produktow` (`ID_produktu`, `nazwa_produktu`, `liczba_zamowien`, `laczna_kwota`, `cena_jednostkowa`) VALUES
(1, 'Laptop', 0, 0.00, 17.45),
(2, 'Smartfon', 2, 966.54, 483.27),
(3, 'Tablet', 0, 0.00, 314.05),
(4, 'Drukarka', 2, 371.46, 185.73),
(5, 'Skaner', 0, 0.00, 461.25),
(6, 'Kamera', 2, 109.26, 54.63),
(7, 'Myszka', 0, 0.00, 324.42),
(8, 'Klawiatura', 3, 1089.42, 363.14),
(9, 'Monitor', 0, 0.00, 190.6),
(10, 'Głośniki', 2, 662.24, 331.12),
(11, 'Pamięć USB', 4, 375.20, 93.8),
(12, 'Zasilacz', 1, 484.40, 484.4),
(13, 'Słuchawki', 2, 941.42, 470.71),
(14, 'Faks', 3, 813.39, 271.13),
(15, 'Koperta', 5, 1067.60, 213.52),
(16, 'Długopis', 5, 552.75, 110.55),
(17, 'Ołówek', 2, 28.86, 14.43),
(18, 'Notatnik', 0, 0.00, 371.55),
(19, 'Kartridż', 0, 0.00, 27.62),
(20, 'Papier', 3, 1158.87, 386.29),
(21, 'Projektor', 3, 991.80, 330.6),
(22, 'Mikrofon', 1, 353.27, 353.27),
(23, 'Router', 2, 549.04, 274.52),
(24, 'Modem', 2, 902.68, 451.34),
(25, 'Kabel HDMI', 1, 333.86, 333.86),
(26, 'Kabel USB', 1, 270.09, 270.09),
(27, 'Słuchawki bezprzewodowe', 0, 0.00, 149.27),
(28, 'Głośnik Bluetooth', 0, 0.00, 471.67),
(29, 'Powerbank', 0, 0.00, 24.67),
(30, 'Kamera internetowa', 1, 480.25, 480.25),
(31, 'Tablet graficzny', 3, 381.21, 127.07),
(32, 'Drukarka 3D', 1, 316.52, 316.52),
(33, 'Kserokopiarka', 0, 0.00, 234.52),
(34, 'Folia do laminowania', 1, 16.14, 16.14),
(35, 'Spinacz', 0, 0.00, 108.02),
(36, 'Teczka', 4, 1657.24, 414.31),
(37, 'Segregator', 2, 364.02, 182.01),
(38, 'Kleje', 2, 957.32, 478.66),
(39, 'Taśma klejąca', 3, 1460.28, 486.76),
(40, 'Nożyczki', 1, 473.12, 473.12),
(41, 'Zeszyt', 1, 217.49, 217.49),
(42, 'Marker', 0, 0.00, 493.8),
(43, 'Flamastry', 2, 409.38, 204.69),
(44, 'Kalkulator', 1, 321.28, 321.28),
(45, 'Tablica suchościeralna', 0, 0.00, 462.05),
(46, 'Pióro wieczne', 3, 1316.10, 438.7),
(47, 'Kredki', 2, 970.62, 485.31),
(48, 'Papier kolorowy', 2, 903.66, 451.83),
(49, 'Papier ksero', 3, 705.72, 235.24),
(50, 'Papier samoprzylepny', 0, 0.00, 195.86);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `zamowienie`
--

DROP TABLE IF EXISTS `zamowienie`;
CREATE TABLE `zamowienie` (
  `ID_zamowienia` int(11) NOT NULL,
  `ID_kuriera` int(11) NOT NULL,
  `nr_magazynowy` int(11) NOT NULL,
  `ID_odbiorcy` int(11) NOT NULL,
  `ID_nadawcy` int(11) NOT NULL,
  `rozmiar` varchar(45) DEFAULT NULL,
  `waga` float DEFAULT NULL,
  `data_zlozenia` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='Tabela zamowienia';

--
-- Dumping data for table `zamowienie`
--

INSERT INTO `zamowienie` (`ID_zamowienia`, `ID_kuriera`, `nr_magazynowy`, `ID_odbiorcy`, `ID_nadawcy`, `rozmiar`, `waga`, `data_zlozenia`) VALUES
(1, 4, 1, 40, 48, 'M', 2.73, '2020-02-25'),
(2, 19, 2, 50, 20, 'XS', 2.67, '2019-07-10'),
(3, 12, 3, 41, 30, 'XL', 2.52, '2021-11-15'),
(4, 6, 4, 6, 43, 'M', 6.71, '2018-08-15'),
(5, 17, 5, 50, 1, 'XS', 7.66, '2019-05-20'),
(6, 20, 6, 39, 19, 'XL', 2.3, '2022-05-05'),
(7, 16, 7, 8, 33, 'XL', 7.37, '2017-01-01'),
(8, 13, 8, 7, 44, 'M', 6.1, '2023-11-10'),
(9, 15, 9, 38, 23, 'XXL', 8.8, '2020-06-18'),
(10, 1, 10, 37, 16, 'S', 4.02, '2024-01-25'),
(11, 6, 11, 39, 17, 'XS', 1.37, '2025-06-28'),
(12, 8, 12, 35, 16, 'S', 9.52, '2016-04-10'),
(13, 4, 13, 39, 17, 'XL', 3.1, '2019-02-28'),
(14, 19, 14, 50, 12, 'S', 2.63, '2020-10-10'),
(15, 20, 15, 19, 43, 'XXL', 5.96, '2015-07-15'),
(16, 15, 16, 23, 43, 'S', 2.17, '2022-03-30'),
(17, 16, 17, 17, 36, 'XS', 7.25, '2018-12-22'),
(18, 14, 18, 39, 12, 'S', 7.46, '2023-09-05'),
(19, 20, 19, 30, 2, 'XL', 7.04, '2014-06-25'),
(20, 8, 20, 15, 37, 'XXL', 1.57, '2024-01-05'),
(21, 5, 21, 49, 13, 'L', 6.77, '2025-02-03'),
(22, 6, 22, 7, 16, 'L', 5.88, '2018-11-28'),
(23, 5, 23, 11, 48, 'M', 2.65, '2021-02-20'),
(24, 7, 24, 10, 33, 'XL', 8.87, '2025-08-10'),
(25, 12, 25, 14, 44, 'M', 5.38, '2017-09-15'),
(26, 14, 26, 38, 8, 'XL', 9.68, '2019-06-01'),
(27, 3, 27, 29, 21, 'S', 6.08, '2020-01-28'),
(28, 11, 28, 15, 32, 'XXL', 7, '2023-04-10'),
(29, 4, 29, 33, 30, 'S', 4.35, '2017-11-05'),
(30, 10, 30, 16, 5, 'S', 4.94, '2024-09-20'),
(31, 6, 31, 9, 15, 'XL', 1.22, '2016-03-20'),
(32, 9, 32, 30, 42, 'XS', 6.2, '2022-06-18'),
(33, 8, 33, 46, 26, 'XL', 6.69, '2022-06-28'),
(34, 4, 34, 47, 13, 'XL', 8.49, '2018-09-10'),
(35, 6, 35, 8, 31, 'S', 5.03, '2020-12-10'),
(36, 10, 36, 7, 32, 'XS', 7.44, '2015-01-28'),
(37, 4, 37, 23, 1, 'XS', 2.58, '2023-06-01'),
(38, 1, 38, 2, 26, 'XXL', 4.08, '2024-11-01'),
(39, 19, 39, 20, 17, 'S', 8.19, '2019-03-15'),
(40, 1, 40, 25, 48, 'XL', 8.53, '2025-08-15'),
(41, 2, 41, 35, 14, 'S', 1.58, '2019-11-15'),
(42, 18, 42, 45, 42, 'L', 9.96, '2020-07-12'),
(43, 1, 43, 30, 49, 'M', 2.34, '2021-05-05'),
(44, 5, 44, 50, 12, 'XS', 7.97, '2026-02-10'),
(45, 18, 45, 45, 8, 'S', 2.16, '2024-04-18'),
(46, 7, 46, 40, 14, 'XL', 2.85, '2025-07-01'),
(47, 16, 47, 14, 37, 'XS', 7.17, '2014-09-20'),
(48, 9, 48, 13, 1, 'M', 1.45, '2015-11-05'),
(49, 1, 49, 18, 20, 'S', 3.02, '2018-01-01'),
(51, 16, 51, 5, 15, 'M', 5.5, '2025-02-04'),
(52, 14, 52, 18, 22, 'XXL', 15.5, '2025-02-04'),
(53, 20, 53, 51, 12, 'XXL', 12.5, '2025-02-04'),
(54, 14, 54, 18, 25, 'XXL', 30.15, '2025-02-04'),
(55, 5, 55, 18, 25, 'XXL', 30.15, '2025-02-04');

--
-- Wyzwalacze `zamowienie`
--
DROP TRIGGER IF EXISTS `sprawdz_wage_paczki`;
DELIMITER $$
CREATE TRIGGER `sprawdz_wage_paczki` BEFORE INSERT ON `zamowienie` FOR EACH ROW BEGIN
    IF NEW.waga > 30 OR NEW.waga<=0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Waga paczki musi byc z przedzialu (0;30)';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `zamowienie_produkt`
--

DROP TABLE IF EXISTS `zamowienie_produkt`;
CREATE TABLE `zamowienie_produkt` (
  `ID_produktu` int(11) NOT NULL,
  `ID_zamowienia` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci COMMENT='przypisanie produktu do zamowienia';

--
-- Dumping data for table `zamowienie_produkt`
--

INSERT INTO `zamowienie_produkt` (`ID_produktu`, `ID_zamowienia`) VALUES
(2, 29),
(2, 35),
(4, 43),
(4, 45),
(6, 17),
(6, 38),
(8, 2),
(8, 22),
(8, 26),
(10, 28),
(10, 37),
(11, 8),
(11, 11),
(11, 25),
(11, 40),
(12, 49),
(13, 6),
(13, 40),
(14, 16),
(14, 20),
(14, 24),
(15, 21),
(15, 32),
(15, 33),
(15, 44),
(15, 45),
(16, 7),
(16, 12),
(16, 22),
(16, 47),
(16, 48),
(17, 10),
(17, 11),
(20, 10),
(20, 33),
(20, 48),
(21, 4),
(21, 39),
(21, 52),
(22, 22),
(22, 53),
(22, 54),
(22, 55),
(23, 27),
(23, 45),
(24, 32),
(24, 51),
(25, 14),
(26, 6),
(30, 3),
(31, 1),
(31, 15),
(31, 18),
(32, 7),
(34, 23),
(36, 2),
(36, 5),
(36, 11),
(36, 36),
(37, 31),
(37, 46),
(38, 13),
(38, 28),
(39, 14),
(39, 30),
(39, 36),
(40, 47),
(41, 19),
(43, 7),
(43, 42),
(44, 33),
(46, 3),
(46, 34),
(46, 44),
(47, 9),
(47, 25),
(48, 28),
(48, 49),
(49, 5),
(49, 26),
(49, 41);

-- --------------------------------------------------------

--
-- Struktura widoku `analiza_zamowien_miesieczna`
--
DROP TABLE IF EXISTS `analiza_zamowien_miesieczna`;

DROP VIEW IF EXISTS `analiza_zamowien_miesieczna`;
CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `analiza_zamowien_miesieczna`  AS SELECT date_format(`z`.`data_zlozenia`,'%Y-%m') AS `miesiac`, count(`z`.`ID_zamowienia`) AS `liczba_zamowien`, count(distinct `z`.`ID_odbiorcy`) AS `liczba_unikalnych_klientow`, round(avg(`z`.`waga`),2) AS `srednia_waga`, round(sum(`p`.`cena`),2) AS `laczna_wartosc_produktow`, sum(case when `asz`.`czy_oplacono` = 'TAK' then 1 else 0 end) AS `liczba_oplaconych`, round(sum(case when `asz`.`czy_oplacono` = 'TAK' then 1 else 0 end) * 100.0 / count(`z`.`ID_zamowienia`),2) AS `procent_oplaconych` FROM (((`zamowienie` `z` left join `zamowienie_produkt` `zp` on(`zp`.`ID_zamowienia` = `z`.`ID_zamowienia`)) left join `produkt` `p` on(`p`.`ID_produktu` = `zp`.`ID_produktu`)) left join `aktualny_status_zamowienia` `asz` on(`asz`.`ID_zamowienia` = `z`.`ID_zamowienia`)) GROUP BY date_format(`z`.`data_zlozenia`,'%Y-%m') ORDER BY date_format(`z`.`data_zlozenia`,'%Y-%m') DESC ;

-- --------------------------------------------------------

--
-- Struktura widoku `statystyki_klientow`
--
DROP TABLE IF EXISTS `statystyki_klientow`;

DROP VIEW IF EXISTS `statystyki_klientow`;
CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `statystyki_klientow`  AS SELECT `k`.`ID_klienta` AS `ID_klienta`, `k`.`imie` AS `imie`, `k`.`nazwisko` AS `nazwisko`, count(`z`.`ID_zamowienia`) AS `laczna_ilosc_zamowien`, round(sum(`p`.`cena`),2) AS `laczna_kwota_zamowienia`, round(avg(`p`.`cena`),2) AS `srednia_kwota_produktow`, count(distinct `p`.`ID_produktu`) AS `liczba_unikalnych_produktow`, max(`z`.`data_zlozenia`) AS `najnowsze_zamowienie`, min(`z`.`data_zlozenia`) AS `najstarsze_zamowienie`, timestampdiff(MONTH,min(`z`.`data_zlozenia`),max(`z`.`data_zlozenia`)) AS `ilosc_miesiecy_wspolpracy` FROM ((((`klient` `k` join `zamowienie` `z` on(`k`.`ID_klienta` = `z`.`ID_odbiorcy`)) join `zamowienie_produkt` `zp` on(`z`.`ID_zamowienia` = `zp`.`ID_zamowienia`)) join `cennik` `c` on(`z`.`rozmiar` = `c`.`rozmiar`)) join `produkt` `p` on(`p`.`ID_produktu` = `zp`.`ID_produktu`)) GROUP BY `k`.`ID_klienta` ;

--
-- Indeksy dla zrzutów tabel
--

--
-- Indeksy dla tabeli `aktualny_status_zamowienia`
--
ALTER TABLE `aktualny_status_zamowienia`
  ADD PRIMARY KEY (`ID_zamowienia`);

--
-- Indeksy dla tabeli `auto`
--
ALTER TABLE `auto`
  ADD PRIMARY KEY (`ID_auta`),
  ADD UNIQUE KEY `nr_rej` (`nr_rej`);

--
-- Indeksy dla tabeli `cennik`
--
ALTER TABLE `cennik`
  ADD PRIMARY KEY (`rozmiar`);

--
-- Indeksy dla tabeli `karta_pojazdu`
--
ALTER TABLE `karta_pojazdu`
  ADD PRIMARY KEY (`id_auta`,`nr_prawa_jazdy_kierowcy`),
  ADD KEY `fk_karta_kurier` (`nr_prawa_jazdy_kierowcy`);

--
-- Indeksy dla tabeli `klient`
--
ALTER TABLE `klient`
  ADD PRIMARY KEY (`ID_klienta`);

--
-- Indeksy dla tabeli `kurier`
--
ALTER TABLE `kurier`
  ADD PRIMARY KEY (`ID_kuriera`),
  ADD UNIQUE KEY `nr_prawa_jazdy` (`nr_prawa_jazdy`);

--
-- Indeksy dla tabeli `magazyn`
--
ALTER TABLE `magazyn`
  ADD PRIMARY KEY (`ID_magazynu`);

--
-- Indeksy dla tabeli `paczka`
--
ALTER TABLE `paczka`
  ADD PRIMARY KEY (`id_paczki`),
  ADD KEY `ID_magazynu` (`ID_magazynu`);

--
-- Indeksy dla tabeli `produkt`
--
ALTER TABLE `produkt`
  ADD PRIMARY KEY (`ID_produktu`);

--
-- Indeksy dla tabeli `statystyki_produktow`
--
ALTER TABLE `statystyki_produktow`
  ADD PRIMARY KEY (`ID_produktu`);

--
-- Indeksy dla tabeli `zamowienie`
--
ALTER TABLE `zamowienie`
  ADD PRIMARY KEY (`ID_zamowienia`),
  ADD KEY `ID_kuriera` (`ID_kuriera`),
  ADD KEY `ID_nadawcy` (`ID_nadawcy`),
  ADD KEY `ID_odbiorcy` (`ID_odbiorcy`),
  ADD KEY `nr_magazynowy` (`nr_magazynowy`),
  ADD KEY `rozmiar` (`rozmiar`);

--
-- Indeksy dla tabeli `zamowienie_produkt`
--
ALTER TABLE `zamowienie_produkt`
  ADD PRIMARY KEY (`ID_produktu`,`ID_zamowienia`),
  ADD KEY `ID_zamowienia` (`ID_zamowienia`,`ID_produktu`) USING BTREE;

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `auto`
--
ALTER TABLE `auto`
  MODIFY `ID_auta` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT for table `klient`
--
ALTER TABLE `klient`
  MODIFY `ID_klienta` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=52;

--
-- AUTO_INCREMENT for table `kurier`
--
ALTER TABLE `kurier`
  MODIFY `ID_kuriera` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT for table `magazyn`
--
ALTER TABLE `magazyn`
  MODIFY `ID_magazynu` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `paczka`
--
ALTER TABLE `paczka`
  MODIFY `id_paczki` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=57;

--
-- AUTO_INCREMENT for table `produkt`
--
ALTER TABLE `produkt`
  MODIFY `ID_produktu` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=51;

--
-- AUTO_INCREMENT for table `zamowienie`
--
ALTER TABLE `zamowienie`
  MODIFY `ID_zamowienia` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=57;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `aktualny_status_zamowienia`
--
ALTER TABLE `aktualny_status_zamowienia`
  ADD CONSTRAINT `fk_status_zamowienia_zamowienie` FOREIGN KEY (`ID_zamowienia`) REFERENCES `zamowienie` (`ID_zamowienia`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `karta_pojazdu`
--
ALTER TABLE `karta_pojazdu`
  ADD CONSTRAINT `fk_karta_auto` FOREIGN KEY (`id_auta`) REFERENCES `auto` (`ID_auta`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_karta_kurier` FOREIGN KEY (`nr_prawa_jazdy_kierowcy`) REFERENCES `kurier` (`nr_prawa_jazdy`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `paczka`
--
ALTER TABLE `paczka`
  ADD CONSTRAINT `fk_paczka_magazyn` FOREIGN KEY (`ID_magazynu`) REFERENCES `magazyn` (`ID_magazynu`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `zamowienie`
--
ALTER TABLE `zamowienie`
  ADD CONSTRAINT `fk_zamowienie_cennik` FOREIGN KEY (`rozmiar`) REFERENCES `cennik` (`rozmiar`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_zamowienie_kurier` FOREIGN KEY (`ID_kuriera`) REFERENCES `kurier` (`ID_kuriera`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_zamowienie_nadawca` FOREIGN KEY (`ID_nadawcy`) REFERENCES `klient` (`ID_klienta`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_zamowienie_odbiorca` FOREIGN KEY (`ID_odbiorcy`) REFERENCES `klient` (`ID_klienta`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_zamowienie_paczka` FOREIGN KEY (`nr_magazynowy`) REFERENCES `paczka` (`id_paczki`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `zamowienie_produkt`
--
ALTER TABLE `zamowienie_produkt`
  ADD CONSTRAINT `fk_produkt_zamowienie` FOREIGN KEY (`ID_produktu`) REFERENCES `produkt` (`ID_produktu`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_zamowienie_produkt` FOREIGN KEY (`ID_zamowienia`) REFERENCES `zamowienie` (`ID_zamowienia`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
