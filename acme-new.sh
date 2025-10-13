#!/bin/bash
# ✅ 使用 CF_Token
# ✅ 根域 + 泛域签发
# ✅ 成功判断修正
# ✅ 只使用 cron 定时任务（不再尝试 systemd timer）

set -Eeuo pipefail

#=========================== 颜色 ===========================#
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

printf "${GREEN}====================自动申请SSL证书=========================${NC}\n"
printf "${BLUE} 本脚本支持：Debian9+ / Ubuntu16.04+ / Centos7+${NC}\n"
printf "${BLUE} 本脚本禁止在国内任何网站转载${NC}\n"
printf "${GREEN}==========================================================${NC}\n"

#=========================== 默认路径 ===========================#
DEFAULT_KEY_FILE="/etc/ssl/private/1.key"
DEFAULT_CERT_FILE="/etc/ssl/certs/1.crt"

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
        [[ "$USE_EXISTING_ACCOUNT" =~ ^[yY]$ ]] && return 0 || return 1
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
  touch /root/.acme.sh/account.conf
  sed -i '/SAVED_CF_/d;/^export[[:space:]]\+CF_Key/d;/^export[[:space:]]\+CF_Email/d;/^export[[:space:]]\+CF_Token/d;/^LOG_FILE=/d;/^LOG_LEVEL=/d' /root/.acme.sh/account.conf
  echo "export CF_Token=\"$CF_TOKEN\"" >> /root/.acme.sh/account.conf
  echo 'LOG_FILE="/root/.acme.sh/acme.sh.log"' >> /root/.acme.sh/account.conf
  echo 'LOG_LEVEL=2'                             >> /root/.acme.sh/account.conf
  chmod 600 /root/.acme.sh/account.conf
}

request_certificate() {
  /root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN"
}

install_certificate() {
  install -d "$(dirname "$CERT_FILE")" "$(dirname "$KEY_FILE")"
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
  # ✅ 仅使用 cron，不再尝试 systemd
  /root/.acme.sh/acme.sh --install-cronjob || true
}

#=========================== 主流程 ===========================#
main() {
  if ! check_acme_installation; then
    input_parameters
  else
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
