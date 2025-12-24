USE XKKBUS;
GO


----------------------------------------------------------------------------------
-- ЭКСПОРТ И ИМПОРТ БРОНИРОВАНИЙ 
----------------------------------------------------------------------------------

-- Экспорт бронирований в JSON
IF OBJECT_ID('sp_ExportBookingsToJson', 'P') IS NOT NULL DROP PROCEDURE sp_ExportBookingsToJson;
GO
CREATE PROCEDURE sp_ExportBookingsToJson
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
        B.UserID,
        U.Login AS UserLogin,
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

-- Импорт бронирований из JSON (оптимизированная версия)
IF OBJECT_ID('sp_ImportBookingsFromJson', 'P') IS NOT NULL DROP PROCEDURE sp_ImportBookingsFromJson;
GO
CREATE PROCEDURE sp_ImportBookingsFromJson
    @JsonData NVARCHAR(MAX),
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
    
    IF @JsonData IS NULL OR LEN(LTRIM(RTRIM(@JsonData))) = 0
    BEGIN
        RAISERROR(N'JSON данные не предоставлены.', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
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
        
        -- Загружаем данные из JSON во временную таблицу с ценами
        INSERT INTO #BulkBookings (TripID, UserID, SeatNumber, PassengerPhone, PricePaid)
        SELECT 
            B.TripID,
            B.UserID,
            B.SeatNumber,
            B.PassengerPhone,
            ISNULL(R.BasePrice, 0) AS PricePaid
        FROM OPENJSON(@JsonData, '$.Bookings')
        WITH (
            TripID INT '$.TripID',
            UserID INT '$.UserID',
            SeatNumber INT '$.SeatNumber',
            PassengerPhone NVARCHAR(20) '$.PassengerPhone'
        ) B
        INNER JOIN Trips T ON T.TripID = B.TripID
        INNER JOIN Routes R ON R.RouteID = T.RouteID
        WHERE B.TripID IS NOT NULL
        AND B.UserID IS NOT NULL
        AND B.SeatNumber > 0
        AND B.PassengerPhone IS NOT NULL
        AND EXISTS (SELECT 1 FROM Users WHERE UserID = B.UserID);
        
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
        
        -- Используем процедуру для batch вставки
        DECLARE @InsertedRows INT;
        EXEC sp_BulkInsertBookings @AdminUserID = @AdminUserID, @InsertedRows = @InsertedRows OUTPUT;
        
        -- Обрабатываем отмененные бронирования из JSON (если есть)
        DECLARE @TripID INT;
        DECLARE @UserID INT;
        DECLARE @SeatNumber INT;
        DECLARE @IsCancelled BIT;
        
        DECLARE cancelled_cursor CURSOR FOR
        SELECT
            TripID,
            UserID,
            SeatNumber
        FROM OPENJSON(@JsonData, '$.Bookings')
        WITH (
            TripID INT '$.TripID',
            UserID INT '$.UserID',
            SeatNumber INT '$.SeatNumber',
            IsCancelled BIT '$.IsCancelled'
        )
        WHERE TripID IS NOT NULL
        AND UserID IS NOT NULL
        AND SeatNumber > 0
        AND ISNULL(IsCancelled, 0) = 1;
        
        OPEN cancelled_cursor;
        FETCH NEXT FROM cancelled_cursor INTO @TripID, @UserID, @SeatNumber;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                DECLARE @BookingID BIGINT;
                SELECT @BookingID = BookingID 
                FROM Bookings 
                WHERE TripID = @TripID 
                AND UserID = @UserID 
                AND SeatNumber = @SeatNumber 
                AND IsCancelled = 0;
                
                IF @BookingID IS NOT NULL
                BEGIN
                    EXEC sp_CancelBooking @BookingID, NULL;
                END
            END TRY
            BEGIN CATCH
                -- Игнорируем ошибки
            END CATCH
            
            FETCH NEXT FROM cancelled_cursor INTO @TripID, @UserID, @SeatNumber;
        END
        
        CLOSE cancelled_cursor;
        DEALLOCATE cancelled_cursor;
        
        -- Финальное обновление счетчиков
        UPDATE T
        SET BookedSeats = (
            SELECT COUNT(*)
            FROM Bookings B
            WHERE B.TripID = T.TripID
            AND B.IsCancelled = 0
        )
        FROM Trips T;
        
        DROP TABLE #BulkBookings;
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#BulkBookings') IS NOT NULL DROP TABLE #BulkBookings;
        DECLARE @ErrMsg NVARCHAR(4000);
        SET @ErrMsg = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO

