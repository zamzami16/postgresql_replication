# Rebuild pg_node1 as a fresh replica of pg_node2

# Set schema path
$schemaPath = Join-Path $PSScriptRoot "schema.sql"

if (-Not (Test-Path $schemaPath)) {
    Write-Host "`nERROR: schema.sql not found in $schemaPath"
    exit 1
}

Write-Host "`nRemoving old pg_node1 container and volume..."
docker rm -f pg_node1
docker volume rm replication_pg_node1_data

Write-Host "`nRecreating pg_node1 container..."
docker compose up -d pg_node1

# Wait for PostgreSQL to be ready
function Wait-For-Postgres {
    param ([string]$container)
    Write-Host "`nWaiting for $container to become ready..."
    for ($i = 0; $i -lt 30; $i++) {
        $result = docker exec -i $container pg_isready -U postgres
        if ($result -like "*accepting connections*") {
            return
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "`nERROR: $container did not become ready in time." -ForegroundColor Red
    exit 1
}

Wait-For-Postgres -container "pg_node1"

Write-Host "`nReapplying schema.sql to pg_node1..."
docker cp $schemaPath pg_node1:/schema.sql
docker exec -i pg_node1 psql -U postgres -d postgres -f /schema.sql

Write-Host "`nSetting replication configuration on pg_node1..."
docker exec -i pg_node1 psql -U postgres -d postgres -c "ALTER SYSTEM SET wal_level = logical;"
docker exec -i pg_node1 psql -U postgres -d postgres -c "ALTER SYSTEM SET max_replication_slots = 10;"
docker exec -i pg_node1 psql -U postgres -d postgres -c "ALTER SYSTEM SET max_wal_senders = 10;"

Write-Host "`nRestarting pg_node1 to apply settings..."
docker restart pg_node1
Wait-For-Postgres -container "pg_node1"

Write-Host "`nCreating subscription on pg_node1 to replicate from pg_node2..."
docker exec -i pg_node1 psql -U postgres -d postgres -c "CREATE SUBSCRIPTION sub_from_node2_to_node1 CONNECTION 'host=host.docker.internal port=5442 user=postgres password=postgres dbname=postgres' PUBLICATION pub_all;"

Write-Host "`n"
Write-Host "`n pg_node1 is now rebuilt and replicating from pg_node2."

Write-Host "`nChecking data replication on pg_node1..."
docker exec -i pg_node1 psql -U postgres -d postgres -c "SELECT * FROM users;"
