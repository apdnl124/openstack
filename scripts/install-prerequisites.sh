#!/bin/bash

# OpenStack 설치를 위한 사전 요구사항 설치 스크립트
# CentOS 9 Stream 환경용

set -e

echo "=== OpenStack 사전 요구사항 설치 시작 ==="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# 시스템 업데이트
log_info "시스템 패키지 업데이트 중..."
dnf update -y

# 필수 패키지 설치
log_info "필수 패키지 설치 중..."
dnf groupinstall -y "Development Tools"
dnf install -y vim wget curl git net-tools bind-utils chrony

# SELinux 설정
log_info "SELinux를 Permissive 모드로 설정..."
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# 방화벽 비활성화 (테스트 환경)
log_info "방화벽 비활성화..."
systemctl stop firewalld
systemctl disable firewalld

# 시간 동기화 설정
log_info "시간 동기화 설정..."
systemctl enable chronyd
systemctl start chronyd

# 스왑 설정 확인
log_info "스왑 설정 확인..."
if ! swapon --show | grep -q "/swapfile"; then
    log_info "스왑 파일 생성..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 호스트명 설정
log_info "호스트명 설정..."
hostnamectl set-hostname openstack-controller

# /etc/hosts 파일 업데이트
log_info "/etc/hosts 파일 업데이트..."
if ! grep -q "openstack-controller" /etc/hosts; then
    cat >> /etc/hosts << EOF
192.168.1.10    openstack-controller controller
192.168.100.10  openstack-controller-provider
EOF
fi

# 하드웨어 가상화 지원 확인
log_info "하드웨어 가상화 지원 확인..."
if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]]; then
    log_warn "하드웨어 가상화가 지원되지 않습니다. VMware 설정을 확인하세요."
else
    log_info "하드웨어 가상화 지원 확인됨"
fi

# 네트워크 설정 확인
log_info "네트워크 인터페이스 확인..."
ip link show

# 디스크 공간 확인
log_info "디스크 공간 확인..."
df -h

AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
if [[ $AVAILABLE_SPACE -lt 50000000 ]]; then
    log_warn "사용 가능한 디스크 공간이 부족할 수 있습니다. (50GB 이상 권장)"
fi

log_info "=== 사전 요구사항 설치 완료 ==="
log_info "시스템을 재부팅한 후 Packstack 설치를 진행하세요."

echo ""
echo "다음 명령어로 재부팅하세요:"
echo "sudo reboot"
