#!/bin/bash

# Octavia 자동 설치 및 구성 스크립트
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
OCTAVIA_DB_PASSWORD="octavia_pass"
OCTAVIA_PASSWORD="octavia_pass"

echo "=== Octavia 설치 및 구성 시작 ==="

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   log_error "이 스크립트는 root 권한으로 실행해야 합니다."
   exit 1
fi

# OpenStack 환경 변수 로드
source /root/keystonerc_admin

# Octavia 패키지 설치
log_info "Octavia 패키지 설치 중..."
dnf install -y openstack-octavia-api openstack-octavia-health-manager
dnf install -y openstack-octavia-housekeeping openstack-octavia-worker
dnf install -y python3-octaviaclient git qemu-img debootstrap kpartx

# DIB 설치
log_info "Disk Image Builder 설치..."
pip3 install diskimage-builder

# Octavia 데이터베이스 생성
log_info "Octavia 데이터베이스 생성..."
mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS octavia;
GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'localhost' IDENTIFIED BY '$OCTAVIA_DB_PASSWORD';
GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'%' IDENTIFIED BY '$OCTAVIA_DB_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Keystone 서비스 등록
log_info "Keystone 서비스 등록..."
openstack user create --domain default --password $OCTAVIA_PASSWORD octavia || true
openstack role add --project service --user octavia admin || true

openstack service create --name octavia --description "OpenStack Load Balancer" load-balancer || true

openstack endpoint create --region RegionOne load-balancer public http://$CONTROLLER_IP:9876 || true
openstack endpoint create --region RegionOne load-balancer internal http://$CONTROLLER_IP:9876 || true
openstack endpoint create --region RegionOne load-balancer admin http://$CONTROLLER_IP:9876 || true

# Octavia 사용자 생성
log_info "Octavia 시스템 사용자 생성..."
useradd --system --shell /bin/false --home-dir /var/lib/octavia octavia || true

# Amphora 이미지 빌드
log_info "Amphora 이미지 빌드 중... (시간이 오래 걸릴 수 있습니다)"
cd /tmp
if [[ ! -d octavia ]]; then
    git clone https://opendev.org/openstack/octavia.git
fi

cd octavia/diskimage-create

# 환경 변수 설정
export DIB_REPOLOCATION_pip_and_virtualenv=https://github.com/pypa/get-pip
export DIB_REPOREF_pip_and_virtualenv=main

# Ubuntu 기반 Amphora 이미지 생성
if [[ ! -f amphora-x64-haproxy.qcow2 ]]; then
    log_info "Amphora 이미지 빌드 시작..."
    ./diskimage-create.sh -a amd64 -o amphora-x64-haproxy -t qcow2 -i ubuntu-minimal
fi

# Amphora 이미지 등록
log_info "Amphora 이미지 등록..."
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --file amphora-x64-haproxy.qcow2 \
  --tag amphora \
  --property hw_architecture='x86_64' \
  --property hw_rng_model=virtio \
  amphora-x64-haproxy || true

# Octavia Management 네트워크 생성
log_info "Octavia Management 네트워크 생성..."
openstack network create lb-mgmt-net || true

openstack subnet create \
  --network lb-mgmt-net \
  --subnet-range 172.16.0.0/24 \
  --allocation-pool start=172.16.0.100,end=172.16.0.200 \
  --gateway 172.16.0.1 \
  lb-mgmt-subnet || true

# 보안 그룹 생성
log_info "Octavia 보안 그룹 생성..."
openstack security group create lb-mgmt-sec-grp || true
openstack security group create lb-health-mgr-sec-grp || true

# Management 보안 그룹 규칙
openstack security group rule create --protocol icmp lb-mgmt-sec-grp || true
openstack security group rule create --protocol tcp --dst-port 22 lb-mgmt-sec-grp || true
openstack security group rule create --protocol tcp --dst-port 9443 lb-mgmt-sec-grp || true

# Health Manager 보안 그룹 규칙
openstack security group rule create --protocol udp --dst-port 5555 lb-health-mgr-sec-grp || true

# Amphora 전용 Flavor 생성
log_info "Amphora Flavor 생성..."
openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 amphora || true

# 인증서 생성
log_info "Octavia 인증서 생성..."
mkdir -p /etc/octavia/certs
cd /etc/octavia/certs

# CA 개인키 생성
openssl genrsa -passout pass:foobar -des3 -out ca_key.pem 2048

# CA 인증서 생성
openssl req -new -x509 -passin pass:foobar -key ca_key.pem -out ca_01.pem -days 365 \
  -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"

# 클라이언트 인증서 생성
openssl genrsa -passout pass:foobar -des3 -out client_key.pem 2048
openssl req -new -key client_key.pem -passin pass:foobar -out client.csr \
  -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
openssl x509 -req -passin pass:foobar -in client.csr -CA ca_01.pem -CAkey ca_key.pem -CAcreateserial -out client-.pem -days 365

# 권한 설정
chown -R octavia:octavia /etc/octavia/certs
chmod 700 /etc/octavia/certs
chmod 600 /etc/octavia/certs/*

# Octavia 설정 파일 생성
log_info "Octavia 설정 파일 생성..."
LB_MGMT_NET_ID=$(openstack network show lb-mgmt-net -f value -c id)

cat > /etc/octavia/octavia.conf << EOF
[DEFAULT]
debug = True
log_dir = /var/log/octavia
transport_url = rabbit://guest:guest@$CONTROLLER_IP:5672/

[api_settings]
bind_host = $CONTROLLER_IP
bind_port = 9876

[database]
connection = mysql+pymysql://octavia:$OCTAVIA_DB_PASSWORD@$CONTROLLER_IP/octavia

[health_manager]
bind_ip = $CONTROLLER_IP
bind_port = 5555
controller_ip_port_list = $CONTROLLER_IP:5555
heartbeat_key = insecure

[keystone_authtoken]
www_authenticate_uri = http://$CONTROLLER_IP:5000
auth_url = http://$CONTROLLER_IP:5000
memcached_servers = $CONTROLLER_IP:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = octavia
password = $OCTAVIA_PASSWORD

[certificates]
ca_certificate = /etc/octavia/certs/ca_01.pem
ca_private_key = /etc/octavia/certs/ca_key.pem
ca_private_key_passphrase = foobar

[haproxy_amphora]
client_cert = /etc/octavia/certs/client-.pem
client_cert_key = /etc/octavia/certs/client_key.pem

[controller_worker]
amp_image_tag = amphora
amp_ssh_key_name = openstack-key
amp_secgroup_list = lb-mgmt-sec-grp
amp_flavor_id = 200
amp_boot_network_list = $LB_MGMT_NET_ID
network_driver = allowed_address_pairs_driver
compute_driver = compute_nova_driver
amphora_driver = amphora_haproxy_rest_driver

[task_flow]
engine = parallel
max_workers = 5

[oslo_messaging]
topic = octavia_prov

[oslo_messaging_notifications]
driver = messagingv2
EOF

# 로그 디렉토리 생성
log_info "로그 디렉토리 생성..."
mkdir -p /var/log/octavia
chown octavia:octavia /var/log/octavia

# 데이터베이스 초기화
log_info "Octavia 데이터베이스 초기화..."
sudo -u octavia octavia-db-manage upgrade head

# systemd 서비스 파일 생성
log_info "systemd 서비스 파일 생성..."

# Octavia API 서비스
cat > /etc/systemd/system/octavia-api.service << EOF
[Unit]
Description=OpenStack Octavia API Server
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=octavia
ExecStart=/usr/bin/octavia-api --config-file /etc/octavia/octavia.conf

[Install]
WantedBy=multi-user.target
EOF

# Octavia Health Manager
cat > /etc/systemd/system/octavia-health-manager.service << EOF
[Unit]
Description=OpenStack Octavia Health Manager
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=octavia
ExecStart=/usr/bin/octavia-health-manager --config-file /etc/octavia/octavia.conf

[Install]
WantedBy=multi-user.target
EOF

# Octavia Housekeeping
cat > /etc/systemd/system/octavia-housekeeping.service << EOF
[Unit]
Description=OpenStack Octavia Housekeeping
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=octavia
ExecStart=/usr/bin/octavia-housekeeping --config-file /etc/octavia/octavia.conf

[Install]
WantedBy=multi-user.target
EOF

# Octavia Worker
cat > /etc/systemd/system/octavia-worker.service << EOF
[Unit]
Description=OpenStack Octavia Worker
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=octavia
ExecStart=/usr/bin/octavia-worker --config-file /etc/octavia/octavia.conf

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
log_info "Octavia 서비스 시작..."
systemctl daemon-reload

systemctl enable octavia-api
systemctl enable octavia-health-manager
systemctl enable octavia-housekeeping
systemctl enable octavia-worker

systemctl start octavia-api
systemctl start octavia-health-manager
systemctl start octavia-housekeeping
systemctl start octavia-worker

# 서비스 상태 확인
sleep 5
systemctl status octavia-api --no-pager
systemctl status octavia-health-manager --no-pager
systemctl status octavia-housekeeping --no-pager
systemctl status octavia-worker --no-pager

log_info "=== Octavia 설치 완료 ==="
echo ""
echo "Octavia 서비스 상태:"
echo "- API: $(systemctl is-active octavia-api)"
echo "- Health Manager: $(systemctl is-active octavia-health-manager)"
echo "- Housekeeping: $(systemctl is-active octavia-housekeeping)"
echo "- Worker: $(systemctl is-active octavia-worker)"
echo ""
echo "로드밸런서 생성 예제:"
echo "openstack loadbalancer create --name test-lb --vip-subnet-id internal-subnet"
echo ""
echo "로드밸런서 상태 확인:"
echo "openstack loadbalancer list"
