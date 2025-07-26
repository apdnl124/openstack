# 4. Octavia 설치 및 구성

Octavia는 OpenStack의 로드밸런서 서비스로, Amphora 가상머신을 사용하여 고가용성 로드밸런싱을 제공합니다.

## 사전 요구사항

### 1.1 필수 서비스 확인

```bash
# OpenStack 기본 서비스 상태 확인
openstack service list

# Neutron 및 Nova 서비스 확인
openstack network agent list
openstack compute service list
```

### 1.2 필수 패키지 설치

```bash
# Octavia 관련 패키지 설치
sudo dnf install -y openstack-octavia-api openstack-octavia-health-manager
sudo dnf install -y openstack-octavia-housekeeping openstack-octavia-worker
sudo dnf install -y python3-octaviaclient

# 이미지 빌드 도구 설치
sudo dnf install -y git qemu-img debootstrap kpartx
```

## Octavia 데이터베이스 설정

### 2.1 데이터베이스 생성

```bash
# MariaDB 접속
sudo mysql -u root

# Octavia 데이터베이스 및 사용자 생성
CREATE DATABASE octavia;
GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'localhost' IDENTIFIED BY 'octavia_pass';
GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'%' IDENTIFIED BY 'octavia_pass';
FLUSH PRIVILEGES;
EXIT;
```

### 2.2 Keystone 서비스 등록

```bash
# Octavia 사용자 생성
openstack user create --domain default --password octavia_pass octavia

# Octavia 사용자에 admin 역할 부여
openstack role add --project service --user octavia admin

# Octavia 서비스 생성
openstack service create --name octavia --description "OpenStack Load Balancer" load-balancer

# Octavia 엔드포인트 생성
openstack endpoint create --region RegionOne load-balancer public http://192.168.1.10:9876
openstack endpoint create --region RegionOne load-balancer internal http://192.168.1.10:9876
openstack endpoint create --region RegionOne load-balancer admin http://192.168.1.10:9876
```

## Amphora 이미지 생성

### 3.1 DIB (Disk Image Builder) 설치

```bash
# DIB 설치
sudo pip3 install diskimage-builder

# Octavia 이미지 빌드 스크립트 다운로드
git clone https://opendev.org/openstack/octavia.git
cd octavia/diskimage-create
```

### 3.2 Amphora 이미지 빌드

```bash
# 환경 변수 설정
export DIB_REPOLOCATION_pip_and_virtualenv=https://github.com/pypa/get-pip
export DIB_REPOREF_pip_and_virtualenv=main

# Ubuntu 기반 Amphora 이미지 생성 (권장)
./diskimage-create.sh -a amd64 -o amphora-x64-haproxy -t qcow2 -i ubuntu-minimal

# 또는 CentOS 기반 이미지 생성
# ./diskimage-create.sh -a amd64 -o amphora-x64-haproxy -t qcow2 -i centos-minimal
```

### 3.3 Amphora 이미지 등록

```bash
# OpenStack에 Amphora 이미지 등록
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --file amphora-x64-haproxy.qcow2 \
  --tag amphora \
  --property hw_architecture='x86_64' \
  --property hw_rng_model=virtio \
  amphora-x64-haproxy

# 이미지 확인
openstack image list | grep amphora
```

## Octavia 네트워크 설정

### 4.1 Management 네트워크 생성

```bash
# Octavia Management 네트워크 생성
openstack network create lb-mgmt-net

# Management 서브넷 생성
openstack subnet create \
  --network lb-mgmt-net \
  --subnet-range 172.16.0.0/24 \
  --allocation-pool start=172.16.0.100,end=172.16.0.200 \
  --gateway 172.16.0.1 \
  lb-mgmt-subnet
```

### 4.2 보안 그룹 생성

```bash
# Octavia 보안 그룹 생성
openstack security group create lb-mgmt-sec-grp
openstack security group create lb-health-mgr-sec-grp

# Management 보안 그룹 규칙
openstack security group rule create --protocol icmp lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 22 lb-mgmt-sec-grp
openstack security group rule create --protocol tcp --dst-port 9443 lb-mgmt-sec-grp

# Health Manager 보안 그룹 규칙
openstack security group rule create --protocol udp --dst-port 5555 lb-health-mgr-sec-grp
```

### 4.3 Flavor 생성

```bash
# Amphora 전용 Flavor 생성
openstack flavor create --id 200 --vcpus 1 --ram 1024 --disk 2 amphora
```

## Octavia 설정

### 5.1 인증서 생성

```bash
# 인증서 디렉토리 생성
sudo mkdir -p /etc/octavia/certs
cd /etc/octavia/certs

# CA 개인키 생성
sudo openssl genrsa -passout pass:foobar -des3 -out ca_key.pem 2048

# CA 인증서 생성
sudo openssl req -new -x509 -passin pass:foobar -key ca_key.pem -out ca_01.pem -days 365 \
  -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"

# 클라이언트 인증서 생성
sudo openssl genrsa -passout pass:foobar -des3 -out client_key.pem 2048
sudo openssl req -new -key client_key.pem -passin pass:foobar -out client.csr \
  -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
sudo openssl x509 -req -passin pass:foobar -in client.csr -CA ca_01.pem -CAkey ca_key.pem -CAcreateserial -out client-.pem -days 365

# 권한 설정
sudo chown -R octavia:octavia /etc/octavia/certs
sudo chmod 700 /etc/octavia/certs
sudo chmod 600 /etc/octavia/certs/*
```

### 5.2 Octavia 설정 파일 생성

```bash
# Octavia 설정 파일 생성
sudo tee /etc/octavia/octavia.conf << 'EOF'
[DEFAULT]
debug = True
log_dir = /var/log/octavia
transport_url = rabbit://guest:guest@192.168.1.10:5672/

[api_settings]
bind_host = 192.168.1.10
bind_port = 9876

[database]
connection = mysql+pymysql://octavia:octavia_pass@192.168.1.10/octavia

[health_manager]
bind_ip = 192.168.1.10
bind_port = 5555
controller_ip_port_list = 192.168.1.10:5555
heartbeat_key = insecure

[keystone_authtoken]
www_authenticate_uri = http://192.168.1.10:5000
auth_url = http://192.168.1.10:5000
memcached_servers = 192.168.1.10:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = octavia
password = octavia_pass

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
amp_boot_network_list = $(openstack network show lb-mgmt-net -f value -c id)
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
```

### 5.3 로그 디렉토리 생성

```bash
# 로그 디렉토리 생성
sudo mkdir -p /var/log/octavia
sudo chown octavia:octavia /var/log/octavia
```

### 5.4 데이터베이스 초기화

```bash
# Octavia 데이터베이스 스키마 생성
sudo -u octavia octavia-db-manage upgrade head
```

## Octavia 서비스 시작

### 6.1 systemd 서비스 파일 생성

**Octavia API 서비스:**
```bash
sudo tee /etc/systemd/system/octavia-api.service << 'EOF'
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
```

**Octavia Health Manager:**
```bash
sudo tee /etc/systemd/system/octavia-health-manager.service << 'EOF'
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
```

**Octavia Housekeeping:**
```bash
sudo tee /etc/systemd/system/octavia-housekeeping.service << 'EOF'
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
```

**Octavia Worker:**
```bash
sudo tee /etc/systemd/system/octavia-worker.service << 'EOF'
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
```

### 6.2 서비스 시작 및 활성화

```bash
# systemd 데몬 리로드
sudo systemctl daemon-reload

# Octavia 서비스 시작
sudo systemctl enable octavia-api
sudo systemctl enable octavia-health-manager
sudo systemctl enable octavia-housekeeping
sudo systemctl enable octavia-worker

sudo systemctl start octavia-api
sudo systemctl start octavia-health-manager
sudo systemctl start octavia-housekeeping
sudo systemctl start octavia-worker

# 서비스 상태 확인
sudo systemctl status octavia-api
sudo systemctl status octavia-health-manager
sudo systemctl status octavia-housekeeping
sudo systemctl status octavia-worker
```

## 로드밸런서 생성 및 테스트

### 7.1 테스트 웹 서버 생성

```bash
# 웹 서버 인스턴스 2개 생성
openstack server create --flavor m1.small \
  --image cirros \
  --key-name openstack-key \
  --security-group default \
  --network internal \
  web-server-1

openstack server create --flavor m1.small \
  --image cirros \
  --key-name openstack-key \
  --security-group default \
  --network internal \
  web-server-2

# 인스턴스 상태 확인
openstack server list
```

### 7.2 로드밸런서 생성

```bash
# 로드밸런서 생성
openstack loadbalancer create --name test-lb --vip-subnet-id internal-subnet

# 로드밸런서 상태 확인
openstack loadbalancer list
openstack loadbalancer show test-lb
```

### 7.3 리스너 생성

```bash
# HTTP 리스너 생성
openstack loadbalancer listener create --name test-listener \
  --protocol HTTP \
  --protocol-port 80 \
  test-lb

# 리스너 상태 확인
openstack loadbalancer listener list
```

### 7.4 풀 생성

```bash
# 백엔드 풀 생성
openstack loadbalancer pool create --name test-pool \
  --lb-algorithm ROUND_ROBIN \
  --listener test-listener \
  --protocol HTTP

# 풀 상태 확인
openstack loadbalancer pool list
```

### 7.5 멤버 추가

```bash
# 웹 서버 IP 주소 확인
WEB1_IP=$(openstack server show web-server-1 -f value -c addresses | cut -d'=' -f2)
WEB2_IP=$(openstack server show web-server-2 -f value -c addresses | cut -d'=' -f2)

# 풀에 멤버 추가
openstack loadbalancer member create --subnet-id internal-subnet \
  --address $WEB1_IP \
  --protocol-port 80 \
  test-pool

openstack loadbalancer member create --subnet-id internal-subnet \
  --address $WEB2_IP \
  --protocol-port 80 \
  test-pool

# 멤버 상태 확인
openstack loadbalancer member list test-pool
```

### 7.6 헬스 모니터 생성

```bash
# 헬스 모니터 생성
openstack loadbalancer healthmonitor create --delay 5 \
  --max-retries 3 \
  --timeout 3 \
  --type HTTP \
  --url-path / \
  test-pool

# 헬스 모니터 상태 확인
openstack loadbalancer healthmonitor list
```

### 7.7 Floating IP 할당

```bash
# 로드밸런서 VIP 확인
LB_VIP=$(openstack loadbalancer show test-lb -f value -c vip_address)

# Floating IP 생성 및 할당
openstack floating ip create external
FLOATING_IP=$(openstack floating ip list --status DOWN -f value -c "Floating IP Address" | head -1)

# VIP 포트 확인 및 Floating IP 할당
VIP_PORT_ID=$(openstack port list --fixed-ip ip-address=$LB_VIP -f value -c ID)
openstack floating ip set --port $VIP_PORT_ID $FLOATING_IP

echo "Load Balancer accessible at: http://$FLOATING_IP"
```

## 로드밸런서 테스트

### 8.1 웹 서버 설정

```bash
# 각 웹 서버에 접속하여 간단한 웹 페이지 생성
# Web Server 1
ssh cirros@$(openstack server show web-server-1 -f value -c addresses | cut -d'=' -f2)
# 웹 서버에서 실행:
# while true; do echo -e "HTTP/1.1 200 OK\n\nServer 1 Response" | nc -l -p 80; done &

# Web Server 2
ssh cirros@$(openstack server show web-server-2 -f value -c addresses | cut -d'=' -f2)
# 웹 서버에서 실행:
# while true; do echo -e "HTTP/1.1 200 OK\n\nServer 2 Response" | nc -l -p 80; done &
```

### 8.2 로드밸런싱 테스트

```bash
# 로드밸런서를 통한 접속 테스트
for i in {1..10}; do
  curl http://$FLOATING_IP
  echo "Request $i completed"
  sleep 1
done
```

## SSL/TLS 로드밸런서 설정

### 9.1 SSL 인증서 생성

```bash
# 자체 서명 인증서 생성
openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"

# Barbican에 인증서 저장
openstack secret store --name='server-crt' --payload-content-type='text/plain' \
  --payload="$(cat server.crt)"

openstack secret store --name='server-key' --payload-content-type='text/plain' \
  --payload="$(cat server.key)"
```

### 9.2 HTTPS 리스너 생성

```bash
# HTTPS 리스너 생성
openstack loadbalancer listener create --name https-listener \
  --protocol TERMINATED_HTTPS \
  --protocol-port 443 \
  --default-tls-container-ref $(openstack secret list --name server-crt -f value -c "Secret href") \
  test-lb
```

## 모니터링 및 관리

### 10.1 Octavia 상태 확인

```bash
# Octavia 서비스 상태
openstack loadbalancer status show test-lb

# Amphora 인스턴스 확인
openstack server list | grep amphora

# 로드밸런서 통계
openstack loadbalancer stats show test-lb
```

### 10.2 로그 모니터링

```bash
# Octavia 로그 확인
sudo tail -f /var/log/octavia/octavia-api.log
sudo tail -f /var/log/octavia/octavia-worker.log
sudo tail -f /var/log/octavia/octavia-health-manager.log
sudo tail -f /var/log/octavia/octavia-housekeeping.log
```

## 문제 해결

### 11.1 일반적인 문제들

**1. Amphora 인스턴스 생성 실패**
```bash
# Nova 로그 확인
sudo tail -f /var/log/nova/nova-compute.log

# 네트워크 연결 확인
openstack network show lb-mgmt-net
openstack subnet show lb-mgmt-subnet
```

**2. 헬스 체크 실패**
```bash
# 보안 그룹 규칙 확인
openstack security group rule list default

# 멤버 서버 상태 확인
openstack loadbalancer member show test-pool <member-id>
```

**3. SSL 인증서 문제**
```bash
# Barbican 서비스 상태 확인
openstack secret list

# 인증서 내용 확인
openstack secret get --payload $(openstack secret list --name server-crt -f value -c "Secret href")
```

### 11.2 디버깅 팁

```bash
# Octavia 디버그 모드 활성화
sudo sed -i 's/debug = False/debug = True/g' /etc/octavia/octavia.conf
sudo systemctl restart octavia-*

# Amphora 인스턴스에 직접 접속
openstack server list | grep amphora
ssh -i ~/.ssh/openstack-key ubuntu@<amphora-ip>
```

## 고급 설정

### 12.1 고가용성 로드밸런서

```bash
# Active-Standby 로드밸런서 생성
openstack loadbalancer create --name ha-lb \
  --vip-subnet-id internal-subnet \
  --topology ACTIVE_STANDBY
```

### 12.2 L7 정책 설정

```bash
# L7 정책 생성 (URL 기반 라우팅)
openstack loadbalancer l7policy create --action REDIRECT_TO_POOL \
  --redirect-pool test-pool \
  --name redirect-policy \
  test-listener

# L7 규칙 생성
openstack loadbalancer l7rule create --compare-type STARTS_WITH \
  --type PATH \
  --value /api \
  redirect-policy
```

이제 OpenStack Zed 환경에서 Octavia 로드밸런서 서비스가 완전히 구성되었습니다!
