-- ForgeOps: ForgeTasks Development Seed Data (V1_1__dev_seed.sql)
-- Isolated in db/dev-data to preserve production schema purity.
-- Test accounts use BCrypt hashed passwords ('Password123!').

INSERT INTO accounts (id, username, password_hash, role)
VALUES 
    ('a0000000-0000-0000-0000-000000000001', 'dev_admin', '$2a$12$Nq9v7e8Vn4X5K7e9W6z0OuY1t2r3s4a5b6c7d8e9f0g1h2i3j4k5l', 'ROLE_ADMIN'),
    ('a0000000-0000-0000-0000-000000000002', 'dev_user', '$2a$12$Nq9v7e8Vn4X5K7e9W6z0OuY1t2r3s4a5b6c7d8e9f0g1h2i3j4k5l', 'ROLE_USER')
ON CONFLICT (username) DO NOTHING;
