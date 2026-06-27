# ====== Stage 1: Build ======
# 用 Maven 21 编译 jar
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

# 先 copy pom 利用 Docker 缓存（依赖没变就不重新下载）
COPY pom.xml .
RUN mvn -B -e -ntp dependency:go-offline

# 复制源码并打包（跳过测试，测试交给 CI）
COPY src ./src
RUN mvn -B -e -ntp clean package -DskipTests

# ====== Stage 2: Runtime ======
# JRE 21 slim 镜像（比 JDK 小约 600MB）
FROM eclipse-temurin:21-jre-jammy

# 设置中文环境
ENV LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Dfile.encoding=UTF-8" \
    SPRING_PROFILES_ACTIVE=prod

# 用非 root 用户运行（安全）
RUN groupadd -r moehair && useradd -r -g moehair -d /opt/moehair-backend -s /bin/false moehair

WORKDIR /opt/moehair-backend

# 复制 jar（从 builder 阶段）
COPY --from=builder /build/target/zhiyu-1.0-SNAPSHOT.jar /opt/moehair-backend/app.jar

# 密钥目录（如需挂载用 volume；路径必须与 application-prod.yml 中 auth.jwt.* 配置一致）
RUN mkdir -p /opt/moehair-backend/keys && chown -R moehair:moehair /opt/moehair-backend

USER moehair

EXPOSE 8080

# 健康检查：actuator/health
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/actuator/health || exit 1

# 启动
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/moehair-backend/app.jar"]
