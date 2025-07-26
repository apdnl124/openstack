# 3. Magnum 설치 및 구성

Magnum은 OpenStack에서 컨테이너 오케스트레이션 엔진(Kubernetes, Docker Swarm 등)을 관리하는 서비스입니다.

## 사전 요구사항

### 1.1 필수 서비스 확인

```bash
# OpenStack 기본 서비스 상태 확인
openstack service list

# Heat 서비스 확인 (Magnum에 필수)
openstack orchestration service list
```

### 1.2 추가 패키지 설치

```bash
# Magnum 관련 패키지 설치
sudo dnf install -y openstack-magnum-api openstack-magnum-conductor
sudo dnf install -y python3-magnumclient

# Docker 설치 (컨테이너 이미지 빌드용)
sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
```

## Magnum 데이터베이스 설정

### 2.1 데이터베이스 생성

```bash
# MariaDB 접속
sudo mysql -u root

# Magnum 데이터베이스 및 사용자 생성
CREATE DATABASE magnum;
GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'localhost' IDENTIFIED BY 'magnum_pass';
GRANT ALL PRIVILEGES ON magnum.* TO 'magnum'@'%' IDENTIFIED BY 'magnum_pass';
FLUSH PRIVILEGES;
EXIT;
```

### 2.2 Keystone 서비스 등록

```bash
# Magnum 사용자 생성
openstack user create --domain default --password magnum_pass magnum

# Magnum 사용자에 admin 역할 부여
openstack role add --project service --user magnum admin

# Magnum 서비스 생성
openstack service create --name magnum --description "OpenStack Container Infrastructure Management Service" container-infra

# Magnum 엔드포인트 생성
openstack endpoint create --region RegionOne container-infra public http://192.168.1.10:9511/v1
openstack endpoint create --region RegionOne container-infra internal http://192.168.1.10:9511/v1
openstack endpoint create --region RegionOne container-infra admin http://192.168.1.10:9511/v1
```

## Magnum 설정

### 3.1 Magnum 설정 파일 생성

```bash
# 설정 디렉토리 생성
sudo mkdir -p /etc/magnum

# Magnum 설정 파일 생성
sudo tee /etc/magnum/magnum.conf << 'EOF'
[DEFAULT]
debug = True
log_dir = /var/log/magnum
transport_url = rabbit://guest:guest@192.168.1.10:5672/

[api]
host = 192.168.1.10
port = 9511

[database]
connection = mysql+pymysql://magnum:magnum_pass@192.168.1.10/magnum

[keystone_authtoken]
www_authenticate_uri = http://192.168.1.10:5000
auth_url = http://192.168.1.10:5000
memcached_servers = 192.168.1.10:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = magnum
password = magnum_pass

[trust]
trustee_domain_admin_id = magnum
trustee_domain_admin_password = magnum_pass

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
```

### 3.2 로그 디렉토리 생성

```bash
# 로그 디렉토리 생성
sudo mkdir -p /var/log/magnum
sudo chown magnum:magnum /var/log/magnum
```

### 3.3 데이터베이스 초기화

```bash
# Magnum 데이터베이스 스키마 생성
sudo -u magnum magnum-db-manage upgrade
```

## Magnum 서비스 시작

### 4.1 systemd 서비스 파일 생성

**Magnum API 서비스:**
```bash
sudo tee /etc/systemd/system/openstack-magnum-api.service << 'EOF'
[Unit]
Description=OpenStack Magnum API Server
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=magnum
ExecStart=/usr/bin/magnum-api

[Install]
WantedBy=multi-user.target
EOF
```

**Magnum Conductor 서비스:**
```bash
sudo tee /etc/systemd/system/openstack-magnum-conductor.service << 'EOF'
[Unit]
Description=OpenStack Magnum Conductor
After=syslog.target network.target

[Service]
Type=notify
Restart=always
User=magnum
ExecStart=/usr/bin/magnum-conductor

[Install]
WantedBy=multi-user.target
EOF
```

### 4.2 서비스 시작 및 활성화

```bash
# systemd 데몬 리로드
sudo systemctl daemon-reload

# Magnum 서비스 시작
sudo systemctl enable openstack-magnum-api
sudo systemctl enable openstack-magnum-conductor
sudo systemctl start openstack-magnum-api
sudo systemctl start openstack-magnum-conductor

# 서비스 상태 확인
sudo systemctl status openstack-magnum-api
sudo systemctl status openstack-magnum-conductor
```

## 클러스터 템플릿 생성

### 5.1 Kubernetes 클러스터 템플릿

#### Fedora CoreOS 이미지 다운로드
```bash
# Fedora CoreOS 이미지 다운로드
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/38.20230918.3.0/x86_64/fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2.xz

# 압축 해제
xz -d fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2.xz

# OpenStack에 이미지 등록
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --file fedora-coreos-38.20230918.3.0-openstack.x86_64.qcow2 \
  --property os_distro=fedora-coreos \
  --public \
  fedora-coreos-38
```

#### Kubernetes 클러스터 템플릿 생성
```bash
# Kubernetes 클러스터 템플릿 생성
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
  --labels kube_tag=v1.27.3
```

### 5.2 Docker Swarm 클러스터 템플릿

#### Fedora Atomic 이미지 다운로드 (Docker Swarm용)
```bash
# Fedora Atomic 이미지 다운로드
wget https://download.fedoraproject.org/pub/fedora/linux/releases/37/Cloud/x86_64/images/Fedora-Cloud-Base-37-1.7.x86_64.qcow2

# OpenStack에 이미지 등록
openstack image create \
  --disk-format qcow2 \
  --container-format bare \
  --file Fedora-Cloud-Base-37-1.7.x86_64.qcow2 \
  --property os_distro=fedora-atomic \
  --public \
  fedora-atomic-37
```

#### Docker Swarm 클러스터 템플릿 생성
```bash
# Docker Swarm 클러스터 템플릿 생성
openstack coe cluster template create swarm-cluster-template \
  --image fedora-atomic-37 \
  --keypair openstack-key \
  --external-network external \
  --dns-nameserver 8.8.8.8 \
  --flavor m1.small \
  --master-flavor m1.small \
  --docker-volume-size 20 \
  --network-driver docker \
  --coe swarm-mode
```

## 클러스터 생성 및 관리

### 6.1 Kubernetes 클러스터 생성

```bash
# Kubernetes 클러스터 생성
openstack coe cluster create k8s-cluster \
  --cluster-template kubernetes-cluster-template \
  --master-count 1 \
  --node-count 2 \
  --timeout 60

# 클러스터 생성 상태 확인
openstack coe cluster list
openstack coe cluster show k8s-cluster
```

### 6.2 클러스터 상태 모니터링

```bash
# 클러스터 생성 진행 상황 확인
watch -n 30 'openstack coe cluster list'

# Heat 스택 상태 확인
openstack stack list
openstack stack show k8s-cluster-<cluster-id>
```

### 6.3 kubectl 설정

```bash
# 클러스터 설정 파일 다운로드
mkdir -p ~/.kube
openstack coe cluster config k8s-cluster --dir ~/.kube

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# 클러스터 연결 테스트
kubectl get nodes
kubectl get pods --all-namespaces
```

## Docker Swarm 클러스터 관리

### 7.1 Docker Swarm 클러스터 생성

```bash
# Docker Swarm 클러스터 생성
openstack coe cluster create swarm-cluster \
  --cluster-template swarm-cluster-template \
  --master-count 1 \
  --node-count 2 \
  --timeout 60

# 클러스터 상태 확인
openstack coe cluster show swarm-cluster
```

### 7.2 Docker Swarm 클라이언트 설정

```bash
# Docker 환경 변수 설정
eval $(openstack coe cluster config swarm-cluster)

# Swarm 클러스터 정보 확인
docker info
docker node ls
```

## 클러스터 확장 및 관리

### 8.1 클러스터 노드 확장

```bash
# 클러스터 노드 수 증가
openstack coe cluster update k8s-cluster replace node_count=4

# 업데이트 상태 확인
openstack coe cluster show k8s-cluster
```

### 8.2 클러스터 삭제

```bash
# 클러스터 삭제
openstack coe cluster delete k8s-cluster
openstack coe cluster delete swarm-cluster

# 클러스터 템플릿 삭제
openstack coe cluster template delete kubernetes-cluster-template
openstack coe cluster template delete swarm-cluster-template
```

## 애플리케이션 배포 예제

### 9.1 Kubernetes 애플리케이션 배포

```bash
# Nginx 배포
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# 서비스 상태 확인
kubectl get deployments
kubectl get services
kubectl get pods
```

### 9.2 Docker Swarm 서비스 배포

```bash
# Nginx 서비스 생성
docker service create --name nginx --publish 80:80 nginx

# 서비스 상태 확인
docker service ls
docker service ps nginx
```

## 모니터링 및 로그

### 10.1 Magnum 로그 확인

```bash
# Magnum API 로그
sudo tail -f /var/log/magnum/magnum-api.log

# Magnum Conductor 로그
sudo tail -f /var/log/magnum/magnum-conductor.log

# Heat 로그 (클러스터 생성 관련)
sudo tail -f /var/log/heat/heat-engine.log
```

### 10.2 클러스터 리소스 모니터링

```bash
# 클러스터 리소스 사용량 확인
openstack server list | grep k8s-cluster
openstack volume list | grep k8s-cluster

# Heat 스택 리소스 확인
openstack stack resource list k8s-cluster-<cluster-id>
```

## 문제 해결

### 11.1 일반적인 문제들

**1. 클러스터 생성 실패**
```bash
# Heat 스택 이벤트 확인
openstack stack event list k8s-cluster-<cluster-id>

# 실패한 리소스 확인
openstack stack resource list k8s-cluster-<cluster-id> --filter status=CREATE_FAILED
```

**2. 이미지 관련 문제**
```bash
# 이미지 속성 확인
openstack image show fedora-coreos-38

# 필요한 속성 추가
openstack image set --property os_distro=fedora-coreos fedora-coreos-38
```

**3. 네트워크 연결 문제**
```bash
# 보안 그룹 규칙 확인
openstack security group rule list default

# Kubernetes API 포트 허용 (6443)
openstack security group rule create --protocol tcp --dst-port 6443 default
```

### 11.2 디버깅 팁

```bash
# Magnum 서비스 디버그 모드 활성화
sudo sed -i 's/debug = False/debug = True/g' /etc/magnum/magnum.conf
sudo systemctl restart openstack-magnum-api
sudo systemctl restart openstack-magnum-conductor

# 클러스터 노드에 직접 접속
openstack server list | grep k8s-cluster
ssh -i ~/.ssh/openstack-key fedora@<node-floating-ip>
```

## 다음 단계

Magnum 설정이 완료되면 [Octavia 설치 및 구성](04-octavia-setup.md)으로 진행하세요.
