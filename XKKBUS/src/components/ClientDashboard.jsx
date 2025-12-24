import React, { useState, useEffect, useCallback } from 'react';

const API_URL = 'http://localhost:3001/api';

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

const ClientDashboard = ({ user }) => {
  const [view, setView] = useState('search');
  const [routes, setRoutes] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [selectedTrip, setSelectedTrip] = useState(null);
  const [selectedTripDriver, setSelectedTripDriver] = useState(null);
  const [showDriverModal, setShowDriverModal] = useState(null);
  
  // Для динамического поиска
  const [departureCities, setDepartureCities] = useState([]);
  const [arrivalCities, setArrivalCities] = useState([]);
  const [selectedDepartureCity, setSelectedDepartureCity] = useState('');
  const [selectedArrivalCity, setSelectedArrivalCity] = useState('');
  const [selectedDate, setSelectedDate] = useState('');
  const [searchMessage, setSearchMessage] = useState('');
  
  // Для бронирования
  const [seats, setSeats] = useState([]);
  const [selectedSeat, setSelectedSeat] = useState(null);
  const [passName, setPassName] = useState(user?.FullName || '');
  const [passPhone, setPassPhone] = useState(user?.Phone || '');
  
  // Пагинация для "Мои билеты"
  const [currentBookingsPage, setCurrentBookingsPage] = useState(1);
  const bookingsPerPage = 10;

  const fetchBookings = useCallback(() => {
    if (!user?.UserID) return;
    fetch(`${API_URL}/user-bookings/${user.UserID}`)
      .then(r => r.json())
      .then(setBookings)
      .catch(err => console.error('Ошибка загрузки бронирований:', err));
  }, [user?.UserID]);

  // Загрузка списка городов отправления
  useEffect(() => {
    fetch(`${API_URL}/routes`)
      .then(r => r.json())
      .then(data => {
        setRoutes(data);
        const cities = [...new Set(data.map(r => r.DepartureCity))].sort();
        setDepartureCities(cities);
      })
      .catch(err => console.error('Ошибка загрузки маршрутов:', err));
    fetchBookings();
  }, [fetchBookings]);

  // Обновление телефона при изменении пользователя (но не блокируем ввод)
  useEffect(() => {
    if (user?.Phone && !passPhone) {
      setPassPhone(user.Phone);
    }
  }, [user]);

  // Обновление списка городов прибытия при выборе города отправления
  useEffect(() => {
    if (selectedDepartureCity) {
      const availableArrivals = routes
        .filter(r => r.DepartureCity === selectedDepartureCity)
        .map(r => r.ArrivalCity);
      const uniqueArrivals = [...new Set(availableArrivals)].sort();
      setArrivalCities(uniqueArrivals);
      setSelectedArrivalCity('');
    } else {
      setArrivalCities([]);
      setSelectedArrivalCity('');
    }
    setSearchResults([]);
    setSearchMessage('');
  }, [selectedDepartureCity, routes]);

  // Поиск рейсов по городам и дате
  const handleSearchRoutes = async () => {
    if (!selectedDepartureCity || !selectedArrivalCity || !selectedDate) {
      setSearchMessage('⚠️ Пожалуйста, заполните все поля для поиска: город отправления, город прибытия и дату поездки.');
      return;
    }
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const searchDate = new Date(selectedDate);
    searchDate.setHours(0, 0, 0, 0);
    
    if (searchDate < today) {
      setSearchMessage('⚠️ Нельзя выбрать прошедшую дату. Пожалуйста, выберите сегодняшнюю или будущую дату.');
      return;
    }
    
    setSearchMessage('🔍 Поиск рейсов...');
    setSearchResults([]);
    
    try {
      const res = await fetch(`${API_URL}/routes/search?departureCity=${encodeURIComponent(selectedDepartureCity)}&arrivalCity=${encodeURIComponent(selectedArrivalCity)}&tripDate=${selectedDate}`);
      const data = await res.json();
      
      if (data.success === false && data.message) {
        setSearchMessage(`❌ ${data.message}`);
        setSearchResults([]);
      } else if (data.routes && data.routes.length > 0) {
        // Фильтруем прошедшие рейсы (по дате и времени)
        const now = new Date();
        const filteredRoutes = data.routes.filter(route => {
          if (!route.TripDate) return false;
          const tripDate = new Date(route.TripDate);
          tripDate.setHours(0, 0, 0, 0);
          const today = new Date();
          today.setHours(0, 0, 0, 0);
          
          // Если дата рейса в прошлом, исключаем
          if (tripDate < today) return false;
          
          // Если дата рейса сегодня, проверяем время отправления
          if (tripDate.getTime() === today.getTime() && route.DepartureTime) {
            const [hours, minutes] = route.DepartureTime.split(':').map(Number);
            const departureTime = new Date();
            departureTime.setHours(hours || 0, minutes || 0, 0, 0);
            // Если время отправления уже прошло, исключаем
            if (departureTime < now) return false;
          }
          
          return true;
        });
        
        setSearchResults(filteredRoutes);
        if (filteredRoutes.length > 0) {
          setSearchMessage(`✅ Найдено рейсов: ${filteredRoutes.length}`);
        } else {
          setSearchMessage('❌ По вашему запросу не найдено доступных рейсов. Все найденные рейсы уже прошли.');
        }
      } else {
        setSearchMessage('❌ По вашему запросу ничего не найдено. Попробуйте изменить параметры поиска или выбрать другую дату.');
        setSearchResults([]);
      }
    } catch (error) {
      setSearchMessage('❌ Ошибка поиска: ' + error.message);
      setSearchResults([]);
    }
  };

  const openBooking = async (trip) => {
    setSelectedTrip(trip);
    // Сохраняем информацию о водителе из результатов поиска
    if (trip.DriverID) {
      setSelectedTripDriver({
        DriverID: trip.DriverID,
        FullName: trip.DriverFullName,
        Phone: trip.DriverPhone,
        ExperienceYears: trip.DriverExperience
      });
    }
    try {
      const res = await fetch(`${API_URL}/trip-availability/${trip.TripID}`);
      const occupiedData = await res.json();
      const occupiedNums = occupiedData.filter(b => !b.IsCancelled).map(b => b.SeatNumber);

      const totalSeats = trip.TotalSeats || trip.AvailableSeats + occupiedNums.length || 50;
      const newSeats = [];
      for(let i=1; i<=totalSeats; i++) {
        newSeats.push({ num: i, occupied: occupiedNums.includes(i) });
      }
      setSeats(newSeats);
      setSelectedSeat(null);
    } catch (error) {
      alert('Ошибка загрузки информации о местах: ' + error.message);
    }
  };

  const bookTicket = async () => {
    if(!selectedSeat) return;
    
    // Убираем дефисы из телефона
    let phoneValue = passPhone;
    if (phoneValue && typeof phoneValue === 'string') {
      phoneValue = phoneValue.replace(/-/g, '');
    }
    
    // Проверка формата телефона перед бронированием
    if (!phoneValue || !/^\+375\d{9}$/.test(phoneValue)) {
      alert('Телефон должен быть в формате +375XXXXXXXXX (13 символов, только цифры после +375)');
      return;
    }
    try {
      const res = await fetch(`${API_URL}/book-ticket`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          tripId: selectedTrip.TripID,
          userId: user.UserID,
          seatNumber: selectedSeat,
          passengerName: passName,
          passengerPhone: phoneValue
        })
      });
      const data = await res.json();
      if(data.success) {
        alert('Билет забронирован!');
        setSelectedTrip(null);
        setSelectedSeat(null);
        setSelectedTripDriver(null);
        fetchBookings(); // Обновляем список бронирований
        // Обновляем результаты поиска, чтобы показать обновленное количество мест
        if (selectedDepartureCity && selectedArrivalCity && selectedDate) {
          handleSearchRoutes();
        }
      } else {
        alert(data.message || 'Ошибка бронирования');
      }
    } catch (error) {
      alert('Ошибка бронирования: ' + error.message);
    }
  };

  const cancelBooking = async (id) => {
    if(!window.confirm('Отменить бронь?')) return;
    try {
      const res = await fetch(`${API_URL}/cancel-booking/${id}?userId=${user.UserID}`, { method: 'DELETE' });
      const data = await res.json();
      if(data.success) {
        // Удаляем отмененное бронирование из списка сразу
        setBookings(prev => prev.filter(b => b.BookingID !== id));
        alert('Бронирование успешно отменено');
      } else {
        alert(data.message || 'Ошибка отмены бронирования');
      }
    } catch (error) {
      alert('Ошибка отмены бронирования: ' + error.message);
    }
  };

  // Получаем минимальную дату (сегодня)
  const getMinDate = () => {
    const today = new Date();
    return today.toISOString().split('T')[0];
  };

  // Получаем максимальную дату (через год)
  const getMaxDate = () => {
    const maxDate = new Date();
    maxDate.setFullYear(maxDate.getFullYear() + 1);
    return maxDate.toISOString().split('T')[0];
  };

  return (
    <div className="dashboard">
      <div className="dashboard-nav">
        <button className={`nav-btn ${view === 'search' ? 'active' : ''}`} onClick={() => setView('search')}>Поиск Рейсов</button>
        <button className={`nav-btn ${view === 'bookings' ? 'active' : ''}`} onClick={() => setView('bookings')}>Мои Билеты</button>
      </div>

      {view === 'search' && (
        <div className="card">
          <h3>Поиск Рейсов</h3>
          
          {/* Динамический поиск по городам и дате */}
          <div className="search-filters">
            <div className="form-group">
              <label>Город отправления:</label>
              <select 
                className="styled-select"
                value={selectedDepartureCity}
                onChange={(e) => setSelectedDepartureCity(e.target.value)}
              >
                <option value="">Выберите город отправления...</option>
                {departureCities.map(city => (
                  <option key={city} value={city}>{city}</option>
                ))}
              </select>
            </div>
            
            <div className="form-group">
              <label>Город прибытия:</label>
              <select 
                className="styled-select"
                value={selectedArrivalCity}
                onChange={(e) => setSelectedArrivalCity(e.target.value)}
                disabled={!selectedDepartureCity}
              >
                <option value="">Выберите город прибытия...</option>
                {arrivalCities.map(city => (
                  <option key={city} value={city}>{city}</option>
                ))}
              </select>
            </div>
            
            <div className="form-group">
              <label>Дата поездки:</label>
              <input 
                type="date" 
                className="styled-input"
                value={selectedDate}
                onChange={(e) => setSelectedDate(e.target.value)}
                min={getMinDate()}
                max={getMaxDate()}
              />
            </div>
            
            <button 
              className="btn btn-primary" 
              onClick={handleSearchRoutes}
              disabled={!selectedDepartureCity || !selectedArrivalCity || !selectedDate}
            >
              Найти рейсы
            </button>
            
            {(selectedDepartureCity || selectedArrivalCity || selectedDate) && (
              <button 
                className="btn btn-secondary" 
                onClick={() => {
                  setSelectedDepartureCity('');
                  setSelectedArrivalCity('');
                  setSelectedDate('');
                  setSearchResults([]);
                  setSearchMessage('');
                }}
              >
                Сбросить
              </button>
            )}
          </div>

          {searchMessage && (
            <div className={`message ${searchResults.length > 0 ? 'info' : 'error'}`}>
              {searchMessage}
            </div>
          )}

          {!selectedTrip && searchResults.length > 0 && (
            <div className="trips-list">
              <h4>Найденные рейсы:</h4>
              {searchResults.map(trip => (
                <div key={trip.TripID} className="trip-item">
                  <div>
                    <strong>Маршрут:</strong> {trip.RouteName || `${trip.DepartureCity} → ${trip.ArrivalCity}`}<br/>
                    <strong>Дата:</strong> {formatDate(trip.TripDate)} {trip.DepartureTime ? `в ${formatTime(trip.DepartureTime)}` : ''}<br/>
                    <small>Свободных мест: {trip.AvailableSeats !== undefined ? trip.AvailableSeats : (trip.TotalSeats - trip.BookedSeats || 0)}</small>
                    {trip.DriverID && (
                      <div style={{ marginTop: '8px' }}>
                        <button 
                          className="btn btn-secondary small-btn"
                          onClick={() => setShowDriverModal(trip)}
                          style={{ fontSize: '0.85em' }}
                        >
                          ℹ️ Информация о водителе
                        </button>
                      </div>
                    )}
                  </div>
                  <div>
                    <strong>{trip.BasePrice || trip.PricePaid || 0} BYN</strong>
                    <button 
                      className="btn btn-primary btn-margin-left" 
                      onClick={() => openBooking(trip)}
                      disabled={!trip.AvailableSeats || trip.AvailableSeats <= 0}
                    >
                      Выбрать
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {selectedTrip && (
            <div className="booking-area">
              <h4>Бронирование: {selectedTrip.RouteName}</h4>
              
              <div className="bus-layout">
                {seats.map(s => (
                  <button 
                    key={s.num} 
                    className={`seat ${s.occupied ? 'occupied' : 'available'} ${selectedSeat === s.num ? 'selected' : ''}`}
                    onClick={() => !s.occupied && setSelectedSeat(s.num)}
                    disabled={s.occupied}
                  >
                    {s.num}
                  </button>
                ))}
              </div>
              
              <div className="form-group">
                <label>Пассажир:</label>
                <input value={passName} onChange={e => setPassName(e.target.value)} />
              </div>
              <div className="form-group">
                <label>Телефон:</label>
                <input 
                  value={passPhone} 
                  onChange={(e) => {
                    const value = e.target.value;
                    // Разрешаем ввод любых символов, проверка будет при submit
                    setPassPhone(value);
                  }}
                  placeholder="+375291153368"
                  maxLength={13}
                />
              </div>
              <button className="btn btn-primary" onClick={bookTicket} disabled={!selectedSeat}>Подтвердить бронь</button>
              <button className="btn btn-secondary btn-margin-left" onClick={() => {
                setSelectedTrip(null);
                setSelectedTripDriver(null);
              }}>Отмена</button>
            </div>
          )}
        </div>
      )}

      {view === 'bookings' && (
        <div className="card">
          <h3>Мои Бронирования</h3>
          {(() => {
            const activeBookings = bookings.filter(b => !b.IsCancelled);
            const totalBookingsPages = Math.ceil(activeBookings.length / bookingsPerPage);
            const startIndex = (currentBookingsPage - 1) * bookingsPerPage;
            const endIndex = startIndex + bookingsPerPage;
            const paginatedBookings = activeBookings.slice(startIndex, endIndex);
            
            return (
              <>
                {activeBookings.length === 0 ? (
                  <div className="message info">У вас нет бронирований</div>
                ) : (
                  <>
                    {paginatedBookings.map(b => (
                      <div key={b.BookingID} className="booking-item">
                        <div>
                          <strong>Рейс:</strong> {b.RouteName} <br/>
                          <strong>Дата:</strong> {formatDate(b.TripDate)} {b.DepartureTime ? formatTime(b.DepartureTime) : ''} <br/>
                          <strong>Место:</strong> {b.SeatNumber} <br/>
                          <strong>Цена:</strong> {b.PricePaid} BYN <br/>
                          <span className="status-badge active">АКТИВНО</span>
                        </div>
                        <button className="btn btn-danger" onClick={() => cancelBooking(b.BookingID)}>Отменить</button>
                      </div>
                    ))}
                    {totalBookingsPages > 1 && (
                      <div style={{ marginTop: '20px', display: 'flex', justifyContent: 'center', gap: '10px', alignItems: 'center' }}>
                        <button 
                          className="btn btn-secondary small-btn"
                          onClick={() => setCurrentBookingsPage(1)}
                          disabled={currentBookingsPage === 1}
                        >
                          ««
                        </button>
                        <button 
                          className="btn btn-secondary small-btn"
                          onClick={() => setCurrentBookingsPage(p => Math.max(1, p - 1))}
                          disabled={currentBookingsPage === 1}
                        >
                          «
                        </button>
                        <span style={{ padding: '0 15px' }}>
                          Страница {currentBookingsPage} из {totalBookingsPages}
                        </span>
                        <button 
                          className="btn btn-secondary small-btn"
                          onClick={() => setCurrentBookingsPage(p => Math.min(totalBookingsPages, p + 1))}
                          disabled={currentBookingsPage === totalBookingsPages}
                        >
                          »
                        </button>
                        <button 
                          className="btn btn-secondary small-btn"
                          onClick={() => setCurrentBookingsPage(totalBookingsPages)}
                          disabled={currentBookingsPage === totalBookingsPages}
                        >
                          »»
                        </button>
                      </div>
                    )}
                  </>
                )}
              </>
            );
          })()}
        </div>
      )}

      {/* Модальное окно с информацией о водителе */}
      {showDriverModal && (
        <div className="modal-overlay" onClick={() => setShowDriverModal(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>Информация о водителе</h3>
              <button className="modal-close" onClick={() => setShowDriverModal(null)}>×</button>
            </div>
            <div className="modal-body">
              <div className="driver-info">
                <div className="info-row">
                  <strong>ФИО:</strong> {showDriverModal.DriverFullName || 'Не указано'}
                </div>
                <div className="info-row">
                  <strong>Телефон:</strong> {showDriverModal.DriverPhone || 'Не указан'}
                </div>
                <div className="info-row">
                  <strong>Опыт работы:</strong> {showDriverModal.DriverExperience || 0} лет
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowDriverModal(null)}>Закрыть</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ClientDashboard;
