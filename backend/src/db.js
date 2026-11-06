import mysql from 'mysql2/promise';

export function createPool(driver = mysql) {
  const pool = driver.createPool({
    host: process.env.MYSQL_HOST ?? '127.0.0.1',
    port: Number(process.env.MYSQL_PORT ?? 3306),
    user: process.env.MYSQL_USER ?? 'coscircle',
    password: process.env.MYSQL_PASSWORD ?? 'coscircle',
    database: process.env.MYSQL_DATABASE ?? 'coscircle',
    waitForConnections: true,
    connectionLimit: 10,
    timezone: 'Z',
  });
  // TIMESTAMP reads and CURRENT_TIMESTAMP must share the UTC wire contract.
  pool.on('connection', connection => {
    connection.query("SET time_zone = '+00:00'", error => {
      if (error) connection.destroy();
    });
  });
  return pool;
}
