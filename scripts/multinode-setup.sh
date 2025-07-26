#!/bin/bash

# 멀티 노드 OpenStack 설치 스크립트
# Controller + Compute 노드 구성

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
COMPUTE_NODES="192.168.1.11,192.168.1.12"  # 쉼표로 구분
DEFAULT_PASSWORD="openstack123"
ADMIN_PASSWORD="admin123"

echo "=== 멀티 노드 OpenStack 설치 시작 ==="

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# 현재 노드가 Controller인지 확인
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [[ "$CURRENT_IP" != "$CONTROLLER_IP" ]]; then
   log_error "이 스크립트는 Controller 노드($CONTROLLER_IP)에서 실행해야 합니다."
   log_error "현재 IP: $CURRENT_IP"
   exit 1
fi

# SSH 키 생성 및 배포
log_info "SSH 키 설정..."
if [[ ! -f /root/.ssh/id_rsa ]]; then
    ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ""
fi

# Compute 노드들에 SSH 키 복사
IFS=',' read -ra NODES <<< "$COMPUTE_NODES"
for node in "${NODES[@]}"; do
    log_info "SSH 키를 $node에 복사 중..."
    ssh-copy-id -o StrictHostKeyChecking=no root@$node || {
        log_error "$node에 SSH 키 복사 실패. 수동으로 설정하세요:"
        log_error "ssh-copy-id root@$node"
        exit 1
    }
    
    # 연결 테스트
    ssh root@$node "hostname" || {
        log_error "$node SSH 연결 실패"
        exit 1
    }
done

# RDO 저장소 설치
log_info "RDO 저장소 설치 중..."
dnf install -y centos-release-openstack-zed epel-release
dnf update -y

# Packstack 설치
log_info "Packstack 설치 중..."
dnf install -y openstack-packstack

# 멀티 노드용 응답 파일 생성
log_info "멀티 노드용 Packstack 응답 파일 생성 중..."
packstack --gen-answer-file=/root/packstack-answers-multinode.txt

# 응답 파일 백업
cp /root/packstack-answers-multinode.txt /root/packstack-answers-multinode.txt.backup

# 응답 파일 수정
log_info "응답 파일 설정 중..."
sed -i "s/CONFIG_DEFAULT_PASSWORD=.*/CONFIG_DEFAULT_PASSWORD=$DEFAULT_PASSWORD/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_KEYSTONE_ADMIN_PW=.*/CONFIG_KEYSTONE_ADMIN_PW=$ADMIN_PASSWORD/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_CONTROLLER_HOST=.*/CONFIG_CONTROLLER_HOST=$CONTROLLER_IP/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_COMPUTE_HOSTS=.*/CONFIG_COMPUTE_HOSTS=$COMPUTE_NODES/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NETWORK_HOSTS=.*/CONFIG_NETWORK_HOSTS=$CONTROLLER_IP/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_STORAGE_HOST=.*/CONFIG_STORAGE_HOST=$CONTROLLER_IP/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=.*/CONFIG_NEUTRON_ML2_TYPE_DRIVERS=vxlan,flat,vlan/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=.*/CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=vxlan/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NEUTRON_ML2_MECHANISM_DRIVERS=.*/CONFIG_NEUTRON_ML2_MECHANISM_DRIVERS=openvswitch/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=.*/CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=extnet:br-ex/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_NEUTRON_OVS_BRIDGE_IFACES=.*/CONFIG_NEUTRON_OVS_BRIDGE_IFACES=br-ex:enp0s8/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_HORIZON_SSL=.*/CONFIG_HORIZON_SSL=n/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_CINDER_INSTALL=.*/CONFIG_CINDER_INSTALL=y/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_SWIFT_INSTALL=.*/CONFIG_SWIFT_INSTALL=n/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_HEAT_INSTALL=.*/CONFIG_HEAT_INSTALL=y/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_MAGNUM_INSTALL=.*/CONFIG_MAGNUM_INSTALL=n/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_OCTAVIA_INSTALL=.*/CONFIG_OCTAVIA_INSTALL=n/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_PROVISION_DEMO=.*/CONFIG_PROVISION_DEMO=y/" /root/packstack-answers-multinode.txt
sed -i "s/CONFIG_USE_EPEL=.*/CONFIG_USE_EPEL=y/" /root/packstack-answers-multinode.txt

# SSH 키 파일 경로 설정
echo "CONFIG_SSH_KEY_FILE=/root/.ssh/id_rsa.pub" >> /root/packstack-answers-multinode.txt

# Compute 노드들 사전 준비
log_info "Compute 노드들 사전 준비 중..."
for node in "${NODES[@]}"; do
    log_info "$node 노드 준비 중..."
    
    # 기본 패키지 설치 및 설정
    ssh root@$node << 'EOF'
        # 시스템 업데이트
        dnf update -y
        
        # 필수 패키지 설치
        dnf groupinstall -y "Development Tools"
        dnf install -y vim wget curl git net-tools bind-utils chrony
        
        # SELinux 설정
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        
        # 방화벽 비활성화
        systemctl stop firewalld
        systemctl disable firewalld
        
        # 시간 동기화
        systemctl enable chronyd
        systemctl start chronyd
        
        # RDO 저장소 설치
        dnf install -y centos-release-openstack-zed epel-release
        dnf update -y
        
        # 하드웨어 가상화 확인
        if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]]; then
            echo "WARNING: 하드웨어 가상화가 지원되지 않습니다."
        fi
        
        echo "노드 준비 완료: $(hostname)"
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "$node 노드 준비 완료"
    else
        log_error "$node 노드 준비 실패"
        exit 1
    fi
done

# Packstack 실행
log_info "멀티 노드 OpenStack 설치 시작... (약 45-90분 소요)"
log_info "설치 로그는 /var/tmp/packstack/latest/openstack-setup.log에서 확인할 수 있습니다."

packstack --answer-file=/root/packstack-answers-multinode.txt

# 설치 완료 확인
if [[ $? -eq 0 ]]; then
    log_info "멀티 노드 OpenStack 설치 완료!"
else
    log_error "OpenStack 설치 실패!"
    exit 1
fi

# 환경 변수 설정
log_info "환경 변수 설정..."
if [[ -f /root/keystonerc_admin ]]; then
    cp /root/keystonerc_admin /home/$(logname)/
    chown $(logname):$(logname) /home/$(logname)/keystonerc_admin
    
    if ! grep -q "keystonerc_admin" /home/$(logname)/.bashrc; then
        echo "source /home/$(logname)/keystonerc_admin" >> /home/$(logname)/.bashrc
    fi
fi

# OpenStack 클라이언트 설치
log_info "OpenStack 클라이언트 설치..."
dnf install -y python3-openstackclient

# 설치 후 확인
log_info "설치 확인 중..."
source /root/keystonerc_admin

# 서비스 상태 확인
log_info "OpenStack 서비스 확인..."
openstack service list

# 컴퓨트 서비스 확인
log_info "컴퓨트 서비스 확인..."
openstack compute service list

# 하이퍼바이저 확인
log_info "하이퍼바이저 확인..."
openstack hypervisor list

# 네트워크 에이전트 확인
log_info "네트워크 에이전트 확인..."
openstack network agent list

# 기본 네트워크 설정
log_info "기본 네트워크 설정..."

# External 네트워크 생성
openstack network create --external \
  --provider-physical-network extnet \
  --provider-network-type flat \
  external || true

# External 서브넷 생성
openstack subnet create --network external \
  --allocation-pool start=192.168.100.100,end=192.168.100.200 \
  --dns-nameserver 8.8.8.8 \
  --gateway 192.168.100.1 \
  --subnet-range 192.168.100.0/24 \
  external-subnet || true

# Internal 네트워크 생성
openstack network create internal || true

# Internal 서브넷 생성
openstack subnet create --network internal \
  --dns-nameserver 8.8.8.8 \
  --gateway 10.0.0.1 \
  --subnet-range 10.0.0.0/24 \
  internal-subnet || true

# 라우터 생성 및 설정
openstack router create router1 || true
openstack router set --external-gateway external router1 || true
openstack router add subnet router1 internal-subnet || true

# 보안 그룹 규칙 추가
log_info "보안 그룹 규칙 설정..."
openstack security group rule create --protocol tcp --dst-port 22 default || true
openstack security group rule create --protocol icmp default || true
openstack security group rule create --protocol tcp --dst-port 80 default || true
openstack security group rule create --protocol tcp --dst-port 443 default || true

# SSH 키페어 생성
log_info "SSH 키페어 생성..."
if [[ ! -f /home/$(logname)/.ssh/openstack-key ]]; then
    sudo -u $(logname) ssh-keygen -t rsa -b 2048 -f /home/$(logname)/.ssh/openstack-key -N ""
    openstack keypair create --public-key /home/$(logname)/.ssh/openstack-key.pub openstack-key || true
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
  --public || true

# Flavor 생성
log_info "Flavor 생성..."
openstack flavor create --id 1 --vcpus 1 --ram 512 --disk 1 m1.tiny || true
openstack flavor create --id 2 --vcpus 1 --ram 2048 --disk 20 m1.small || true
openstack flavor create --id 3 --vcpus 2 --ram 4096 --disk 40 m1.medium || true

# 테스트 인스턴스 생성 (노드 분산 확인)
log_info "테스트 인스턴스 생성 중..."
for i in {1..3}; do
    openstack server create --flavor m1.small \
      --image cirros \
      --key-name openstack-key \
      --security-group default \
      --network internal \
      test-multinode-$i || true
done

log_info "=== 멀티 노드 OpenStack 설치 완료 ==="
echo ""
echo "설치된 구성:"
echo "- Controller 노드: $CONTROLLER_IP"
echo "- Compute 노드들: $COMPUTE_NODES"
echo ""
echo "Horizon 대시보드 접근 정보:"
echo "URL: http://$CONTROLLER_IP/dashboard"
echo "사용자명: admin"
echo "패스워드: $ADMIN_PASSWORD"
echo ""
echo "CLI 환경 변수 로드:"
echo "source /root/keystonerc_admin"
echo ""
echo "노드 상태 확인:"
echo "openstack compute service list"
echo "openstack hypervisor list"
echo ""
echo "인스턴스 분산 확인:"
echo "openstack server list --long"
