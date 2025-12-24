USE XKKBUS;
GO

----------------------------------------------------------------------------------
-- СОЗДАНИЕ ТАБЛИЦ И ПРИМЕНЕНИЕ ТЕХНОЛОГИЙ БЕЗОПАСНОСТИ
----------------------------------------------------------------------------------

-- 1. ТАБЛИЦА Users (Без Dynamic Data Masking)
CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Login NVARCHAR(50) UNIQUE NOT NULL,
    PasswordHash VARBINARY(64) NOT NULL, -- Хранение хэша (SHA2_256)
    Role NVARCHAR(20) CHECK (Role IN ('admin', 'user')) NOT NULL,
    FullName NVARCHAR(100),
    Phone NVARCHAR(15),
    Email NVARCHAR(100),
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- 2. ТАБЛИЦА Routes (Маршруты)
CREATE TABLE Routes (
    RouteID INT IDENTITY(1,1) PRIMARY KEY,
    RouteName NVARCHAR(100) NOT NULL,
    DepartureCity NVARCHAR(50) NOT NULL,
    ArrivalCity NVARCHAR(50) NOT NULL,
    DistanceKM INT CHECK (DistanceKM > 0),
    DurationMinutes INT CHECK (DurationMinutes > 0),
    TotalSeats INT NOT NULL CHECK (TotalSeats BETWEEN 10 AND 60),
    BasePrice DECIMAL(10,2) NOT NULL CHECK (BasePrice > 0)
);
GO

-- 3. ТАБЛИЦА Drivers (С Cell-Level Encryption и DDM для обычных пользователей)
-- DDM применяется к FullName через MASKED WITH
CREATE TABLE Drivers (
    DriverID INT IDENTITY(1,1) PRIMARY KEY,
    -- Полное имя с маскированием через DDM
    FullName NVARCHAR(100) MASKED WITH (FUNCTION = 'partial(1, "XXXX", 0)') NOT NULL,
    -- Cell-Level Encryption: VARBINARY(MAX) для хранения шифра (не показываем обычным пользователям)
    LicenseNumber VARBINARY(MAX) NOT NULL,  
    -- Телефон: полностью видно для обычных пользователей (для связи) - маскирование не применяется
    Phone NVARCHAR(15) NOT NULL,
    ExperienceYears INT CHECK (ExperienceYears >= 0),
    IsActive BIT DEFAULT 1
);
GO

-- 4. ТАБЛИЦА Trips (Рейсы) - с каскадным удалением
-- Измененный фрагмент создания таблицы Trips (Вариант CASCADE)
CREATE TABLE Trips (
    TripID INT IDENTITY(1,1) PRIMARY KEY,
    RouteID INT NOT NULL,
    DriverID INT NOT NULL, 
    TripDate DATE NOT NULL,
    DepartureTime TIME NOT NULL,
    TotalSeats INT NOT NULL,
    BookedSeats INT DEFAULT 0,
    AvailableSeats AS (TotalSeats - BookedSeats) PERSISTED,
    Status NVARCHAR(20) DEFAULT 'planned'
        CHECK (Status IN ('planned', 'in_progress', 'completed', 'cancelled')),
    CONSTRAINT CHK_TripSeats CHECK (TotalSeats BETWEEN 10 AND 60),
    CONSTRAINT FK_Trips_Routes FOREIGN KEY (RouteID) REFERENCES Routes(RouteID) ON DELETE CASCADE,
    -- ИЗМЕНЕНО: теперь CASCADE вместо NO ACTION
    CONSTRAINT FK_Trips_Drivers FOREIGN KEY (DriverID) REFERENCES Drivers(DriverID) ON DELETE CASCADE
);
GO

-- 5. ТАБЛИЦА Bookings (Без Dynamic Data Masking) - с каскадным удалением
CREATE TABLE Bookings (
    BookingID BIGINT IDENTITY(1,1) PRIMARY KEY,
    TripID INT NOT NULL,
    UserID INT NOT NULL,
    SeatNumber INT NOT NULL,
    PassengerPhone NVARCHAR(15),
    BookingTime DATETIME2 DEFAULT SYSDATETIME(),
    IsConfirmed BIT DEFAULT 1,
    IsCancelled BIT DEFAULT 0,
    PricePaid DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_Bookings_Trips FOREIGN KEY (TripID) REFERENCES Trips(TripID) ON DELETE CASCADE,
    CONSTRAINT FK_Bookings_Users FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE NO ACTION
);
GO

-- Создаем фильтрованный уникальный индекс для предотвращения дублирования мест (только для неотмененных)
CREATE UNIQUE NONCLUSTERED INDEX UQ_Booking_Seat_Active 
ON Bookings(TripID, SeatNumber) 
WHERE IsCancelled = 0;
GO

-- Индексы для оптимизации производительности (100k+ строк)
CREATE NONCLUSTERED INDEX IX_Bookings_Trip_Time ON Bookings (TripID, BookingTime) 
INCLUDE (PricePaid, IsConfirmed, IsCancelled);
GO

CREATE NONCLUSTERED INDEX IX_Bookings_User_Cancelled ON Bookings (UserID, IsCancelled) 
INCLUDE (TripID, BookingTime);
GO

CREATE NONCLUSTERED INDEX IX_Trips_Route_Date ON Trips (RouteID, TripDate, Status) 
INCLUDE (DepartureTime, AvailableSeats);
GO

CREATE NONCLUSTERED INDEX IX_Routes_Cities ON Routes (DepartureCity, ArrivalCity) 
INCLUDE (RouteID, BasePrice);
GO

CREATE NONCLUSTERED INDEX IX_Drivers_Active ON Drivers (IsActive) 
INCLUDE (DriverID, FullName);
GO

----------------------------------------------------------------------------------
-- РЕАЛИЗАЦИЯ ШИФРОВАНИЯ НА УРОВНЕ ЯЧЕЕК (CELL-LEVEL ENCRYPTION)
----------------------------------------------------------------------------------

-- Создание Мастер-ключа Базы Данных (DMK)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE symmetric_key_id = 101)
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'XKKBUS_Strong_Password_2025!';
END
GO

-- Создание Сертификата
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'Cert_DriverLicense')
BEGIN
    CREATE CERTIFICATE Cert_DriverLicense WITH SUBJECT = 'Certificate for Driver License Encryption';
END
GO

-- Создание Симметричного Ключа
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'SK_DriverLicense')
BEGIN
    CREATE SYMMETRIC KEY SK_DriverLicense
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE Cert_DriverLicense;
END
GO

SELECT * FROM Users;
SELECT * FROM Bookings;
SELECT * FROM Trips;
SELECT * FROM Drivers;
SELECT * FROM Routes;
DELETE FROM Bookings;
DELETE FROM Trips;
DELETE FROM Drivers;
DELETE FROM Routes;
DELETE FROM Users;
GO

----------------------------------------------------------------------------------
-- УДАЛЕНИЕ ОБЪЕКТОВ (В КОНЦЕ ФАЙЛА)
----------------------------------------------------------------------------------

-- Удаление таблиц (в обратном порядке зависимостей)
IF OBJECT_ID('Bookings', 'U') IS NOT NULL DROP TABLE Bookings;
IF OBJECT_ID('Trips', 'U') IS NOT NULL DROP TABLE Trips;
IF OBJECT_ID('Drivers', 'U') IS NOT NULL DROP TABLE Drivers;
IF OBJECT_ID('Routes', 'U') IS NOT NULL DROP TABLE Routes;
IF OBJECT_ID('Users', 'U') IS NOT NULL DROP TABLE Users;
GO

-- Удаление ключей и сертификатов
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'SK_DriverLicense')
     DROP SYMMETRIC KEY SK_DriverLicense;
 GO
 IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'Cert_DriverLicense')
     DROP CERTIFICATE Cert_DriverLicense;
 GO
 IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE symmetric_key_id = 101)
     DROP MASTER KEY;
 GO
