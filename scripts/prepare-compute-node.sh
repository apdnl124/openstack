#!/bin/bash

# Compute 노드 준비 스크립트
# 각 Compute 노드에서 실행

set -e

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

# 설정 변수
CONTROLLER_IP="192.168.1.10"
COMPUTE_NODE_NAME=""

echo "=== Compute 노드 준비 시작 ==="

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# 현재 IP 확인
CURRENT_IP=$(hostname -I | awk '{print $1}')
log_info "현재 노드 IP: $CURRENT_IP"

# 노드 이름 설정
case $CURRENT_IP in
    "192.168.1.11")
        COMPUTE_NODE_NAME="compute-node-1"
        ;;
    "192.168.1.12")
        COMPUTE_NODE_NAME="compute-node-2"
        ;;
    "192.168.1.13")
        COMPUTE_NODE_NAME="compute-node-3"
        ;;
    *)
        log_warn "알 수 없는 IP 주소입니다. 수동으로 노드 이름을 입력하세요."
        read -p "Compute 노드 이름을 입력하세요 (예: compute-node-1): " COMPUTE_NODE_NAME
        ;;
esac

log_info "노드 이름: $COMPUTE_NODE_NAME"

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

# 방화벽 비활성화
log_info "방화벽 비활성화..."
systemctl stop firewalld
systemctl disable firewalld

# 시간 동기화 설정
log_info "시간 동기화 설정..."
systemctl enable chronyd
systemctl start chronyd

# 호스트명 설정
log_info "호스트명 설정..."
hostnamectl set-hostname $COMPUTE_NODE_NAME

# /etc/hosts 파일 설정
log_info "/etc/hosts 파일 업데이트..."
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

# OpenStack 노드들
$CONTROLLER_IP    controller openstack-controller
192.168.1.11      compute-node-1
192.168.1.12      compute-node-2
192.168.1.13      compute-node-3
192.168.100.10    openstack-controller-provider
EOF

# RDO 저장소 설치
log_info "RDO 저장소 설치 중..."
dnf install -y centos-release-openstack-zed epel-release
dnf update -y

# 하드웨어 가상화 지원 확인
log_info "하드웨어 가상화 지원 확인..."
VIRT_SUPPORT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
if [[ $VIRT_SUPPORT -eq 0 ]]; then
    log_warn "하드웨어 가상화가 지원되지 않습니다. VMware 설정을 확인하세요."
    log_warn "VMware에서 'Virtualize Intel VT-x/EPT or AMD-V/RVI' 옵션을 활성화하세요."
else
    log_info "하드웨어 가상화 지원 확인됨 ($VIRT_SUPPORT cores)"
fi

# 중첩 가상화 활성화 (VMware 환경)
log_info "중첩 가상화 설정..."
if lsmod | grep -q kvm_intel; then
    echo 'options kvm_intel nested=1' > /etc/modprobe.d/kvm.conf
    modprobe -r kvm_intel 2>/dev/null || true
    modprobe kvm_intel
    log_info "Intel VT-x 중첩 가상화 활성화됨"
elif lsmod | grep -q kvm_amd; then
    echo 'options kvm_amd nested=1' > /etc/modprobe.d/kvm.conf
    modprobe -r kvm_amd 2>/dev/null || true
    modprobe kvm_amd
    log_info "AMD-V 중첩 가상화 활성화됨"
fi

# 네트워크 설정 확인
log_info "네트워크 인터페이스 확인..."
ip link show

# Management 네트워크 설정 확인
if ip addr show | grep -q "$CURRENT_IP"; then
    log_info "Management 네트워크 설정 확인됨: $CURRENT_IP"
else
    log_warn "Management 네트워크 설정을 확인하세요."
fi

# Provider 네트워크 인터페이스 확인
if ip link show enp0s8 >/dev/null 2>&1; then
    log_info "Provider 네트워크 인터페이스 확인됨: enp0s8"
else
    log_warn "Provider 네트워크 인터페이스(enp0s8)를 확인하세요."
fi

# 스왑 설정 확인
log_info "스왑 설정 확인..."
if ! swapon --show | grep -q "/swapfile"; then
    log_info "스왑 파일 생성..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_info "4GB 스왑 파일 생성 완료"
else
    log_info "스왑 설정 확인됨"
fi

# 디스크 공간 확인
log_info "디스크 공간 확인..."
df -h

AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
if [[ $AVAILABLE_SPACE -lt 30000000 ]]; then
    log_warn "사용 가능한 디스크 공간이 부족할 수 있습니다. (30GB 이상 권장)"
else
    log_info "충분한 디스크 공간 확인됨"
fi

# Controller 노드 연결 테스트
log_info "Controller 노드 연결 테스트..."
if ping -c 3 $CONTROLLER_IP >/dev/null 2>&1; then
    log_info "Controller 노드 연결 확인됨"
else
    log_error "Controller 노드에 연결할 수 없습니다. 네트워크 설정을 확인하세요."
    exit 1
fi

# SSH 서비스 확인
log_info "SSH 서비스 확인..."
systemctl enable sshd
systemctl start sshd

if systemctl is-active sshd >/dev/null 2>&1; then
    log_info "SSH 서비스 활성화됨"
else
    log_error "SSH 서비스 시작 실패"
    exit 1
fi

# 필요한 패키지 사전 설치 (Packstack이 설치할 패키지들)
log_info "OpenStack 관련 패키지 사전 설치..."
dnf install -y python3-openstackclient openstack-nova-compute openstack-neutron-openvswitch

# 서비스 상태 확인
log_info "시스템 서비스 상태 확인..."
systemctl status chronyd --no-pager -l
systemctl status sshd --no-pager -l

log_info "=== Compute 노드 준비 완료 ==="
echo ""
echo "노드 정보:"
echo "- 호스트명: $COMPUTE_NODE_NAME"
echo "- IP 주소: $CURRENT_IP"
echo "- 하드웨어 가상화: $([ $VIRT_SUPPORT -gt 0 ] && echo '지원됨' || echo '미지원')"
echo ""
echo "다음 단계:"
echo "1. Controller 노드에서 SSH 키를 이 노드에 복사하세요:"
echo "   ssh-copy-id root@$CURRENT_IP"
echo ""
echo "2. Controller 노드에서 멀티 노드 설치를 실행하세요:"
echo "   ./scripts/multinode-setup.sh"
echo ""
echo "3. 또는 Packstack 응답 파일에 이 노드를 추가하세요:"
echo "   CONFIG_COMPUTE_HOSTS=192.168.1.10,$CURRENT_IP"
