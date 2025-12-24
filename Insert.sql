    USE XKKBUS;
GO

----------------------------------------------------------------------------------
-- ОЧИСТКА ДАННЫХ И СБРОС СЧЕТЧИКОВ
-- Примечание: Для очистки используются прямые DELETE, так как это служебная операция
-- Все вставки данных выполняются только через хранимые процедуры
----------------------------------------------------------------------------------

-- Получаем ID админа для использования в процедурах (если существует)
DECLARE @AdminUserID INT;
SET @AdminUserID = NULL;
SELECT TOP 1 @AdminUserID = UserID FROM Users WHERE Role = 'admin';

-- Очистка данных (служебная операция)
DELETE FROM Bookings;
DELETE FROM Trips;
DELETE FROM Drivers;
DELETE FROM Routes;
DELETE FROM Users;
GO

DBCC CHECKIDENT ('Bookings', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('Trips', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('Drivers', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('Routes', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('Users', RESEED, 0) WITH NO_INFOMSGS;
GO

----------------------------------------------------------------------------------
-- ВСТАВКА БАЗОВЫХ ДАННЫХ
----------------------------------------------------------------------------------

-- 1. Сначала создаем ПЕРВОГО админа напрямую (это исключение для инициализации системы)
INSERT INTO Users (Login, PasswordHash, Role, FullName, Phone, Email)
VALUES ('admin', HASHBYTES('SHA2_256', 'admin123'), 'admin', N'Главный Админ', '+375290000000', 'admin@bus.by');

-- 2. Теперь получаем его ID
DECLARE @RealAdminID INT;
SELECT @RealAdminID = UserID FROM Users WHERE Login = 'admin';

-- 3. Всех остальных пользователей создаем уже ЧЕРЕЗ процедуру, передавая @RealAdminID
EXEC sp_CreateUser 
    @Login = 'admin2', 
    @Password = 'admin123', 
    @Role = 'admin', 
    @FullName = N'Второй Админ', 
    @Phone = N'+375291234567', 
    @Email = 'admin2@bus.by', 
    @AdminUserID = @RealAdminID; -- Теперь здесь валидный ID
GO
-- Создаем админа через процедуру (с правильным хешированием)
DECLARE @AdminUserID INT;
SET @AdminUserID = NULL;
EXEC sp_CreateUser @Login = 'admin', @Password = 'admin123', @Role = 'admin', @FullName = N'Иванов Иван Иванович', @Phone = N'+375291234567', @Email = 'admin@bus.by', @AdminUserID = @AdminUserID;
GO

-- Получаем ID созданного админа для последующих операций
DECLARE @AdminUserID INT;
SELECT @AdminUserID = UserID FROM Users WHERE Login = 'admin' AND Role = 'admin';
GO

-- Остальные пользователи (используем процедуры с проверкой прав админа)
-- Создаем 500 пользователей для оптимизации распределения бронирований
DECLARE @AdminUserID INT;
SELECT @AdminUserID = UserID FROM Users WHERE Login = 'admin' AND Role = 'admin';

-- Русские имена и фамилии для генерации пользователей
DECLARE @LastNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @LastNames (Name) VALUES 
    (N'Иванов'), (N'Петров'), (N'Сидоров'), (N'Смирнов'), (N'Козлов'), (N'Волков'), (N'Лебедев'), (N'Новиков'),
    (N'Морозов'), (N'Павлов'), (N'Соколов'), (N'Михайлов'), (N'Федоров'), (N'Васильев'), (N'Семенов'), (N'Голов'),
    (N'Андреев'), (N'Александров'), (N'Леонидов'), (N'Романов'), (N'Дмитриев'), (N'Сергеев'), (N'Николаев'), (N'Викторов');

DECLARE @FirstNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @FirstNames (Name) VALUES 
    (N'Александр'), (N'Дмитрий'), (N'Максим'), (N'Сергей'), (N'Андрей'), (N'Алексей'), (N'Артем'), (N'Иван'),
    (N'Михаил'), (N'Никита'), (N'Роман'), (N'Егор'), (N'Кирилл'), (N'Владимир'), (N'Павел'), (N'Антон'),
    (N'Виктор'), (N'Игорь'), (N'Олег'), (N'Юрий'), (N'Денис'), (N'Станислав'), (N'Вадим'), (N'Григорий');

DECLARE @MiddleNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @MiddleNames (Name) VALUES 
    (N'Александрович'), (N'Дмитриевич'), (N'Сергеевич'), (N'Андреевич'), (N'Алексеевич'), (N'Иванович'), (N'Михайлович'),
    (N'Николаевич'), (N'Петрович'), (N'Владимирович'), (N'Викторович'), (N'Олегович'), (N'Юрьевич'), (N'Романович'),
    (N'Павлович'), (N'Антонович'), (N'Игоревич'), (N'Денисович'), (N'Станиславович'), (N'Вадимович');

DECLARE @UserCounter INT = 1;
DECLARE @TotalUsers INT = 500; -- Создаем 500 пользователей

WHILE @UserCounter <= @TotalUsers
BEGIN
    DECLARE @LastName NVARCHAR(50);
    DECLARE @FirstName NVARCHAR(50);
    DECLARE @MiddleName NVARCHAR(50);
    DECLARE @FullName NVARCHAR(100);
    DECLARE @Login NVARCHAR(50) = 'user' + CAST(@UserCounter AS NVARCHAR(10));
    DECLARE @Phone NVARCHAR(20);
    
    -- Выбираем случайные имена
    SELECT @LastName = Name FROM @LastNames WHERE ID = ((@UserCounter - 1) % (SELECT COUNT(*) FROM @LastNames)) + 1;
    SELECT @FirstName = Name FROM @FirstNames WHERE ID = ((@UserCounter * 3) % (SELECT COUNT(*) FROM @FirstNames)) + 1;
    SELECT @MiddleName = Name FROM @MiddleNames WHERE ID = ((@UserCounter * 5) % (SELECT COUNT(*) FROM @MiddleNames)) + 1;
    
    SET @FullName = @LastName + ' ' + @FirstName + ' ' + @MiddleName;
    
    -- Генерируем белорусский телефон
    DECLARE @PhonePrefix NVARCHAR(6) = CASE ((@UserCounter - 1) % 4)
        WHEN 0 THEN N'+37529'
        WHEN 1 THEN N'+37533'
        WHEN 2 THEN N'+37544'
        ELSE N'+37525'
    END;
    DECLARE @PhoneSuffix INT = 1000000 + ((@UserCounter - 1) * 12345) % 9000000;
    DECLARE @PhoneSuffixStr VARCHAR(7) = RIGHT('0000000' + CAST(@PhoneSuffix AS VARCHAR(7)), 7);
    SET @Phone = @PhonePrefix + SUBSTRING(@PhoneSuffixStr, 1, 3) + SUBSTRING(@PhoneSuffixStr, 4, 2) + SUBSTRING(@PhoneSuffixStr, 6, 2);
    
    -- Формируем email
    DECLARE @Email NVARCHAR(100) = @Login + N'@mail.by';
    
    BEGIN TRY
        EXEC sp_CreateUser 
            @Login = @Login, 
            @Password = 'user123', 
            @Role = 'user', 
            @FullName = @FullName, 
            @Phone = @Phone, 
            @Email = @Email, 
            @AdminUserID = @AdminUserID;
    END TRY
    BEGIN CATCH
        -- Игнорируем ошибки дублирования
    END CATCH
    
    SET @UserCounter = @UserCounter + 1;
    
    -- Выводим прогресс каждые 100 пользователей
    IF @UserCounter % 100 = 0
    BEGIN
        PRINT N'Создано пользователей: ' + CAST(@UserCounter - 1 AS NVARCHAR(10));
    END
END
GO

-- Водители (используем процедуры с проверкой прав админа)
-- Создаем 50 водителей для лучшего распределения рейсов
DECLARE @AdminUserID INT;
SELECT @AdminUserID = UserID FROM Users WHERE Login = 'admin' AND Role = 'admin';

-- Базовые водители
EXEC sp_CreateDriver @FullName = N'Смирнов Андрей Владимирович', @LicenseNumber = 'BY12345678', @Phone = N'+375291111222', @ExperienceYears = 5, @AdminUserID = @AdminUserID;
EXEC sp_CreateDriver @FullName = N'Козлов Дмитрий Петрович', @LicenseNumber = 'BY87654321', @Phone = N'+375292222333', @ExperienceYears = 8, @AdminUserID = @AdminUserID;
EXEC sp_CreateDriver @FullName = N'Петров Михаил Сергеевич', @LicenseNumber = 'BY11223344', @Phone = N'+375293333444', @ExperienceYears = 12, @AdminUserID = @AdminUserID;
EXEC sp_CreateDriver @FullName = N'Иванов Александр Олегович', @LicenseNumber = 'BY55667788', @Phone = N'+375294444555', @ExperienceYears = 3, @AdminUserID = @AdminUserID;
EXEC sp_CreateDriver @FullName = N'Соколов Алексей Дмитриевич', @LicenseNumber = 'BY99887766', @Phone = N'+375295555666', @ExperienceYears = 15, @AdminUserID = @AdminUserID;
EXEC sp_CreateDriver @FullName = N'Новиков Игорь Викторович', @LicenseNumber = 'BY44332211', @Phone = N'+375296666777', @ExperienceYears = 7, @AdminUserID = @AdminUserID;

-- Дополнительные водители (генерируем через цикл)
DECLARE @DriverCounter INT = 7;
DECLARE @TotalDrivers INT = 50; -- Всего 50 водителей

-- Списки для генерации имен водителей
DECLARE @DriverLastNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @DriverLastNames (Name) VALUES 
    (N'Волков'), (N'Лебедев'), (N'Морозов'), (N'Павлов'), (N'Михайлов'), (N'Федоров'), (N'Васильев'), (N'Семенов'),
    (N'Голов'), (N'Андреев'), (N'Александров'), (N'Леонидов'), (N'Романов'), (N'Дмитриев'), (N'Сергеев'), (N'Николаев'),
    (N'Викторов'), (N'Максимов'), (N'Антонов'), (N'Ильин'), (N'Тарасов'), (N'Филиппов'), (N'Степанов'), (N'Орлов'),
    (N'Григорьев'), (N'Борисов'), (N'Кузнецов'), (N'Попов'), (N'Соколов'), (N'Новиков'), (N'Морозов'), (N'Петров');

DECLARE @DriverFirstNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @DriverFirstNames (Name) VALUES 
    (N'Александр'), (N'Дмитрий'), (N'Максим'), (N'Сергей'), (N'Андрей'), (N'Алексей'), (N'Артем'), (N'Иван'),
    (N'Михаил'), (N'Никита'), (N'Роман'), (N'Егор'), (N'Кирилл'), (N'Владимир'), (N'Павел'), (N'Антон'),
    (N'Виктор'), (N'Игорь'), (N'Олег'), (N'Юрий'), (N'Денис'), (N'Станислав'), (N'Вадим'), (N'Григорий'),
    (N'Константин'), (N'Артур'), (N'Руслан'), (N'Тимур'), (N'Даниил'), (N'Матвей'), (N'Илья'), (N'Федор');

DECLARE @DriverMiddleNames TABLE (ID INT IDENTITY(1,1), Name NVARCHAR(50));
INSERT INTO @DriverMiddleNames (Name) VALUES 
    (N'Александрович'), (N'Дмитриевич'), (N'Сергеевич'), (N'Андреевич'), (N'Алексеевич'), (N'Иванович'), (N'Михайлович'),
    (N'Николаевич'), (N'Петрович'), (N'Владимирович'), (N'Викторович'), (N'Олегович'), (N'Юрьевич'), (N'Романович'),
    (N'Павлович'), (N'Антонович'), (N'Игоревич'), (N'Денисович'), (N'Станиславович'), (N'Вадимович'), (N'Григорьевич'),
    (N'Константинович'), (N'Артурович'), (N'Русланович'), (N'Тимурович'), (N'Даниилович'), (N'Матвеевич'), (N'Ильич'), (N'Федорович');

WHILE @DriverCounter <= @TotalDrivers
BEGIN
    DECLARE @DriverLastName NVARCHAR(50);
    DECLARE @DriverFirstName NVARCHAR(50);
    DECLARE @DriverMiddleName NVARCHAR(50);
    DECLARE @DriverFullName NVARCHAR(100);
    DECLARE @DriverLicense NVARCHAR(20) = 'BY' + RIGHT('00000000' + CAST((10000000 + @DriverCounter * 12345) % 100000000 AS NVARCHAR(8)), 8);
    DECLARE @DriverPhone NVARCHAR(20);
    DECLARE @DriverExp INT = (ABS(CHECKSUM(NEWID())) % 20) + 1; -- Опыт от 1 до 20 лет
    
    -- Выбираем случайные имена
    SELECT @DriverLastName = Name FROM @DriverLastNames WHERE ID = ((@DriverCounter - 1) % (SELECT COUNT(*) FROM @DriverLastNames)) + 1;
    SELECT @DriverFirstName = Name FROM @DriverFirstNames WHERE ID = ((@DriverCounter * 3) % (SELECT COUNT(*) FROM @DriverFirstNames)) + 1;
    SELECT @DriverMiddleName = Name FROM @DriverMiddleNames WHERE ID = ((@DriverCounter * 5) % (SELECT COUNT(*) FROM @DriverMiddleNames)) + 1;
    
    SET @DriverFullName = @DriverLastName + N' ' + @DriverFirstName + N' ' + @DriverMiddleName;
    
    -- Генерируем белорусский телефон
    DECLARE @DriverPhonePrefix NVARCHAR(6) = CASE ((@DriverCounter - 1) % 4)
        WHEN 0 THEN N'+37529'
        WHEN 1 THEN N'+37533'
        WHEN 2 THEN N'+37544'
        ELSE N'+37525'
    END;
    DECLARE @DriverPhoneSuffix INT = 1000000 + ((@DriverCounter - 1) * 23456) % 9000000;
    DECLARE @DriverPhoneSuffixStr VARCHAR(7) = RIGHT('0000000' + CAST(@DriverPhoneSuffix AS VARCHAR(7)), 7);
    SET @DriverPhone = @DriverPhonePrefix + SUBSTRING(@DriverPhoneSuffixStr, 1, 3) + SUBSTRING(@DriverPhoneSuffixStr, 4, 2) + SUBSTRING(@DriverPhoneSuffixStr, 6, 2);
    
    BEGIN TRY
        EXEC sp_CreateDriver 
            @FullName = @DriverFullName, 
            @LicenseNumber = @DriverLicense, 
            @Phone = @DriverPhone, 
            @ExperienceYears = @DriverExp, 
            @AdminUserID = @AdminUserID;
    END TRY
    BEGIN CATCH
        -- Игнорируем ошибки дублирования
    END CATCH
    
    SET @DriverCounter = @DriverCounter + 1;
    
    -- Выводим прогресс каждые 10 водителей
    IF @DriverCounter % 10 = 0
    BEGIN
        PRINT N'Создано водителей: ' + CAST(@DriverCounter - 1 AS NVARCHAR(10));
    END
END
GO

-- Маршруты (используем процедуры с проверкой прав админа) - белорусские города на русском языке
DECLARE @AdminUserID INT;
SELECT @AdminUserID = UserID FROM Users WHERE Login = 'admin' AND Role = 'admin';

-- Сохраняем ID сразу после создания маршрутов
DECLARE @RouteID1 INT;
DECLARE @RouteID2 INT;
DECLARE @RouteID3 INT;
DECLARE @RouteID4 INT;
DECLARE @RouteID5 INT;
DECLARE @RouteID6 INT;
DECLARE @RouteID7 INT;
DECLARE @RouteID8 INT;

DECLARE @RouteResult TABLE (ID INT);

EXEC sp_CreateRoute @RouteName = N'Минск - Гомель', @DepartureCity = N'Минск', @ArrivalCity = N'Гомель', @DistanceKm = 310, @DurationMinutes = 300, @BasePrice = 25.00, @AdminUserID = @AdminUserID;
SELECT @RouteID1 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Гомель';

EXEC sp_CreateRoute @RouteName = N'Минск - Витебск', @DepartureCity = N'Минск', @ArrivalCity = N'Витебск', @DistanceKm = 280, @DurationMinutes = 270, @BasePrice = 22.00, @AdminUserID = @AdminUserID;
SELECT @RouteID2 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Витебск';

EXEC sp_CreateRoute @RouteName = N'Минск - Гродно', @DepartureCity = N'Минск', @ArrivalCity = N'Гродно', @DistanceKm = 280, @DurationMinutes = 270, @BasePrice = 22.00, @AdminUserID = @AdminUserID;
SELECT @RouteID3 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Гродно';

EXEC sp_CreateRoute @RouteName = N'Гомель - Минск', @DepartureCity = N'Гомель', @ArrivalCity = N'Минск', @DistanceKm = 310, @DurationMinutes = 300, @BasePrice = 25.00, @AdminUserID = @AdminUserID;
SELECT @RouteID4 = MAX(RouteID) FROM Routes WHERE RouteName = N'Гомель - Минск';

EXEC sp_CreateRoute @RouteName = N'Минск - Брест', @DepartureCity = N'Минск', @ArrivalCity = N'Брест', @DistanceKm = 350, @DurationMinutes = 330, @BasePrice = 28.00, @AdminUserID = @AdminUserID;
SELECT @RouteID5 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Брест';

EXEC sp_CreateRoute @RouteName = N'Минск - Могилев', @DepartureCity = N'Минск', @ArrivalCity = N'Могилев', @DistanceKm = 200, @DurationMinutes = 180, @BasePrice = 18.00, @AdminUserID = @AdminUserID;
SELECT @RouteID6 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Могилев';

EXEC sp_CreateRoute @RouteName = N'Минск - Бобруйск', @DepartureCity = N'Минск', @ArrivalCity = N'Бобруйск', @DistanceKm = 150, @DurationMinutes = 120, @BasePrice = 15.00, @AdminUserID = @AdminUserID;
SELECT @RouteID7 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Бобруйск';

EXEC sp_CreateRoute @RouteName = N'Минск - Барановичи', @DepartureCity = N'Минск', @ArrivalCity = N'Барановичи', @DistanceKm = 140, @DurationMinutes = 110, @BasePrice = 14.00, @AdminUserID = @AdminUserID;
SELECT @RouteID8 = MAX(RouteID) FROM Routes WHERE RouteName = N'Минск - Барановичи';
GO

-- Рейсы (создаем рейсы на разные даты) - используем прямой INSERT для скорости
DECLARE @RouteID1 INT;
DECLARE @RouteID2 INT;
DECLARE @RouteID3 INT;
DECLARE @RouteID4 INT;
DECLARE @RouteID5 INT;
DECLARE @RouteID6 INT;
DECLARE @RouteID7 INT;
DECLARE @RouteID8 INT;

DECLARE @StartDate DATE;
DECLARE @DateOffset INT;
DECLARE @CurrentDate DATE;

-- Получаем ID маршрутов один раз
SELECT @RouteID1 = RouteID FROM Routes WHERE RouteName = N'Минск - Гомель';
SELECT @RouteID2 = RouteID FROM Routes WHERE RouteName = N'Минск - Витебск';
SELECT @RouteID3 = RouteID FROM Routes WHERE RouteName = N'Минск - Гродно';
SELECT @RouteID4 = RouteID FROM Routes WHERE RouteName = N'Гомель - Минск';
SELECT @RouteID5 = RouteID FROM Routes WHERE RouteName = N'Минск - Брест';
SELECT @RouteID6 = RouteID FROM Routes WHERE RouteName = N'Минск - Могилев';
SELECT @RouteID7 = RouteID FROM Routes WHERE RouteName = N'Минск - Бобруйск';
SELECT @RouteID8 = RouteID FROM Routes WHERE RouteName = N'Минск - Барановичи';

-- Создаем временную таблицу с ID всех активных водителей для быстрого доступа
IF OBJECT_ID('tempdb..#ActiveDrivers') IS NOT NULL DROP TABLE #ActiveDrivers;
SELECT DriverID, ROW_NUMBER() OVER (ORDER BY DriverID) AS RowNum
INTO #ActiveDrivers
FROM Drivers
WHERE IsActive = 1;

DECLARE @TotalDriversCount INT = (SELECT COUNT(*) FROM #ActiveDrivers);

SET @StartDate = CAST(GETDATE() AS DATE);
SET @DateOffset = 0;

SET @StartDate = CAST(GETDATE() AS DATE);
SET @DateOffset = 0;

-- Получаем TotalSeats для каждого маршрута один раз
DECLARE @TotalSeats1 INT;
DECLARE @TotalSeats2 INT;
DECLARE @TotalSeats3 INT;
DECLARE @TotalSeats4 INT;
DECLARE @TotalSeats5 INT;
DECLARE @TotalSeats6 INT;
DECLARE @TotalSeats7 INT;
DECLARE @TotalSeats8 INT;

SELECT @TotalSeats1 = TotalSeats FROM Routes WHERE RouteID = @RouteID1;
SELECT @TotalSeats2 = TotalSeats FROM Routes WHERE RouteID = @RouteID2;
SELECT @TotalSeats3 = TotalSeats FROM Routes WHERE RouteID = @RouteID3;
SELECT @TotalSeats4 = TotalSeats FROM Routes WHERE RouteID = @RouteID4;
SELECT @TotalSeats5 = TotalSeats FROM Routes WHERE RouteID = @RouteID5;
SELECT @TotalSeats6 = TotalSeats FROM Routes WHERE RouteID = @RouteID6;
SELECT @TotalSeats7 = TotalSeats FROM Routes WHERE RouteID = @RouteID7;
SELECT @TotalSeats8 = TotalSeats FROM Routes WHERE RouteID = @RouteID8;

-- Генерируем рейсы на 90 дней (для генерации 100000+ бронирований) - используем прямой INSERT для скорости
-- Используем случайных водителей из всех доступных для лучшего распределения
WHILE @DateOffset < 90
BEGIN
    SET @CurrentDate = DATEADD(DAY, @DateOffset, @StartDate);
    
    -- Функция для получения случайного водителя
    DECLARE @GetRandomDriver INT;
    SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
    
    -- Используем прямой INSERT для массовой генерации (в реальном приложении используются процедуры)
    -- Рейсы по маршруту 1 (Минск - Гомель) - 4 рейса в день
    IF @RouteID1 IS NOT NULL AND @TotalSeats1 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID1, @GetRandomDriver, @CurrentDate, '06:00:00', @TotalSeats1, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID1, @GetRandomDriver, @CurrentDate, '10:00:00', @TotalSeats1, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID1, @GetRandomDriver, @CurrentDate, '14:00:00', @TotalSeats1, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID1, @GetRandomDriver, @CurrentDate, '18:00:00', @TotalSeats1, 0, 'planned');
    END
    
    -- Рейсы по маршруту 2 (Минск - Витебск) - 4 рейса в день
    IF @RouteID2 IS NOT NULL AND @TotalSeats2 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID2, @GetRandomDriver, @CurrentDate, '07:00:00', @TotalSeats2, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID2, @GetRandomDriver, @CurrentDate, '11:00:00', @TotalSeats2, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID2, @GetRandomDriver, @CurrentDate, '15:00:00', @TotalSeats2, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID2, @GetRandomDriver, @CurrentDate, '19:00:00', @TotalSeats2, 0, 'planned');
    END
    
    -- Рейсы по маршруту 3 (Минск - Гродно) - 3 рейса в день
    IF @RouteID3 IS NOT NULL AND @TotalSeats3 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID3, @GetRandomDriver, @CurrentDate, '08:00:00', @TotalSeats3, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID3, @GetRandomDriver, @CurrentDate, '13:00:00', @TotalSeats3, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID3, @GetRandomDriver, @CurrentDate, '17:00:00', @TotalSeats3, 0, 'planned');
    END
    
    -- Рейсы по маршруту 4 (Гомель - Минск) - 3 рейса в день
    IF @RouteID4 IS NOT NULL AND @TotalSeats4 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID4, @GetRandomDriver, @CurrentDate, '09:00:00', @TotalSeats4, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID4, @GetRandomDriver, @CurrentDate, '12:00:00', @TotalSeats4, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID4, @GetRandomDriver, @CurrentDate, '16:00:00', @TotalSeats4, 0, 'planned');
    END
    
    -- Рейсы по маршруту 5 (Минск - Брест) - 4 рейса в день
    IF @RouteID5 IS NOT NULL AND @TotalSeats5 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID5, @GetRandomDriver, @CurrentDate, '05:00:00', @TotalSeats5, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID5, @GetRandomDriver, @CurrentDate, '10:00:00', @TotalSeats5, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID5, @GetRandomDriver, @CurrentDate, '15:00:00', @TotalSeats5, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID5, @GetRandomDriver, @CurrentDate, '20:00:00', @TotalSeats5, 0, 'planned');
    END
    
    -- Рейсы по маршруту 6 (Минск - Могилев) - 3 рейса в день
    IF @RouteID6 IS NOT NULL AND @TotalSeats6 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID6, @GetRandomDriver, @CurrentDate, '06:30:00', @TotalSeats6, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID6, @GetRandomDriver, @CurrentDate, '12:30:00', @TotalSeats6, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID6, @GetRandomDriver, @CurrentDate, '18:30:00', @TotalSeats6, 0, 'planned');
    END
    
    -- Рейсы по маршруту 7 (Минск - Бобруйск) - 3 рейса в день
    IF @RouteID7 IS NOT NULL AND @TotalSeats7 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID7, @GetRandomDriver, @CurrentDate, '07:30:00', @TotalSeats7, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID7, @GetRandomDriver, @CurrentDate, '13:30:00', @TotalSeats7, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID7, @GetRandomDriver, @CurrentDate, '19:30:00', @TotalSeats7, 0, 'planned');
    END
    
    -- Рейсы по маршруту 8 (Минск - Барановичи) - 3 рейса в день
    IF @RouteID8 IS NOT NULL AND @TotalSeats8 IS NOT NULL AND @TotalDriversCount > 0
    BEGIN
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID8, @GetRandomDriver, @CurrentDate, '08:30:00', @TotalSeats8, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID8, @GetRandomDriver, @CurrentDate, '14:30:00', @TotalSeats8, 0, 'planned');
        
        SET @GetRandomDriver = (SELECT TOP 1 DriverID FROM #ActiveDrivers ORDER BY NEWID());
        INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats, BookedSeats, Status)
        VALUES (@RouteID8, @GetRandomDriver, @CurrentDate, '20:30:00', @TotalSeats8, 0, 'planned');
    END
    
    SET @DateOffset = @DateOffset + 1;
    
    -- Выводим прогресс каждые 15 дней
    IF @DateOffset % 15 = 0
BEGIN
        PRINT N'Создано рейсов за ' + CAST(@DateOffset AS NVARCHAR(10)) + N' дней';
    END
END

-- Очищаем временную таблицу
DROP TABLE #ActiveDrivers;
GO

----------------------------------------------------------------------------------
-- ГЕНЕРАЦИЯ 100000 БРОНИРОВАНИЙ (УПРОЩЕННАЯ БЫСТРАЯ ВЕРСИЯ)
----------------------------------------------------------------------------------

PRINT N'Начало генерации 100000 бронирований...';
DECLARE @StartTime DATETIME;
SET @StartTime = GETDATE();

-- Получаем ID админа
DECLARE @AdminUserID INT;
SELECT @AdminUserID = UserID FROM Users WHERE Login = 'admin' AND Role = 'admin';

-- Получаем информацию о рейсах с ценами
IF OBJECT_ID('tempdb..#TripInfo') IS NOT NULL DROP TABLE #TripInfo;
SELECT 
    T.TripID,
    T.TotalSeats,
    R.BasePrice
INTO #TripInfo
FROM Trips T
JOIN Routes R ON T.RouteID = R.RouteID;

CREATE CLUSTERED INDEX IX_TripInfo_TripID ON #TripInfo(TripID);

-- Получаем диапазоны
DECLARE @MinTripID INT;
DECLARE @MaxTripID INT;
DECLARE @MinUserID INT;
DECLARE @MaxUserID INT;
DECLARE @TotalTrips INT;
DECLARE @TotalUsers INT;

SELECT @MinTripID = MIN(TripID) FROM #TripInfo;
SELECT @MaxTripID = MAX(TripID) FROM #TripInfo;
SELECT @MinUserID = MIN(UserID) FROM Users WHERE Role = 'user';
SELECT @MaxUserID = MAX(UserID) FROM Users WHERE Role = 'user';
SET @TotalTrips = @MaxTripID - @MinTripID + 1;
SET @TotalUsers = @MaxUserID - @MinUserID + 1;

-- Создаем временную таблицу для batch вставки
IF OBJECT_ID('tempdb..#BulkBookings') IS NOT NULL DROP TABLE #BulkBookings;
CREATE TABLE #BulkBookings (
    TripID INT NOT NULL,
    UserID INT NOT NULL,
    SeatNumber INT NOT NULL,
    PassengerPhone NVARCHAR(20) NOT NULL,
    PricePaid DECIMAL(10,2) NOT NULL,
    INDEX IX_Bulk_Trip_Seat (TripID, SeatNumber)
);

-- Параметры
DECLARE @TotalRows INT;
DECLARE @BatchSize INT;
DECLARE @TotalInserted INT;
DECLARE @CurrentBatch INT;

SET @TotalRows = 100000;
SET @BatchSize = 20000;
SET @TotalInserted = 0;
SET @CurrentBatch = 0;

-- Генерируем и вставляем батчами
WHILE @TotalInserted < @TotalRows
BEGIN
    SET @CurrentBatch = @CurrentBatch + 1;
    TRUNCATE TABLE #BulkBookings;
    
    -- Простая генерация данных
    INSERT INTO #BulkBookings (TripID, UserID, SeatNumber, PassengerPhone, PricePaid)
    SELECT TOP (@BatchSize * 2) -- Генерируем больше для учета дубликатов
        TI.TripID,
        @MinUserID + (ABS(CHECKSUM(NEWID())) % @TotalUsers) AS UserID,
        (ABS(CHECKSUM(NEWID())) % TI.TotalSeats) + 1 AS SeatNumber,
        N'+37529' + RIGHT('0000000' + CAST(ABS(CHECKSUM(NEWID())) % 10000000 AS VARCHAR(7)), 7) AS PassengerPhone,
        TI.BasePrice AS PricePaid
    FROM #TripInfo TI
    CROSS JOIN (SELECT TOP 1000 1 AS n FROM sys.objects) AS Multiplier
    ORDER BY NEWID();
    
    -- Удаляем дубликаты из временной таблицы
    WITH Duplicates AS (
        SELECT TripID, SeatNumber,
               ROW_NUMBER() OVER (PARTITION BY TripID, SeatNumber ORDER BY (SELECT NULL)) AS rn
        FROM #BulkBookings
    )
    DELETE FROM #BulkBookings
    WHERE EXISTS (
        SELECT 1 FROM Duplicates D
        WHERE D.TripID = #BulkBookings.TripID
        AND D.SeatNumber = #BulkBookings.SeatNumber
        AND D.rn > 1
    );
    
    -- Вставляем через процедуру
    BEGIN TRY
        DECLARE @InsertedInBatch INT;
        EXEC sp_BulkInsertBookings @AdminUserID = @AdminUserID, @InsertedRows = @InsertedInBatch OUTPUT;
        
        SET @TotalInserted = @TotalInserted + ISNULL(@InsertedInBatch, 0);
        
        IF @CurrentBatch % 1 = 0
            PRINT N'Вставлено: ' + CAST(@TotalInserted AS NVARCHAR(10)) + N' / ' + CAST(@TotalRows AS NVARCHAR(10));
        
        IF @TotalInserted >= @TotalRows BREAK;
    END TRY
    BEGIN CATCH
        -- Игнорируем ошибки, продолжаем
    END CATCH
END

-- Обновляем счетчики один раз в конце
UPDATE T
SET BookedSeats = (SELECT COUNT(*) FROM Bookings B WHERE B.TripID = T.TripID AND B.IsCancelled = 0)
FROM Trips T;

DECLARE @EndTime DATETIME;
DECLARE @Duration INT;

SET @EndTime = GETDATE();
SET @Duration = DATEDIFF(SECOND, @StartTime, @EndTime);
PRINT N'Готово! Вставлено: ' + CAST(@TotalInserted AS NVARCHAR(10)) + N', Время: ' + CAST(@Duration AS NVARCHAR(10)) + N' сек';

DROP TABLE #BulkBookings;
DROP TABLE #TripInfo;
GO

PRINT N'Вставка данных завершена успешно.';
GO
