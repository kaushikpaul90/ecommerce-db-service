-- Simple init script: creates database and items table if not exists
CREATE TABLE IF NOT EXISTS items (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT
);
