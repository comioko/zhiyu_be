# 知域后端 ECS 部署

## 一次性准备（每台 ECS 跑一次）

### 1. 安装 JDK 21

```bash
# Ubuntu / Debian
sudo apt update
sudo apt install -y openjdk-21-jdk

# CentOS / RHEL
sudo yum install -y java-21-openjdk
```

### 2. 准备中间件（任选其一）

- **云托管**：阿里云 RDS for MySQL / 阿里云 Redis / 阿里云 Elasticsearch
- **本机起**：docker run -d mysql:8 / redis:7 / apache/kafka / elasticsearch:8.18.1

### 3. 上传源码 + 跑安装脚本

```bash
# 本地构建
cd zhiyu_be
mvn clean package -DskipTests
# 生成 target/zhiyu-1.0-SNAPSHOT.jar

# 上传到 ECS
scp target/zhiyu-1.0-SNAPSHOT.jar root@<ecs-host>:/tmp/
scp deploy/install.sh deploy/moehair-backend.service root@<ecs-host>:/tmp/

# 在 ECS 上执行
ssh root@<ecs-host>
cd /tmp
sudo ./install.sh
```

`install.sh` 会自动：
- 创建 `moehair` 系统用户
- 建目录 `/opt/moehair-backend/`、`/var/log/moehair-backend/`、`/etc/moehair/`
- 复制 systemd unit
- 生成 `/etc/moehair/backend.env` 环境变量模板

### 4. 准备 RSA 密钥（JWT 签名）

```bash
# 生成新密钥（生产环境必须用新生成的，不能用代码库里的）
ssh-keygen -t rsa -b 2048 -f /opt/moehair-backend/keys/private.pem -N ""
ssh-keygen -t rsa -b 2048 -f /opt/moehair-backend/keys/public.pem -N ""

# 修正权限
sudo chown moehair:moehair /opt/moehair-backend/keys/*
sudo chmod 600 /opt/moehair-backend/keys/*
```

> ⚠️ **不要把代码库 `src/main/resources/keys/private.pem` 部署到生产！** 那个是开发用的，会被别人伪造 token。

### 5. 填环境变量

```bash
sudo vim /etc/moehair/backend.env
```

必填项：
- `DB_PASSWORD`
- `REDIS_PASSWORD`（如 Redis 设了密码）
- `MAIL_USERNAME` / `MAIL_PASSWORD`（QQ 邮箱 SMTP 授权码）
- `DEEPSEEK_API_KEY` / `QWEN_API_KEY`
- `ES_PASSWORD`
- `OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET`

### 6. 把 jar 放到部署目录 + 启动

```bash
# 移动之前 scp 过来的 jar
sudo mv /tmp/zhiyu-1.0-SNAPSHOT.jar /opt/moehair-backend/
sudo chown moehair:moehair /opt/moehair-backend/zhiyu-1.0-SNAPSHOT.jar

# 启动
sudo systemctl start moehair-backend
sudo systemctl status moehair-backend
```

### 7. 验证

```bash
# 健康检查
curl http://localhost:8080/actuator/health
# 期望：{"status":"UP"}

# 查看实时日志
sudo journalctl -u moehair-backend -f

# Flyway 迁移日志
sudo journalctl -u moehair-backend | grep -i "flyway\|migrat"
# 期望看到：Migrating schema "zhiguang" to version "1 - init schema"
#          Successfully applied 1 migration to schema "zhiguang"
```

## 后续部署（用 GitHub Actions 自动）

每次 push 到 main 触发：

1. CI workflow（`.github/workflows/ci.yml`）跑：
   - 单元测试
   - 用 service container MySQL 跑 Flyway 校验
2. deploy workflow（`.github/workflows/deploy.yml`）：
   - 打包 jar
   - SCP 到 ECS `/opt/moehair-backend/`
   - `systemctl restart moehair-backend`
3. ECS 上 Spring Boot 启动 → Flyway 自动跑新 migration

**前提**：GitHub 仓库 Settings → Secrets 配置：
- `SERVER_HOST`：ECS 公网 IP / 域名
- `SERVER_USER`：SSH 用户名（推荐 `moehair`）
- `SERVER_SSH_KEY`：SSH 私钥
- `SERVER_PORT`：SSH 端口

## 安全提示

⚠️ **生产部署前必做**：

1. **轮换所有密钥**（之前 application.yml 里的密钥已经在 GitHub 公开仓库里，**必须换**）：
   - MySQL root 密码
   - Redis 密码
   - ES 密码
   - 阿里云 OSS AccessKey
   - AI API keys（DeepSeek、通义千问）
   - QQ 邮箱授权码
   - JWT RSA 密钥对
2. **关闭 application.yml 默认值** —— 改成环境变量必填，无 fallback
3. **ECS 安全组**：仅开放 22（SSH）+ 80/443（HTTP/HTTPS）入站，8080 只允许内网
4. **HTTPS**：在 ECS 上用 Nginx + Let's Encrypt 反向代理 8080
5. **备份**：MySQL 每日全量 + binlog 增量

## 卸载

```bash
sudo ./install.sh --uninstall
```
