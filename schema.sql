CREATE TABLE readers (
  id serial PRIMARY KEY,
  name text NOT NULL UNIQUE
);

INSERT INTO readers
(name)
VALUES
('Simeon'),
('Rya');

CREATE TABLE reading_sessions (
  id serial PRIMARY KEY,
  reader_id integer NOT NULL REFERENCES readers(id),
  session_date date NOT NULL DEFAULT CURRENT_DATE,
  pages_read integer NOT NULL
);

-- INSERT INTO reading_sessions
-- (reader_id, session_date, pages_read)
-- VALUES
-- (1, '2026-06-01', 10),
-- (1, '2026-06-02', 5),
-- (1, '2026-06-07', 20),
-- (1, DEFAULT, 5),
-- (2, '2026-06-01', 100),
-- (2, '2026-06-02', 50),
-- (2, '2026-06-07', 200),
-- (2, DEFAULT, 50);