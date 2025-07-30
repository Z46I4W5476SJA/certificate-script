#!/bin/bash

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 修改：添加操作系统检测
OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
    printf "${YELLOW}检测到 macOS 系统。脚本已适配，但请确保安装 Homebrew。${NC}\n"
elif [[ "$OS" != "Linux" ]]; then
    printf "${RED}不支持的操作系统: $OS。脚本仅支持 Linux 和 macOS。${NC}\n"
    exit 1
fi

# 修改：动态路径定义（使用 $HOME 代替 /root，便于 macOS 和非 root 用户）
ACME_DIR="$HOME/.acme.sh"
DEFAULT_KEY_FILE="$HOME/opt/wwjzx.top.key"
DEFAULT_CERT_FILE="$HOME/opt/wwjzx.top.crt"

printf "${GREEN}====================自动申请SSL证书=========================${NC}\n"
printf "${BLUE} 本脚本支持：Debian9+ / Ubuntu16.04+ / Centos7+ / macOS${NC}\n"  # 修改：添加 macOS 支持
printf "${BLUE} 原创：www.v2rayssr.com ，根据这个修改（已开启禁止国内访问）${NC}\n"
printf "${BLUE} 本脚本禁止在国内任何网站转载${NC}\n"
printf "${GREEN}==========================================================${NC}\n"

check_acme_installation() {
    if [ -d "$ACME_DIR" ]; then  # 修改：使用动态路径
        if [ -f "$ACME_DIR/account.conf" ]; then
            CF_KEY=$(grep 'SAVED_CF_Key' "$ACME_DIR/account.conf" | cut -d'=' -f2 | sed "s/'//g" | sed 's/"//g')  # 修改：去除可能的引号
            CF_EMAIL=$(grep 'SAVED_CF_Email' "$ACME_DIR/account.conf" | cut -d'=' -f2 | sed "s/'//g" | sed 's/"//g')
            if [ -n "$CF_KEY" ] && [ -n "$CF_EMAIL" ]; then
                CF_KEY_DISPLAY="*****${CF_KEY: -8}"
                printf "${YELLOW}ACME 已安装。${NC}\n"
                printf "${YELLOW}已读取到的 Cloudflare API 密钥: ${CF_KEY_DISPLAY}${NC}\n"
                printf "${YELLOW}已读取到的 Cloudflare 邮箱地址: $CF_EMAIL${NC}\n"
                read -p "是否使用这组账号继续？(y/n): " USE_EXISTING_ACCOUNT
                if [[ "$USE_EXISTING_ACCOUNT" == "y" || "$USE_EXISTING_ACCOUNT" == "Y" ]]; then
                    return 0
                else
                    return 1
                fi
            else
                printf "${YELLOW}ACME 已安装，但未能读取到 Cloudflare API 密钥和邮箱信息。${NC}\n"
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
    read -p "请输入注册 Cloudflare 帐户的邮箱地址: " EMAIL
    read -p "请输入 Cloudflare API 密钥: " API_KEY
    read -p "请输入密钥文件路径 (按回车使用默认路径 $DEFAULT_KEY_FILE): " KEY_FILE
    KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
    read -p "请输入证书文件路径 (按回车使用默认路径 $DEFAULT_CERT_FILE): " CERT_FILE
    CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
}

install_socat() {
    # 修改：DNS 模式不需要 socat，添加可选安装
    read -p "DNS 验证模式通常不需要 socat，是否仍要安装？(y/n，默认 n): " INSTALL_SOCAT
    INSTALL_SOCAT=${INSTALL_SOCAT:-n}
    if [[ "$INSTALL_SOCAT" != "y" && "$INSTALL_SOCAT" != "Y" ]]; then
        printf "${YELLOW}跳过 socat 安装。${NC}\n"
        return 0
    fi

    if [[ "$OS" == "Linux" ]]; then
        if [[ -x "$(command -v yum)" ]]; then
            yum install -y socat
        elif [[ -x "$(command -v dnf)" ]]; then  # 改进：添加 Fedora 支持
            dnf install -y socat
        elif [[ -x "$(command -v apt-get)" || -x "$(command -v apt)" ]]; then
            apt-get update -qy || apt update -qy  # 改进：支持 apt
            apt-get install -y socat || apt install -y socat
        else
            printf "${RED}未知的 Linux 发行版，无法安装 socat。请手动安装。${NC}\n"
            exit 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if ! command -v brew &> /dev/null; then
            printf "${RED}Homebrew 未安装。请先安装 Homebrew：${NC}\n"
            printf "${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}\n"
            exit 1
        fi
        brew install socat || { printf "${RED}socat 安装失败。请检查 Homebrew。${NC}\n"; exit 1; }  # 改进：添加错误处理
    fi
    printf "${GREEN}socat 安装成功。${NC}\n"
}

install_acme() {
    # 改进：检查 curl 是否存在
    if ! command -v curl &> /dev/null; then
        printf "${RED}curl 未安装。请先安装 curl。${NC}\n"
        exit 1
    fi
    install_socat
    curl https://get.acme.sh | sh || { printf "${RED}acme.sh 安装失败。请检查网络。${NC}\n"; exit 1; }  # 改进：添加错误处理
}

register_account_email() {
    "$ACME_DIR/acme.sh" --register-account -m "$EMAIL" --server zerossl || { printf "${RED}账户注册失败。${NC}\n"; exit 1; }  # 修改：动态路径 + 错误处理
}

write_cloudflare_config() {
    # 修改：使用 echo 追加，避免 sed 兼容性问题（macOS sed 不同）
    echo "SAVED_CF_Key='$API_KEY'" >> "$ACME_DIR/account.conf"
    echo "SAVED_CF_Email='$EMAIL'" >> "$ACME_DIR/account.conf"
}

request_certificate() {
    "$ACME_DIR/acme.sh" --issue --dns dns_cf -d "*.$DOMAIN" || { printf "${RED}证书请求失败。请检查域名和 API。${NC}\n"; exit 1; }  # 修改：动态路径 + 错误处理
}

install_certificate() {
    "$ACME_DIR/acme.sh" --installcert -d "*.$DOMAIN" --key-file "$KEY_FILE" --fullchain-file "$CERT_FILE" || { printf "${RED}证书安装失败。${NC}\n"; exit 1; }  # 修改：动态路径 + 错误处理
}

main() {
    check_acme_installation
    if [ $? -ne 0 ]; then
        input_parameters
    else
        read -p "请输入域名 (例如: v2rayssr.com): " DOMAIN  # 注意：这里原脚本有拼写错误，应为 "请输入主域名"
        EMAIL=$CF_EMAIL
        API_KEY=$CF_KEY
        read -p "请输入密钥文件路径 (按回车使用默认路径 $DEFAULT_KEY_FILE): " KEY_FILE
        KEY_FILE=${KEY_FILE:-$DEFAULT_KEY_FILE}
        read -p "请输入证书文件路径 (按回车使用默认路径 $DEFAULT_CERT_FILE): " CERT_FILE
        CERT_FILE=${CERT_FILE:-$DEFAULT_CERT_FILE}
    fi

    if [ ! -d "$ACME_DIR" ]; then
        install_acme
    fi
    register_account_email
    write_cloudflare_config
    request_certificate
    # 修改：检查证书目录的动态路径
    if [ -f "$ACME_DIR/*.$DOMAIN"_ecc/ca.cer ]; then
        install_certificate
        printf "${GREEN}证书申请成功。${NC}\n"
        printf "${GREEN}您的证书文件: ${CERT_FILE}${NC}\n"
        printf "${GREEN}您的密钥文件: ${KEY_FILE}${NC}\n"
    else
        printf "${RED}证书未能下发。请检查日志: $ACME_DIR/acme.sh.log${NC}\n"
    fi
}

main
