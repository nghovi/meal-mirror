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

  create table if not exists users (
    id bigint primary key auto_increment,
    sync_key varchar(128) null unique,
    display_name varchar(120) not null default 'Meal Mirror User',
    phone_number varchar(20) null unique,
    password_hash varchar(255) null,
    auth_provider varchar(20) not null default 'device',
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp on update current_timestamp
  );

  create table if not exists user_sessions (
    session_token varchar(64) primary key,
    user_id bigint not null,
    expires_at datetime not null,
    created_at timestamp default current_timestamp,
    index idx_user_sessions_user_id (user_id),
    constraint fk_user_sessions_user_id
      foreign key (user_id) references users(id)
      on delete cascade
  );

  create table if not exists user_snapshots (
    user_id bigint primary key,
    snapshot_json longtext not null,
    updated_at datetime not null,
    created_at timestamp default current_timestamp,
    synced_at timestamp default current_timestamp on update current_timestamp,
    constraint fk_user_snapshots_user_id
      foreign key (user_id) references users(id)
      on delete cascade
  );

  create table if not exists devices (
    id bigint primary key auto_increment,
    user_id bigint not null,
    device_id varchar(128) not null unique,
    last_seen_at datetime not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp on update current_timestamp,
    constraint fk_devices_user_id
      foreign key (user_id) references users(id)
      on delete cascade
  );

  create table if not exists meal_types (
    id tinyint primary key,
    slug varchar(24) not null unique,
    label varchar(24) not null
  );

  create table if not exists meals (
    id bigint primary key auto_increment,
    user_id bigint not null,
    device_id varchar(128) not null,
    external_meal_id varchar(191) not null,
    meal_type_id tinyint not null,
    captured_at datetime not null,
    feeling_rating tinyint not null default 3,
    feeling_note varchar(255) not null default '',
    drink_volume_ml int not null default 0,
    ai_suggested_summary text not null,
    ai_suggested_calories int not null default 0,
    ai_review text not null,
    is_shared_meal tinyint(1) not null default 0,
    shared_meal_people_count int not null default 1,
    user_portion_percent int not null default 100,
    user_edited_summary text null,
    user_edited_calories int null,
    tags_json json not null,
    raw_json longtext not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp on update current_timestamp,
    unique key uq_meals_device_external (device_id, external_meal_id),
    index idx_meals_user_captured_at (user_id, captured_at),
    constraint fk_meals_user_id
      foreign key (user_id) references users(id)
      on delete cascade,
    constraint fk_meals_meal_type_id
      foreign key (meal_type_id) references meal_types(id)
  );

  create table if not exists meal_images (
    id bigint primary key auto_increment,
    meal_id bigint not null,
    sort_order int not null default 0,
    image_url text not null,
    created_at timestamp default current_timestamp,
    index idx_meal_images_meal_id (meal_id),
    constraint fk_meal_images_meal_id
      foreign key (meal_id) references meals(id)
      on delete cascade
  );

  create table if not exists diet_goals (
    id bigint primary key auto_increment,
    user_id bigint not null unique,
    mission text not null,
    ai_brief text not null,
    goal_updated_at datetime not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp on update current_timestamp,
    constraint fk_diet_goals_user_id
      foreign key (user_id) references users(id)
      on delete cascade
  );

  create table if not exists mira_conversations (
    id bigint primary key auto_increment,
    user_id bigint not null unique,
    title varchar(120) not null default 'Mira Chat',
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp on update current_timestamp,
    constraint fk_mira_conversations_user_id
      foreign key (user_id) references users(id)
      on delete cascade
  );

  create table if not exists mira_messages (
    id bigint primary key auto_increment,
    conversation_id bigint not null,
    sort_order int not null,
    role varchar(16) not null,
    text longtext not null,
    created_at timestamp default current_timestamp,
    index idx_mira_messages_conversation_id (conversation_id),
    constraint fk_mira_messages_conversation_id
      foreign key (conversation_id) references mira_conversations(id)
      on delete cascade
  );
`);

await connection.query(`
  insert into meal_types (id, slug, label) values
    (1, 'breakfast', 'Breakfast'),
    (2, 'lunch', 'Lunch'),
    (3, 'dinner', 'Dinner'),
    (4, 'snack', 'Snack'),
    (5, 'drink', 'Drink')
  on duplicate key update
    slug = values(slug),
    label = values(label)
`);

await connection.query(`
  alter table users
    modify column sync_key varchar(128) null
`);

async function hasColumn(tableName, columnName) {
  const [rows] = await connection.query(
    `select 1
     from information_schema.columns
     where table_schema = ?
       and table_name = ?
       and column_name = ?
     limit 1`,
    [config.database, tableName, columnName]
  );
  return rows.length > 0;
}

if (!(await hasColumn("users", "phone_number"))) {
  await connection.query(`
    alter table users
      add column phone_number varchar(20) null after display_name,
      add unique key uq_users_phone_number (phone_number)
  `);
}

if (!(await hasColumn("users", "password_hash"))) {
  await connection.query(`
    alter table users
      add column password_hash varchar(255) null after phone_number
  `);
}

if (!(await hasColumn("users", "auth_provider"))) {
  await connection.query(`
    alter table users
      add column auth_provider varchar(20) not null default 'device' after password_hash
  `);
}

await connection.end();

console.log(`Meal Mirror MySQL setup complete for database: ${config.database}`);
