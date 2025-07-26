#!/bin/bash

# Packstack을 이용한 OpenStack Zed 자동 설치 스크립트
# CentOS 9 Stream 환경용

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
PROVIDER_INTERFACE="enp0s8"
DEFAULT_PASSWORD="openstack123"
ADMIN_PASSWORD="admin123"

echo "=== OpenStack Zed Packstack 설치 시작 ==="

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# RDO 저장소 설치
log_info "RDO 저장소 설치 중..."
dnf install -y centos-release-openstack-zed epel-release
dnf update -y

# Packstack 설치
log_info "Packstack 설치 중..."
dnf install -y openstack-packstack

# 응답 파일 생성
log_info "Packstack 응답 파일 생성 중..."
packstack --gen-answer-file=/root/packstack-answers.txt

# 응답 파일 백업
cp /root/packstack-answers.txt /root/packstack-answers.txt.backup

# 응답 파일 수정
log_info "응답 파일 설정 중..."
sed -i "s/CONFIG_DEFAULT_PASSWORD=.*/CONFIG_DEFAULT_PASSWORD=$DEFAULT_PASSWORD/" /root/packstack-answers.txt
sed -i "s/CONFIG_KEYSTONE_ADMIN_PW=.*/CONFIG_KEYSTONE_ADMIN_PW=$ADMIN_PASSWORD/" /root/packstack-answers.txt
sed -i "s/CONFIG_COMPUTE_HOSTS=.*/CONFIG_COMPUTE_HOSTS=$CONTROLLER_IP/" /root/packstack-answers.txt
sed -i "s/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=.*/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=vxlan,flat,vlan/" /root/packstack-answers.txt
sed -i "s/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=.*/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=vxlan/" /root/packstack-answers.txt
sed -i "s/CONFIG_NEUTRON_ML2_MECHANISM_DRIVERS=.*/CONFIG_NEUTRON_ML2_MECHANISM_DRIVERS=openvswitch/" /root/packstack-answers.txt
sed -i "s/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=.*/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=extnet:br-ex/" /root/packstack-answers.txt
sed -i "s/CONFIG_NEUTRON_OVS_BRIDGE_IFACES=.*/CONFIG_NEUTRON_OVS_BRIDGE_IFACES=br-ex:$PROVIDER_INTERFACE/" /root/packstack-answers.txt
sed -i "s/CONFIG_HORIZON_SSL=.*/CONFIG_HORIZON_SSL=n/" /root/packstack-answers.txt
sed -i "s/CONFIG_CINDER_INSTALL=.*/CONFIG_CINDER_INSTALL=y/" /root/packstack-answers.txt
sed -i "s/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/" /root/packstack-answers.txt
sed -i "s/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/" /root/packstack-answers.txt
sed -i "s/CONFIG_MAGNUM_INSTALL=.*/CONFIG_MAGNUM_INSTALL=n/" /root/packstack-answers.txt
sed -i "s/CONFIG_OCTAVIA_INSTALL=.*/CONFIG_OCTAVIA_INSTALL=n/" /root/packstack-answers.txt
sed -i "s/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=y/" /root/packstack-answers.txt
sed -i "s/CONFIG_CEILOMETER_INSTALL=.*/CONFIG_CEILOMETER_INSTALL=y/" /root/packstack-answers.txt
sed -i "s/CONFIG_AODH_INSTALL=.*/CONFIG_AODH_INSTALL=y/" /root/packstack-answers.txt

# Packstack 실행
log_info "OpenStack 설치 시작... (약 30-60분 소요)"
log_info "설치 로그는 /var/tmp/packstack/latest/openstack-setup.log에서 확인할 수 있습니다."

packstack --answer-file=/root/packstack-answers.txt

# 설치 완료 확인
if [[ $? -eq 0 ]]; then
    log_info "OpenStack 설치 완료!"
else
    log_error "OpenStack 설치 실패!"
    exit 1
fi

# 환경 변수 설정
log_info "환경 변수 설정..."
if [[ -f /root/keystonerc_admin ]]; then
    cp /root/keystonerc_admin /home/$(logname)/
    chown $(logname):$(logname) /home/$(logname)/keystonerc_admin
    
    # 일반 사용자의 .bashrc에 추가
    if ! grep -q "keystonerc_admin" /home/$(logname)/.bashrc; then
        echo "source /home/$(logname)/keystonerc_admin" >> /home/$(logname)/.bashrc
    fi
fi

# OpenStack 클라이언트 설치
log_info "OpenStack 클라이언트 설치..."
dnf install -y python3-openstackclient

# 기본 서비스 상태 확인
log_info "OpenStack 서비스 상태 확인..."
source /root/keystonerc_admin
openstack service list

# 기본 네트워크 설정
log_info "기본 네트워크 설정..."

# External 네트워크 생성
openstack network create --external \
  --provider-physical-network extnet \
  --provider-network-type flat \
  external

# External 서브넷 생성
openstack subnet create --network external \
  --allocation-pool start=192.168.100.100,end=192.168.100.200 \
  --dns-nameserver 8.8.8.8 \
  --gateway 192.168.100.1 \
  --subnet-range 192.168.100.0/24 \
  external-subnet

# Internal 네트워크 생성
openstack network create internal

# Internal 서브넷 생성
openstack subnet create --network internal \
  --dns-nameserver 8.8.8.8 \
  --gateway 10.0.0.1 \
  --subnet-range 10.0.0.0/24 \
  internal-subnet

# 라우터 생성 및 설정
openstack router create router1
openstack router set --external-gateway external router1
openstack router add subnet router1 internal-subnet

# 보안 그룹 규칙 추가
log_info "보안 그룹 규칙 설정..."
openstack security group rule create --protocol tcp --dst-port 22 default
openstack security group rule create --protocol icmp default
openstack security group rule create --protocol tcp --dst-port 80 default
openstack security group rule create --protocol tcp --dst-port 443 default

# SSH 키페어 생성
log_info "SSH 키페어 생성..."
if [[ ! -f /home/$(logname)/.ssh/openstack-key ]]; then
    sudo -u $(logname) ssh-keygen -t rsa -b 2048 -f /home/$(logname)/.ssh/openstack-key -N ""
    openstack keypair create --public-key /home/$(logname)/.ssh/openstack-key.pub openstack-key
fi

# 테스트 이미지 다운로드 및 등록
log_info "테스트 이미지 다운로드 및 등록..."
if [[ ! -f /tmp/cirros-0.6.2-x86_64-disk.img ]]; then
    wget -O /tmp/cirros-0.6.2-x86_64-disk.img http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
fi

openstack image create "cirros" \
  --file /tmp/cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public

# Flavor 생성
log_info "Flavor 생성..."
openstack flavor create --id 1 --vcpus 1 --ram 512 --disk 1 m1.tiny || true
openstack flavor create --id 2 --vcpus 1 --ram 2048 --disk 20 m1.small || true

log_info "=== OpenStack 설치 완료 ==="
echo ""
echo "Horizon 대시보드 접근 정보:"
echo "URL: http://$CONTROLLER_IP/dashboard"
echo "사용자명: admin"
echo "패스워드: $ADMIN_PASSWORD"
echo ""
echo "CLI 환경 변수 로드:"
echo "source /root/keystonerc_admin"
echo ""
echo "다음 단계: Magnum 및 Octavia 설치"
