# Full Setup Script for PostgreSQL Logical Replication with Docker
# Ensure you're running this from the same folder as schema.sql and docker-compose.yml

# Variables
$schemaPath = Join-Path $PSScriptRoot "schema.sql"
$nodes = @("pg_node1", "pg_node2", "pg_node3")
$ports = @{ pg_node1 = 5441; pg_node2 = 5442; pg_node3 = 5443 }

# Step 1: Bring down and clean up
Write-Host "Stopping existing containers and cleaning volumes..."
docker compose down -v
docker volume prune -f

# Step 2: Start containers
Write-Host "`nStarting PostgreSQL containers..."
docker compose up -d

# Step 3: Apply schema to all nodes
if (-Not (Test-Path $schemaPath)) {
    Write-Host "ERROR: schema.sql not found in $schemaPath"
    exit 1
}

function Wait-For-Postgres {
    param (
        [string]$container
    )
    Write-Host "Waiting for $container to become ready..."
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $result = docker exec -i $container pg_isready -U postgres
        if ($result -like "*accepting connections*") {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Write-Host "ERROR: $container did not become ready in time." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nWaiting for PostgreSQL containers to become ready..."
foreach ($node in $nodes) {
    Wait-For-Postgres -container $node
}

Write-Host "`nApplying schema.sql to all nodes..."
foreach ($node in $nodes) {
    docker cp $schemaPath "${node}:/schema.sql"
    docker exec -i $node psql -U postgres -d postgres -f /schema.sql
}


# Step 4: Set replication config
Write-Host "`nConfiguring replication parameters on all nodes..."
foreach ($node in $nodes) {
    docker exec -i $node psql -U postgres -d postgres -c "ALTER SYSTEM SET wal_level = logical;"
    docker exec -i $node psql -U postgres -d postgres -c "ALTER SYSTEM SET max_replication_slots = 10;"
    docker exec -i $node psql -U postgres -d postgres -c "ALTER SYSTEM SET max_wal_senders = 10;"
}

# Step 5: Restart containers
Write-Host "`nRestarting containers to apply replication settings..."
foreach ($node in $nodes) {
    docker restart $node
}

# Step 6: Create publication on pg_node1
Write-Host "`nCreating publication on pg_node1..."
docker exec -i pg_node1 psql -U postgres -d postgres -c "CREATE PUBLICATION pub_all FOR ALL TABLES;"

# Step 7: Create subscriptions on pg_node2 and pg_node3
Write-Host "`nCreating subscriptions..."
docker exec -i pg_node2 psql -U postgres -d postgres -c "CREATE SUBSCRIPTION sub_from_node1_to_node2 CONNECTION 'host=host.docker.internal port=5441 user=postgres password=postgres dbname=postgres' PUBLICATION pub_all;"
docker exec -i pg_node3 psql -U postgres -d postgres -c "CREATE SUBSCRIPTION sub_from_node1_to_node3 CONNECTION 'host=host.docker.internal port=5441 user=postgres password=postgres dbname=postgres' PUBLICATION pub_all;"

Write-Host "`n Setup complete: logical replication is active across all nodes."

Write-Host ""
Write-Host "Insert into node1"
docker exec -i pg_node1 psql -U postgres -d postgres -c "insert into users (username, email) values ('user1', 'email1'), ('user2', 'email2');"

Write-Host ""
Write-Host "get data on node1"
docker exec -i pg_node1 psql -U postgres -d postgres -c "select * from users;";


Write-Host ""
Write-Host "get data on node2"
docker exec -i pg_node2 psql -U postgres -d postgres -c "select * from users;";


Write-Host ""
Write-Host "get data on node3"
docker exec -i pg_node3 psql -U postgres -d postgres -c "select * from users;";
