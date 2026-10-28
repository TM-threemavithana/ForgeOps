-- ForgeOps Gate G13: Synthetic Test Dataset for Disaster Recovery Rehearsal
-- Enforces clean relational schema without real or sensitive data

-- Insert synthetic accounts (BCrypt hash for 'Password123!')
INSERT INTO accounts (id, username, password_hash, role)
VALUES
    ('d0000000-0000-0000-0000-000000000001', 'dr_admin', '$2a$12$Nq9v7e8Vn4X5K7e9W6z0OuY1t2r3s4a5b6c7d8e9f0g1h2i3j4k5l', 'ROLE_ADMIN'),
    ('d0000000-0000-0000-0000-000000000002', 'dr_user', '$2a$12$Nq9v7e8Vn4X5K7e9W6z0OuY1t2r3s4a5b6c7d8e9f0g1h2i3j4k5l', 'ROLE_USER')
ON CONFLICT (username) DO NOTHING;

-- Insert synthetic projects
INSERT INTO projects (id, owner_id, name, description, version)
VALUES
    ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'DR Verification Project Alpha', 'Primary synthetic project for disaster recovery rehearsal', 0),
    ('d1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'DR Rehearsal Project Beta', 'Secondary synthetic project for backup restoration testing', 0)
ON CONFLICT (id) DO NOTHING;

-- Insert synthetic tasks across distinct statuses and priorities
INSERT INTO tasks (id, project_id, assigned_account_id, title, description, status, priority, version)
VALUES
    ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Verify Backup Integrity', 'Automated SHA-256 and TOC inspection', 'TODO', 'HIGH', 0),
    ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'Rehearse Scratch Restore', 'Restore into fresh isolated PostgreSQL instance', 'IN_PROGRESS', 'HIGH', 0),
    ('d2000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'Validate Foreign Keys', 'Ensure zero orphaned projects or tasks post-restore', 'DONE', 'MEDIUM', 0),
    ('d2000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Document Observed RTO and RPO', 'Measure recovery time and backup data age', 'BLOCKED', 'LOW', 0)
ON CONFLICT (id) DO NOTHING;
