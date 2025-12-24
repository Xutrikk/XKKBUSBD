const express = require('express');
const sql = require('mssql');
const cors = require('cors');

const app = express();
const port = 3001;

// --- КОНФИГУРАЦИЯ БАЗЫ ДАННЫХ (ЗАМЕНИТЕ НА СВОИ ДАННЫЕ!) ---


const dbConfig= {
    user: 'NodeUser', 
    password: '12345', 
    server: 'DESKTOP-DMJJTUE',
    database: 'XKKBUS', 
    pool: { max: 10, min: 4, idleTimeoutMillis: 30000 },
    options: {
        trustServerCertificate: true,
        enableArithAbort: true,
        requestTimeout: 60000, // 60 секунд для больших запросов
    },
    connectionTimeout: 30000
};

// --- MIDDLEWARE ---
app.use(cors()); // Разрешаем запросы с фронтенда (React по умолчанию на 3000/5173)
// Увеличиваем лимит для импорта больших JSON файлов (100000+ строк)
app.use(express.json({ limit: '100mb' })); // Для парсинга JSON-тел запросов
app.use(express.urlencoded({ extended: true, limit: '100mb' })); // Для form-data

// --- ХЕЛПЕР ДЛЯ ВЫПОЛНЕНИЯ ХРАНИМЫХ ПРОЦЕДУР ---

/**
 * Выполняет хранимую процедуру с заданными входными параметрами.
 * @param {string} procedureName Имя хранимой процедуры.
 * @param {Array<{name: string, type: any, value: any}>} inputParameters Массив параметров.
 * @returns {Promise<any>} Результат выполнения процедуры.
 */
// Глобальный пул подключений
let pool = null;

// Инициализация подключения к БД
async function initDatabase() {
    try {
        pool = await sql.connect(dbConfig);
        console.log('   Успешное подключение к базе данных XKKBUS');
        console.log(`   Сервер: ${dbConfig.server}`);
        console.log(`   База данных: ${dbConfig.database}`);
        console.log(`   Пользователь: ${dbConfig.user}`);
        return true;
    } catch (err) {
        console.error('❌ Ошибка подключения к базе данных:', err.message);
        throw err;
    }
}

async function executeProcedure(procedureName, inputParameters = []) {
    try {
        // Используем существующий пул или создаем новый
        if (!pool) {
            await initDatabase();
        }
        
        const request = pool.request();
        
        // Увеличиваем таймаут для запросов (особенно для больших таблиц)
        request.timeout = 60000; // 60 секунд

        // Добавляем входные параметры
        for (const param of inputParameters) {
            // Используем тип sql.Int, sql.NVarChar и т.д.
            request.input(param.name, param.type, param.value);
        }

        // Выполняем хранимую процедуру
        const result = await request.execute(procedureName);
        
        // Возвращаем первую таблицу данных (если есть)
        return result.recordsets[0]; 

    } catch (err) {
        console.error(`Ошибка при выполнении SP ${procedureName}:`, err);
        // Добавляем сообщение об ошибке из SQL, если доступно
        const errorMessage = err.originalError ? err.originalError.info.message : err.message;
        throw new Error(`SQL Error: ${errorMessage}`);
    }
}


// =========================================================================
// --- A. АУТЕНТИФИКАЦИЯ (АВТОРИЗАЦИЯ И РЕГИСТРАЦИЯ) ---
// =========================================================================

// POST /api/register
app.post('/api/register', async (req, res) => {
    const { login, password, fullName, phone, email } = req.body;

    const inputs = [
        { name: 'Login', type: sql.NVarChar(50), value: login },
        { name: 'Password', type: sql.NVarChar(128), value: password }, // Пароль должен быть хэширован в SP
        { name: 'FullName', type: sql.NVarChar(100), value: fullName },
        { name: 'Phone', type: sql.NVarChar(20), value: phone },
        { name: 'Email', type: sql.NVarChar(100), value: email || null },
    ];

    try {
        // Предполагается, что sp_RegisterUser возвращает ID или статус
        const result = await executeProcedure('sp_RegisterUser', inputs);
        
        if (result && result.length > 0 && result[0].Success) {
            return res.json({ success: true, message: 'Пользователь успешно зарегистрирован.' });
        } else {
             // Возврат ошибки, если SP не вернула Success=1
            return res.status(400).json({ success: false, message: result[0].Message || 'Ошибка регистрации.' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// POST /api/login
app.post('/api/login', async (req, res) => {
    const { login, password } = req.body;

    const inputs = [
        { name: 'Login', type: sql.NVarChar(50), value: login },
        { name: 'Password', type: sql.NVarChar(128), value: password }
    ];

    try {
        const result = await executeProcedure('sp_AuthenticateUser', inputs);
        
        if (result && result.length === 1 && result[0].UserID) {
            // Результат должен содержать все необходимые данные пользователя, включая Role
            const user = result[0];
            return res.json({ success: true, user });
        } else {
            return res.status(401).json({ success: false, message: 'Неверный логин или пароль.' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// =========================================================================
// --- B. КЛИЕНТСКИЙ ФУНКЦИОНАЛ (ПОИСК И БРОНИРОВАНИЕ) ---
// =========================================================================

// GET /api/routes - Получить список всех маршрутов (для получения списка городов)
app.get('/api/routes', async (req, res) => {
    try {
        const routes = await executeProcedure('sp_GetAllRoutes', [{ name: 'AdminUserID', type: sql.Int, value: null }]);
        res.json(routes);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// GET /api/routes/search - Поиск маршрутов по городам и дате (обязательные параметры: откуда, куда, дата)
app.get('/api/routes/search', async (req, res) => {
    const { departureCity, arrivalCity, tripDate } = req.query;
    
    // Валидация: все параметры обязательны
    if (!departureCity || !arrivalCity || !tripDate) {
        return res.status(400).json({ 
            success: false, 
            message: 'Необходимо указать: откуда (departureCity), куда (arrivalCity) и дату (tripDate).' 
        });
    }
    
    // Валидация даты: нельзя выбрать прошедшую дату
    const selectedDate = new Date(tripDate);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    selectedDate.setHours(0, 0, 0, 0);
    
    if (selectedDate < today) {
        return res.status(400).json({ 
            success: false, 
            message: 'Нельзя выбрать прошедшую дату.' 
        });
    }
    
    try {
        const inputs = [
            { name: 'DepartureCity', type: sql.NVarChar(50), value: departureCity },
            { name: 'ArrivalCity', type: sql.NVarChar(50), value: arrivalCity },
            { name: 'TripDate', type: sql.Date, value: tripDate }
        ];
        const routes = await executeProcedure('sp_SearchRoutes', inputs);
        
        // Если ничего не найдено, возвращаем специальное сообщение
        if (!routes || routes.length === 0) {
            return res.json({ 
                success: false, 
                message: 'По вашему запросу ничего не найдено. Попробуйте изменить параметры поиска.',
                routes: [] 
            });
        }
        
        res.json({ success: true, routes });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// GET /api/drivers - Получить информацию о водителях (для обычных пользователей - маскирование)
app.get('/api/drivers', async (req, res) => {
    try {
        const drivers = await executeProcedure('sp_GetDriversForUser');
        res.json(drivers);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// GET /api/trips/:routeId - Получить рейсы по маршруту
app.get('/api/trips/:routeId', async (req, res) => {
    const routeId = parseInt(req.params.routeId);
    if (isNaN(routeId)) return res.status(400).json({ message: 'Неверный ID маршрута.' });

    const inputs = [
        { name: 'RouteID', type: sql.Int, value: routeId }
    ];

    try {
        const trips = await executeProcedure('sp_GetTripsByRoute', inputs);
        res.json(trips);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// GET /api/trip-availability/:tripId - Получить занятые места для рейса
app.get('/api/trip-availability/:tripId', async (req, res) => {
    const tripId = parseInt(req.params.tripId);
    if (isNaN(tripId)) return res.status(400).json({ message: 'Неверный ID рейса.' });

    const inputs = [
        { name: 'TripID', type: sql.Int, value: tripId }
    ];

    try {
        // Предполагается, что sp_GetTripAvailability возвращает SeatNumber и IsCancelled
        const seats = await executeProcedure('sp_GetTripAvailability', inputs); 
        res.json(seats);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// POST /api/book-ticket - Забронировать билет
app.post('/api/book-ticket', async (req, res) => {
    const { tripId, userId, seatNumber, passengerPhone } = req.body;

    const inputs = [
        { name: 'TripID', type: sql.Int, value: tripId },
        { name: 'UserID', type: sql.Int, value: userId },
        { name: 'SeatNumber', type: sql.Int, value: seatNumber },
        { name: 'PassengerPhone', type: sql.NVarChar(20), value: passengerPhone },
    ];

    try {
        // Предполагается, что sp_BookTicket обрабатывает транзакцию и проверку
        const result = await executeProcedure('sp_BookTicket', inputs); 
        
        if (result && result.length > 0 && result[0].Success) {
            return res.json({ success: true, message: 'Бронирование успешно!' });
        } else {
            // Возврат ошибки, если SP не вернула Success=1 (например, место занято)
            return res.status(400).json({ success: false, message: result[0].Message || 'Не удалось забронировать билет.' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// GET /api/user-bookings/:userId - Получить заказы пользователя
app.get('/api/user-bookings/:userId', async (req, res) => {
    const userId = parseInt(req.params.userId);
    if (isNaN(userId)) return res.status(400).json({ message: 'Неверный ID пользователя.' });

    const inputs = [
        { name: 'UserID', type: sql.Int, value: userId }
    ];

    try {
        const bookings = await executeProcedure('sp_GetUserBookings', inputs);
        res.json(bookings);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});

// DELETE /api/cancel-booking/:id - Отменить бронирование (для пользователя)
app.delete('/api/cancel-booking/:id', async (req, res) => {
    const bookingId = parseInt(req.params.id);
    // userId передается в query параметре (для DELETE запросов тело может быть недоступно)
    const userId = parseInt(req.query.userId || (req.body && req.body.userId) || 0);
    
    if (isNaN(bookingId)) return res.status(400).json({ success: false, message: 'Неверный ID бронирования.' });
    if (isNaN(userId) || userId === 0) return res.status(400).json({ success: false, message: 'Неверный ID пользователя.' });

    const inputs = [
        { name: 'BookingID', type: sql.BigInt, value: bookingId },
        { name: 'UserID', type: sql.Int, value: userId }
    ];

    try {
        const result = await executeProcedure('sp_CancelBooking', inputs);
        
        // Процедура возвращает Success через SELECT
        if (result && result.length > 0) {
            if (result[0].Success === 1 || result[0].Success === true) {
                return res.json({ success: true, message: result[0].Message || 'Бронирование успешно отменено.' });
            } else {
                return res.status(400).json({ success: false, message: result[0].Message || 'Ошибка отмены бронирования.' });
            }
        }
        return res.json({ success: true, message: 'Бронирование успешно отменено.' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});


// =========================================================================
// --- C. АДМИН-ФУНКЦИОНАЛ (CRUD + ОТМЕНА БРОНИРОВАНИЯ) ---
// =========================================================================
// Замечание: Все эти процедуры должны быть защищены проверкой Role='admin' в SP

// -------------------------------------------------------------------------
// C.1. ЧТЕНИЕ ДАННЫХ ДЛЯ АДМИНА (GET /api/admin/:tableName)
// -------------------------------------------------------------------------

app.get('/api/admin/:tableName', async (req, res) => {
    const tableName = req.params.tableName.toLowerCase();
    const adminUserId = parseInt(req.query.adminUserId || req.body.adminUserId || 0);
    
    if (!adminUserId || isNaN(adminUserId)) {
        return res.status(400).json({ message: 'Требуется ID администратора (adminUserId).' });
    }
    
    const procedureMap = {
        'users': 'sp_GetAllUsers',
        'drivers': 'sp_GetAllDrivers',
        'routes': 'sp_GetAllRoutes',
        'trips': 'sp_GetAllTrips',
        'bookings': 'sp_GetAllBookings',
        'statistics': 'sp_GetSystemStatistics',
        'analysis': 'sp_GetRouteAnalysis',
    };
    
    // Для водителей админ видит все кроме лицензии (лицензия через отдельный endpoint)
    const procedureName = procedureMap[tableName];

    if (!procedureName) {
        return res.status(404).json({ message: 'Неизвестная таблица.' });
    }

    try {
        const inputs = [
            { name: 'AdminUserID', type: sql.Int, value: adminUserId }
        ];
        const data = await executeProcedure(procedureName, inputs);
        res.json(data);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
});


// -------------------------------------------------------------------------
// C.2. CREATE/UPDATE ДАННЫХ (POST/PUT /api/admin/:tableName)
// -------------------------------------------------------------------------

// POST /api/admin/:tableName (CREATE)
app.post('/api/admin/:tableName', async (req, res) => {
    const tableName = req.params.tableName.toLowerCase();
    const payload = req.body;
    const adminUserId = parseInt(payload.adminUserId || req.query.adminUserId || 0);
    
    if (!adminUserId || isNaN(adminUserId)) {
        return res.status(400).json({ success: false, message: 'Требуется ID администратора (adminUserId).' });
    }
    
    let procedureName;
    let inputs = [];

    // Создание Водителя
    if (tableName === 'drivers') {
        procedureName = 'sp_CreateDriver';
        // Убираем дефисы из номера телефона
        let phoneValue = payload.Phone;
        if (phoneValue && typeof phoneValue === 'string') {
            phoneValue = phoneValue.replace(/-/g, '');
        }
        inputs = [
            { name: 'FullName', type: sql.NVarChar(100), value: payload.FullName },
            { name: 'LicenseNumber', type: sql.NVarChar(50), value: payload.LicenseNumber },
            { name: 'Phone', type: sql.NVarChar(20), value: phoneValue },
            { name: 'ExperienceYears', type: sql.Int, value: payload.ExperienceYears },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    } 
    // Создание Маршрута
    else if (tableName === 'routes') {
        procedureName = 'sp_CreateRoute';
        inputs = [
            { name: 'RouteName', type: sql.NVarChar(100), value: payload.RouteName },
            { name: 'DepartureCity', type: sql.NVarChar(50), value: payload.DepartureCity },
            { name: 'ArrivalCity', type: sql.NVarChar(50), value: payload.ArrivalCity },
            { name: 'DistanceKm', type: sql.Int, value: payload.DistanceKm },
            { name: 'DurationMinutes', type: sql.Int, value: payload.DurationMinutes },
            { name: 'BasePrice', type: sql.Decimal(10, 2), value: payload.BasePrice },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    }
    // Создание Рейса
    else if (tableName === 'trips') {
        procedureName = 'sp_CreateTrip';
        // Преобразуем время из формата HH:mm (от input type="time") в HH:mm:ss для SQL
        let departureTime = payload.DepartureTime;
        
        if (departureTime === null || departureTime === undefined || departureTime === '') {
            return res.status(400).json({ success: false, message: 'Время отправления не указано' });
        }
        
        if (typeof departureTime !== 'string') {
            departureTime = String(departureTime);
        }
        
        departureTime = departureTime.trim();
        
        if (departureTime === '') {
            return res.status(400).json({ success: false, message: 'Время отправления не указано' });
        }
        
        // Простое преобразование: если HH:mm, добавляем :00
        let departureTimeFormatted = departureTime;
        if (departureTime.match(/^\d{1,2}:\d{2}$/)) {
            // Формат HH:mm - добавляем секунды
            departureTimeFormatted = departureTime + ':00';
        } else if (departureTime.match(/^\d{1,2}:\d{2}:\d{2}$/)) {
            // Уже в формате HH:mm:ss - используем как есть
            departureTimeFormatted = departureTime;
        } else {
            return res.status(400).json({ success: false, message: 'Неверный формат времени. Ожидается HH:mm' });
        }
        
        // Валидация и нормализация
        const timeParts = departureTimeFormatted.split(':');
        const hours = parseInt(timeParts[0], 10);
        const mins = parseInt(timeParts[1], 10);
        const secs = parseInt(timeParts[2] || '0', 10);
        
        if (isNaN(hours) || isNaN(mins) || hours < 0 || hours > 23 || mins < 0 || mins > 59 || secs < 0 || secs > 59) {
            return res.status(400).json({ success: false, message: 'Неверное значение времени. Часы: 0-23, минуты: 0-59' });
        }
        
        // Нормализуем формат (добавляем ведущие нули)
        departureTimeFormatted = `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
        
        // Проверка что нельзя создать рейс на прошедшее время
        const tripDate = new Date(payload.TripDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        tripDate.setHours(0, 0, 0, 0);
        
        if (tripDate.getTime() === today.getTime()) {
            const departureDateTime = new Date();
            departureDateTime.setHours(hours, mins, 0, 0);
            const now = new Date();
            if (departureDateTime < now) {
                return res.status(400).json({ success: false, message: 'Нельзя создать рейс на прошедшее время' });
            }
        } else if (tripDate < today) {
            return res.status(400).json({ success: false, message: 'Нельзя создать рейс на прошедшую дату' });
        }
        
        // Создаем объект Date для sql.Time (mssql может требовать Date объект)
        // Используем сегодняшнюю дату с нужным временем
        const timeDate = new Date();
        timeDate.setHours(hours, mins, secs, 0);
        
        inputs = [
            { name: 'RouteID', type: sql.Int, value: payload.RouteID },
            { name: 'DriverID', type: sql.Int, value: payload.DriverID },
            { name: 'BusID', type: sql.Int, value: payload.BusID || 0 },
            { name: 'TripDate', type: sql.Date, value: payload.TripDate },
            { name: 'DepartureTime', type: sql.NVarChar(8), value: departureTimeFormatted },
            { name: 'TotalSeats', type: sql.Int, value: payload.TotalSeats || 0 },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    }
    
    if (!procedureName) return res.status(404).json({ success: false, message: 'Операция CREATE не поддерживается для этой таблицы.' });

    try {
        const result = await executeProcedure(procedureName, inputs);
        if (result && result.length > 0 && result[0] && result[0].Success) {
            return res.json({ success: true, message: `${tableName.slice(0, -1)} успешно добавлен. ID: ${result[0].ID}` });
        } else {
            const errorMessage = (result && result.length > 0 && result[0] && result[0].Message) ? result[0].Message : `Ошибка добавления ${tableName.slice(0, -1)}.`;
            return res.status(400).json({ success: false, message: errorMessage });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message || 'Внутренняя ошибка сервера' });
    }
});


// PUT /api/admin/:tableName/:id (UPDATE)
app.put('/api/admin/:tableName/:id', async (req, res) => {
    const tableName = req.params.tableName.toLowerCase();
    const id = parseInt(req.params.id);
    const payload = req.body;
    const adminUserId = parseInt(payload.adminUserId || req.query.adminUserId || 0);
    
    if (!adminUserId || isNaN(adminUserId)) {
        return res.status(400).json({ success: false, message: 'Требуется ID администратора (adminUserId).' });
    }
    
    let procedureName;
    let inputs = [];

    // Обновление Водителя
    if (tableName === 'drivers') {
        procedureName = 'sp_UpdateDriver';
        // Убираем дефисы из номера телефона
        let phoneValue = payload.Phone;
        if (phoneValue && typeof phoneValue === 'string') {
            phoneValue = phoneValue.replace(/-/g, '');
        }
        inputs = [
            { name: 'DriverID', type: sql.Int, value: id },
            { name: 'FullName', type: sql.NVarChar(100), value: (payload.FullName !== null && payload.FullName !== undefined && payload.FullName !== '') ? payload.FullName : null },
            { name: 'LicenseNumber', type: sql.NVarChar(50), value: (payload.LicenseNumber !== null && payload.LicenseNumber !== undefined && payload.LicenseNumber !== '') ? payload.LicenseNumber : null },
            { name: 'Phone', type: sql.NVarChar(20), value: (phoneValue !== null && phoneValue !== undefined && phoneValue !== '') ? phoneValue : null },
            { name: 'ExperienceYears', type: sql.Int, value: (payload.ExperienceYears !== null && payload.ExperienceYears !== undefined && payload.ExperienceYears !== '') ? payload.ExperienceYears : null },
            { name: 'IsActive', type: sql.Bit, value: payload.IsActive !== undefined ? (payload.IsActive === true || payload.IsActive === 1 || payload.IsActive === 'true') : null },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    } 
    // Обновление Маршрута
    else if (tableName === 'routes') {
        procedureName = 'sp_UpdateRoute';
        inputs = [
            { name: 'RouteID', type: sql.Int, value: id },
            { name: 'RouteName', type: sql.NVarChar(100), value: (payload.RouteName !== null && payload.RouteName !== undefined && payload.RouteName !== '') ? payload.RouteName : null },
            { name: 'DepartureCity', type: sql.NVarChar(50), value: (payload.DepartureCity !== null && payload.DepartureCity !== undefined && payload.DepartureCity !== '') ? payload.DepartureCity : null },
            { name: 'ArrivalCity', type: sql.NVarChar(50), value: (payload.ArrivalCity !== null && payload.ArrivalCity !== undefined && payload.ArrivalCity !== '') ? payload.ArrivalCity : null },
            { name: 'DistanceKM', type: sql.Int, value: (payload.DistanceKm !== null && payload.DistanceKm !== undefined && payload.DistanceKm !== '') ? payload.DistanceKm : null },
            { name: 'DurationMinutes', type: sql.Int, value: (payload.DurationMinutes !== null && payload.DurationMinutes !== undefined && payload.DurationMinutes !== '') ? payload.DurationMinutes : null },
            { name: 'TotalSeats', type: sql.Int, value: (payload.TotalSeats !== null && payload.TotalSeats !== undefined && payload.TotalSeats !== '') ? payload.TotalSeats : null },
            { name: 'BasePrice', type: sql.Decimal(10, 2), value: (payload.BasePrice !== null && payload.BasePrice !== undefined && payload.BasePrice !== '') ? payload.BasePrice : null },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    }
    // Обновление Рейса
    else if (tableName === 'trips') {
        procedureName = 'sp_UpdateTrip';
        inputs = [
            { name: 'TripID', type: sql.Int, value: id },
            { name: 'RouteID', type: sql.Int, value: (payload.RouteID !== null && payload.RouteID !== undefined && payload.RouteID !== '') ? payload.RouteID : null },
            { name: 'DriverID', type: sql.Int, value: (payload.DriverID !== null && payload.DriverID !== undefined && payload.DriverID !== '') ? payload.DriverID : null },
            { name: 'BusID', type: sql.Int, value: (payload.BusID !== null && payload.BusID !== undefined && payload.BusID !== '') ? payload.BusID : null },
            { name: 'TripDate', type: sql.Date, value: (payload.TripDate !== null && payload.TripDate !== undefined && payload.TripDate !== '') ? payload.TripDate : null },
            { name: 'DepartureTime', type: sql.NVarChar(8), value: (() => {
                let departureTime = payload.DepartureTime;
                
                if (departureTime === null || departureTime === undefined || departureTime === '') {
                    return null; // Если время не указано, оставляем как есть (не обновляем)
                }
                
                if (typeof departureTime !== 'string') {
                    departureTime = String(departureTime);
                }
                
                departureTime = departureTime.trim();
                
                // Простое преобразование: если HH:mm, добавляем :00
                if (departureTime.match(/^\d{1,2}:\d{2}$/)) {
                    const parts = departureTime.split(':');
                    const hours = parseInt(parts[0], 10);
                    const minutes = parseInt(parts[1], 10);
                    
                    if (isNaN(hours) || isNaN(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
                        return null;
                    }
                    
                    departureTime = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`;
                }
                // Если уже в формате HH:mm:ss, нормализуем
                else if (departureTime.match(/^\d{1,2}:\d{2}:\d{2}$/)) {
                    const parts = departureTime.split(':');
                    const hours = parseInt(parts[0], 10);
                    const minutes = parseInt(parts[1], 10);
                    const seconds = parseInt(parts[2], 10);
                    
                    if (isNaN(hours) || isNaN(minutes) || isNaN(seconds) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59) {
                        return null;
                    }
                    
                    departureTime = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
                }
                else {
                    // Неизвестный формат
                    return null;
                }
                
                return departureTime;
            })() },
            { name: 'Status', type: sql.NVarChar(20), value: (payload.Status !== null && payload.Status !== undefined && payload.Status !== '') ? payload.Status : null },
            { name: 'TotalSeats', type: sql.Int, value: (payload.TotalSeats !== null && payload.TotalSeats !== undefined && payload.TotalSeats !== '') ? payload.TotalSeats : null },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId },
        ];
    }

    if (!procedureName) return res.status(404).json({ success: false, message: 'Операция UPDATE не поддерживается для этой таблицы.' });

    try {
        const result = await executeProcedure(procedureName, inputs);
        // Если процедура вернула результат с Success и Message
        if (result && result.length > 0 && result[0]) {
            if (result[0].Success === 1 || result[0].Success === true) {
                return res.json({ success: true, message: result[0].Message || `${tableName.slice(0, -1)} ID ${id} успешно обновлен.` });
            } else {
                const errorMessage = result[0].Message || `Ошибка обновления ${tableName.slice(0, -1)}.`;
                return res.status(400).json({ success: false, message: errorMessage });
            }
        } else {
            // Если процедура не вернула результат, но и не выбросила исключение, считаем успешным
            return res.json({ success: true, message: `${tableName.slice(0, -1)} ID ${id} успешно обновлен.` });
        }
    } catch (error) {
        // Обрабатываем исключения от RAISERROR
        let errorMessage = 'Внутренняя ошибка сервера';
        if (error && error.message) {
            errorMessage = error.message.replace('SQL Error: ', '');
        } else if (error && typeof error === 'string') {
            errorMessage = error;
        }
        return res.status(400).json({ success: false, message: errorMessage });
    }
});


// -------------------------------------------------------------------------
// C.3. DELETE ДАННЫХ (DELETE /api/admin/:tableName/:id)
// -------------------------------------------------------------------------

app.delete('/api/admin/:tableName/:id', async (req, res) => {
    const tableName = req.params.tableName.toLowerCase();
    const id = parseInt(req.params.id);
    const adminUserId = parseInt(req.query.adminUserId || req.body.adminUserId || 0);
    
    if (!adminUserId || isNaN(adminUserId)) {
        return res.status(400).json({ success: false, message: 'Требуется ID администратора (adminUserId).' });
    }
    
    let procedureName;

    const procedureMap = {
        'drivers': 'sp_DeleteDriver',
        'routes': 'sp_DeleteRoute',
        'trips': 'sp_DeleteTrip',
        'bookings': 'sp_DeleteBooking',
    };
    procedureName = procedureMap[tableName];

    if (!procedureName) {
        return res.status(404).json({ success: false, message: 'Операция DELETE не поддерживается для этой таблицы.' });
    }

    // Для bookings используем BookingID (BIGINT), для остальных - обычный ID (INT)
    let inputs;
    if (tableName === 'bookings') {
        inputs = [
            { name: 'BookingID', type: sql.BigInt, value: id },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId }
        ];
    } else {
        inputs = [
            { name: `${tableName.slice(0, -1)}ID`, type: sql.Int, value: id },
            { name: 'AdminUserID', type: sql.Int, value: adminUserId }
        ];
    }

    try {
        const result = await executeProcedure(procedureName, inputs);
        // Процедуры удаления могут не возвращать результат или возвращать пустой набор
        // Если ошибок нет, считаем операцию успешной
        if (!result || result.length === 0 || (result[0] && result[0].Success !== 0 && result[0].Success !== false)) {
            return res.json({ success: true, message: `${tableName.slice(0, -1)} ID ${id} успешно удален.` });
        } else if (result && result.length > 0 && result[0].Message) {
            return res.status(400).json({ success: false, message: result[0].Message });
        } else {
            return res.json({ success: true, message: `${tableName.slice(0, -1)} ID ${id} успешно удален.` });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});


// -------------------------------------------------------------------------
// C.4. ОТМЕНА БРОНИРОВАНИЯ (PUT /api/admin/bookings/cancel/:id)
// -------------------------------------------------------------------------

app.put('/api/admin/bookings/cancel/:id', async (req, res) => {
    const bookingId = parseInt(req.params.id);

    const inputs = [
        { name: 'BookingID', type: sql.BigInt, value: bookingId },
        { name: 'UserID', type: sql.Int, value: null } // NULL для админа
    ];

    try {
        // sp_CancelBooking принимает NULL UserID для админа
        const result = await executeProcedure('sp_CancelBooking', inputs); 
        
        if (result && result.length > 0 && result[0].Success) {
            return res.json({ success: true, message: `Бронирование ID ${bookingId} успешно отменено.` });
        } else {
             return res.status(400).json({ success: false, message: result[0].Message || 'Ошибка отмены бронирования.' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// -------------------------------------------------------------------------
// C.5. ПРОСМОТР ЛИЦЕНЗИИ ВОДИТЕЛЯ (С ПАРОЛЕМ АДМИНА)
// -------------------------------------------------------------------------

// POST /api/admin/drivers/:driverId/license - Получить лицензию водителя с проверкой пароля
app.post('/api/admin/drivers/:driverId/license', async (req, res) => {
    const driverId = parseInt(req.params.driverId);
    const { adminPassword } = req.body;
    
    if (isNaN(driverId)) return res.status(400).json({ success: false, message: 'Неверный ID водителя.' });
    if (!adminPassword) return res.status(400).json({ success: false, message: 'Пароль администратора не предоставлен.' });

    const inputs = [
        { name: 'DriverID', type: sql.Int, value: driverId },
        { name: 'AdminPassword', type: sql.NVarChar(128), value: adminPassword }
    ];

    try {
        const result = await executeProcedure('sp_GetDriverLicenseWithPassword', inputs);
        if (result && result.length > 0 && result[0].Success === 1) {
            return res.json({ success: true, licenseNumber: result[0].LicenseNumber });
        } else {
            return res.status(400).json({ success: false, message: result[0].Message || 'Ошибка получения лицензии.' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// -------------------------------------------------------------------------
// C.6. JSON ЭКСПОРТ/ИМПОРТ ВСЕХ ТИПОВ ДАННЫХ
// -------------------------------------------------------------------------

// GET /api/admin/export/:dataType - Экспорт данных в JSON
app.get('/api/admin/export/:dataType', async (req, res) => {
    const dataType = req.params.dataType.toLowerCase();
    const adminUserId = parseInt(req.query.adminUserId || req.body.adminUserId || 0);
    
    if (!adminUserId || isNaN(adminUserId)) {
        return res.status(400).json({ success: false, message: 'Требуется ID администратора (adminUserId).' });
    }
    
    // Только экспорт бронирований
    const procedureMap = {
        'bookings': 'sp_ExportBookingsToJson'
        // 'routes': 'sp_ExportRoutesToJson',
        // 'drivers': 'sp_ExportDriversToJson',
        // 'trips': 'sp_ExportTripsToJson',
        // 'users': 'sp_ExportUsersToJson'
    };
    
    const procedureName = procedureMap[dataType];
    if (!procedureName) {
        return res.status(404).json({ success: false, message: 'Неизвестный тип данных для экспорта.' });
    }

    try {
        const inputs = [
            { name: 'AdminUserID', type: sql.Int, value: adminUserId }
        ];
        const data = await executeProcedure(procedureName, inputs);
        const jsonData = { [dataType.charAt(0).toUpperCase() + dataType.slice(1)]: data };
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Content-Disposition', `attachment; filename=${dataType}_export.json`);
        res.json(jsonData);
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// POST /api/admin/import/:dataType - Импорт данных из JSON
app.post('/api/admin/import/:dataType', async (req, res) => {
    const dataType = req.params.dataType.toLowerCase();
    const { jsonData, adminUserId } = req.body;
    
    if (!jsonData) {
        return res.status(400).json({ success: false, message: 'JSON данные не предоставлены.' });
    }
    
    const adminId = parseInt(adminUserId || req.query.adminUserId || 0);
    if (!adminId || isNaN(adminId)) {
        return res.status(400).json({ success: false, message: 'Требуется ID администратора (adminUserId).' });
    }

    // Только импорт бронирований
    const procedureMap = {
        'bookings': 'sp_ImportBookingsFromJson'
        // 'routes': 'sp_ImportRoutesFromJson',
        // 'drivers': 'sp_ImportDriversFromJson',
        // 'trips': 'sp_ImportTripsFromJson',
        // 'users': 'sp_ImportUsersFromJson'
    };
    
    const procedureName = procedureMap[dataType];
    if (!procedureName) {
        return res.status(404).json({ success: false, message: 'Неизвестный тип данных для импорта.' });
    }

    try {
        const jsonString = typeof jsonData === 'string' ? jsonData : JSON.stringify(jsonData);
        const inputs = [
            { name: 'JsonData', type: sql.NVarChar(sql.MAX), value: jsonString },
            { name: 'AdminUserID', type: sql.Int, value: adminId }
        ];
        await executeProcedure(procedureName, inputs);
        return res.json({ success: true, message: `${dataType} успешно импортированы.` });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});


// --- ЗАПУСК СЕРВЕРА ---
(async () => {
    try {
        // Инициализация подключения к БД
        await initDatabase();
        
        // Запуск сервера
        app.listen(port, () => {
            console.log('');
            console.log('═══════════════════════════════════════════════════════');
            console.log(` Сервер запущен на http://localhost:${port}`);
            console.log('═══════════════════════════════════════════════════════');
            console.log('');
        });
    } catch (error) {
        console.error(' Не удалось запустить сервер:', error.message);
        process.exit(1);
    }
})();