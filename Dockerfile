# 多阶段构建 Dockerfile
# 第一阶段：构建阶段，使用完整的 Go 环境编译代码
FROM golang:1.21-alpine AS builder

# 接收目标架构参数，用于多架构构建 (amd64 / arm64)
ARG TARGETARCH

# 设置工作目录
WORKDIR /app

# 安装必要的工具
# git: 用于下载 Go 依赖
# ca-certificates: HTTPS 证书，用于访问外部 API
RUN apk add --no-cache git ca-certificates

# 设置 Go 代理（国内推荐使用 goproxy.cn）
ENV GOPROXY=https://goproxy.cn,direct

# 直接复制所有源代码（包括 go.mod、cmd、internal 等）
COPY . .

# 自动整理依赖并生成完整的 go.sum 文件
RUN go mod tidy

# 编译应用
# CGO_ENABLED=0: 禁用 CGO，生成纯静态二进制文件
# GOOS=linux: 目标系统 Linux
# GOARCH=${TARGETARCH}: 目标架构，由构建环境自动传入
# -ldflags="-s -w": 去除调试信息和符号表，减小二进制文件大小
# -trimpath: 去除路径前缀，有利于可重复构建
# -o: 输出文件路径
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build \
    -ldflags="-s -w" \
    -trimpath \
    -o /app/dailyhot-api-go \
    ./cmd/api

# 第二阶段：运行阶段，使用最小镜像运行编译好的二进制文件
FROM alpine:latest

# 安装 ca-certificates（访问 HTTPS 需要）、时区数据、wget（健康检查需要）
RUN apk --no-cache add ca-certificates tzdata wget

# 设置时区为上海（东八区）
ENV TZ=Asia/Shanghai

# 创建非 root 用户运行应用（安全最佳实践）
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app

# 设置工作目录
WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /app/dailyhot-api-go .

# 复制配置文件（如果项目根目录存在 config.yaml 则复制）
COPY --from=builder /app/config.yaml .

# 创建日志目录并设置权限
RUN mkdir -p /app/logs && chown -R app:app /app

# 切换到非 root 用户
USER app

# 暴露端口
EXPOSE 6688

# 健康检查（每 30 秒检查一次，超时 3 秒，重试 3 次）
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:6688/health || exit 1

# 启动应用
CMD ["./dailyhot-api-go"]
