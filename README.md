[README_EN.md](https://github.com/user-attachments/files/29192915/README_EN.md)
# WordPress on PostgreSQL with JumpServer PAM

A fully containerized deployment of WordPress backed by **PostgreSQL** (not MySQL), served behind **Nginx**, with privileged access managed through **JumpServer**, an open-source Privileged Access Management (PAM) platform.

![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=flat-square&logo=nginx&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-21759B?style=flat-square&logo=wordpress&logoColor=white)
![License](https://img.shields.io/badge/license-Educational-lightgrey?style=flat-square)

---

## Overview

This project deploys a complete WordPress stack on Docker with two distinguishing characteristics:

- **WordPress runs on PostgreSQL instead of MySQL**, made possible by the PG4WP compatibility layer.
- **All administrative access is brokered through JumpServer**, a bastion host that holds credentials, records every session, and removes the need for direct SSH access to the application containers.

The stack is intended as a reference for system administrators and DevOps engineers who need to run WordPress on PostgreSQL while enforcing controlled, auditable access to infrastructure.

| Component | Role | Exposed Port |
|-----------|------|--------------|
| Nginx | Web server | 80 |
| PostgreSQL | WordPress database | 5432 (internal) |
| WordPress | Application (via PG4WP) | 8080 |
| JumpServer | PAM / bastion host | 8088, 2222 |

---

## Architecture

```
                          +-----------------+
                          |  Administrator  |
                          +--------+--------+
                                   | HTTPS / SSH
                                   v
                          +-----------------+
                          |   JumpServer    |   PAM - session recording
                          |  Port 8088/2222 |
                          +--------+--------+
                                   | SSH (172.18.0.x)
                                   v
        +----------------------------------------------+
        |          Docker Network (wp-network)         |
        |                                              |
        |  +---------+   +----------+   +-----------+  |
        |  |  Nginx  |   | WordPress|   | PostgreSQL|  |
        |  |   :80   |   |  :8080   |---|   :5432   |  |
        |  |         |   |  (PG4WP) |   |           |  |
        |  +---------+   +----------+   +-----------+  |
        |                                              |
        +----------------------------------------------+
                     Host: Ubuntu 24 (VMware)
```

**Request flow**

1. Administrators connect through JumpServer rather than SSHing directly into any server.
2. JumpServer stores the target credentials and records each session for audit.
3. WordPress serves requests and persists all data to PostgreSQL through PG4WP.

---

## Prerequisites

- Ubuntu 24.04 (tested on VMware)
- Minimum 4 GB RAM (JumpServer is resource-intensive)
- Minimum 20 GB disk (larger images require headroom)
- `sudo` privileges
- Outbound internet access

> **Note:** The JumpServer, PostgreSQL, and WordPress images are large. Provision sufficient disk space to avoid a `No space left on device` failure during setup.

---

## 1. Install Docker

```bash
# Update the system and install dependencies
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install the Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker run hello-world
```

**Expected result:** the message `Hello from Docker!` is printed.

---

## 2. Nginx

```bash
# Create a shared Docker network so the containers can reach each other
docker network create wp-network

# Run Nginx
docker run -d \
  --name nginx \
  --network wp-network \
  -p 80:80 \
  nginx
```

**Verify:** open `http://<server-ip>` and confirm the "Welcome to nginx!" page.

---

## 3. PostgreSQL

```bash
docker run -d \
  --name postgres \
  --network wp-network \
  -e POSTGRES_DB=wordpress \
  -e POSTGRES_USER=wpuser \
  -e POSTGRES_PASSWORD=wppassword \
  postgres
```

**Verify:** `docker ps` shows the `postgres` container in the `Up` state.

---

## 4. WordPress with PG4WP

The official WordPress image targets MySQL by default. A custom image is required to bundle the **PG4WP** compatibility layer so WordPress can communicate with PostgreSQL.

### 4.1 Create the Dockerfile

```bash
mkdir ~/wordpress-pg && cd ~/wordpress-pg

cat > Dockerfile << 'EOF'
FROM wordpress:latest

RUN apt-get update && apt-get install -y \
    libpq-dev \
    unzip \
    git \
    && docker-php-ext-install pdo pdo_pgsql pgsql

RUN git clone --branch v3.4.1 https://github.com/PostgreSQL-For-Wordpress/postgresql-for-wordpress.git /tmp/pg4wp-repo \
    && cp -r /tmp/pg4wp-repo/pg4wp /var/www/html/wp-content/pg4wp \
    && cp /var/www/html/wp-content/pg4wp/db.php /var/www/html/wp-content/db.php \
    && rm -rf /tmp/pg4wp-repo
EOF
```

> **About PG4WP:** the plugin intercepts the MySQL driver calls that WordPress issues and rewrites them into PostgreSQL queries. This lets WordPress run on PostgreSQL without MySQL present anywhere in the system. This build pins version **v3.4.1**, the latest release.

### 4.2 Build and run

```bash
# Build the image
docker build -t wordpress-pg .

# Run WordPress
docker run -d \
  --name wordpress \
  --network wp-network \
  -e WORDPRESS_DB_HOST=postgres \
  -e WORDPRESS_DB_USER=wpuser \
  -e WORDPRESS_DB_PASSWORD=wppassword \
  -e WORDPRESS_DB_NAME=wordpress \
  -e WORDPRESS_DB_TYPE=pgsql \
  -p 8080:80 \
  wordpress-pg
```

**Verify:** open `http://<server-ip>:8080` and confirm the WordPress installer (language selection) appears.

---

## 5. JumpServer (PAM)

JumpServer requires its own PostgreSQL and Redis instances, so the full set is managed with Docker Compose.

### 5.1 Create docker-compose.yml

```bash
mkdir ~/jumpserver && cd ~/jumpserver

cat > docker-compose.yml << 'EOF'
services:
  db:
    image: postgres:16
    container_name: jumpserver_db
    restart: always
    environment:
      - POSTGRES_DB=jumpserver
      - POSTGRES_USER=jumpserver
      - POSTGRES_PASSWORD=jumpserver
    volumes:
      - db_data:/var/lib/postgresql/data

  redis:
    image: redis:7
    container_name: jumpserver_redis
    restart: always
    command: redis-server --requirepass jumpserver

  jumpserver:
    image: jumpserver/jms_all:latest
    container_name: jumpserver
    restart: always
    privileged: true
    environment:
      - SECRET_KEY=jumpserversecretkey1234567890abcdef
      - BOOTSTRAP_TOKEN=bootstraptoken1234
      - LOG_LEVEL=ERROR
      - DB_ENGINE=postgresql
      - DB_HOST=db
      - DB_PORT=5432
      - DB_USER=jumpserver
      - DB_PASSWORD=jumpserver
      - DB_NAME=jumpserver
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=jumpserver
      - DOMAINS=<server-ip>:8088
    ports:
      - "8088:80"
      - "2222:2222"
    depends_on:
      - db
      - redis

volumes:
  db_data:
EOF
```

> Replace `<server-ip>` in `DOMAINS` with the host's real IP, for example `192.168.91.146:8088`.

### 5.2 Start the stack

```bash
docker compose up -d

# Inspect the logs (allow 2-3 minutes for initialization)
docker logs jumpserver --tail 20
```

**Verify:** open `http://<server-ip>:8088` and sign in with `admin` / `admin`.

> **Important:** Use **PostgreSQL 16**, not 13. Recent JumpServer releases issue the `REFRESH COLLATION VERSION` statement, which is only supported on PostgreSQL 14 and later.

---

## 6. Remote Access to WordPress via JumpServer

### 6.1 Prepare the WordPress container for SSH

```bash
# Install and configure SSH and Python (required by JumpServer's Ansible checks)
docker exec -it wordpress bash -c "\
  apt-get update && \
  apt-get install -y openssh-server python3 && \
  ln -sf /usr/bin/python3 /usr/bin/python && \
  mkdir -p /run/sshd && \
  echo 'root:p@ssword' | chpasswd && \
  sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  /usr/sbin/sshd"

# Attach JumpServer to the same network as WordPress
docker network connect wp-network jumpserver

# Find the WordPress container's IP
docker inspect wordpress | grep IPAddress
```

### 6.2 Configure the asset in JumpServer (Web UI)

1. **Assets → Asset list → Create → Linux**
   - Name: `WordPress`
   - IP/Host: `172.18.0.4` (the IP from the previous step)
   - Platform: `Linux`, Port: `22`
   - Nodes: `DEFAULT`
2. **Add an account:** username `root`, password `p@ssword`, marked as privileged.
3. **Permissions → Asset Permissions → Create**
   - Users: `admin`
   - Assets: `WordPress`
   - Accounts: `All`
4. **Test:** select the asset and run **Test connectivity**. A successful run reports `ok=1`.

### 6.3 Connect through the web terminal

Open `http://<server-ip>:8088/luna/`, select the **WordPress** asset, and the terminal session opens.

**Confirm:** run `ls /var/www/html` and verify the WordPress files (`wp-config.php`, `wp-content`, and so on) are listed.

---

## Troubleshooting

Issues encountered during setup, with their causes and resolutions.

| # | Symptom | Cause | Resolution |
|---|---------|-------|------------|
| 1 | `REMOTE HOST IDENTIFICATION HAS CHANGED` | Stale SSH host key | `ssh-keygen -R <ip>`, then reconnect |
| 2 | `su: Authentication failure` | Ubuntu disables direct root login | Use `sudo su` or `sudo -i` |
| 3 | `unzip: not found` during build | Base image lacks unzip | Add `unzip` to the Dockerfile |
| 4 | `End-of-central-directory signature not found` | curl did not follow the GitHub redirect | Use `git clone` instead |
| 5 | WordPress targets MySQL, not PostgreSQL | Default image uses MySQL | Build a custom image with PG4WP |
| 6 | `No space left on device` | Disk full | `docker image prune -a`, or extend the disk with `lvextend` and `resize2fs` |
| 7 | `database "jumpserver" does not exist` | JumpServer has no database of its own | Add a dedicated PostgreSQL service to Compose |
| 8 | `AUTH called without any password` (Redis) | Redis has no password set | Add `--requirepass` and `REDIS_PASSWORD` |
| 9 | `syntax error at or near "REFRESH"` | PostgreSQL 13 is too old | Switch to `postgres:16` |
| 10 | `Configuration file has problems` at login | `DOMAINS` not configured | Add `DOMAINS=<ip>:8088` |
| 11 | Asset reported `UNREACHABLE` (SSH timeout) | JumpServer and WordPress on different networks | `docker network connect wp-network jumpserver` |
| 12 | `Invalid/incorrect password` | Container and JumpServer passwords differ | Align them with `chpasswd` |
| 13 | `/usr/bin/python: not found` (Ansible) | WordPress container lacks Python | Install `python3` and symlink it to `python` |
| 14 | Empty asset tree in Luna | No asset permission configured | Create an asset permission linking the user to the asset |

### Disk extension (related to issue 6)

```bash
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
df -h   # confirm the new free space
```

---

## Revision History

| Version | Date | Description | Author |
|---------|------|-------------|--------|
| 1.0 | 2026-06-22 | Initial release covering the full stack | - |

---

## References

- [PG4WP — PostgreSQL for WordPress](https://github.com/PostgreSQL-For-Wordpress/postgresql-for-wordpress)
- [JumpServer](https://www.jumpserver.org)
- [Docker Documentation](https://docs.docker.com)

---

<div align="center">
Prepared for educational purposes — Docker, PostgreSQL, and JumpServer lab.
</div>
