# SeaweedFS Setup Prerequisites

Before starting the SeaweedFS cluster, complete the following steps.

---

## 1. Create the Shared Docker Network

Create the external Docker network used by SeaweedFS and PostgreSQL:

```bash
docker network create shared_network
```

> If the network already exists, Docker will return an error that can be safely ignored.

---

## 2. Start PostgreSQL

Ensure your PostgreSQL container is running and attached to the `shared_network` network.

Verify connectivity before proceeding.

---

## 3. Create the SeaweedFS Database

Connect to PostgreSQL and create a dedicated database for SeaweedFS metadata:

```sql
CREATE DATABASE seaweedfs;
```

---

## 4. Initialize the Required Database Schema

Connect to the `seaweedfs` database and execute the following DDL statements.

### File Metadata Table

```sql
CREATE TABLE IF NOT EXISTS filemeta (
    dirhash BIGINT,
    name VARCHAR(65535),
    directory VARCHAR(65535),
    meta BYTEA,
    PRIMARY KEY (dirhash, name)
);
```

### Configuration Table

```sql
CREATE TABLE IF NOT EXISTS configuration (
    id INT PRIMARY KEY,
    value BYTEA
);
```

---

## 5. Verify the Tables

Run the following query to confirm the tables were created successfully:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public';
```

Expected result:

```text
configuration
filemeta
```

---

## 6. Deploy SeaweedFS

After completing the steps above, start the SeaweedFS Docker Compose stack:

```bash
docker compose up -d
```

---

## Architecture Overview

```text
Application
    │
    ▼
Seaweed S3 Gateway (1120)
    │
    ▼
Seaweed Filer
    │
    ▼
PostgreSQL (Metadata)
    │
    ▼
Seaweed Masters (Cluster)
    │
    ▼
Seaweed Volume Servers
```

### Responsibilities

| Component              | Responsibility                             |
| ---------------------- | ------------------------------------------ |
| PostgreSQL             | Stores filer metadata                      |
| Seaweed Masters        | Cluster coordination and volume assignment |
| Seaweed Volume Servers | Stores actual file contents                |
| Seaweed Filer          | Metadata and filesystem abstraction        |
| Seaweed S3 Gateway     | S3-compatible API endpoint                 |

---

## S3 Endpoint

After deployment, use:

```text
http://<host>:1120
```

as your S3-compatible endpoint.
