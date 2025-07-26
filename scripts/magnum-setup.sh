#!/bin/bash

# Magnum 자동 설치 및 구성 스크립트
# OpenStack Zed 환경용

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
MAGNUM_DB_PASSWORD="magnum_pass"
MAGNUM_PASSWORD="magnum_pass"

echo "=== Magnum 설치 및 구성 시작 ==="

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# OpenStack 환경 변수 로드
source /root/keystonerc_admin

# Magnum 패키지 설치
log_info "Magnum 패키지 설치 중..."
dnf install -y openstack-magnum-api openstack-magnum-conductor
dnf install -y python3-magnumclient docker

# Docker 서비스 시작
log_info "Docker 서비스 설정..."
systemctl enable docker
systemctl start docker
usermod -aG docker $(logname)

# Magnum 데이터베이스 생성
log_info "Magnum 데이터베이스 생성..."
mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS magnum;
GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'localhost' IDENTIFIED BY '$MAGNUM_DB_PASSWORD';
GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'%' IDENTIFIED BY '$MAGNUM_DB_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Keystone 서비스 등록
log_info "Keystone 서비스 등록..."
openstack user create --domain default --password $MAGNUM_PASSWORD magnum || true
openstack role add --project service --user magnum admin || true

openstack service create --name magnum --description "OpenStack Container Infrastructure Management Service" container-infra || true

openstack endpoint create --region RegionOne container-infra public http://$CONTROLLER_IP:9511/v1 || true
openstack endpoint create --region RegionOne container-infra internal http://$CONTROLLER_IP:9511/v1 || true
openstack endpoint create --region RegionOne container-infra admin http://$CONTROLLER_IP:9511/v1 || true

# Magnum 사용자 생성
log_info "Magnum 시스템 사용자 생성..."
useradd --system --shell /bin/false --home-dir /var/lib/magnum magnum || true

# Magnum 설정 파일 생성
log_info "Magnum 설정 파일 생성..."
mkdir -p /etc/magnum
cat > /etc/magnum/magnum.conf << EOF
[DEFAULT]
debug = True
log_dir = /var/log/magnum
transport_url = rabbit://guest:guest@$CONTROLLER_IP:5672/

[api]
host = $CONTROLLER_IP
port = 9511

[database]
connection = mysql+pymysql://magnum:$MAGNUM_DB_PASSWORD@$CONTROLLER_IP/magnum

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = magnum
password = $MAGNUM_PASSWORD

[trust]
trustee_domain_admin_id = magnum
trustee_domain_admin_password = $MAGNUM_PASSWORD

[cinder_client]
region_name = RegionOne

[barbican_client]
region_name = RegionOne

[glance_client]
region_name = RegionOne

[heat_client]
region_name = RegionOne

[magnum_client]
region_name = RegionOne

[neutron_client]
region_name = RegionOne

[nova_client]
region_name = RegionOne

[octavia_client]
region_name = RegionOne
EOF

# 로그 디렉토리 생성
log_info "로그 디렉토리 생성..."
mkdir -p /var/log/magnum
chown magnum:magnum /var/log/magnum

# 데이터베이스 초기화
log_info "Magnum 데이터베이스 초기화..."
sudo -u magnum magnum-db-manage upgrade

# systemd 서비스 파일 생성
log_info "systemd 서비스 파일 생성..."

# Magnum API 서비스
cat > /etc/systemd/system/openstack-magnum-api.service << EOF
[Unit]
Description=OpenStack Magnum API Server
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=magnum
ExecStart=/usr/bin/magnum-api --config-file /etc/magnum/magnum.conf

[Install]
WantedBy=multi-user.target
EOF

# Magnum Conductor 서비스
cat > /etc/systemd/system/openstack-magnum-conductor.service << EOF
[Unit]
Description=OpenStack Magnum Conductor
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=magnum
ExecStart=/usr/bin/magnum-conductor --config-file /etc/magnum/magnum.conf

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
log_info "Magnum 서비스 시작..."
systemctl daemon-reload
systemctl enable openstack-magnum-api
systemctl enable openstack-magnum-conductor
systemctl start openstack-magnum-api
systemctl start openstack-magnum-conductor

# 서비스 상태 확인
sleep 5
systemctl status openstack-magnum-api --no-pager
systemctl status openstack-magnum-conductor --no-pager

# Fedora CoreOS 이미지 다운로드 및 등록
log_info "Fedora CoreOS 이미지 다운로드 중..."
cd /tmp
if [[ ! -f fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2 ]]; then
    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/38.20230918.3.0/x86_64/fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2.xz
    xz -d fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2.xz
fi

log_info "Fedora CoreOS 이미지 등록..."
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --file fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2 \
  --property os_distro=fedora-coreos \
  --public \
  fedora-coreos-38 || true

# Kubernetes 클러스터 템플릿 생성
log_info "Kubernetes 클러스터 템플릿 생성..."
openstack coe cluster template create kubernetes-cluster-template \
  --image fedora-coreos-38 \
  --keypair openstack-key \
  --external-network external \
  --dns-nameserver 8.8.8.8 \
  --flavor m1.small \
  --master-flavor m1.small \
  --docker-volume-size 20 \
  --network-driver flannel \
  --coe kubernetes \
  --labels kube_tag=v1.27.3 || true

# 보안 그룹 규칙 추가 (Kubernetes API)
log_info "Kubernetes API 포트 보안 그룹 규칙 추가..."
openstack security group rule create --protocol tcp --dst-port 6443 default || true

# kubectl 설치
log_info "kubectl 설치..."
if [[ ! -f /usr/local/bin/kubectl ]]; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

log_info "=== Magnum 설치 완료 ==="
echo ""
echo "Magnum 서비스 상태:"
echo "- API: $(systemctl is-active openstack-magnum-api)"
echo "- Conductor: $(systemctl is-active openstack-magnum-conductor)"
echo ""
echo "클러스터 템플릿 확인:"
echo "openstack coe cluster template list"
echo ""
echo "Kubernetes 클러스터 생성 예제:"
echo "openstack coe cluster create k8s-cluster \\"
echo "  --cluster-template kubernetes-cluster-template \\"
echo "  --master-count 1 \\"
echo "  --node-count 2 \\"
echo "  --timeout 60"
echo ""
echo "클러스터 상태 확인:"
echo "openstack coe cluster list"
