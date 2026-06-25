# 知域后端 Docker 部署指南

> 一行命令起完整后端栈（MySQL + Redis + Kafka + Elasticsearch + 后端），适合本地集成 + 单服务器部署。

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                  zhiyu-net (bridge)                    │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │  MySQL   │  │  Redis   │  │  Kafka   │  │  ES    │  │
│  │  :3306   │  │  :6379   │  │  :9092   │  │ :9200  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───┬────┘  │
│       │             │             │            │       │
│       └─────────────┴──────┬──────┴────────────┘       │
│                             │                            │
│                      ┌──────▼──────┐                     │
│                      │   backend   │  :8080              │
│                      │ zhiyu-be    │                     │
│                      └─────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

## 快速开始

### 1. 准备环境

```bash
# 服务器安装 Docker（Ubuntu/Debian）
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# 重新登录使组生效

# 验证
docker --version
docker compose version
```

### 2. 克隆代码

```bash
git clone https://github.com/comioko/zhiyu_be.git
cd zhiyu_be
```

### 3. 配置环境变量

```bash
cp .env.example .env
vim .env
# 必填：
#   MYSQL_ROOT_PASSWORD=<新密码>
#   DEEPSEEK_API_KEY=<DeepSeek key>
#   QWEN_API_KEY=<通义千问 key>
#   OSS_ACCESS_KEY_ID=<阿里云 key>
#   OSS_ACCESS_KEY_SECRET=<阿里云 secret>
#   MAIL_USERNAME=<QQ 邮箱>
#   MAIL_PASSWORD=<QQ 邮箱授权码>
```

### 4. 准备 JWT RSA 密钥

```bash
mkdir -p secrets/keys
ssh-keygen -t rsa -b 2048 -f secrets/keys/private.pem -N ""
ssh-keygen -t rsa -b 2048 -f secrets/keys/public.pem -N ""
chmod 600 secrets/keys/*
```

### 5. 启动

```bash
docker compose up -d
# 首次启动会：
# 1. 拉镜像（mysql/redis/kafka/elasticsearch + 构建 zhiyu-be）
# 2. 启动 mysql，自动导入 db/schema.sql
# 3. 等 MySQL/Redis/ES 健康检查通过
# 4. 启动 backend，Flyway 自动执行 V1__init_schema.sql

# 查看启动状态
docker compose ps
docker compose logs -f backend
```

### 6. 验证

```bash
# 健康检查
curl http://localhost:8080/actuator/health
# 期望：{"status":"UP"}

# Flyway 迁移日志（应该看到 Successfully applied 1 migration）
docker compose logs backend | grep -i flyway
# 期望：
#   Migrating schema "zhiguang" to version "1 - init schema"
#   Successfully applied 1 migration to schema "zhiguang" (execution time 00:00.XXXs)

# 业务 API（首页 feed）
curl "http://localhost:8080/api/v1/knowposts/feed?page=1&size=20"
# 期望：JSON 数组（如果 DB 里有数据）
```

## 常用命令

```bash
# 查看所有服务状态
docker compose ps

# 查看后端日志
docker compose logs -f backend

# 查看所有服务日志
docker compose logs -f

# 进入后端容器调试
docker compose exec backend sh

# 进入 MySQL
docker compose exec mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD}

# 停止
docker compose down

# 停止并清理数据卷（**危险**，会删所有数据）
docker compose down -v
```

## 升级流程

```bash
# 1. 拉最新代码
git pull origin main

# 2. 重新构建并滚动重启 backend
docker compose up -d --build backend

# 3. 其他中间件不重启
# Flyway 会自动执行新版本的 migration（V2、V3...）
docker compose logs -f backend | grep -i flyway
```

## 生产环境推荐

**生产环境**应该用云托管服务代替容器化中间件，**更稳**：

| 服务 | 本地 (Docker) | 生产 (云) |
|---|---|---|
| MySQL | mysql:8 容器 | 阿里云 RDS for MySQL |
| Redis | redis:7-alpine 容器 | 阿里云 Redis（Tair） |
| Elasticsearch | elasticsearch:8.18.1 容器 | 阿里云 ES |
| Kafka | apache/kafka:3 容器 | 阿里云 Kafka / Confluent Cloud |
| 后端 | zhiyu-be 容器 | 阿里云 ECS / 容器服务 ACK |

**生产部署**只需修改 `docker-compose.yml`：
- 注释掉 mysql/redis/kafka/elasticsearch service
- 修改 backend 的 `DB_URL` / `REDIS_HOST` / `ES_URIS` / `KAFKA_BOOTSTRAP_SERVERS` 指向云服务
- 保留 backend service

或直接用 systemd（参见 `deploy/README.md`）。

## 安全提示

⚠️ **生产部署前**：

1. **轮换所有密钥**（之前 application.yml 里的密钥已经在 GitHub 公开仓库里，**必须换**）
2. **关闭 MySQL/Redis/Kafka/ES 的公网访问**（用云内网）
3. **配置 HTTPS**（在 ECS 上用 Nginx + Let's Encrypt 反代 8080）
4. **定期备份 MySQL**（`docker exec mysql mysqldump ... > backup.sql`）
5. **更新 .env 不进 git**（.gitignore 已配）

## 故障排查

### Backend 一直重启

```bash
docker compose logs backend --tail=100
# 常见错误：
# 1. MySQL 连不上 → 检查 MYSQL_ROOT_PASSWORD / mysql 是否 healthy
# 2. JWT 密钥缺失 → 检查 secrets/keys/*.pem 是否存在
# 3. AI key 无效 → 检查 DEEPSEEK_API_KEY / QWEN_API_KEY
```

### MySQL 数据丢失

```bash
# 数据卷还在
docker volume ls | grep zhiyu
# 恢复：recreate 容器，volume 会自动挂载
docker compose up -d
```

### 端口冲突

```bash
# 修改 .env
MYSQL_PORT=3307
REDIS_PORT=6380
KAFKA_PORT=9093
ES_PORT=9201
BACKEND_PORT=8081
```

## 卸载

```bash
# 停止并删除容器 + 网络
docker compose down

# 清理数据卷（**危险**）
docker compose down -v

# 删除构建的镜像
docker rmi zhiyu-be:latest
```
