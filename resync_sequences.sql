DO $$
DECLARE
    seq RECORD;
    current_max BIGINT;
BEGIN
    FOR seq IN
        SELECT s.relname AS sequence_name,
               t.relname AS table_name,
               a.attname AS column_name
        FROM pg_class s
        JOIN pg_depend d ON d.objid = s.oid
        JOIN pg_class t ON d.refobjid = t.oid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S'
    LOOP
        EXECUTE format('SELECT MAX(%I) FROM %I', seq.column_name, seq.table_name)
        INTO current_max;

        IF current_max IS NULL THEN
            current_max := 0;
        END IF;

        EXECUTE format('SELECT setval(%L, %s)', seq.sequence_name, current_max + 1);
    END LOOP;
END
$$;
