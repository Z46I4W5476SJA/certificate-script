#!/bin/bash
# 修正点：
# 1) 仅使用 Cloudflare CF_Token（不再写入/使用 CF_Key/CF_Email）
# 2) 同时签发 根域 + 泛域（-d "$DOMAIN" -d "*.$DOMAIN"）
# 3) 成功判断改为基于返回码；默认路径改为 key=.key / cert=.crt
# 4) 可选：安装后自动 reload 服务（默认：systemctl reload nginx，可留空）

set -Eeuo pipefail

#=========================== 颜色 ===========================#
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

printf "${GREEN}====================自动申请SSL证书=========================${NC}\n"
printf "${BLUE} 本脚本支持：Debian9+ / Ubuntu16.04+ / Centos7+${NC}\n"
printf "${BLUE} 原创：www.v2rayssr.com （已开启禁止国内访问）${NC}\n"
printf "${BLUE} YouTube频道：波仔分享${NC}\n"
printf "${BLUE} 本脚本禁止在国内任何网站转载${NC}\n"
printf "${GREEN}==========================================================${NC}\n"

#=========================== 默认路径（已修正） ===========================#
DEFAULT_KEY_FILE="/etc/ssl/private/1.key"   # 私钥 .key
DEFAULT_CERT_FILE="/etc/ssl/certs/1.crt"    # 证书(完整链) .crt

#=========================== 工具函数 ===========================#
install_socat() {
  if command -v yum >/dev/null 2>&1; then
    yum install -y socat
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qy
    apt-get install -y socat
  else
    printf "${RED}未知的 Linux 发行版，无法安装 socat。${NC}\n"
    exit 1
  fi
}

install_acme() {
  install_socat
  if [ ! -x /root/.acme.sh/acme.sh ]; then
    curl https://get.acme.sh | sh
  fi
}

register_account_email() {
  # 保持你原先用 ZeroSSL（仅用于 ACME 账号注册）
  /root/.acme.sh/acme.sh --register-account -m "$EMAIL" --server zerossl
}

check_acme_installation() {
  if [ -d "/root/.acme.sh" ]; then
    if [ -f "/root/.acme.sh/account.conf" ]; then
      CF_TOKEN=$(grep -E '^export[[:space:]]+CF_Token=' /root/.acme.sh/account.conf | cut -d'=' -f2- | sed 's/^"//;s/"$//') || true
      if [ -n "${CF_TOKEN:-}" ]; then
        CF_TOKEN_DISPLAY="*****${CF_TOKEN: -8}"
        printf "${YELLOW}ACME 已安装。${NC}\n"
        printf "${YELLOW}已读取到的 Cloudflare API Token: ${CF_TOKEN_DISPLAY}${NC}\n"
        read -p "是否使用这枚 Token 继续？(y/n): " USE_EXISTING_ACCOUNT
        if [[ "$USE_EXISTING_ACCOUNT" =~ ^[yY]$ ]]; then
          return 0
        else
          return 1
        fi
      else
        printf "${YELLOW}ACME 已安装，但未读取到 Cloudflare API Token（CF_Token）。${NC}\n"
        return 1
      fi
    else
      printf "${YELLOW}ACME 已安装，但未找到配置文件。${NC}\n"
      return 1
    fi
  else
    printf "${YELLOW}ACME 未安装。即将安装 ACME 脚本，生产环境请注意覆盖。${NC}\n"
    return 1
  fi
}

input_parameters() {
  read -p "请输入主域名 (例如: example.com): " DOMAIN
  read -p "请输入注册 Cloudflare 帐户的邮箱地址（用于注册 CA 账号，不用于 DNS 验证）: " EMAIL
  read -p "请输入 Cloudflare API Token（Zone:DNS Edit）: " CF_TOKEN
  read -p "请输入证书文件路径(Fullchain, 默认: $DEFAULT_CERT_FILE): " CERT_FILE
  CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
  read -p "请输入密钥文件路径(Private Key, 默认: $DEFAULT_KEY_FILE): " KEY_FILE
  KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
  read -p "证书安装后重载命令(默认: systemctl reload nginx；留空则不重载): " RELOAD_CMD
  RELOAD_CMD=${RELOAD_CMD:-"systemctl reload nginx"}
}

write_cloudflare_config() {
  # 清理历史无效变量，并写入 CF_Token；顺便开启日志
  touch /root/.acme.sh/account.conf
  sed -i '/SAVED_CF_/d;/^export[[:space:]]\+CF_Key/d;/^export[[:space:]]\+CF_Email/d;/^export[[:space:]]\+CF_Token/d;/^LOG_FILE=/d;/^LOG_LEVEL=/d' /root/.acme.sh/account.conf
  echo "export CF_Token=\"$CF_TOKEN\"" >> /root/.acme.sh/account.conf
  echo 'LOG_FILE="/root/.acme.sh/acme.sh.log"' >> /root/.acme.sh/account.conf
  echo 'LOG_LEVEL=2'                             >> /root/.acme.sh/account.conf
  chmod 600 /root/.acme.sh/account.conf
}

request_certificate() {
  # 根域 + 泛域一起签发
  /root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN"
}

install_certificate() {
  # 确保目录存在
  install -d "$(dirname "$CERT_FILE")" "$(dirname "$KEY_FILE")"
  # 组装 installcert 命令（可选 reload）
  if [ -n "${RELOAD_CMD:-}" ]; then
    /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
      --key-file "$KEY_FILE" \
      --fullchain-file "$CERT_FILE" \
      --reloadcmd "$RELOAD_CMD"
  else
    /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
      --key-file "$KEY_FILE" \
      --fullchain-file "$CERT_FILE"
  fi
}

ensure_scheduler() {
  # acme.sh 安装时已装过 cron；这里再稳妥确保一次
  if command -v systemctl >/dev/null 2>&1; then
    /root/.acme.sh/acme.sh --install-systemd || true
    systemctl enable --now acme.timer || true
  else
    /root/.acme.sh/acme.sh --install-cronjob || true
  fi
}

#=========================== 主流程 ===========================#
main() {
  if ! check_acme_installation; then
    # 未安装或不复用旧配置 → 走输入
    input_parameters
  else
    # 复用 CF_Token，只收集域名与路径
    read -p "请输入域名 (例如: example.com): " DOMAIN
    read -p "请输入注册 Cloudflare 帐户的邮箱地址（用于注册 CA 账号）: " EMAIL
    read -p "请输入证书文件路径(Fullchain, 默认: $DEFAULT_CERT_FILE): " CERT_FILE
    CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
    read -p "请输入密钥文件路径(Private Key, 默认: $DEFAULT_KEY_FILE): " KEY_FILE
    KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
    read -p "证书安装后重载命令(默认: systemctl reload nginx；留空则不重载): " RELOAD_CMD
    RELOAD_CMD=${RELOAD_CMD:-"systemctl reload nginx"}
  fi

  if [ ! -d "/root/.acme.sh" ]; then
    install_acme
  fi

  register_account_email
  write_cloudflare_config

  # 以返回码判断是否签发成功（修复你原来的通配符判断问题）
  if request_certificate; then
    install_certificate
    ensure_scheduler
    printf "${GREEN}证书申请并安装成功${NC}\n"
    printf "${GREEN}证书(Fullchain): ${CERT_FILE}${NC}\n"
    printf "${GREEN}私钥(Private Key): ${KEY_FILE}${NC}\n"
  else
    printf "${RED}证书未能下发，请查看日志：/root/.acme.sh/acme.sh.log${NC}\n"
    exit 1
  fi
}

main
