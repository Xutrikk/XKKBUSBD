import React from 'react';

const Message = ({ text, type }) => {
  if (!text) return null;
  return <div className={`message ${type}`}>{text}</div>;
};

export default Message;

