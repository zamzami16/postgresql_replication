# Failover simulation: pg_node1 goes down, pg_node2 becomes new primary
# Assumes resync_sequences.sql exists in the same directory

# Path to SQL script for sequence sync
$sequenceFixPath = Join-Path $PSScriptRoot "resync_sequences.sql"

if (-Not (Test-Path $sequenceFixPath)) {
    Write-Host "`nERROR: resync_sequences.sql not found at $sequenceFixPath"
    exit 1
}

Write-Host "`n`nStopping pg_node1 (old primary)..."
docker stop pg_node1

# Step 1: Drop old subscription from node1 on pg_node2
Write-Host "`n`nRemoving old subscription on pg_node2 (from pg_node1)..."
docker exec -i pg_node2 psql -U postgres -d postgres -c "ALTER SUBSCRIPTION sub_from_node1_to_node2 DISABLE;"
docker exec -i pg_node2 psql -U postgres -d postgres -c "ALTER SUBSCRIPTION sub_from_node1_to_node2 SET (slot_name = NONE);"
docker exec -i pg_node2 psql -U postgres -d postgres -c "DROP SUBSCRIPTION sub_from_node1_to_node2;"

# Step 2: Create publication on new primary (pg_node2)
Write-Host "`n`nCreating publication on pg_node2 (new primary)..."
docker exec -i pg_node2 psql -U postgres -d postgres -c "CREATE PUBLICATION pub_all FOR ALL TABLES;"

# Step 3: Remove old subscription on pg_node3 (from pg_node1)
Write-Host "`nRemoving old subscription on pg_node3..."
docker exec -i pg_node3 psql -U postgres -d postgres -c "ALTER SUBSCRIPTION sub_from_node1_to_node3 DISABLE;"
docker exec -i pg_node3 psql -U postgres -d postgres -c "ALTER SUBSCRIPTION sub_from_node1_to_node3 SET (slot_name = NONE);"
docker exec -i pg_node3 psql -U postgres -d postgres -c "DROP SUBSCRIPTION sub_from_node1_to_node3;"

# Step 4: Truncate replicated tables on pg_node3 with RESTART IDENTITY CASCADE
Write-Host "`nTruncating replicated tables on pg_node3 (restart identity)..."
docker exec -i pg_node3 psql -U postgres -d postgres -c "TRUNCATE users RESTART IDENTITY CASCADE;"

# Step 5: Create new subscription from pg_node2 to pg_node3
Write-Host "`nCreating new subscription on pg_node3 from pg_node2..."
docker exec -i pg_node3 psql -U postgres -d postgres -c "CREATE SUBSCRIPTION sub_from_node2_to_node3 CONNECTION 'host=host.docker.internal port=5442 user=postgres password=postgres dbname=postgres' PUBLICATION pub_all WITH (copy_data = true);"

# Step 6: Run resync_sequences.sql on pg_node2 to fix sequences
Write-Host "`nSyncing sequences on pg_node2..."
docker cp $sequenceFixPath pg_node2:/resync_sequences.sql
docker exec -i pg_node2 psql -U postgres -d postgres -f /resync_sequences.sql

# Step 7: Insert test data into pg_node2 (now primary)
Write-Host "`nInserting test data into pg_node2..."
docker exec -i pg_node2 psql -U postgres -d postgres -c "INSERT INTO users (username, email) VALUES ('after_failover', 'node2@example.com');"

# Step 8: Query pg_node3 and pg_node1 to verify replication (pg_node1 must be running)
Write-Host "`nChecking data replication on pg_node3..."
docker exec -i pg_node3 psql -U postgres -d postgres -c "SELECT * FROM users;"

Write-Host "`nChecking data replication on pg_node1 (if online)..."
docker exec -i pg_node1 psql -U postgres -d postgres -c "SELECT * FROM users;"
