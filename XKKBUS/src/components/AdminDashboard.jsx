import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';

const API_URL = 'http://localhost:3001/api';

const AdminDashboard = ({ user }) => {
  const [table, setTable] = useState('statistics');
  const [data, setData] = useState([]);
  const [form, setForm] = useState({});
  const [loading, setLoading] = useState(false);
  // Пагинация
  const [currentPage, setCurrentPage] = useState(1);
  const [itemsPerPage, setItemsPerPage] = useState(20);
  // Фильтры
  const [filters, setFilters] = useState({});
  // Лицензии водителей (расшифрованные)
  const [decryptedLicenses, setDecryptedLicenses] = useState({});
  const [licensePassword, setLicensePassword] = useState('');
  const [showLicenseModal, setShowLicenseModal] = useState(null);
  // Редактирование
  const [editingItem, setEditingItem] = useState(null); // {type: 'drivers'|'routes'|'trips', data: {...}}
  const editingModalRef = useRef(null);

  const loadData = useCallback(() => {
    if (!user || !user.UserID) {
      console.error('Пользователь не авторизован');
      setData([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    fetch(`${API_URL}/admin/${table}?adminUserId=${user.UserID}`)
      .then(r => r.json())
      .then(data => {
        setData(data);
        setLoading(false);
      })
      .catch(err => {
        console.error('Ошибка загрузки данных:', err);
        setData([]);
        setLoading(false);
      });
  }, [table, user]);

  useEffect(() => {
    // Очищаем данные при смене вкладки
    setData([]);
    setLoading(true);
    setCurrentPage(1);
    setFilters({});
    loadData();
  }, [table, loadData]);

  // Прокрутка к началу страницы при открытии модального окна редактирования
  // Используем useRef для отслеживания предыдущего значения, чтобы срабатывало только при открытии/закрытии
  const prevEditingItemRef = useRef(null);
  useEffect(() => {
    const wasNull = prevEditingItemRef.current === null;
    const isNowNotNull = editingItem !== null;
    
    // Срабатывает только при открытии модального окна (переходе от null к не-null)
    if (wasNull && isNowNotNull) {
      // Прокручиваем к началу страницы, чтобы модальное окно было видно
      window.scrollTo({ top: 0, behavior: 'smooth' });
      // Также фокусируемся на модальном окне
      if (editingModalRef.current) {
        setTimeout(() => {
          editingModalRef.current?.focus();
        }, 100);
      }
    }
    
    // Обновляем ref для следующего рендера
    prevEditingItemRef.current = editingItem;
  }, [editingItem]);

  // Автообновление статистики при изменении данных
  useEffect(() => {
    if (table === 'statistics') {
      const interval = setInterval(() => {
        loadData();
      }, 5000); // Обновление каждые 5 секунд
      return () => clearInterval(interval);
    }
  }, [table, user, loadData]);

  const handleUpdate = async (e) => {
    e.preventDefault();
    if (!user || !user.UserID) {
      alert('Пользователь не авторизован');
      return;
    }
    
    if (!editingItem || !editingItem.data) {
      alert('Нет данных для обновления');
      return;
    }
    
    // Проверка формата телефона для водителей
    if (editingItem.type === 'drivers' && editingItem.data.Phone && !/^\+375\d{9}$/.test(editingItem.data.Phone)) {
      alert('Телефон должен быть в формате +375XXXXXXXXX (13 символов, только цифры после +375)');
      return;
    }
    
    try {
      const id = editingItem.data.DriverID || editingItem.data.RouteID || editingItem.data.TripID;
      
      // Подготавливаем payload, убирая пустые строки и преобразуя их в null для числовых полей
      const payload = { ...editingItem.data };
      
      // Обрабатываем числовые поля - пустые строки преобразуем в null
      if (editingItem.type === 'drivers') {
        if (payload.ExperienceYears === '' || payload.ExperienceYears === undefined) {
          payload.ExperienceYears = null;
        }
        if (payload.Phone === '') {
          payload.Phone = null;
        }
        // НЕ передаем лицензию при обновлении, так как она не редактируется в форме
        // Лицензия должна обновляться отдельно, если нужно
        // Удаляем LicenseNumber из payload, чтобы не было проблем с шифрованием
        delete payload.LicenseNumber;
      } else if (editingItem.type === 'routes') {
        if (payload.DistanceKm === '' || payload.DistanceKm === undefined) {
          payload.DistanceKm = payload.DistanceKM || null;
        }
        if (payload.DurationMinutes === '' || payload.DurationMinutes === undefined) {
          payload.DurationMinutes = null;
        }
        if (payload.TotalSeats === '' || payload.TotalSeats === undefined) {
          payload.TotalSeats = null;
        }
        if (payload.BasePrice === '' || payload.BasePrice === undefined) {
          payload.BasePrice = null;
        }
      } else if (editingItem.type === 'trips') {
        if (payload.RouteID === '' || payload.RouteID === undefined) {
          payload.RouteID = null;
        }
        if (payload.DriverID === '' || payload.DriverID === undefined) {
          payload.DriverID = null;
        }
        if (payload.BusID === '' || payload.BusID === undefined) {
          payload.BusID = null;
        }
        if (payload.TripDate === '' || payload.TripDate === undefined) {
          payload.TripDate = null;
        }
        if (payload.DepartureTime === '' || payload.DepartureTime === undefined) {
          payload.DepartureTime = null;
        }
        if (payload.Status === '' || payload.Status === undefined) {
          payload.Status = null;
        }
        if (payload.TotalSeats === '' || payload.TotalSeats === undefined) {
          payload.TotalSeats = null;
        }
      }
      
      payload.adminUserId = user.UserID;
      
      const res = await fetch(`${API_URL}/admin/${editingItem.type}/${id}`, {
        method: 'PUT',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(payload)
      });
      
      if(res.ok) {
        const result = await res.json();
        if(result && result.success !== false) {
          // НЕ очищаем расшифрованную лицензию после обновления водителя,
          // так как лицензия в базе данных не изменяется (мы не передаем LicenseNumber)
          // Расшифрованная лицензия должна остаться, если она была расшифрована до обновления
          setEditingItem(null);
          loadData(); // Сразу обновляем данные
          // Обновляем статистику если она открыта
          if (table !== 'statistics') {
            setTimeout(() => {
              if (table === 'bookings' || table === 'trips' || table === 'routes' || table === 'users' || table === 'drivers') {
                fetch(`${API_URL}/admin/statistics?adminUserId=${user.UserID}`)
                  .then(r => r.json())
                  .catch(() => {});
              }
            }, 500);
          }
          alert('Данные успешно обновлены');
        } else {
          alert((result && result.message) || 'Ошибка обновления');
        }
      } else {
        let result = {};
        try {
          result = await res.json();
        } catch {
          result = { message: 'Ошибка обновления' };
        }
        alert((result && result.message) || 'Ошибка обновления');
      }
    } catch (error) {
      const errorMessage = (error && error.message) ? error.message : 'Ошибка обновления';
      alert('Ошибка обновления: ' + errorMessage);
    }
  };

  const handleDelete = async (id) => {
    if(!window.confirm('Удалить запись?')) return;
    if (!user || !user.UserID) {
      alert('Пользователь не авторизован');
      return;
    }
    try {
      const res = await fetch(`${API_URL}/admin/${table}/${id}?adminUserId=${user.UserID}`, { method: 'DELETE' });
      const result = await res.json();
      if(res.ok && result.success !== false) {
        loadData(); // Сразу обновляем данные
        // Если удаляем из таблицы, которая влияет на статистику, обновляем статистику
        if (table !== 'statistics') {
          // Обновляем статистику в фоне
          setTimeout(() => {
            if (table === 'bookings' || table === 'trips' || table === 'routes' || table === 'users' || table === 'drivers') {
              fetch(`${API_URL}/admin/statistics?adminUserId=${user.UserID}`)
                .then(r => r.json())
                .catch(() => {});
            }
          }, 500);
        }
      } else {
        alert(result.message || 'Ошибка удаления');
      }
    } catch (error) {
      alert('Ошибка удаления: ' + error.message);
    }
  };

  const handleAdd = async (e) => {
    e.preventDefault();
    if (!user || !user.UserID) {
      alert('Пользователь не авторизован');
      return;
    }
    
    // Проверка формата телефона для водителей
    if (table === 'drivers' && form.Phone && !/^\+375\d{9}$/.test(form.Phone)) {
      alert('Телефон должен быть в формате +375XXXXXXXXX (13 символов, только цифры после +375)');
      return;
    }
    
    try {
      const res = await fetch(`${API_URL}/admin/${table}`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({...form, adminUserId: user.UserID})
      });
      if(res.ok) {
        const result = await res.json();
        if(result && result.success !== false) {
          // Показываем уведомление об успешном добавлении
          const tableNames = {
            'drivers': 'Водитель',
            'routes': 'Маршрут',
            'trips': 'Рейс'
          };
          const tableName = tableNames[table] || 'Запись';
          alert(`${tableName} успешно добавлен.`);
          setForm({});
          loadData(); // Сразу обновляем данные
          // Обновляем статистику если она открыта
          if (table !== 'statistics') {
            setTimeout(() => {
              fetch(`${API_URL}/admin/statistics?adminUserId=${user.UserID}`)
                .then(r => r.json())
                .catch(() => {});
            }, 500);
          }
        } else {
          alert((result && result.message) || 'Ошибка добавления');
        }
      } else {
        let error = {};
        try {
          error = await res.json();
        } catch {
          error = { message: 'Ошибка добавления' };
        }
        alert((error && error.message) || 'Ошибка добавления');
      }
    } catch (error) {
      alert('Ошибка добавления: ' + error.message);
    }
  };

  const handleExportJson = async (dataType) => {
    if (!user || !user.UserID) {
      alert('Пользователь не авторизован');
      return;
    }
    try {
      const res = await fetch(`${API_URL}/admin/export/${dataType}?adminUserId=${user.UserID}`);
      if (!res.ok) {
        const error = await res.json();
        throw new Error(error.message || 'Ошибка экспорта');
      }
      const jsonData = await res.json();
      const jsonString = JSON.stringify(jsonData, null, 2);
      const blob = new Blob([jsonString], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${dataType}_export.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      alert('Экспорт выполнен успешно!');
    } catch (error) {
      alert('Ошибка экспорта: ' + error.message);
    }
  };

  const handleFileImport = async (event, dataType) => {
    const file = event.target.files[0];
    if (!file) return;
    
    if (!user || !user.UserID) {
      alert('Пользователь не авторизован');
      return;
    }

    const reader = new FileReader();
    reader.onload = async (e) => {
      try {
        const fileContent = e.target.result;
        const jsonData = JSON.parse(fileContent);
        const jsonString = JSON.stringify(jsonData);
        
        const res = await fetch(`${API_URL}/admin/import/${dataType}`, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({ jsonData: jsonString, adminUserId: user.UserID })
        });
        const result = await res.json();
        if (res.ok && result.success) {
          // Если импортируем водителей, очищаем все расшифрованные лицензии
          if (dataType === 'drivers') {
            setDecryptedLicenses({});
          }
          alert('Импорт выполнен успешно!');
          loadData();
        } else {
          alert(result.message || 'Ошибка импорта');
        }
      } catch (error) {
        alert('Ошибка импорта: ' + error.message);
      }
    };
    reader.readAsText(file);
    event.target.value = ''; // Сброс input
  };


  const handleDecryptLicense = async (driverId) => {
    if (!licensePassword.trim()) {
      alert('Введите пароль администратора');
      return;
    }
    try {
      // Нормализуем driverId к числу для консистентности ключей
      const normalizedDriverId = parseInt(driverId, 10);
      const res = await fetch(`${API_URL}/admin/drivers/${normalizedDriverId}/license`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ adminPassword: licensePassword })
      });
      const result = await res.json();
      if (res.ok && result.success) {
        // Используем нормализованный ID как ключ
        setDecryptedLicenses({ ...decryptedLicenses, [normalizedDriverId]: result.licenseNumber });
        setLicensePassword('');
        setShowLicenseModal(null);
      } else {
        alert(result.message || 'Ошибка расшифровки лицензии');
      }
    } catch (error) {
      alert('Ошибка расшифровки: ' + error.message);
    }
  };

  // Фильтрация данных
  const filteredData = useMemo(() => {
    if (!filters || Object.keys(filters).length === 0) return data;
    
    return data.filter(row => {
      return Object.keys(filters).every(key => {
        const filterValue = filters[key];
        if (!filterValue || filterValue === '') return true;
        const cellValue = String(row[key] || '').toLowerCase();
        return cellValue.includes(String(filterValue).toLowerCase());
      });
    });
  }, [data, filters]);

  // Пагинация
  const totalPages = Math.ceil(filteredData.length / itemsPerPage);
  const paginatedData = useMemo(() => {
    const start = (currentPage - 1) * itemsPerPage;
    return filteredData.slice(start, start + itemsPerPage);
  }, [filteredData, currentPage, itemsPerPage]);

  const handleFilterChange = (key, value) => {
    setFilters({ ...filters, [key]: value });
    setCurrentPage(1);
  };

  const keys = data.length > 0 ? Object.keys(data[0]) : [];
  
  // Маппинг английских названий на русские
  const columnNames = {
    'UserID': 'ID пользователя',
    'Login': 'Логин',
    'Role': 'Роль',
    'FullName': 'ФИО',
    'Phone': 'Телефон',
    'Email': 'Email',
    'CreatedAt': 'Дата создания',
    'DriverID': 'ID водителя',
    'LicenseNumber': 'Лицензия',
    'ExperienceYears': 'Опыт (лет)',
    'IsActive': 'Активен',
    'RouteID': 'ID маршрута',
    'RouteName': 'Название маршрута',
    'DepartureCity': 'Город отправления',
    'ArrivalCity': 'Город прибытия',
    'DistanceKM': 'Расстояние (км)',
    'DurationMinutes': 'Длительность (мин)',
    'TotalSeats': 'Всего мест',
    'BasePrice': 'Базовая цена',
    'TripID': 'ID рейса',
    'TripDate': 'Дата',
    'DepartureTime': 'Время отправления',
    'BookedSeats': 'Забронировано',
    'AvailableSeats': 'Доступно',
    'Status': 'Статус',
    'BookingID': 'ID бронирования',
    'UserLogin': 'Логин пользователя',
    'UserFullName': 'ФИО пользователя',
    'SeatNumber': 'Номер места',
    'PassengerName': 'Имя пассажира',
    'PassengerPhone': 'Телефон пассажира',
    'BookingTime': 'Время бронирования',
    'PricePaid': 'Оплачено',
    'IsCancelled': 'Отменено',
    'TotalTrips': 'Всего рейсов',
    'ActiveBookings': 'Активных бронирований',
    'TotalBookings': 'Всего бронирований',
    'TotalRevenue': 'Выручка',
    'AvgBookingPrice': 'Средняя цена',
    'OccupancyRate': 'Загрузка (%)',
    'TotalRoutes': 'Маршрутов',
    'ActiveTrips': 'Активных рейсов',
    'TotalUsers': 'Пользователей',
    'ActiveDrivers': 'Активных водителей',
    'DriverName': 'Водитель'
  };
  
  // Функция для получения русского названия колонки
  const getColumnName = (key) => {
    return columnNames[key] || key;
  };
  
  // Функция для отображения зашифрованной лицензии
  const getLicenseDisplay = (row, rowId = null) => {
    // Используем тот же способ получения driverId, что и в рендере
    let driverId = row.DriverID || rowId;
    // Нормализуем driverId к числу для консистентности ключей
    if (driverId != null) {
      driverId = parseInt(driverId, 10);
      // Проверяем расшифрованную лицензию (приоритет) - пробуем и как число, и как строку
      if (!isNaN(driverId)) {
        if (decryptedLicenses[driverId]) {
          return decryptedLicenses[driverId];
        }
        // Также проверяем строковый ключ на случай, если где-то сохранился как строка
        if (decryptedLicenses[String(driverId)]) {
          return decryptedLicenses[String(driverId)];
        }
      }
    }
    // Показываем зашифрованный вид из базы данных (если есть) или заглушку
    if (row.LicenseNumber) {
      return row.LicenseNumber; // Это будет зашифрованная строка из БД
    }
    return '🔒 ENCRYPTED: ****-****-****';
  };
  
  // Функция форматирования значений
  const formatCellValue = (key, value) => {
    if (value === null || value === undefined) return '-';
    
    // Форматирование дат
    if (key.includes('Date') || key === 'CreatedAt' || key === 'BookingTime') {
      if (typeof value === 'string' && value.includes('T')) {
        return formatDate(value);
      }
      return value;
    }
    
    // Форматирование времени
    if (key.includes('Time')) {
      return formatTime(value);
    }
    
    // Форматирование цен
    if (key.includes('Price') || key === 'BasePrice' || key === 'PricePaid' || key === 'TotalRevenue' || key === 'AvgBookingPrice') {
      return typeof value === 'number' ? value.toFixed(2) + ' BYN' : value;
    }
    
    // Форматирование булевых значений
    if (key === 'IsActive' || key === 'IsCancelled' || key === 'IsConfirmed') {
      return value ? 'Да' : 'Нет';
    }
    
    // Перевод статусов на русский
    if (key === 'Status') {
      const statusMap = {
        'planned': 'Запланирован',
        'in_progress': 'В пути',
        'completed': 'Завершен',
        'cancelled': 'Отменен'
      };
      return statusMap[value] || value;
    }
    
    return value;
  };
  
  // Функция форматирования даты
  const formatDate = (dateString) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    return date.toLocaleDateString('ru-RU', { 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    });
  };
  
  // Функция форматирования времени
  const formatTime = (timeString) => {
    if (!timeString) return '';
    
    // Если это объект Date, преобразуем в строку
    if (timeString instanceof Date) {
      const hours = String(timeString.getHours()).padStart(2, '0');
      const minutes = String(timeString.getMinutes()).padStart(2, '0');
      return `${hours}:${minutes}`;
    }
    
    if (typeof timeString === 'string') {
      // Если это время в формате HH:mm:ss или HH:mm
      if (timeString.includes(':') && !timeString.includes('T') && !timeString.includes('1970')) {
        return timeString.substring(0, 5);
      }
      // Если это дата-время, извлекаем только время
      if (timeString.includes('T')) {
        const timePart = timeString.split('T')[1];
        if (timePart && !timePart.includes('1970')) {
          return timePart.substring(0, 5);
        }
      }
      // Проверяем, что это не дата 1970
      if (timeString.includes('1970')) {
        return '';
      }
      return timeString.substring(0, 5);
    }
    return timeString;
  };

  return (
    <div className="dashboard">
      <div className="dashboard-nav">
        {['statistics', 'analysis', 'drivers', 'routes', 'trips', 'users', 'bookings'].map(t => {
          const labels = {
            'statistics': 'СТАТИСТИКА',
            'analysis': 'АНАЛИЗ МАРШРУТОВ',
            'drivers': 'ВОДИТЕЛИ',
            'routes': 'МАРШРУТЫ',
            'trips': 'РЕЙСЫ',
            'users': 'ПОЛЬЗОВАТЕЛИ',
            'bookings': 'БРОНИРОВАНИЯ'
          };
          return (
            <button key={t} className={`nav-btn ${table === t ? 'active' : ''}`} onClick={() => setTable(t)}>
              {labels[t] || t.toUpperCase()}
            </button>
          );
        })}
      </div>

      <div className="card">
        <h3>
          {table === 'statistics' ? 'Статистика системы' : 
           table === 'analysis' ? 'Анализ маршрутов' : 
           table === 'drivers' ? 'Управление: водители' :
           table === 'routes' ? 'Управление: маршруты' :
           table === 'trips' ? 'Управление: рейсы' :
           table === 'users' ? 'Управление: пользователи' :
           table === 'bookings' ? 'Управление: бронирования' :
           `Управление: ${table}`}
        </h3>
        
        {/* JSON экспорт/импорт только для бронирований */}
        {table === 'bookings' && (
          <div className="json-actions">
            <div className="json-section">
              <h4>Экспорт {table === 'drivers' ? 'водителей' : table === 'routes' ? 'маршрутов' : table === 'trips' ? 'рейсов' : table === 'users' ? 'пользователей' : table === 'bookings' ? 'бронирований' : table} в JSON</h4>
              <button className="btn btn-primary" onClick={() => handleExportJson(table)}>Экспортировать в JSON</button>
            </div>
            <div className="json-section">
              <h4>Импорт {table === 'drivers' ? 'водителей' : table === 'routes' ? 'маршрутов' : table === 'trips' ? 'рейсов' : table === 'users' ? 'пользователей' : table === 'bookings' ? 'бронирований' : table} из JSON</h4>
              <div style={{ marginBottom: '10px' }}>
                <label style={{ display: 'block', marginBottom: '5px', fontWeight: 'bold' }}>
                  Загрузить JSON файл:
                </label>
                <input 
                  type="file" 
                  accept=".json"
                  onChange={(e) => handleFileImport(e, table)}
                  style={{ marginBottom: '10px' }}
                />
              </div>
            </div>
          </div>
        )}
        
        {/* Отображение статистики */}
        {table === 'statistics' && data.length > 0 && (
          <div className="stats-grid">
            <div className="stat-card">
              <div className="stat-value">{data[0].TotalRoutes ?? 0}</div>
              <div className="stat-label">Маршрутов</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{data[0].ActiveTrips ?? 0}</div>
              <div className="stat-label">Активных рейсов</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{data[0].ActiveBookings ?? 0}</div>
              <div className="stat-label">Активных бронирований</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{data[0].TotalBookings ?? 0}</div>
              <div className="stat-label">Всего бронирований</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{data[0].TotalUsers ?? 0}</div>
              <div className="stat-label">Пользователей</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{data[0].ActiveDrivers ?? 0}</div>
              <div className="stat-label">Активных водителей</div>
            </div>
            <div className="stat-card revenue">
              <div className="stat-value" style={{ fontSize: '2rem' }}>
                {Math.round(data[0].TotalRevenue ?? 0)} BYN
              </div>
              <div className="stat-label">Общая выручка</div>
            </div>
          </div>
        )}
        
        {/* Форма добавления */}
        {table === 'drivers' && (
            <form onSubmit={handleAdd} className="admin-form">
                <h4>Добавить Водителя</h4>
                <div className="admin-form-row">
                    <input placeholder="ФИО" value={form.FullName || ''} onChange={e => setForm({...form, FullName: e.target.value})} required />
                    <input placeholder="Лицензия" value={form.LicenseNumber || ''} onChange={e => setForm({...form, LicenseNumber: e.target.value})} required />
                    <input 
                      placeholder="Телефон (+375291153368)" 
                      value={form.Phone || ''} 
                      onChange={(e) => {
                        const value = e.target.value;
                        // Разрешаем ввод любых символов, проверка будет при submit
                        setForm({...form, Phone: value});
                      }}
                      maxLength={13}
                      required 
                    />
                    <input 
                      placeholder="Опыт (лет)" 
                      type="number" 
                      min="0"
                      step="1"
                      value={form.ExperienceYears || ''} 
                      onChange={e => {
                        const val = parseInt(e.target.value);
                        if (!isNaN(val) && val >= 0) {
                          setForm({...form, ExperienceYears: val});
                        } else if (e.target.value === '') {
                          setForm({...form, ExperienceYears: ''});
                        }
                      }} 
                      required 
                    />
                    <button className="btn btn-primary">Добавить</button>
                </div>
            </form>
        )}

        {table === 'routes' && (
            <form onSubmit={handleAdd} className="admin-form">
                <h4>Добавить Маршрут</h4>
                <div className="admin-form-row">
                    <input placeholder="Название маршрута" value={form.RouteName || ''} onChange={e => setForm({...form, RouteName: e.target.value})} required />
                    <input placeholder="Город отправления" value={form.DepartureCity || ''} onChange={e => setForm({...form, DepartureCity: e.target.value})} required />
                    <input placeholder="Город прибытия" value={form.ArrivalCity || ''} onChange={e => setForm({...form, ArrivalCity: e.target.value})} required />
                    <input 
                      placeholder="Расстояние (км)" 
                      type="number" 
                      min="1"
                      step="1"
                      value={form.DistanceKm || ''} 
                      onChange={e => {
                        const val = parseInt(e.target.value);
                        if (!isNaN(val) && val > 0) {
                          setForm({...form, DistanceKm: val});
                        } else if (e.target.value === '') {
                          setForm({...form, DistanceKm: ''});
                        }
                      }} 
                      required 
                    />
                    <input 
                      placeholder="Длительность (мин)" 
                      type="number" 
                      min="1"
                      step="1"
                      value={form.DurationMinutes || ''} 
                      onChange={e => {
                        const val = parseInt(e.target.value);
                        if (!isNaN(val) && val > 0) {
                          setForm({...form, DurationMinutes: val});
                        } else if (e.target.value === '') {
                          setForm({...form, DurationMinutes: ''});
                        }
                      }} 
                      required 
                    />
                    <input 
                      placeholder="Цена (BYN)" 
                      type="number" 
                      min="0.01"
                      step="0.01"
                      value={form.BasePrice || ''} 
                      onChange={e => {
                        const val = parseFloat(e.target.value);
                        if (!isNaN(val) && val > 0) {
                          setForm({...form, BasePrice: val});
                        } else if (e.target.value === '') {
                          setForm({...form, BasePrice: ''});
                        }
                      }} 
                      required 
                    />
                    <button className="btn btn-primary">Добавить</button>
                </div>
            </form>
        )}

        {/* Форма добавления рейса */}
        {table === 'trips' && (
            <form onSubmit={handleAdd} className="admin-form">
                <h4>Добавить Рейс</h4>
                <div className="admin-form-row">
                    <input 
                      placeholder="ID маршрута" 
                      type="number" 
                      min="1"
                      step="1"
                      value={form.RouteID || ''} 
                      onChange={e => {
                        const val = parseInt(e.target.value);
                        if (!isNaN(val) && val > 0) {
                          setForm({...form, RouteID: val});
                        } else if (e.target.value === '') {
                          setForm({...form, RouteID: ''});
                        }
                      }} 
                      required 
                    />
                    <input 
                      placeholder="ID водителя" 
                      type="number" 
                      min="1"
                      step="1"
                      value={form.DriverID || ''} 
                      onChange={e => {
                        const val = parseInt(e.target.value);
                        if (!isNaN(val) && val > 0) {
                          setForm({...form, DriverID: val});
                        } else if (e.target.value === '') {
                          setForm({...form, DriverID: ''});
                        }
                      }} 
                      required 
                    />
                    <input 
                      placeholder="Дата рейса" 
                      type="date" 
                      value={form.TripDate || ''} 
                      onChange={e => setForm({...form, TripDate: e.target.value})} 
                      min={new Date().toISOString().split('T')[0]}
                      required 
                    />
                    <input 
                      placeholder="Время отправления (HH:mm)" 
                      type="time" 
                      value={form.DepartureTime || ''} 
                      onChange={e => setForm({...form, DepartureTime: e.target.value})} 
                      required 
                    />
                    <button className="btn btn-primary">Добавить</button>
                </div>
            </form>
        )}

        {(table !== 'statistics' || data.length === 0) && (
          <>
            {/* Фильтры - минималистичный дизайн */}
            {data.length > 0 && (
              <div className="filters-section-minimal">
                <div className="filters-row">
                  {keys.slice(0, 6).map(k => (
                    <input
                      key={k}
                      type="text"
                      className="filter-input"
                      placeholder={getColumnName(k)}
                      value={filters[k] || ''}
                      onChange={(e) => handleFilterChange(k, e.target.value)}
                    />
                  ))}
                  {Object.keys(filters).some(k => filters[k]) && (
                    <button 
                      className="btn btn-secondary small-btn" 
                      onClick={() => setFilters({})}
                      title="Сбросить фильтры"
                    >
                      ✕
                    </button>
                  )}
                </div>
              </div>
            )}

            {/* Информация о пагинации */}
            {filteredData.length > 0 && (
              <div style={{ marginBottom: '15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
                <div>
                  <span>Показано: {paginatedData.length} из {filteredData.length} записей</span>
                  <select 
                    value={itemsPerPage} 
                    onChange={(e) => {
                      setItemsPerPage(Number(e.target.value));
                      setCurrentPage(1);
                    }}
                    style={{ marginLeft: '10px', padding: '5px' }}
                  >
                    <option value={10}>10 на странице</option>
                    <option value={20}>20 на странице</option>
                    <option value={50}>50 на странице</option>
                    <option value={100}>100 на странице</option>
                  </select>
                </div>
                {totalPages > 1 && (
                  <div style={{ display: 'flex', gap: '5px', alignItems: 'center' }}>
                    <button 
                      className="btn btn-secondary small-btn"
                      onClick={() => setCurrentPage(1)}
                      disabled={currentPage === 1}
                    >
                      ««
                    </button>
                    <button 
                      className="btn btn-secondary small-btn"
                      onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                      disabled={currentPage === 1}
                    >
                      «
                    </button>
                    <span>Страница {currentPage} из {totalPages}</span>
                    <button 
                      className="btn btn-secondary small-btn"
                      onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                      disabled={currentPage === totalPages}
                    >
                      »
                    </button>
                    <button 
                      className="btn btn-secondary small-btn"
                      onClick={() => setCurrentPage(totalPages)}
                      disabled={currentPage === totalPages}
                    >
                      »»
                    </button>
                  </div>
                )}
              </div>
            )}

            <div className="table-container">
                <table>
                    <thead>
                        <tr>
                            {keys.map(k => <th key={k}>{getColumnName(k)}</th>)}
                            {(table !== 'users' && table !== 'analysis') && <th>Действия</th>}
                        </tr>
                    </thead>
                    <tbody>
                        {loading ? (
                          <tr>
                            <td colSpan={keys.length + (table !== 'users' && table !== 'analysis' ? 1 : 0)} style={{textAlign: 'center', padding: '20px', color: 'var(--text-light)'}}>
                              Загрузка...
                            </td>
                          </tr>
                        ) : filteredData.length === 0 ? (
                          <tr>
                            <td colSpan={keys.length + (table !== 'users' && table !== 'analysis' ? 1 : 0)} style={{textAlign: 'center', padding: '20px', color: 'var(--text-light)'}}>
                              {data.length === 0 ? 'Нет данных' : 'Нет данных, соответствующих фильтрам'}
                            </td>
                          </tr>
                        ) : (
                          paginatedData.map((row, i) => {
                            const rowId = Object.values(row)[0];
                            return (
                              <tr key={i}>
                                  {keys.map(k => {
                                    // Специальная обработка для лицензии водителя
                                    if (table === 'drivers' && k === 'LicenseNumber') {
                                      let driverId = row.DriverID || rowId;
                                      // Нормализуем driverId к числу для консистентности
                                      if (driverId != null) {
                                        driverId = parseInt(driverId, 10);
                                      }
                                      const normalizedDriverId = !isNaN(driverId) ? driverId : null;
                                      return (
                                        <td key={k}>
                                          <span style={{ fontFamily: 'monospace', fontSize: '0.9em' }}>
                                            {getLicenseDisplay(row, rowId)}
                                          </span>
                                          {normalizedDriverId && !decryptedLicenses[normalizedDriverId] && !decryptedLicenses[String(normalizedDriverId)] && (
                                            <button 
                                              className="btn btn-secondary small-btn"
                                              onClick={() => setShowLicenseModal(normalizedDriverId)}
                                              style={{ marginLeft: '10px', fontSize: '0.85em' }}
                                              title="Нажмите для расшифровки лицензии (требуется пароль администратора)"
                                            >
                                              🔓 Расшифровать
                                            </button>
                                          )}
                                          {normalizedDriverId && (decryptedLicenses[normalizedDriverId] || decryptedLicenses[String(normalizedDriverId)]) && (
                                            <span style={{ marginLeft: '10px', color: 'green', fontSize: '0.9em' }}>
                                              ✓ Расшифровано
                                            </span>
                                          )}
                                        </td>
                                      );
                                    }
                                    return <td key={k}>{formatCellValue(k, row[k])}</td>;
                                  })}
                                  {(table !== 'users' && table !== 'analysis') && (
                                    <td>
                                        {table !== 'bookings' && table !== 'trips' && (
                                          <button 
                                            className="btn btn-primary small-btn" 
                                            onClick={() => {
                                              if (table === 'drivers') {
                                                setEditingItem({ type: 'drivers', data: {...row} });
                                              } else if (table === 'routes') {
                                                setEditingItem({ type: 'routes', data: {...row} });
                                              } else if (table === 'trips') {
                                              // Правильно обрабатываем время для редактирования
                                              const tripData = {...row};
                                              // Преобразуем время в формат HH:mm для input type="time"
                                              // Используем raw значение из row, не отформатированное
                                              let rawTime = row.DepartureTime;
                                              
                                              // Обрабатываем все возможные форматы времени
                                              if (rawTime !== null && rawTime !== undefined && rawTime !== '') {
                                                // Если это объект Date
                                                if (rawTime instanceof Date) {
                                                  const hours = String(rawTime.getHours()).padStart(2, '0');
                                                  const minutes = String(rawTime.getMinutes()).padStart(2, '0');
                                                  tripData.DepartureTime = `${hours}:${minutes}`;
                                                }
                                                // Если это строка
                                                else if (typeof rawTime === 'string') {
                                                  // Убираем возможные пробелы
                                                  rawTime = rawTime.trim();
                                                  
                                                  // Пропускаем строки с '1970' или 'T' (дата-время)
                                                  if (rawTime.includes('1970') || rawTime.includes('T')) {
                                                    tripData.DepartureTime = '';
                                                  }
                                                  // Если время в формате HH:mm:ss или HH:mm
                                                  else if (rawTime.includes(':')) {
                                                    const timeParts = rawTime.split(':');
                                                    if (timeParts.length >= 2) {
                                                      const hours = timeParts[0].trim();
                                                      const minutes = timeParts[1].trim();
                                                      // Проверяем, что это валидные числа
                                                      const hoursNum = parseInt(hours, 10);
                                                      const minutesNum = parseInt(minutes, 10);
                                                      if (!isNaN(hoursNum) && !isNaN(minutesNum) && hoursNum >= 0 && hoursNum <= 23 && minutesNum >= 0 && minutesNum <= 59) {
                                                        tripData.DepartureTime = `${String(hoursNum).padStart(2, '0')}:${String(minutesNum).padStart(2, '0')}`;
                                                      } else {
                                                        tripData.DepartureTime = '';
                                                      }
                                                    } else {
                                                      tripData.DepartureTime = '';
                                                    }
                                                  } else {
                                                    tripData.DepartureTime = '';
                                                  }
                                                }
                                                // Если это число (миллисекунды), преобразуем в Date
                                                else if (typeof rawTime === 'number') {
                                                  const date = new Date(rawTime);
                                                  if (!isNaN(date.getTime())) {
                                                    const hours = String(date.getHours()).padStart(2, '0');
                                                    const minutes = String(date.getMinutes()).padStart(2, '0');
                                                    tripData.DepartureTime = `${hours}:${minutes}`;
                                                  } else {
                                                    tripData.DepartureTime = '';
                                                  }
                                                }
                                                // Если это другой тип
                                                else {
                                                  tripData.DepartureTime = '';
                                                }
                                              } else {
                                                tripData.DepartureTime = '';
                                              }
                                              
                                              setEditingItem({ type: 'trips', data: tripData });
                                            }
                                          }}
                                          style={{ marginRight: '8px', width: '80px' }}
                                        >
                                          Изменить
                                        </button>
                                        )}
                                        <button className="btn btn-danger small-btn" onClick={() => handleDelete(rowId)} style={{ width: '80px' }}>Удалить</button>
                                    </td>
                                  )}
                              </tr>
                            );
                          })
                        )}
                    </tbody>
                </table>
            </div>

            {/* Модальное окно для редактирования */}
            {editingItem && (
              <div className="modal-overlay" onClick={() => setEditingItem(null)}>
                <div className="modal-content" ref={editingModalRef} onClick={(e) => e.stopPropagation()} tabIndex={-1}>
                  <div className="modal-header">
                    <h3>
                      {editingItem.type === 'drivers' ? 'Редактировать водителя' :
                       editingItem.type === 'routes' ? 'Редактировать маршрут' :
                       editingItem.type === 'trips' ? 'Редактировать рейс' : 'Редактировать'}
                    </h3>
                    <button className="modal-close" onClick={() => setEditingItem(null)}>×</button>
                  </div>
                  <div className="modal-body">
                    <form onSubmit={handleUpdate}>
                      {editingItem.type === 'drivers' && (
                        <>
                          <div className="form-group">
                            <label>ФИО:</label>
                            <input 
                              value={editingItem.data.FullName || ''} 
                              onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, FullName: e.target.value}})} 
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Телефон:</label>
                            <input 
                              value={editingItem.data.Phone || ''} 
                              onChange={e => {
                                const value = e.target.value;
                                // Разрешаем ввод любых символов, проверка будет при submit
                                setEditingItem({...editingItem, data: {...editingItem.data, Phone: value}});
                              }}
                              placeholder="+375291153368"
                              maxLength={13}
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Опыт (лет):</label>
                            <input 
                              type="number" 
                              min="0"
                              step="1"
                              value={editingItem.data.ExperienceYears || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, ExperienceYears: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, ExperienceYears: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              <input 
                                type="checkbox"
                                checked={editingItem.data.IsActive === true || editingItem.data.IsActive === 1} 
                                onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, IsActive: e.target.checked ? 1 : 0}})} 
                                style={{ width: '16px', height: '16px', margin: 0 }}
                              />
                              Активен
                            </label>
                          </div>
                        </>
                      )}
                      
                      {editingItem.type === 'routes' && (
                        <>
                          <div className="form-group">
                            <label>Название маршрута:</label>
                            <input 
                              value={editingItem.data.RouteName || ''} 
                              onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, RouteName: e.target.value}})} 
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Город отправления:</label>
                            <input 
                              value={editingItem.data.DepartureCity || ''} 
                              onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, DepartureCity: e.target.value}})} 
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Город прибытия:</label>
                            <input 
                              value={editingItem.data.ArrivalCity || ''} 
                              onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, ArrivalCity: e.target.value}})} 
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Расстояние (км):</label>
                            <input 
                              type="number" 
                              min="1"
                              step="1"
                              value={editingItem.data.DistanceKm || editingItem.data.DistanceKM || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DistanceKm: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DistanceKm: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label>Длительность (мин):</label>
                            <input 
                              type="number" 
                              min="1"
                              step="1"
                              value={editingItem.data.DurationMinutes || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DurationMinutes: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DurationMinutes: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label>Всего мест:</label>
                            <input 
                              type="number" 
                              min="1"
                              step="1"
                              value={editingItem.data.TotalSeats || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, TotalSeats: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, TotalSeats: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label>Цена (BYN):</label>
                            <input 
                              type="number" 
                              min="0.01"
                              step="0.01"
                              value={editingItem.data.BasePrice || 0} 
                              onChange={e => {
                                const val = parseFloat(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, BasePrice: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, BasePrice: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                        </>
                      )}
                      
                      {editingItem.type === 'trips' && (
                        <>
                          <div className="form-group">
                            <label>ID маршрута:</label>
                            <input 
                              type="number" 
                              min="1"
                              step="1"
                              value={editingItem.data.RouteID || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, RouteID: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, RouteID: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label>ID водителя:</label>
                            <input 
                              type="number" 
                              min="1"
                              step="1"
                              value={editingItem.data.DriverID || 0} 
                              onChange={e => {
                                const val = parseInt(e.target.value);
                                if (!isNaN(val) && val >= 0) {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DriverID: val}});
                                } else if (e.target.value === '') {
                                  setEditingItem({...editingItem, data: {...editingItem.data, DriverID: ''}});
                                }
                              }} 
                              required 
                              style={{ WebkitAppearance: 'textfield', MozAppearance: 'textfield' }}
                            />
                          </div>
                          <div className="form-group">
                            <label>Дата:</label>
                            <input 
                              type="date" 
                              value={editingItem.data.TripDate ? (typeof editingItem.data.TripDate === 'string' && editingItem.data.TripDate.includes('T') ? editingItem.data.TripDate.split('T')[0] : (typeof editingItem.data.TripDate === 'string' ? editingItem.data.TripDate : '')) : ''} 
                              onChange={e => setEditingItem({...editingItem, data: {...editingItem.data, TripDate: e.target.value}})} 
                              required 
                            />
                          </div>
                          <div className="form-group">
                            <label>Время отправления:</label>
                            <input 
                              type="time" 
                              value={(() => {
                                const time = editingItem.data.DepartureTime;
                                if (!time && time !== 0) return '';
                                
                                // Всегда работаем со строками в формате HH:mm
                                if (typeof time === 'string') {
                                  // Убираем пробелы
                                  const cleanTime = time.trim();
                                  
                                  // Если время в формате HH:mm:ss, обрезаем до HH:mm
                                  if (cleanTime.includes(':')) {
                                    const timeParts = cleanTime.split(':');
                                    if (timeParts.length >= 2) {
                                      const hours = timeParts[0].trim();
                                      const minutes = timeParts[1].trim();
                                      // Проверяем, что это валидные числа
                                      if (!isNaN(parseInt(hours, 10)) && !isNaN(parseInt(minutes, 10))) {
                                        return `${hours.padStart(2, '0')}:${minutes.padStart(2, '0')}`;
                                      }
                                    }
                                  }
                                  // Если уже в формате HH:mm, возвращаем как есть
                                  if (cleanTime.match(/^\d{1,2}:\d{2}$/)) {
                                    const parts = cleanTime.split(':');
                                    return `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}`;
                                  }
                                } else if (time instanceof Date) {
                                  // Если это объект Date, преобразуем в HH:mm
                                  const hours = String(time.getHours()).padStart(2, '0');
                                  const minutes = String(time.getMinutes()).padStart(2, '0');
                                  return `${hours}:${minutes}`;
                                } else if (typeof time === 'number') {
                                  // Если это число (миллисекунды), преобразуем в Date
                                  const date = new Date(time);
                                  if (!isNaN(date.getTime())) {
                                    const hours = String(date.getHours()).padStart(2, '0');
                                    const minutes = String(date.getMinutes()).padStart(2, '0');
                                    return `${hours}:${minutes}`;
                                  }
                                }
                                return '';
                              })()} 
                              onChange={e => {
                                // Сохраняем время в формате HH:mm
                                setEditingItem({...editingItem, data: {...editingItem.data, DepartureTime: e.target.value}});
                              }} 
                              required 
                            />
                          </div>
                        </>
                      )}
                      
                      <div className="modal-footer">
                        <button type="button" className="btn btn-secondary" onClick={() => setEditingItem(null)}>
                          Отмена
                        </button>
                        <button type="submit" className="btn btn-primary">
                          Сохранить
                        </button>
                      </div>
                    </form>
                  </div>
                </div>
              </div>
            )}

            {/* Модальное окно для расшифровки лицензии */}
            {showLicenseModal && (
              <div className="modal-overlay" onClick={() => {
                setShowLicenseModal(null);
                setLicensePassword('');
              }}>
                <div className="modal-content" onClick={(e) => e.stopPropagation()}>
                  <div className="modal-header">
                    <h3>Расшифровка лицензии водителя</h3>
                    <button className="modal-close" onClick={() => {
                      setShowLicenseModal(null);
                      setLicensePassword('');
                    }}>×</button>
                  </div>
                  <div className="modal-body">
                  <p>Введите пароль администратора для расшифровки:</p>
                    <input
                      type="password"
                      value={licensePassword}
                      onChange={(e) => setLicensePassword(e.target.value)}
                      placeholder="Пароль администратора"
                      style={{ width: '100%', padding: '12px', marginBottom: '10px', borderRadius: '8px', border: '2px solid var(--border)', fontSize: '1rem' }}
                      onKeyPress={(e) => {
                        if (e.key === 'Enter') {
                          handleDecryptLicense(showLicenseModal);
                        }
                      }}
                      autoFocus
                    />
                  </div>
                  <div className="modal-footer">
                    <button 
                      className="btn btn-secondary"
                      onClick={() => {
                        setShowLicenseModal(null);
                        setLicensePassword('');
                      }}
                    >
                      Отмена
                    </button>
                    <button 
                      className="btn btn-primary"
                      onClick={() => handleDecryptLicense(showLicenseModal)}
                    >
                      Расшифровать
                    </button>
                  </div>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
};

export default AdminDashboard;

