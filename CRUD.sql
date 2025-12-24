USE XKKBUS;
GO

----------------------------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНАЯ ПРОЦЕДУРА ДЛЯ ПРОВЕРКИ ПРАВ АДМИНИСТРАТОРА
----------------------------------------------------------------------------------

IF OBJECT_ID('sp_CheckAdminRights', 'P') IS NOT NULL DROP PROCEDURE sp_CheckAdminRights;
GO
CREATE PROCEDURE sp_CheckAdminRights
    @UserID INT,
    @IsAdmin BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @IsAdmin = 0;
    
    IF @UserID IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID AND Role = 'admin')
        BEGIN
            SET @IsAdmin = 1;
        END
    END
END
GO

----------------------------------------------------------------------------------
-- ХРАНИМЫЕ ПРОЦЕДУРЫ ДЛЯ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ
----------------------------------------------------------------------------------

-- Регистрация нового пользователя (с валидацией)
IF OBJECT_ID('sp_RegisterUser', 'P') IS NOT NULL DROP PROCEDURE sp_RegisterUser;
GO
CREATE PROCEDURE sp_RegisterUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @FullName NVARCHAR(100),
    @Phone NVARCHAR(20),
    @Email NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация входных данных
    IF @Login IS NULL OR LEN(LTRIM(RTRIM(@Login))) = 0
    BEGIN
        SELECT 0 AS Success, N'Логин не может быть пустым.' AS Message;
        RETURN;
    END
    
    IF @Password IS NULL OR LEN(@Password) < 6
    BEGIN
        SELECT 0 AS Success, N'Пароль должен содержать минимум 6 символов.' AS Message;
        RETURN;
    END
    
    IF @FullName IS NULL OR LEN(LTRIM(RTRIM(@FullName))) = 0
    BEGIN
        SELECT 0 AS Success, N'ФИО не может быть пустым.' AS Message;
        RETURN;
    END
    
    IF @Phone IS NULL OR LEN(LTRIM(RTRIM(@Phone))) = 0
    BEGIN
        SELECT 0 AS Success, N'Телефон не может быть пустым.' AS Message;
        RETURN;
    END
    
    -- Проверка на существующий логин
    IF EXISTS (SELECT 1 FROM Users WHERE Login = @Login)
    BEGIN
        SELECT 0 AS Success, N'Пользователь с таким логином уже существует.' AS Message;
        RETURN;
    END
    
    BEGIN TRY
        INSERT INTO Users (Login, PasswordHash, Role, FullName, Phone, Email)
        VALUES (
            LTRIM(RTRIM(@Login)),
            HASHBYTES('SHA2_256', @Password),
            'user', -- По умолчанию роль 'user'
            @FullName,
            @Phone,
            @Email
        );
        
        SELECT 1 AS Success, N'Пользователь успешно зарегистрирован.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrorMessage AS Message;
    END CATCH
END
GO

-- Аутентификация пользователя
IF OBJECT_ID('sp_AuthenticateUser', 'P') IS NOT NULL DROP PROCEDURE sp_AuthenticateUser;
GO
CREATE PROCEDURE sp_AuthenticateUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация
    IF @Login IS NULL OR @Password IS NULL OR LEN(LTRIM(RTRIM(@Login))) = 0
    BEGIN
        RETURN;
    END
    
    -- Обрезаем пробелы и проверяем пользователя
    -- Хеширование должно быть одинаковым как при создании
    -- Используем точно такой же способ хеширования как в sp_CreateUser
    DECLARE @TrimmedLogin NVARCHAR(50);
    DECLARE @PasswordHash VARBINARY(64);
    
    SET @TrimmedLogin = LTRIM(RTRIM(@Login));
    SET @PasswordHash = HASHBYTES('SHA2_256', @Password);
    
    SELECT 
        UserID, 
        Login, 
        Role, 
        FullName
    FROM Users
    WHERE Login = @TrimmedLogin
    AND PasswordHash = @PasswordHash;
END
GO

-- Создание пользователя (для админа, с валидацией)
IF OBJECT_ID('sp_CreateUser', 'P') IS NOT NULL DROP PROCEDURE sp_CreateUser;
GO
CREATE PROCEDURE sp_CreateUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @Role NVARCHAR(20),
    @FullName NVARCHAR(100),
    @Phone NVARCHAR(20),
    @Email NVARCHAR(100),
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    -- Валидация
    IF @Login IS NULL OR LEN(LTRIM(RTRIM(@Login))) = 0
    BEGIN
        RAISERROR(N'Логин не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @Password IS NULL OR LEN(@Password) < 6
    BEGIN
        RAISERROR(N'Пароль должен содержать минимум 6 символов.', 16, 1);
        RETURN;
    END
    
    IF @Role NOT IN ('admin', 'user')
    BEGIN
        RAISERROR(N'Роль должна быть "admin" или "user".', 16, 1);
        RETURN;
    END
    
    IF EXISTS (SELECT 1 FROM Users WHERE Login = @Login)
    BEGIN
        RAISERROR(N'Пользователь с таким логином уже существует.', 16, 1);
        RETURN;
    END
    
    INSERT INTO Users (Login, PasswordHash, Role, FullName, Phone, Email)
    VALUES (
        LTRIM(RTRIM(@Login)),
        HASHBYTES('SHA2_256', @Password),
        @Role,
        @FullName,
        @Phone,
        @Email
    );
END
GO

-- Алиас для совместимости
IF OBJECT_ID('sp_AddUser', 'P') IS NOT NULL DROP PROCEDURE sp_AddUser;
GO
CREATE PROCEDURE sp_AddUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @Role NVARCHAR(20),
    @FullName NVARCHAR(100),
    @Phone NVARCHAR(20),
    @Email NVARCHAR(100) = NULL
AS
BEGIN
    EXEC sp_CreateUser @Login, @Password, @Role, @FullName, @Phone, @Email;
END
GO

-- Получение списка пользователей (Администратор)
IF OBJECT_ID('sp_GetUsersList_AdminOnly', 'P') IS NOT NULL DROP PROCEDURE sp_GetUsersList_AdminOnly;
GO
CREATE PROCEDURE sp_GetUsersList_AdminOnly
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    SELECT UserID, Login, Role, FullName, Phone, Email, CreatedAt
    FROM Users
    ORDER BY CreatedAt DESC;
END
GO

-- Получение всех пользователей (для админа)
IF OBJECT_ID('sp_GetAllUsers', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllUsers;
GO
CREATE PROCEDURE sp_GetAllUsers
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_GetUsersList_AdminOnly @AdminUserID;
END
GO

-- Обновление пользователя (с валидацией)
IF OBJECT_ID('sp_UpdateUser', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateUser;
GO
CREATE PROCEDURE sp_UpdateUser
    @UserID INT,
    @Login NVARCHAR(50),
    @NewPassword NVARCHAR(128),
    @Role NVARCHAR(20),
    @FullName NVARCHAR(100),
    @Phone NVARCHAR(20),
    @Email NVARCHAR(100),
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID)
    BEGIN
        RAISERROR(N'Пользователь не найден.', 16, 1);
        RETURN;
    END
    
    IF @Login IS NOT NULL AND EXISTS (SELECT 1 FROM Users WHERE Login = @Login AND UserID != @UserID)
    BEGIN
        RAISERROR(N'Пользователь с таким логином уже существует.', 16, 1);
        RETURN;
    END
    
    IF @NewPassword IS NOT NULL AND LEN(@NewPassword) < 6
    BEGIN
        RAISERROR(N'Пароль должен содержать минимум 6 символов.', 16, 1);
        RETURN;
    END
    
    IF @Role IS NOT NULL AND @Role NOT IN ('admin', 'user')
    BEGIN
        RAISERROR(N'Роль должна быть "admin" или "user".', 16, 1);
        RETURN;
    END
    
    UPDATE Users
    SET
        Login = ISNULL(@Login, Login),
        PasswordHash = ISNULL(HASHBYTES('SHA2_256', @NewPassword), PasswordHash),
        Role = ISNULL(@Role, Role),
        FullName = ISNULL(@FullName, FullName),
        Phone = ISNULL(@Phone, Phone),
        Email = ISNULL(@Email, Email)
    WHERE UserID = @UserID;
END
GO

-- Удаление пользователя
IF OBJECT_ID('sp_DeleteUser', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteUser;
GO
CREATE PROCEDURE sp_DeleteUser
    @UserID INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID)
    BEGIN
        RAISERROR(N'Пользователь не найден.', 16, 1);
        RETURN;
    END
    
    -- Проверка на зависимые (не отмененные) бронирования
    IF EXISTS (SELECT 1 FROM Bookings WHERE UserID = @UserID AND IsCancelled = 0)
    BEGIN
        RAISERROR(N'Невозможно удалить пользователя, так как у него есть активные бронирования.', 16, 1);
        RETURN;
    END

    DELETE FROM Users WHERE UserID = @UserID;
END
GO

----------------------------------------------------------------------------------
-- ХРАНИМЫЕ ПРОЦЕДУРЫ ДЛЯ УПРАВЛЕНИЯ ВОДИТЕЛЯМИ
----------------------------------------------------------------------------------

-- Добавление водителя (с шифрованием LicenseNumber и валидацией)
IF OBJECT_ID('sp_AddDriver', 'P') IS NOT NULL DROP PROCEDURE sp_AddDriver;
GO
CREATE PROCEDURE sp_AddDriver
    @FullName NVARCHAR(100),
    @LicenseNumber NVARCHAR(50),
    @Phone NVARCHAR(20),
    @ExperienceYears INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация
    IF @FullName IS NULL OR LEN(LTRIM(RTRIM(@FullName))) = 0
    BEGIN
        RAISERROR(N'ФИО водителя не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @LicenseNumber IS NULL OR LEN(LTRIM(RTRIM(@LicenseNumber))) = 0
    BEGIN
        RAISERROR(N'Номер лицензии не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @Phone IS NULL OR LEN(LTRIM(RTRIM(@Phone))) = 0
    BEGIN
        RAISERROR(N'Телефон не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @ExperienceYears IS NULL OR @ExperienceYears < 0
    BEGIN
        RAISERROR(N'Опыт работы не может быть отрицательным.', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        OPEN SYMMETRIC KEY SK_DriverLicense DECRYPTION BY CERTIFICATE Cert_DriverLicense;
        INSERT INTO Drivers (FullName, LicenseNumber, Phone, ExperienceYears)
        VALUES (
            LTRIM(RTRIM(@FullName)),
            EncryptByKey(Key_GUID('SK_DriverLicense'), @LicenseNumber),
            @Phone,
            @ExperienceYears
        );
        CLOSE SYMMETRIC KEY SK_DriverLicense;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'SK_DriverLicense')
            CLOSE SYMMETRIC KEY SK_DriverLicense;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO

-- Создание водителя (алиас для совместимости с server.js)
IF OBJECT_ID('sp_CreateDriver', 'P') IS NOT NULL DROP PROCEDURE sp_CreateDriver;
GO
CREATE PROCEDURE sp_CreateDriver
    @FullName NVARCHAR(100),
    @LicenseNumber NVARCHAR(50),
    @Phone NVARCHAR(20),
    @ExperienceYears INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            SELECT 0 AS Success, NULL AS ID, N'Доступ запрещен. Требуются права администратора.' AS Message;
            RETURN;
        END
    END
    
    BEGIN TRY
        EXEC sp_AddDriver @FullName, @LicenseNumber, @Phone, @ExperienceYears;
        SELECT 1 AS Success, SCOPE_IDENTITY() AS ID, N'Водитель успешно добавлен.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, NULL AS ID, @ErrMsg AS Message;
    END CATCH
END
GO

-- Получение информации о водителях для обычных пользователей (с ручным маскированием)
-- Применяем маскирование вручную, так как пользователь БД может иметь права UNMASK
IF OBJECT_ID('sp_GetDriversForUser', 'P') IS NOT NULL DROP PROCEDURE sp_GetDriversForUser;
GO
CREATE PROCEDURE sp_GetDriversForUser
AS
BEGIN
    SET NOCOUNT ON;
    -- Обычные пользователи видят:
    -- Телефон полностью (для связи)
    -- Опыт работы полностью
    -- FullName с маскированием: первый символ + "XXXX"
    
    SELECT 
        DriverID,
        -- Применяем маскирование вручную: первый символ + "XXXX"
        CASE 
            WHEN LEN(FullName) > 0 
            THEN LEFT(FullName, 1) + 'XXXX'
            ELSE 'XXXX'
        END AS FullName,
        Phone,     -- Полностью видно
        ExperienceYears, -- Полностью видно
        IsActive
    FROM Drivers
    WHERE IsActive = 1
    ORDER BY FullName;
END
GO

-- Получение всех водителей для админа (с зашифрованной лицензией в виде шифра для демонстрации)
IF OBJECT_ID('sp_GetAllDrivers', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllDrivers;
GO
CREATE PROCEDURE sp_GetAllDrivers
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    -- Админ видит все данные без маскирования (FullName не маскируется для админа)
    -- Включая зашифрованную лицензию в виде шифра (для демонстрации шифрования)
    -- Полная расшифровка только через sp_GetDriverLicenseWithPassword с паролем
    SELECT 
        DriverID,
        FullName,  -- Для админа маскирование не применяется
        Phone,
        ExperienceYears,
        IsActive,
        -- Показываем зашифрованную лицензию в виде hex-строки для демонстрации шифрования
        CASE 
            WHEN LicenseNumber IS NOT NULL 
            THEN '🔒 ENCRYPTED: ' + SUBSTRING(CONVERT(NVARCHAR(MAX), LicenseNumber, 2), 1, 32) + '...'
            ELSE NULL
        END AS LicenseNumber
    FROM Drivers
    ORDER BY FullName;
END
GO

-- Получение лицензии водителя с проверкой пароля админа
IF OBJECT_ID('sp_GetDriverLicenseWithPassword', 'P') IS NOT NULL DROP PROCEDURE sp_GetDriverLicenseWithPassword;
GO
CREATE PROCEDURE sp_GetDriverLicenseWithPassword
    @DriverID INT,
    @AdminPassword NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Проверка существования водителя
    IF NOT EXISTS (SELECT 1 FROM Drivers WHERE DriverID = @DriverID)
    BEGIN
        SELECT 0 AS Success, NULL AS LicenseNumber, N'Водитель не найден.' AS Message;
        RETURN;
    END
    
    -- Проверка пароля админа (ищем любого админа с таким паролем)
    IF NOT EXISTS (
        SELECT 1 FROM Users 
        WHERE Role = 'admin' 
        AND PasswordHash = HASHBYTES('SHA2_256', @AdminPassword)
    )
    BEGIN
        SELECT 0 AS Success, NULL AS LicenseNumber, N'Неверный пароль администратора.' AS Message;
        RETURN;
    END
    
    -- Если пароль верный, расшифровываем лицензию
    BEGIN TRY
        OPEN SYMMETRIC KEY SK_DriverLicense DECRYPTION BY CERTIFICATE Cert_DriverLicense;
        
        SELECT 
            1 AS Success,
            CONVERT(NVARCHAR(50), DecryptByKey(LicenseNumber)) AS LicenseNumber,
            N'Лицензия успешно получена.' AS Message
        FROM Drivers
        WHERE DriverID = @DriverID;
        
        CLOSE SYMMETRIC KEY SK_DriverLicense;
    END TRY
    BEGIN CATCH
        IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'SK_DriverLicense')
            CLOSE SYMMETRIC KEY SK_DriverLicense;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, NULL AS LicenseNumber, @ErrMsg AS Message;
    END CATCH
END
GO

-- Обновление данных водителя (с валидацией)
IF OBJECT_ID('sp_UpdateDriver', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateDriver;
GO
CREATE PROCEDURE sp_UpdateDriver
    @DriverID INT,
    @FullName NVARCHAR(100),
    @LicenseNumber NVARCHAR(50),
    @Phone NVARCHAR(20),
    @ExperienceYears INT,
    @IsActive BIT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    DECLARE @ErrMsg NVARCHAR(4000);
    DECLARE @EncryptedLicense VARBINARY(MAX);
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Drivers WHERE DriverID = @DriverID)
    BEGIN
        RAISERROR(N'Водитель не найден.', 16, 1);
        RETURN;
    END
    
    IF @ExperienceYears IS NOT NULL AND @ExperienceYears < 0
    BEGIN
        RAISERROR(N'Опыт работы не может быть отрицательным.', 16, 1);
        RETURN;
    END
    
    -- Обработка лицензии: шифруем только если передана непустая строка
    IF @LicenseNumber IS NOT NULL AND LEN(LTRIM(RTRIM(@LicenseNumber))) > 0
    BEGIN
        BEGIN TRY
            OPEN SYMMETRIC KEY SK_DriverLicense DECRYPTION BY CERTIFICATE Cert_DriverLicense;
            SET @EncryptedLicense = EncryptByKey(Key_GUID('SK_DriverLicense'), LTRIM(RTRIM(@LicenseNumber)));
            CLOSE SYMMETRIC KEY SK_DriverLicense;
        END TRY
        BEGIN CATCH
            IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'SK_DriverLicense')
                CLOSE SYMMETRIC KEY SK_DriverLicense;
            SET @ErrMsg = ERROR_MESSAGE();
            RAISERROR(@ErrMsg, 16, 1);
            RETURN;
        END CATCH
    END
    ELSE
    BEGIN
        -- Если передана пустая строка или NULL, не обновляем лицензию
        SET @EncryptedLicense = NULL;
    END

    BEGIN TRY
        UPDATE Drivers
        SET
            FullName = ISNULL(LTRIM(RTRIM(@FullName)), FullName),
            LicenseNumber = ISNULL(@EncryptedLicense, LicenseNumber),
            Phone = ISNULL(@Phone, Phone),
            ExperienceYears = ISNULL(@ExperienceYears, ExperienceYears),
            IsActive = ISNULL(@IsActive, IsActive)
        WHERE DriverID = @DriverID;
        
        SELECT 1 AS Success, N'Водитель успешно обновлен.' AS Message;
    END TRY
    BEGIN CATCH
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Удаление водителя
IF OBJECT_ID('sp_DeleteDriver', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteDriver;
GO
CREATE PROCEDURE sp_DeleteDriver
    @DriverID INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Drivers WHERE DriverID = @DriverID)
    BEGIN
        RAISERROR(N'Водитель не найден.', 16, 1);
        RETURN;
    END
   
    DELETE FROM Drivers WHERE DriverID = @DriverID;
END
GO

----------------------------------------------------------------------------------
-- ХРАНИМЫЕ ПРОЦЕДУРЫ ДЛЯ УПРАВЛЕНИЯ МАРШРУТАМИ
----------------------------------------------------------------------------------

-- Добавление маршрута (с валидацией)
IF OBJECT_ID('sp_AddRoute', 'P') IS NOT NULL DROP PROCEDURE sp_AddRoute;
GO
CREATE PROCEDURE sp_AddRoute
    @RouteName NVARCHAR(100),
    @DepartureCity NVARCHAR(50),
    @ArrivalCity NVARCHAR(50),
    @DistanceKM INT,
    @DurationMinutes INT,
    @TotalSeats INT,
    @BasePrice DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация
    IF @RouteName IS NULL OR LEN(LTRIM(RTRIM(@RouteName))) = 0
    BEGIN
        RAISERROR(N'Название маршрута не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @DepartureCity IS NULL OR LEN(LTRIM(RTRIM(@DepartureCity))) = 0
    BEGIN
        RAISERROR(N'Город отправления не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @ArrivalCity IS NULL OR LEN(LTRIM(RTRIM(@ArrivalCity))) = 0
    BEGIN
        RAISERROR(N'Город прибытия не может быть пустым.', 16, 1);
        RETURN;
    END
    
    IF @DepartureCity = @ArrivalCity
    BEGIN
        RAISERROR(N'Город отправления и прибытия не могут совпадать.', 16, 1);
        RETURN;
    END
    
    IF @DistanceKM IS NULL OR @DistanceKM <= 0
    BEGIN
        RAISERROR(N'Расстояние должно быть больше 0.', 16, 1);
        RETURN;
    END
    
    IF @DurationMinutes IS NULL OR @DurationMinutes <= 0
    BEGIN
        RAISERROR(N'Длительность должна быть больше 0.', 16, 1);
        RETURN;
    END
    
    IF @TotalSeats IS NULL OR @TotalSeats < 10 OR @TotalSeats > 60
    BEGIN
        RAISERROR(N'Количество мест должно быть от 10 до 60.', 16, 1);
        RETURN;
    END
    
    IF @BasePrice IS NULL OR @BasePrice <= 0
    BEGIN
        RAISERROR(N'Базовая цена должна быть больше 0.', 16, 1);
        RETURN;
    END
    
    INSERT INTO Routes (RouteName, DepartureCity, ArrivalCity, DistanceKM, DurationMinutes, TotalSeats, BasePrice)
    VALUES (@RouteName, @DepartureCity, @ArrivalCity, @DistanceKM, @DurationMinutes, @TotalSeats, @BasePrice);
END
GO

-- Создание маршрута (алиас для совместимости с server.js)
IF OBJECT_ID('sp_CreateRoute', 'P') IS NOT NULL DROP PROCEDURE sp_CreateRoute;
GO
CREATE PROCEDURE sp_CreateRoute
    @RouteName NVARCHAR(100),
    @DepartureCity NVARCHAR(50),
    @ArrivalCity NVARCHAR(50),
    @DistanceKm INT,
    @DurationMinutes INT,
    @BasePrice DECIMAL(10,2),
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    DECLARE @TotalSeats INT;
    SET @TotalSeats = 50; -- Значение по умолчанию
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            SELECT 0 AS Success, NULL AS ID, N'Доступ запрещен. Требуются права администратора.' AS Message;
            RETURN;
        END
    END
    
    BEGIN TRY
        EXEC sp_AddRoute @RouteName, @DepartureCity, @ArrivalCity, @DistanceKm, @DurationMinutes, @TotalSeats, @BasePrice;
        SELECT 1 AS Success, SCOPE_IDENTITY() AS ID, N'Маршрут успешно добавлен.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, NULL AS ID, @ErrMsg AS Message;
    END CATCH
END
GO

-- Обновление маршрута (с валидацией)
IF OBJECT_ID('sp_UpdateRoute', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateRoute;
GO
CREATE PROCEDURE sp_UpdateRoute
    @RouteID INT,
    @RouteName NVARCHAR(100),
    @DepartureCity NVARCHAR(50),
    @ArrivalCity NVARCHAR(50),
    @DistanceKM INT,
    @DurationMinutes INT,
    @TotalSeats INT,
    @BasePrice DECIMAL(10,2),
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Routes WHERE RouteID = @RouteID)
    BEGIN
        RAISERROR(N'Маршрут не найден.', 16, 1);
        RETURN;
    END
    
    IF (@DepartureCity IS NOT NULL AND @ArrivalCity IS NOT NULL) AND @DepartureCity = @ArrivalCity
    BEGIN
        RAISERROR(N'Город отправления и прибытия не могут совпадать.', 16, 1);
        RETURN;
    END
    
    IF @DistanceKM IS NOT NULL AND @DistanceKM <= 0
    BEGIN
        RAISERROR(N'Расстояние должно быть больше 0.', 16, 1);
        RETURN;
    END
    
    IF @DurationMinutes IS NOT NULL AND @DurationMinutes <= 0
    BEGIN
        RAISERROR(N'Длительность должна быть больше 0.', 16, 1);
        RETURN;
    END
    
    IF @TotalSeats IS NOT NULL AND (@TotalSeats < 10 OR @TotalSeats > 60)
    BEGIN
        RAISERROR(N'Количество мест должно быть от 10 до 60.', 16, 1);
        RETURN;
    END
    
    IF @BasePrice IS NOT NULL AND @BasePrice <= 0
    BEGIN
        RAISERROR(N'Базовая цена должна быть больше 0.', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        UPDATE Routes
        SET
            RouteName = ISNULL(@RouteName, RouteName),
            DepartureCity = ISNULL(@DepartureCity, DepartureCity),
            ArrivalCity = ISNULL(@ArrivalCity, ArrivalCity),
            DistanceKM = ISNULL(@DistanceKM, DistanceKM),
            DurationMinutes = ISNULL(@DurationMinutes, DurationMinutes),
            TotalSeats = ISNULL(@TotalSeats, TotalSeats),
            BasePrice = ISNULL(@BasePrice, BasePrice)
        WHERE RouteID = @RouteID;
        
        SELECT 1 AS Success, N'Маршрут успешно обновлен.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Удаление маршрута
IF OBJECT_ID('sp_DeleteRoute', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteRoute;
GO
CREATE PROCEDURE sp_DeleteRoute
    @RouteID INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Routes WHERE RouteID = @RouteID)
    BEGIN
        RAISERROR(N'Маршрут не найден.', 16, 1);
        RETURN;
    END
    
    -- Каскадное удаление сработает автоматически для Trips и Bookings
    DELETE FROM Routes WHERE RouteID = @RouteID;
END
GO

-- Получение списка маршрутов
IF OBJECT_ID('sp_GetRoutesList', 'P') IS NOT NULL DROP PROCEDURE sp_GetRoutesList;
GO
CREATE PROCEDURE sp_GetRoutesList
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RouteID, RouteName, DepartureCity, ArrivalCity, DistanceKM, DurationMinutes, TotalSeats, BasePrice
    FROM Routes
    ORDER BY DepartureCity, ArrivalCity;
END
GO

-- Получение всех маршрутов (алиас)
IF OBJECT_ID('sp_GetRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_GetRoutes;
GO
CREATE PROCEDURE sp_GetRoutes
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_GetRoutesList;
END
GO

-- Получение всех маршрутов (для админа)
IF OBJECT_ID('sp_GetAllRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllRoutes;
GO
CREATE PROCEDURE sp_GetAllRoutes
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    EXEC sp_GetRoutesList;
END
GO

-- Улучшенный поиск маршрутов с датой (для пользователя) - с информацией о водителе
-- Применяем маскирование вручную для обычных пользователей
IF OBJECT_ID('sp_SearchRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_SearchRoutes;
GO
CREATE PROCEDURE sp_SearchRoutes
    @DepartureCity NVARCHAR(50) = NULL,
    @ArrivalCity NVARCHAR(50) = NULL,
    @TripDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Поиск маршрутов с фильтрацией по городам и дате, включая информацию о водителе (маскированную)
    SELECT DISTINCT
        R.RouteID,
        R.RouteName,
        R.DepartureCity,
        R.ArrivalCity,
        R.DistanceKM,
        R.DurationMinutes,
        R.TotalSeats,
        R.BasePrice,
        T.TripID,
        T.TripDate,
        T.DepartureTime,
        T.AvailableSeats,
        T.Status,
        T.DriverID,
        -- Применяем маскирование вручную: первый символ + "XXXX"
        CASE 
            WHEN LEN(D.FullName) > 0 
            THEN LEFT(D.FullName, 1) + 'XXXX'
            ELSE 'XXXX'
        END AS DriverFullName,
        D.Phone AS DriverPhone,
        D.ExperienceYears AS DriverExperience
    FROM Routes R
    LEFT JOIN Trips T ON R.RouteID = T.RouteID
    LEFT JOIN Drivers D ON T.DriverID = D.DriverID
    WHERE 
        (@DepartureCity IS NULL OR R.DepartureCity LIKE '%' + @DepartureCity + '%')
    AND (@ArrivalCity IS NULL OR R.ArrivalCity LIKE '%' + @ArrivalCity + '%')
    AND (@TripDate IS NULL OR T.TripDate = @TripDate)
    AND (T.Status IS NULL OR T.Status != 'cancelled')
    ORDER BY R.BasePrice, T.TripDate, T.DepartureTime;
END
GO

----------------------------------------------------------------------------------
-- ХРАНИМЫЕ ПРОЦЕДУРЫ ДЛЯ УПРАВЛЕНИЯ РЕЙСАМИ
----------------------------------------------------------------------------------

-- Добавление рейса (с валидацией)
IF OBJECT_ID('sp_AddTrip', 'P') IS NOT NULL DROP PROCEDURE sp_AddTrip;
GO
CREATE PROCEDURE sp_AddTrip
    @RouteID INT,
    @DriverID INT,
    @TripDate DATE,
    @DepartureTime TIME
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация
    IF NOT EXISTS (SELECT 1 FROM Routes WHERE RouteID = @RouteID)
    BEGIN
        RAISERROR(N'Маршрут с указанным RouteID не найден.', 16, 1);
        RETURN;
    END
    
    IF NOT EXISTS (SELECT 1 FROM Drivers WHERE DriverID = @DriverID AND IsActive = 1)
    BEGIN
        RAISERROR(N'Водитель не найден или неактивен.', 16, 1);
        RETURN;
    END
    
    IF @TripDate IS NULL OR @TripDate < CAST(GETDATE() AS DATE)
    BEGIN
        RAISERROR(N'Дата рейса не может быть в прошлом.', 16, 1);
        RETURN;
    END
    
    DECLARE @TotalSeats INT;
    SELECT @TotalSeats = TotalSeats FROM Routes WHERE RouteID = @RouteID;

    INSERT INTO Trips (RouteID, DriverID, TripDate, DepartureTime, TotalSeats)
    VALUES (@RouteID, @DriverID, @TripDate, @DepartureTime, @TotalSeats);
END
GO

-- Создание рейса (алиас для совместимости с server.js)
IF OBJECT_ID('sp_CreateTrip', 'P') IS NOT NULL DROP PROCEDURE sp_CreateTrip;
GO
CREATE PROCEDURE sp_CreateTrip
    @RouteID INT,
    @DriverID INT,
    @BusID INT, -- Не используется, но оставлен для совместимости
    @TripDate DATE,
    @DepartureTime NVARCHAR(8), -- Принимаем как строку для более гибкой обработки
    @TotalSeats INT, -- Не используется, берется из маршрута
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            SELECT 0 AS Success, NULL AS ID, N'Доступ запрещен. Требуются права администратора.' AS Message;
            RETURN;
        END
    END
    
    -- Преобразуем строку времени в TIME тип
    DECLARE @DepartureTimeAsTime TIME;
    BEGIN TRY
        SET @DepartureTimeAsTime = CAST(@DepartureTime AS TIME);
    END TRY
    BEGIN CATCH
        SELECT 0 AS Success, NULL AS ID, N'Неверный формат времени. Ожидается HH:mm:ss' AS Message;
        RETURN;
    END CATCH
    
    BEGIN TRY
        EXEC sp_AddTrip @RouteID, @DriverID, @TripDate, @DepartureTimeAsTime;
        SELECT 1 AS Success, SCOPE_IDENTITY() AS ID, N'Рейс успешно добавлен.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, NULL AS ID, @ErrMsg AS Message;
    END CATCH
END
GO

-- Обновление рейса (с валидацией)
IF OBJECT_ID('sp_UpdateTrip', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateTrip;
GO
CREATE PROCEDURE sp_UpdateTrip
    @TripID INT,
    @RouteID INT,
    @DriverID INT,
    @BusID INT, -- Не используется
    @TripDate DATE,
    @DepartureTime NVARCHAR(8), -- Принимаем как строку для более гибкой обработки
    @TotalSeats INT, -- Не используется, берется из маршрута
    @Status NVARCHAR(20),
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    DECLARE @ErrMsg NVARCHAR(4000);
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Trips WHERE TripID = @TripID)
    BEGIN
        RAISERROR(N'Рейс не найден.', 16, 1);
        RETURN;
    END
    
    IF @RouteID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Routes WHERE RouteID = @RouteID)
    BEGIN
        RAISERROR(N'Маршрут не найден.', 16, 1);
        RETURN;
    END
    
    IF @DriverID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Drivers WHERE DriverID = @DriverID AND IsActive = 1)
    BEGIN
        RAISERROR(N'Водитель не найден или неактивен.', 16, 1);
        RETURN;
    END
    
    IF @Status IS NOT NULL AND @Status NOT IN ('planned', 'in_progress', 'completed', 'cancelled')
    BEGIN
        RAISERROR(N'Неверный статус рейса.', 16, 1);
        RETURN;
    END
    
    DECLARE @NewTotalSeats INT;
    IF @RouteID IS NOT NULL
    BEGIN
        SELECT @NewTotalSeats = TotalSeats FROM Routes WHERE RouteID = @RouteID;
    END

    -- Преобразуем строку времени в TIME тип, если она указана
    DECLARE @DepartureTimeAsTime TIME = NULL;
    IF @DepartureTime IS NOT NULL AND @DepartureTime != ''
    BEGIN
        BEGIN TRY
            SET @DepartureTimeAsTime = CAST(@DepartureTime AS TIME);
        END TRY
        BEGIN CATCH
            RAISERROR(N'Неверный формат времени. Ожидается HH:mm:ss', 16, 1);
            RETURN;
        END CATCH
    END

    BEGIN TRY
        UPDATE Trips
        SET
            RouteID = ISNULL(@RouteID, RouteID),
            DriverID = ISNULL(@DriverID, DriverID),
            TripDate = ISNULL(@TripDate, TripDate),
            DepartureTime = ISNULL(@DepartureTimeAsTime, DepartureTime),
            Status = ISNULL(@Status, Status),
            TotalSeats = ISNULL(@NewTotalSeats, TotalSeats)
        WHERE TripID = @TripID;
        
        SELECT 1 AS Success, N'Рейс успешно обновлен.' AS Message;
    END TRY
    BEGIN CATCH
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Удаление рейса
IF OBJECT_ID('sp_DeleteTrip', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteTrip;
GO
CREATE PROCEDURE sp_DeleteTrip
    @TripID INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF NOT EXISTS (SELECT 1 FROM Trips WHERE TripID = @TripID)
    BEGIN
        RAISERROR(N'Рейс не найден.', 16, 1);
        RETURN;
    END
    
    -- Каскадное удаление сработает автоматически для Bookings
    DELETE FROM Trips WHERE TripID = @TripID;
END
GO

-- Получение рейсов по маршруту
-- Применяем маскирование вручную для обычных пользователей
IF OBJECT_ID('sp_GetTripsByRoute', 'P') IS NOT NULL DROP PROCEDURE sp_GetTripsByRoute;
GO
CREATE PROCEDURE sp_GetTripsByRoute
    @RouteID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        T.TripID,
        T.RouteID,
        R.RouteName,
        T.DriverID,
        -- Применяем маскирование вручную: первый символ + "XXXX"
        CASE 
            WHEN LEN(D.FullName) > 0 
            THEN LEFT(D.FullName, 1) + 'XXXX'
            ELSE 'XXXX'
        END AS DriverName,
        T.TripDate,
        T.DepartureTime,
        T.TotalSeats,
        T.BookedSeats,
        T.AvailableSeats,
        T.Status,
        R.BasePrice
    FROM Trips T
    JOIN Routes R ON T.RouteID = R.RouteID
    JOIN Drivers D ON T.DriverID = D.DriverID
    WHERE T.RouteID = @RouteID
    AND T.Status != 'cancelled'
    ORDER BY T.TripDate, T.DepartureTime;
END
GO

-- Получение всех рейсов (для админа)
IF OBJECT_ID('sp_GetAllTrips', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllTrips;
GO
CREATE PROCEDURE sp_GetAllTrips
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    SELECT 
        T.TripID,
        T.RouteID,
        R.RouteName,
        T.DriverID,
        D.FullName AS DriverName,
        T.TripDate,
        CAST(T.DepartureTime AS NVARCHAR(8)) AS DepartureTime, -- Преобразуем TIME в строку для удобной обработки
        T.TotalSeats,
        T.BookedSeats,
        T.AvailableSeats,
        T.Status
    FROM Trips T
    JOIN Routes R ON T.RouteID = R.RouteID
    JOIN Drivers D ON T.DriverID = D.DriverID
    ORDER BY T.TripDate DESC, T.DepartureTime DESC;
END
GO

-- Проверка доступности мест на рейсе
IF OBJECT_ID('sp_GetTripAvailability', 'P') IS NOT NULL DROP PROCEDURE sp_GetTripAvailability;
GO
CREATE PROCEDURE sp_GetTripAvailability
    @TripID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (SELECT 1 FROM Trips WHERE TripID = @TripID)
    BEGIN
        RETURN;
    END
    
    SELECT 
        BookingID,
        SeatNumber,
        IsCancelled
    FROM Bookings
    WHERE TripID = @TripID
    ORDER BY SeatNumber;
END
GO

-- Поиск свободного водителя на дату/время (для Админа)
IF OBJECT_ID('sp_FindAvailableDriver', 'P') IS NOT NULL DROP PROCEDURE sp_FindAvailableDriver;
GO
CREATE PROCEDURE sp_FindAvailableDriver
    @TripDate DATE,
    @DepartureTime TIME,
    @DurationMinutes INT,
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF @DurationMinutes IS NULL OR @DurationMinutes <= 0
    BEGIN
        RETURN;
    END
    
    DECLARE @NewTripStart DATETIME2 = DATEADD(MINUTE, DATEDIFF(MINUTE, 0, @DepartureTime), CAST(@TripDate AS DATETIME2));
    DECLARE @NewTripEnd DATETIME2 = DATEADD(MINUTE, @DurationMinutes, @NewTripStart);

    SELECT
        D.DriverID,
        D.FullName,
        D.ExperienceYears
    FROM Drivers D
    WHERE D.IsActive = 1
    AND D.DriverID NOT IN (
        SELECT T.DriverID
        FROM Trips T
        JOIN Routes R ON T.RouteID = R.RouteID
        WHERE (T.Status = 'planned' OR T.Status = 'in_progress')
        AND T.TripDate = @TripDate
        AND (
            (@NewTripStart < DATEADD(MINUTE, R.DurationMinutes, DATEADD(MINUTE, DATEDIFF(MINUTE, 0, T.DepartureTime), CAST(T.TripDate AS DATETIME2))))
            AND
            (@NewTripEnd > DATEADD(MINUTE, DATEDIFF(MINUTE, 0, T.DepartureTime), CAST(T.TripDate AS DATETIME2)))
        )
    )
    ORDER BY D.ExperienceYears DESC;
END
GO

----------------------------------------------------------------------------------
-- ХРАНИМЫЕ ПРОЦЕДУРЫ ДЛЯ БРОНИРОВАНИЯ
----------------------------------------------------------------------------------

-- Бронирование билета (с валидацией)
IF OBJECT_ID('sp_BookTicket', 'P') IS NOT NULL DROP PROCEDURE sp_BookTicket;
GO
CREATE PROCEDURE sp_BookTicket
    @TripID INT,
    @UserID INT,
    @SeatNumber INT,
    @PassengerPhone NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Валидация
    IF @PassengerPhone IS NULL OR LEN(LTRIM(RTRIM(@PassengerPhone))) = 0
    BEGIN
        SELECT 0 AS Success, N'Телефон пассажира не может быть пустым.' AS Message;
        RETURN;
    END
    
    IF @SeatNumber IS NULL OR @SeatNumber < 1
    BEGIN
        SELECT 0 AS Success, N'Номер места должен быть больше 0.' AS Message;
        RETURN;
    END
    
    DECLARE @TotalSeats INT;
    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @TripStatus NVARCHAR(20);
    
    SELECT 
        @BasePrice = R.BasePrice,
        @TotalSeats = T.TotalSeats,
        @TripStatus = T.Status
    FROM Trips T 
    JOIN Routes R ON T.RouteID = R.RouteID
    WHERE T.TripID = @TripID;

    IF @BasePrice IS NULL 
    BEGIN 
        SELECT 0 AS Success, N'Рейс не найден.' AS Message;
        RETURN; 
    END
    
    IF @TripStatus = 'cancelled'
    BEGIN
        SELECT 0 AS Success, N'Рейс отменен, бронирование невозможно.' AS Message;
        RETURN;
    END

    IF @SeatNumber > @TotalSeats
    BEGIN
        SELECT 0 AS Success, N'Указано недействительное место для этого рейса.' AS Message;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Bookings WHERE TripID = @TripID AND SeatNumber = @SeatNumber AND IsCancelled = 0)
    BEGIN
        SELECT 0 AS Success, N'Место уже занято.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION
    BEGIN TRY
        INSERT INTO Bookings (TripID, UserID, SeatNumber, PassengerPhone, PricePaid)
        VALUES (@TripID, @UserID, @SeatNumber, @PassengerPhone, @BasePrice);

        UPDATE Trips SET BookedSeats = BookedSeats + 1 WHERE TripID = @TripID;

        COMMIT TRANSACTION;
        SELECT 1 AS Success, N'Билет успешно забронирован.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Просмотр бронирований для конкретного пользователя
IF OBJECT_ID('sp_GetUserBookings', 'P') IS NOT NULL DROP PROCEDURE sp_GetUserBookings;
GO
CREATE PROCEDURE sp_GetUserBookings
    @UserID INT,
    @ShowCancelled BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        B.BookingID,
        T.TripID,
        R.RouteID,
        R.RouteName,
        R.DepartureCity,
        R.ArrivalCity,
        T.TripDate,
        T.DepartureTime,
        B.SeatNumber,
        B.PassengerPhone,
        B.PricePaid,
        B.IsCancelled
    FROM Bookings B
    JOIN Trips T ON B.TripID = T.TripID
    JOIN Routes R ON T.RouteID = R.RouteID
    WHERE B.UserID = @UserID
    AND (@ShowCancelled = 1 OR B.IsCancelled = 0)
    ORDER BY T.TripDate, T.DepartureTime;
END
GO

-- Отмена бронирования (транзакционная)
IF OBJECT_ID('sp_CancelBooking', 'P') IS NOT NULL DROP PROCEDURE sp_CancelBooking;
GO
CREATE PROCEDURE sp_CancelBooking
    @BookingID BIGINT,
    @UserID INT = NULL -- NULL для админа, значение для пользователя
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TripID INT;
    DECLARE @IsCancelled BIT;
    DECLARE @ActualUserID INT;
    
    SELECT 
        @TripID = TripID, 
        @IsCancelled = IsCancelled,
        @ActualUserID = UserID
    FROM Bookings 
    WHERE BookingID = @BookingID;
    
    IF @TripID IS NULL
    BEGIN
        SELECT 0 AS Success, N'Бронирование не найдено.' AS Message;
        RETURN;
    END

    IF @UserID IS NOT NULL AND @ActualUserID != @UserID
    BEGIN
        SELECT 0 AS Success, N'Вы не являетесь владельцем этого бронирования.' AS Message;
        RETURN;
    END

    IF @IsCancelled = 1
    BEGIN
        SELECT 0 AS Success, N'Это бронирование уже отменено.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION
    BEGIN TRY
        UPDATE Bookings
        SET IsCancelled = 1
        WHERE BookingID = @BookingID;

        UPDATE Trips
        SET BookedSeats = CASE WHEN BookedSeats > 0 THEN BookedSeats - 1 ELSE 0 END
        WHERE TripID = @TripID;

        COMMIT TRANSACTION;
        SELECT 1 AS Success, N'Бронирование успешно отменено.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Удаление бронирования администратором (полное удаление из БД)
IF OBJECT_ID('sp_DeleteBooking', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteBooking;
GO
CREATE PROCEDURE sp_DeleteBooking
    @BookingID BIGINT,
    @AdminUserID INT -- ID администратора для проверки прав
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    DECLARE @TripID INT;
    DECLARE @IsCancelled BIT;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            SELECT 0 AS Success, N'Доступ запрещен. Требуются права администратора.' AS Message;
            RETURN;
        END
    END
    
    -- Получаем информацию о бронировании
    SELECT 
        @TripID = TripID, 
        @IsCancelled = IsCancelled
    FROM Bookings 
    WHERE BookingID = @BookingID;
    
    IF @TripID IS NULL
    BEGIN
        SELECT 0 AS Success, N'Бронирование не найдено.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION
    BEGIN TRY
        -- Удаляем бронирование
        DELETE FROM Bookings
        WHERE BookingID = @BookingID;

        -- Обновляем счетчик забронированных мест в рейсе
        -- Уменьшаем только если бронирование не было отменено ранее
        IF @IsCancelled = 0
        BEGIN
            UPDATE Trips
            SET BookedSeats = CASE WHEN BookedSeats > 0 THEN BookedSeats - 1 ELSE 0 END
            WHERE TripID = @TripID;
        END

        COMMIT TRANSACTION;
        SELECT 1 AS Success, N'Бронирование успешно удалено.' AS Message;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        SELECT 0 AS Success, @ErrMsg AS Message;
    END CATCH
END
GO

-- Получение всех бронирований (для админа)
IF OBJECT_ID('sp_GetAllBookings', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllBookings;
GO
CREATE PROCEDURE sp_GetAllBookings
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    SELECT 
        B.BookingID,
        B.TripID,
        T.RouteID,
        R.RouteName,
        T.TripDate,
        T.DepartureTime,
        B.UserID,
        U.Login AS UserLogin,
        U.FullName AS UserFullName,
        B.SeatNumber,
        B.PassengerPhone,
        B.BookingTime,
        B.PricePaid,
        B.IsCancelled
    FROM Bookings B
    JOIN Trips T ON B.TripID = T.TripID
    JOIN Routes R ON T.RouteID = R.RouteID
    JOIN Users U ON B.UserID = U.UserID
    ORDER BY B.BookingTime DESC;
END
GO

----------------------------------------------------------------------------------
-- АНАЛИТИЧЕСКИЕ ПРОЦЕДУРЫ
----------------------------------------------------------------------------------

-- Аналитика по маршрутам (для админа)
IF OBJECT_ID('sp_GetRouteAnalysis', 'P') IS NOT NULL DROP PROCEDURE sp_GetRouteAnalysis;
GO
CREATE PROCEDURE sp_GetRouteAnalysis
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    SELECT 
        R.RouteID,
        R.RouteName,
        R.DepartureCity,
        R.ArrivalCity,
        COUNT(DISTINCT T.TripID) AS TotalTrips,
        COUNT(CASE WHEN B.IsCancelled = 0 THEN B.BookingID END) AS ActiveBookings,
        COUNT(B.BookingID) AS TotalBookings,
        SUM(CASE WHEN B.IsCancelled = 0 THEN B.PricePaid ELSE 0 END) AS TotalRevenue,
        AVG(CASE WHEN B.IsCancelled = 0 THEN CAST(B.PricePaid AS FLOAT) ELSE NULL END) AS AvgBookingPrice,
        R.BasePrice,
        R.TotalSeats,
        SUM(CASE WHEN B.IsCancelled = 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT T.TripID) * R.TotalSeats, 0) AS OccupancyRate
    FROM Routes R
    LEFT JOIN Trips T ON R.RouteID = T.RouteID
    LEFT JOIN Bookings B ON T.TripID = B.TripID
    GROUP BY R.RouteID, R.RouteName, R.DepartureCity, R.ArrivalCity, R.BasePrice, R.TotalSeats
    ORDER BY TotalRevenue DESC;
END
GO

-- Получение общей статистики по системе (для админа)
IF OBJECT_ID('sp_GetSystemStatistics', 'P') IS NOT NULL DROP PROCEDURE sp_GetSystemStatistics;
GO
CREATE PROCEDURE sp_GetSystemStatistics
    @AdminUserID INT -- ID администратора для проверки прав (NULL если не требуется проверка)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IsAdmin BIT;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    SELECT 
        ISNULL((SELECT COUNT(*) FROM Routes), 0) AS TotalRoutes,
        ISNULL((SELECT COUNT(*) FROM Trips WHERE Status != 'cancelled'), 0) AS ActiveTrips,
        ISNULL((SELECT COUNT(*) FROM Bookings WHERE IsCancelled = 0), 0) AS ActiveBookings,
        ISNULL((SELECT COUNT(*) FROM Bookings), 0) AS TotalBookings,
        ISNULL((SELECT SUM(PricePaid) FROM Bookings WHERE IsCancelled = 0), 0) AS TotalRevenue,
        ISNULL((SELECT COUNT(*) FROM Users WHERE Role = 'user'), 0) AS TotalUsers,
        ISNULL((SELECT COUNT(*) FROM Drivers WHERE IsActive = 1), 0) AS ActiveDrivers;
END
GO

-- Массовая вставка бронирований (упрощенная и быстрая версия)
IF OBJECT_ID('sp_BulkInsertBookings', 'P') IS NOT NULL 
    DROP PROCEDURE sp_BulkInsertBookings;
GO

CREATE PROCEDURE sp_BulkInsertBookings
    @AdminUserID INT,
    @InsertedRows INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @IsAdmin BIT;
    DECLARE @ErrMsg NVARCHAR(4000);
    
    SET @InsertedRows = 0;
    SET @IsAdmin = 0;
    
    -- Проверка прав администратора
    IF @AdminUserID IS NOT NULL
    BEGIN
        EXEC sp_CheckAdminRights @AdminUserID, @IsAdmin OUTPUT;
        IF @IsAdmin = 0
        BEGIN
            RAISERROR(N'Доступ запрещен. Требуются права администратора.', 16, 1);
            RETURN;
        END
    END
    
    IF OBJECT_ID('tempdb..#BulkBookings') IS NULL
    BEGIN
        RAISERROR(N'Временная таблица #BulkBookings не найдена.', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        -- Простая массовая вставка
        INSERT INTO Bookings (TripID, UserID, SeatNumber, PassengerPhone, PricePaid, IsCancelled)
        SELECT 
            BB.TripID,
            BB.UserID,
            BB.SeatNumber,
            BB.PassengerPhone,
            BB.PricePaid,
            0
        FROM #BulkBookings BB
        WHERE NOT EXISTS (
            SELECT 1 
            FROM Bookings B 
            WHERE B.TripID = BB.TripID 
            AND B.SeatNumber = BB.SeatNumber 
            AND B.IsCancelled = 0
        );
        
        SET @InsertedRows = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        -- Игнорируем ошибки дубликатов
        IF ERROR_NUMBER() = 2601 OR ERROR_NUMBER() = 2627
        BEGIN
            SET @InsertedRows = 0;
        END
        ELSE
        BEGIN
            SET @ErrMsg = ERROR_MESSAGE();
            RAISERROR(@ErrMsg, 16, 1);
        END
    END CATCH
END
GO

----------------------------------------------------------------------------------
-- УДАЛЕНИЕ ПРОЦЕДУР (В КОНЦЕ ФАЙЛА)
----------------------------------------------------------------------------------

-- Раскомментируйте для удаления процедур при необходимости:
/*
IF OBJECT_ID('sp_RegisterUser', 'P') IS NOT NULL DROP PROCEDURE sp_RegisterUser;
IF OBJECT_ID('sp_AuthenticateUser', 'P') IS NOT NULL DROP PROCEDURE sp_AuthenticateUser;
IF OBJECT_ID('sp_CreateUser', 'P') IS NOT NULL DROP PROCEDURE sp_CreateUser;
IF OBJECT_ID('sp_AddUser', 'P') IS NOT NULL DROP PROCEDURE sp_AddUser;
IF OBJECT_ID('sp_GetUsersList_AdminOnly', 'P') IS NOT NULL DROP PROCEDURE sp_GetUsersList_AdminOnly;
IF OBJECT_ID('sp_GetAllUsers', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllUsers;
IF OBJECT_ID('sp_UpdateUser', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateUser;
IF OBJECT_ID('sp_DeleteUser', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteUser;
IF OBJECT_ID('sp_AddDriver', 'P') IS NOT NULL DROP PROCEDURE sp_AddDriver;
IF OBJECT_ID('sp_CreateDriver', 'P') IS NOT NULL DROP PROCEDURE sp_CreateDriver;
IF OBJECT_ID('sp_GetDriversForUser', 'P') IS NOT NULL DROP PROCEDURE sp_GetDriversForUser;
IF OBJECT_ID('sp_GetAllDrivers', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllDrivers;
IF OBJECT_ID('sp_GetDriverLicenseWithPassword', 'P') IS NOT NULL DROP PROCEDURE sp_GetDriverLicenseWithPassword;
IF OBJECT_ID('sp_UpdateDriver', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateDriver;
IF OBJECT_ID('sp_DeleteDriver', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteDriver;
IF OBJECT_ID('sp_AddRoute', 'P') IS NOT NULL DROP PROCEDURE sp_AddRoute;
IF OBJECT_ID('sp_CreateRoute', 'P') IS NOT NULL DROP PROCEDURE sp_CreateRoute;
IF OBJECT_ID('sp_UpdateRoute', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateRoute;
IF OBJECT_ID('sp_DeleteRoute', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteRoute;
IF OBJECT_ID('sp_GetRoutesList', 'P') IS NOT NULL DROP PROCEDURE sp_GetRoutesList;
IF OBJECT_ID('sp_GetRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_GetRoutes;
IF OBJECT_ID('sp_GetAllRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllRoutes;
IF OBJECT_ID('sp_SearchRoutes', 'P') IS NOT NULL DROP PROCEDURE sp_SearchRoutes;
IF OBJECT_ID('sp_AddTrip', 'P') IS NOT NULL DROP PROCEDURE sp_AddTrip;
IF OBJECT_ID('sp_CreateTrip', 'P') IS NOT NULL DROP PROCEDURE sp_CreateTrip;
IF OBJECT_ID('sp_UpdateTrip', 'P') IS NOT NULL DROP PROCEDURE sp_UpdateTrip;
IF OBJECT_ID('sp_DeleteTrip', 'P') IS NOT NULL DROP PROCEDURE sp_DeleteTrip;
IF OBJECT_ID('sp_GetTripsByRoute', 'P') IS NOT NULL DROP PROCEDURE sp_GetTripsByRoute;
IF OBJECT_ID('sp_GetAllTrips', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllTrips;
IF OBJECT_ID('sp_GetTripAvailability', 'P') IS NOT NULL DROP PROCEDURE sp_GetTripAvailability;
IF OBJECT_ID('sp_FindAvailableDriver', 'P') IS NOT NULL DROP PROCEDURE sp_FindAvailableDriver;
IF OBJECT_ID('sp_BookTicket', 'P') IS NOT NULL DROP PROCEDURE sp_BookTicket;
IF OBJECT_ID('sp_GetUserBookings', 'P') IS NOT NULL DROP PROCEDURE sp_GetUserBookings;
IF OBJECT_ID('sp_CancelBooking', 'P') IS NOT NULL DROP PROCEDURE sp_CancelBooking;
IF OBJECT_ID('sp_GetAllBookings', 'P') IS NOT NULL DROP PROCEDURE sp_GetAllBookings;
IF OBJECT_ID('sp_GetRouteAnalysis', 'P') IS NOT NULL DROP PROCEDURE sp_GetRouteAnalysis;
IF OBJECT_ID('sp_GetSystemStatistics', 'P') IS NOT NULL DROP PROCEDURE sp_GetSystemStatistics;
GO
*/
