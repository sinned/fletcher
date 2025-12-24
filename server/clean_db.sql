-- Clean all data from Fletcher database
-- WARNING: This will delete ALL users, locations, tokens, and logs

TRUNCATE TABLE access_logs CASCADE;
TRUNCATE TABLE assistant_connections CASCADE;
TRUNCATE TABLE locations CASCADE;
TRUNCATE TABLE users CASCADE;

-- Verify cleanup
SELECT 'users' as table_name, COUNT(*) as count FROM users
UNION ALL
SELECT 'locations', COUNT(*) FROM locations
UNION ALL
SELECT 'assistant_connections', COUNT(*) FROM assistant_connections
UNION ALL
SELECT 'access_logs', COUNT(*) FROM access_logs;
