#!/usr/bin/env bash
# 知域后端 ECS 一键安装 / 升级脚本
#
# 适用：Ubuntu 20.04+ / Debian 11+ / CentOS 8+（systemd 系统）
# 用法：
#   sudo ./install.sh            # 默认安装到 /opt/moehair-backend/
#   sudo ./install.sh --uninstall # 卸载
#
# 前置：JDK 21 已安装（java -version 输出 21+）
# 首次使用：先手动创建密钥目录 /opt/moehair-backend/keys/
#   sudo mkdir -p /opt/moehair-backend/keys
#   sudo ssh-keygen -t rsa -b 2048 -f /opt/moehair-backend/keys/private.pem -N ""
#   sudo ssh-keygen -t rsa -b 2048 -f /opt/moehair-backend/keys/public.pem -N ""
#   sudo chown -R moehair:moehair /opt/moehair-backend/

set -euo pipefail

APP_NAME="moehair-backend"
APP_USER="moehair"
APP_GROUP="moehair"
APP_DIR="/opt/moehair-backend"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_DIR="/etc/moehair"
ENV_FILE="${ENV_DIR}/backend.env"
LOG_DIR="/var/log/moehair-backend"

# ====== 参数解析 ======
UNINSTALL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=true; shift;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

# ====== 卸载流程 ======
if [ "$UNINSTALL" = true ]; then
  echo "🗑  卸载 ${APP_NAME} 服务"
  systemctl stop ${APP_NAME} 2>/dev/null || true
  systemctl disable ${APP_NAME} 2>/dev/null || true
  rm -f ${SERVICE_FILE}
  rm -rf ${ENV_DIR}
  echo "✅ systemd service + env file 已删除（${APP_DIR} 和 ${LOG_DIR} 保留，可手动 rm -rf）"
  exit 0
fi

# ====== 权限校验 ======
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请用 root 跑：sudo $0" >&2
  exit 1
fi

# ====== Java 21 检查 ======
if ! command -v java >/dev/null 2>&1; then
  echo "❌ 未检测到 java，请先安装 JDK 21" >&2
  echo "   推荐：sudo apt install openjdk-21-jdk  (Ubuntu/Debian)" >&2
  echo "         sudo yum install java-21-openjdk   (CentOS/RHEL)" >&2
  exit 1
fi
JAVA_VER=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}' | cut -d. -f1)
if [ "$JAVA_VER" -lt 21 ]; then
  echo "❌ 当前 java 版本 $(java -version 2>&1 | head -1)，需要 JDK 21+" >&2
  exit 1
fi
echo "✅ Java: $(java -version 2>&1 | head -1)"

# ====== 创建系统用户 ======
if ! id "$APP_USER" >/dev/null 2>&1; then
  echo "👤 创建系统用户 $APP_USER"
  useradd -r -s /bin/false -d $APP_DIR $APP_USER
fi

# ====== 目录结构 ======
echo "📂 创建目录结构"
mkdir -p $APP_DIR
mkdir -p $LOG_DIR
mkdir -p $ENV_DIR
# keys 目录（如已存在则跳过）
mkdir -p $APP_DIR/keys

# 权限
chown -R ${APP_USER}:${APP_GROUP} $APP_DIR
chown -R ${APP_USER}:${APP_GROUP} $LOG_DIR
chmod 750 $APP_DIR
chmod 750 $APP_DIR/keys
chmod 640 $APP_DIR/keys/* 2>/dev/null || true

# ====== 部署 systemd unit ======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/${APP_NAME}.service" ]; then
  echo "🔧 部署 systemd unit: $SERVICE_FILE"
  cp "$SCRIPT_DIR/${APP_NAME}.service" $SERVICE_FILE
  chmod 644 $SERVICE_FILE
else
  echo "❌ 找不到 $SCRIPT_DIR/${APP_NAME}.service" >&2
  exit 1
fi

# ====== 创建环境变量文件（如不存在） ======
if [ ! -f $ENV_FILE ]; then
  echo "📝 创建 $ENV_FILE（请填入真实密钥）"
  cat > $ENV_FILE <<'ENVEOF'
# 知域后端 - 环境变量
# 修改后执行：sudo systemctl restart moehair-backend

# ===== 数据库 =====
DB_URL=jdbc:mysql://127.0.0.1:3306/zhiguang?useUnicode=true&characterEncoding=utf8&useSSL=false&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true
DB_USERNAME=root
DB_PASSWORD=

# ===== Redis =====
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# ===== 邮件（QQ 邮箱） =====
MAIL_HOST=smtp.qq.com
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=

# ===== Kafka =====
KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092
KAFKA_LISTENER_AUTO_STARTUP=false

# ===== Spring AI =====
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=https://api.deepseek.com
QWEN_API_KEY=
QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode

# ===== Elasticsearch =====
ES_URIS=http://127.0.0.1:9200
ES_USERNAME=elastic
ES_PASSWORD=

# ===== 阿里云 OSS =====
OSS_ENDPOINT=oss-cn-beijing.aliyuncs.com
OSS_ACCESS_KEY_ID=
OSS_ACCESS_KEY_SECRET=
OSS_BUCKET=comioko-zhg
OSS_PUBLIC_DOMAIN=
ENVEOF
  chmod 600 $ENV_FILE
  chown root:root $ENV_FILE
  echo "⚠️  $ENV_FILE 已创建，请用 'sudo vim $ENV_FILE' 填入真实密钥"
else
  echo "✅ $ENV_FILE 已存在，跳过"
fi

# ====== 启动服务 ======
echo "🚀 启用并启动 $APP_NAME"
systemctl daemon-reload
systemctl enable $APP_NAME
# 不立即启动（如果 jar 还没传，或者环境变量还没填）
if [ -f $APP_DIR/zhiyu-1.0-SNAPSHOT.jar ]; then
  systemctl restart $APP_NAME
  sleep 3
  systemctl status $APP_NAME --no-pager
else
  echo "⚠️  $APP_DIR/zhiyu-1.0-SNAPSHOT.jar 不存在，请先 scp 上传 jar，再执行："
  echo "   sudo systemctl start $APP_NAME"
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "下一步："
echo "  1. 编辑环境变量: sudo vim $ENV_FILE"
echo "  2. 上传 jar:    sudo scp target/*.jar ${APP_USER}@<host>:$APP_DIR/"
echo "  3. 启动服务:    sudo systemctl start $APP_NAME"
echo "  4. 查看日志:    sudo journalctl -u $APP_NAME -f"
echo "  5. 健康检查:    curl http://localhost:8080/actuator/health"
