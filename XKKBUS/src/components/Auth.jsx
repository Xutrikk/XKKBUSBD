import React, { useState } from 'react';
import Message from './Message';

const API_URL = 'http://localhost:3001/api';

const Auth = ({ setUser }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [formData, setFormData] = useState({ login: '', password: '', fullName: '', phone: '', email: '' });
  const [msg, setMsg] = useState(null);

  const handleChange = (e) => setFormData({ ...formData, [e.target.name]: e.target.value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    const endpoint = isLogin ? 'login' : 'register';
    try {
      const res = await fetch(`${API_URL}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });
      const data = await res.json();
      if (res.ok && data.success) {
        if (isLogin) setUser(data.user);
        else {
          setMsg({ text: 'Регистрация успешна! Войдите.', type: 'success' });
          setIsLogin(true);
        }
      } else {
        setMsg({ text: data.message, type: 'error' });
      }
    } catch { setMsg({ text: 'Ошибка сервера', type: 'error' }); }
  };

  return (
    <div className="auth-wrapper">
      <div className="card auth-card">
        <div className="logo-container">
          <h1 className="logo-main">XKKBUS</h1>
          <p className="logo-subtitle">Система бронирования билетов</p>
        </div>
        <h2>{isLogin ? 'Вход' : 'Регистрация'}</h2>
        <Message text={msg?.text} type={msg?.type} />
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <input name="login" placeholder="Логин" onChange={handleChange} required />
          </div>
          <div className="form-group">
            <input type="password" name="password" placeholder="Пароль" onChange={handleChange} required />
          </div>
          {!isLogin && (
            <>
              <div className="form-group"><input name="fullName" placeholder="ФИО" onChange={handleChange} required /></div>
              <div className="form-group"><input name="phone" placeholder="Телефон" onChange={handleChange} required /></div>
              <div className="form-group"><input name="email" placeholder="Email" onChange={handleChange} /></div>
            </>
          )}
          <button type="submit" className="btn btn-primary btn-full-width">
            {isLogin ? 'Войти' : 'Зарегистрироваться'}
          </button>
        </form>
        <button onClick={() => setIsLogin(!isLogin)} className="toggle-link">
          {isLogin ? 'Нет аккаунта? Создать' : 'Уже есть аккаунт? Войти'}
        </button>
      </div>
    </div>
  );
};

export default Auth;

