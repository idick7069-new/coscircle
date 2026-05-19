import mysql from 'mysql2/promise';

export function createPool() {
  return mysql.createPool({
    host: process.env.MYSQL_HOST ?? '127.0.0.1',
    port: Number(process.env.MYSQL_PORT ?? 3306),
    user: process.env.MYSQL_USER ?? 'coscircle',
    password: process.env.MYSQL_PASSWORD ?? 'coscircle',
    database: process.env.MYSQL_DATABASE ?? 'coscircle',
    waitForConnections: true,
    connectionLimit: 10
  });
}
