import React, { useState } from 'react';
import './App.css';
import Auth from './components/Auth';
import ClientDashboard from './components/ClientDashboard';
import AdminDashboard from './components/AdminDashboard';

const App = () => {
  const [user, setUser] = useState(null);

  return (
    <div className="app-container">
      <header className="header">
        <div className="logo-header">
          <span className="logo-main">XKKBUS</span>
          <span className="logo-tagline">Бронирование билетов</span>
        </div>
        {user && (
          <div className="user-nav">
            <span className={`role-badge ${user.Role === 'admin' ? 'admin' : ''}`}>{user.Role}</span>
            <span>{user.FullName}</span>
            <button className="btn btn-secondary small-btn" onClick={() => setUser(null)}>Выход</button>
          </div>
        )}
      </header>

      <main>
        {!user ? <Auth setUser={setUser} /> : (
            user.Role === 'admin' ? <AdminDashboard user={user} /> : <ClientDashboard user={user} />
        )}
      </main>
    </div>
  );
};

export default App;
