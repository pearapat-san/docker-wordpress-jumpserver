[README.md](https://github.com/user-attachments/files/29192157/README.md)
# 🐳 WordPress + PostgreSQL + JumpServer (PAM) บน Docker

> ระบบ deploy WordPress ที่ใช้ **PostgreSQL** เป็นฐานข้อมูล (ไม่ใช้ MySQL) ทำงานบน **Docker** และเข้าถึงผ่าน **JumpServer** ซึ่งเป็น Open Source PAM (Privileged Access Management) Tool

![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=flat&logo=nginx&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-21759B?style=flat&logo=wordpress&logoColor=white)
![JumpServer](https://img.shields.io/badge/JumpServer-PAM-1ABC9C?style=flat)

---

## 📑 สารบัญ (Table of Contents)

1. [ภาพรวมระบบ (Overview)](#-ภาพรวมระบบ-overview)
2. [Architecture Diagram](#-architecture-diagram)
3. [สิ่งที่ต้องมีก่อน (Prerequisites)](#-สิ่งที่ต้องมีก่อน-prerequisites)
4. [ส่วนที่ 1: ติดตั้ง Docker](#-ส่วนที่-1-ติดตั้ง-docker)
5. [ส่วนที่ 2: Nginx](#-ส่วนที่-2-nginx)
6. [ส่วนที่ 3: PostgreSQL](#-ส่วนที่-3-postgresql)
7. [ส่วนที่ 4: WordPress + PG4WP](#-ส่วนที่-4-wordpress--pg4wp)
8. [ส่วนที่ 5: JumpServer (PAM)](#-ส่วนที่-5-jumpserver-pam)
9. [ส่วนที่ 6: Remote เข้า WordPress ผ่าน JumpServer](#-ส่วนที่-6-remote-เข้า-wordpress-ผ่าน-jumpserver)
10. [Troubleshooting](#-troubleshooting-ปัญหาที่เจอและวิธีแก้)
11. [Revision History](#-revision-history)

---

## 🎯 ภาพรวมระบบ (Overview)

ระบบนี้เป็นการ deploy เว็บไซต์ WordPress แบบ container ทั้งหมดบน Docker โดยมีจุดเด่นคือ:

- **WordPress ใช้ PostgreSQL แทน MySQL** ผ่าน plugin PG4WP (PostgreSQL for WordPress)
- **เข้าถึงเครื่องผ่าน JumpServer** ซึ่งเป็น PAM Tool ที่ทำหน้าที่เป็นตัวกลาง (bastion host) บันทึก session ทุกครั้งที่มีการ remote เข้า server

**กลุ่มเป้าหมายของเอกสาร:** ผู้ดูแลระบบ (System Admin), DevOps, หรือผู้ที่ต้องการ deploy WordPress + PostgreSQL พร้อมระบบควบคุมการเข้าถึง

| Component | หน้าที่ | Port |
|-----------|---------|------|
| **Nginx** | Web server | 80 |
| **PostgreSQL** | ฐานข้อมูลของ WordPress | 5432 (internal) |
| **WordPress** | เว็บไซต์ (ใช้ PG4WP) | 8080 |
| **JumpServer** | PAM / Bastion host | 8088, 2222 |

---

## 🏗️ Architecture Diagram

```
                          ┌─────────────────┐
                          │   ผู้ดูแลระบบ      │
                          │   (Admin)        │
                          └────────┬────────┘
                                   │ HTTPS/SSH
                                   ▼
                          ┌─────────────────┐
                          │   JumpServer     │  ← PAM (บันทึก session)
                          │  Port 8088/2222  │
                          └────────┬────────┘
                                   │ SSH (172.18.0.x)
                                   ▼
        ┌──────────────────────────────────────────────┐
        │            Docker Network (wp-network)         │
        │                                                │
        │   ┌──────────┐  ┌──────────┐  ┌────────────┐  │
        │   │  Nginx   │  │WordPress │  │ PostgreSQL │  │
        │   │  :80     │  │  :8080   │──│   :5432    │  │
        │   │          │  │ (PG4WP)  │  │            │  │
        │   └──────────┘  └──────────┘  └────────────┘  │
        │                                                │
        └──────────────────────────────────────────────┘
                         Host: Ubuntu 24 (VMware)
```

**Flow การทำงาน:**
1. Admin เชื่อมต่อผ่าน JumpServer (ไม่ SSH เข้า server ตรงๆ)
2. JumpServer ถือ credentials แทน และบันทึกทุก session
3. WordPress รับ request แล้วเก็บข้อมูลใน PostgreSQL ผ่าน PG4WP

---

## 📋 สิ่งที่ต้องมีก่อน (Prerequisites)

- **OS:** Ubuntu 24.04 (รันบน VMware)
- **RAM:** อย่างน้อย 4 GB (JumpServer กินทรัพยากรพอสมควร)
- **Disk:** อย่างน้อย 20 GB (แนะนำเผื่อ image ขนาดใหญ่)
- สิทธิ์ `sudo`
- เชื่อมต่อ internet ได้

> ⚠️ **หมายเหตุ:** JumpServer image มีขนาดใหญ่ และ PostgreSQL/WordPress image ก็กินพื้นที่ ควรเตรียม disk ให้พอ มิฉะนั้นจะเจอ `No space left on device`

---

## 🐳 ส่วนที่ 1: ติดตั้ง Docker

```bash
# อัปเดตระบบและติดตั้ง dependencies
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# เพิ่ม GPG key ของ Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# เพิ่ม Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# ติดตั้ง Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ตั้งให้ใช้ docker ได้โดยไม่ต้อง sudo
sudo usermod -aG docker $USER
newgrp docker

# ทดสอบ
docker run hello-world
```

✅ **ผลลัพธ์ที่ถูกต้อง:** เห็นข้อความ `Hello from Docker!`

---

## 🌐 ส่วนที่ 2: Nginx

```bash
# สร้าง Docker network ให้ทุก container คุยกันได้
docker network create wp-network

# รัน Nginx
docker run -d \
  --name nginx \
  --network wp-network \
  -p 80:80 \
  nginx
```

✅ **ทดสอบ:** เปิด browser ไปที่ `http://<server-ip>` → เห็นหน้า **"Welcome to nginx!"**

---

## 🐘 ส่วนที่ 3: PostgreSQL

```bash
docker run -d \
  --name postgres \
  --network wp-network \
  -e POSTGRES_DB=wordpress \
  -e POSTGRES_USER=wpuser \
  -e POSTGRES_PASSWORD=wppassword \
  postgres
```

✅ **ทดสอบ:** `docker ps` → เห็น container `postgres` สถานะ `Up`

---

## 📝 ส่วนที่ 4: WordPress + PG4WP

WordPress image ปกติใช้ MySQL เป็น default จึงต้องสร้าง **custom image** ที่ติดตั้ง plugin **PG4WP** เพื่อให้คุยกับ PostgreSQL ได้

### 4.1 สร้าง Dockerfile

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

> 💡 **เกี่ยวกับ PG4WP:** plugin นี้ทำงานโดยดักจับ (intercept) คำสั่งที่ WordPress ส่งไปหา MySQL driver แล้วแปลงเป็น PostgreSQL query ทำให้ WordPress ใช้ PostgreSQL ได้โดยไม่ต้องมี MySQL ในระบบเลย — เราใช้ version **v3.4.1** ซึ่งเป็น release ล่าสุด

### 4.2 Build และรัน

```bash
# Build image
docker build -t wordpress-pg .

# รัน WordPress
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

✅ **ทดสอบ:** เปิด `http://<server-ip>:8080` → เห็นหน้า WordPress installer (เลือกภาษา)

---

## 🔐 ส่วนที่ 5: JumpServer (PAM)

JumpServer ต้องการ **PostgreSQL** และ **Redis** ของตัวเองแยกต่างหาก จึงใช้ `docker-compose` จัดการทั้งชุด

### 5.1 สร้าง docker-compose.yml

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

> ⚠️ แก้ `<server-ip>` ใน `DOMAINS` เป็น IP จริงของเครื่อง เช่น `192.168.91.146:8088`

### 5.2 รัน

```bash
docker compose up -d

# ตรวจสอบ log (รอ 2-3 นาทีให้ระบบพร้อม)
docker logs jumpserver --tail 20
```

✅ **ทดสอบ:** เปิด `http://<server-ip>:8088` → login ด้วย `admin` / `admin`

> 📌 **สำคัญ:** ต้องใช้ **PostgreSQL 16** (ไม่ใช่ 13) เพราะ JumpServer เวอร์ชันใหม่ใช้คำสั่ง `REFRESH COLLATION VERSION` ที่รองรับใน PostgreSQL 14+ เท่านั้น

---

## 🔗 ส่วนที่ 6: Remote เข้า WordPress ผ่าน JumpServer

### 6.1 เตรียม WordPress container ให้รับ SSH

```bash
# ติดตั้งและตั้งค่า SSH + Python (จำเป็นสำหรับ Ansible ของ JumpServer)
docker exec -it wordpress bash -c "\
  apt-get update && \
  apt-get install -y openssh-server python3 && \
  ln -sf /usr/bin/python3 /usr/bin/python && \
  mkdir -p /run/sshd && \
  echo 'root:p@ssword' | chpasswd && \
  sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  /usr/sbin/sshd"

# เชื่อม JumpServer เข้า network เดียวกับ WordPress
docker network connect wp-network jumpserver

# หา IP ของ WordPress container
docker inspect wordpress | grep IPAddress
```

### 6.2 ตั้งค่าใน JumpServer (Web UI)

1. **Assets → Asset list → Create → Linux**
   - Name: `WordPress`
   - IP/Host: `172.18.0.4` (IP จากขั้นตอนข้างบน)
   - Platform: `Linux` / Port: `22`
   - Nodes: `DEFAULT`
2. **เพิ่ม Account:** Username `root` / Password `p@ssword` / ✅ Privileged
3. **Permissions → Asset Permissions → Create**
   - Users: `admin`
   - Assets: `WordPress`
   - Accounts: `All`
4. **ทดสอบ:** คลิก asset → **Test connectivity** → ต้องได้ `ok=1`

### 6.3 เข้าใช้งานผ่าน Web Terminal

เปิด `http://<server-ip>:8088/luna/` → คลิก asset **WordPress** → เข้า terminal ได้เลย

✅ **ยืนยัน:** พิมพ์ `ls /var/www/html` แล้วเห็นไฟล์ WordPress (`wp-config.php`, `wp-content` ฯลฯ)

---

## 🔧 Troubleshooting (ปัญหาที่เจอและวิธีแก้)

ตารางนี้รวบรวมปัญหาจริงที่พบระหว่างติดตั้ง พร้อมวิธีแก้:

| # | ปัญหา (Error) | สาเหตุ | วิธีแก้ |
|---|---------------|--------|---------|
| 1 | `REMOTE HOST IDENTIFICATION HAS CHANGED` | SSH key เก่าของเครื่องเปลี่ยน | `ssh-keygen -R <ip>` แล้ว SSH ใหม่ |
| 2 | `su: Authentication failure` | Ubuntu ปิด root login | ใช้ `sudo su` หรือ `sudo -i` |
| 3 | `unzip: not found` (ตอน build) | WordPress image ไม่มี unzip | เพิ่ม `unzip` ใน Dockerfile |
| 4 | `End-of-central-directory signature not found` | curl ตาม redirect ของ GitHub ไม่ได้ | เปลี่ยนไปใช้ `git clone` แทน |
| 5 | WordPress ใช้ MySQL ไม่ใช่ PostgreSQL | image ปกติ default เป็น MySQL | สร้าง custom image + PG4WP |
| 6 | `No space left on device` | Disk เต็ม | `docker image prune -a` หรือขยาย disk ด้วย `lvextend` + `resize2fs` |
| 7 | `database "jumpserver" does not exist` | JumpServer ไม่มี DB ของตัวเอง | เพิ่ม PostgreSQL service แยกใน compose |
| 8 | `AUTH called without any password` (Redis) | Redis ไม่ได้ตั้ง password | เพิ่ม `--requirepass` + `REDIS_PASSWORD` |
| 9 | `syntax error at or near "REFRESH"` | PostgreSQL 13 เก่าเกินไป | เปลี่ยนเป็น `postgres:16` |
| 10 | `Configuration file has problems` (login) | ไม่ได้ตั้งค่า DOMAINS | เพิ่ม env `DOMAINS=<ip>:8088` |
| 11 | Asset `UNREACHABLE` (ssh timeout) | JumpServer กับ WordPress คนละ network | `docker network connect wp-network jumpserver` |
| 12 | `Invalid/incorrect password` | password container กับใน JumpServer ไม่ตรง | ตั้ง password ให้ตรงกันด้วย `chpasswd` |
| 13 | `/usr/bin/python: not found` (Ansible) | WordPress container ไม่มี Python | ติดตั้ง `python3` + symlink เป็น `python` |
| 14 | Asset tree ว่างใน Luna | ยังไม่ได้ตั้ง Asset Permission | สร้าง Asset Permission ผูก user กับ asset |

### คำสั่งขยาย disk (อ้างอิงปัญหา #6)

```bash
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
df -h   # ตรวจสอบพื้นที่
```

---

## 📜 Revision History

| Version | วันที่ | รายละเอียด | ผู้จัดทำ |
|---------|--------|------------|----------|
| 1.0 | 2026-06-22 | จัดทำเอกสารฉบับแรก ครอบคลุมทั้งระบบ | - |

---

## 📚 References

- [PG4WP - PostgreSQL for WordPress](https://github.com/PostgreSQL-For-Wordpress/postgresql-for-wordpress)
- [JumpServer Official](https://www.jumpserver.org)
- [Docker Documentation](https://docs.docker.com)

---

<div align="center">

**จัดทำเพื่อการศึกษา** · Docker + PostgreSQL + JumpServer Lab

</div>
