import mysql from "mysql2/promise";

const config = {
  host: process.env.MEAL_MIRROR_DB_HOST || process.env.DB_HOST || "127.0.0.1",
  port: Number(process.env.MEAL_MIRROR_DB_PORT || process.env.DB_PORT || 3306),
  user: process.env.MEAL_MIRROR_DB_USERNAME || process.env.DB_USERNAME || "root",
  password:
    process.env.MEAL_MIRROR_DB_PASSWORD || process.env.DB_PASSWORD || "",
  database: process.env.MEAL_MIRROR_DB_DATABASE || "meal_mirror"
};

const connection = await mysql.createConnection({
  host: config.host,
  port: config.port,
  user: config.user,
  password: config.password,
  multipleStatements: true
});

await connection.query(
  `create database if not exists \`${config.database}\`
   character set utf8mb4
   collate utf8mb4_unicode_ci`
);

await connection.changeUser({ database: config.database });

await connection.query(`
  create table if not exists device_snapshots (
    device_id varchar(128) primary key,
    snapshot_json longtext not null,
    updated_at datetime not null,
    created_at timestamp default current_timestamp,
    synced_at timestamp default current_timestamp on update current_timestamp
  );
`);

await connection.end();

console.log(`Meal Mirror MySQL setup complete for database: ${config.database}`);
