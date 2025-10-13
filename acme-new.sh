#!/bin/bash

# 颜色定义（保持原样）
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

printf "${GREEN}====================自动申请SSL证书=========================${NC}\n"

# 默认密钥文件路径（保持原样）
DEFAULT_KEY_FILE="/etc/ssl/certs/1.crt"
DEFAULT_CERT_FILE="/etc/ssl/private/1.key"

check_acme_installation() {
    if [ -d "/root/.acme.sh" ]; then
        if [ -f "/root/.acme.sh/account.conf" ]; then
            # 仅改这里：检测 CF_Token（不再读取 SAVED_CF_Key/Email）
            CF_TOKEN=$(grep -E '^export[[:space:]]+CF_Token=' /root/.acme.sh/account.conf | cut -d'=' -f2- | sed 's/^"//;s/"$//')
            if [ -n "$CF_TOKEN" ]; then
                CF_TOKEN_DISPLAY="*****${CF_TOKEN: -8}"
                printf "${YELLOW}ACME 已安装。${NC}\n"
                printf "${YELLOW}已读取到的 Cloudflare API Token: ${CF_TOKEN_DISPLAY}${NC}\n"
                read -p "是否使用这枚 Token 继续？(y/n): " USE_EXISTING_ACCOUNT
                if [[ "$USE_EXISTING_ACCOUNT" == "y" || "$USE_EXISTING_ACCOUNT" == "Y" ]]; then
                    return 0
                else
                    return 1
                fi
            else
                printf "${YELLOW}ACME 已安装，但未能读取到 Cloudflare API Token（CF_Token）。${NC}\n"
                return 1
            fi
        else
            printf "${YELLOW}ACME 已安装，但未找到配置文件。${NC}\n"
            return 1
        fi
    else
        printf "${YELLOW}ACME 未安装。即将安装 ACME 脚本，生成环境请注意覆盖。${NC}\n"
        return 1
    fi
}

input_parameters() {
    read -p "请输入主域名 (例如: example.com): " DOMAIN
    read -p "请输入注册 Cloudflare 帐户的邮箱地址（用于注册 CA 账号，不用于 DNS 验证）: " EMAIL
    # 仅改这里：用 CF_Token（不再收集 API_KEY）
    read -p "请输入 Cloudflare API Token（Zone:DNS Edit）: " CF_TOKEN
    read -p "请输入密钥文件路径 (按回车使用默认路径 $DEFAULT_KEY_FILE): " KEY_FILE
    KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
    read -p "请输入证书文件路径 (按回车使用默认路径 $DEFAULT_CERT_FILE): " CERT_FILE
    CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
}

install_socat() {
    if [[ -x "$(command -v yum)" ]]; then
        yum install -y socat
    elif [[ -x "$(command -v apt-get)" ]]; then
        apt-get update -qy
        apt-get install -y socat
    else
        printf "${RED}未知的 Linux 发行版，无法安装 socat。${NC}\n"
        exit 1
    fi
}

install_acme() {
    install_socat
    curl https://get.acme.sh | sh
}

register_account_email() {
    /root/.acme.sh/acme.sh --register-account -m "$EMAIL" --server zerossl
}

write_cloudflare_config() {
    # 仅改这里：写入 export CF_Token，并移除历史的 SAVED_CF_* 残留
    sed -i '/SAVED_CF_/d' /root/.acme.sh/account.conf
    sed -i '/^export[[:space:]]\+CF_Token=/d' /root/.acme.sh/account.conf
    echo "export CF_Token=\"$CF_TOKEN\"" >> /root/.acme.sh/account.conf
}

request_certificate() {
    # 仅改这里：根域 + 泛域一起签发
    /root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN"
}

install_certificate() {
    /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" --key-file "$KEY_FILE" --fullchain-file "$CERT_FILE"
}

main() {
    check_acme_installation
    if [ $? -ne 0 ]; then
        input_parameters
    else
        read -p "请输入域名 (例如: v2rayssr.com): " DOMAIN
        # 使用已读到的 CF_TOKEN 与邮箱（邮箱仍用于 CA 账号注册）
        read -p "请输入注册 Cloudflare 帐户的邮箱地址（用于注册 CA 账号）: " EMAIL
        read -p "请输入密钥文件路径 (按回车使用默认路径 $DEFAULT_KEY_FILE): " KEY_FILE
        KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
        read -p "请输入证书文件路径 (按回车使用默认路径 $DEFAULT_CERT_FILE): " CERT_FILE
        CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
    fi

    if [ ! -d "/root/.acme.sh" ]; then
        install_acme
    fi
    register_account_email
    write_cloudflare_config
    request_certificate
    # 保持你原有的判断与输出（未改动）
    if [ -f "/root/.acme.sh/*.${DOMAIN}_ecc/ca.cer" ]; then
        install_certificate
        printf "${GREEN}证书申请成功。${NC}\n"
        printf "${GREEN}您的证书文件: ${CERT_FILE}${NC}\n"
        printf "${GREEN}您的密钥文件: ${KEY_FILE}${NC}\n"
    else
        printf "${RED}证书未能下发。${NC}\n"
    fi
}

main
