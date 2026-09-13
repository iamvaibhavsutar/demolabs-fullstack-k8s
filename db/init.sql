-- Runs once, automatically, on first Postgres container start
-- (mounted into /docker-entrypoint-initdb.d/ via ConfigMap)
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    done BOOLEAN DEFAULT FALSE
);

INSERT INTO tasks (title, done) VALUES ('Set up demolabs namespace', TRUE);
