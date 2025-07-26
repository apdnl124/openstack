# 5. 멀티 노드 OpenStack 구성

이 가이드는 Controller 노드와 별도의 Compute 노드를 구성하는 방법을 설명합니다.

## 노드 구성

### 권장 구성
- **Controller 노드**: 192.168.1.10 (Keystone, Glance, Nova API, Neutron Server, Horizon 등)
- **Compute 노드 1**: 192.168.1.11 (Nova Compute, Neutron Agent)
- **Compute 노드 2**: 192.168.1.12 (Nova Compute, Neutron Agent) - 선택사항

## Controller 노드 설정

### 1.1 기본 환경 설정
Controller 노드에서는 기존 가이드와 동일하게 설정하되, Packstack 응답 파일을 수정합니다.

```bash
# Controller 노드에서 실행
sudo ./scripts/install-prerequisites.sh
```

### 1.2 Packstack 응답 파일 수정

```bash
# 멀티 노드용 응답 파일 생성
cp configs/packstack-answers-template.txt packstack-answers-multinode.txt

# 주요 설정 수정
vim packstack-answers-multinode.txt
```

**주요 수정 사항:**
```ini
# 컨트롤러 노드
CONFIG_CONTROLLER_HOST=192.168.1.10

# 컴퓨트 노드들 (쉼표로 구분)
CONFIG_COMPUTE_HOSTS=192.168.1.11,192.168.1.12

# 네트워크 노드 (Controller와 동일하게 설정)
CONFIG_NETWORK_HOSTS=192.168.1.10

# 스토리지 노드 (Controller와 동일하게 설정)
CONFIG_STORAGE_HOST=192.168.1.10

# SSH 키 기반 인증 활성화
CONFIG_USE_EPEL=y
CONFIG_SSH_KEY_FILE=/root/.ssh/id_rsa.pub
```

### 1.3 SSH 키 설정

```bash
# Controller 노드에서 SSH 키 생성
ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ""

# Compute 노드들에 SSH 키 복사
ssh-copy-id root@192.168.1.11
ssh-copy-id root@192.168.1.12

# 연결 테스트
ssh root@192.168.1.11 "hostname"
ssh root@192.168.1.12 "hostname"
```

## Compute 노드 설정

각 Compute 노드에서 다음 작업을 수행합니다.

### 2.1 기본 환경 설정

```bash
# 각 Compute 노드에서 실행
sudo dnf update -y

# 필수 패키지 설치
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y vim wget curl git net-tools bind-utils chrony

# SELinux 설정
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# 방화벽 비활성화
sudo systemctl stop firewalld
sudo systemctl disable firewalld

# 시간 동기화
sudo systemctl enable chronyd
sudo systemctl start chronyd
```

### 2.2 호스트명 및 네트워크 설정

**Compute 노드 1 (192.168.1.11):**
```bash
# 호스트명 설정
sudo hostnamectl set-hostname compute-node-1

# /etc/hosts 파일 설정
sudo tee -a /etc/hosts << EOF
192.168.1.10    controller openstack-controller
192.168.1.11    compute-node-1
192.168.1.12    compute-node-2
192.168.100.10  openstack-controller-provider
EOF
```

**Compute 노드 2 (192.168.1.12):**
```bash
# 호스트명 설정
sudo hostnamectl set-hostname compute-node-2

# /etc/hosts 파일 설정
sudo tee -a /etc/hosts << EOF
192.168.1.10    controller openstack-controller
192.168.1.11    compute-node-1
192.168.1.12    compute-node-2
192.168.100.10  openstack-controller-provider
EOF
```

### 2.3 RDO 저장소 설치

```bash
# 각 Compute 노드에서 실행
sudo dnf install -y centos-release-openstack-zed epel-release
sudo dnf update -y
```

### 2.4 하드웨어 가상화 확인

```bash
# CPU 가상화 기능 확인
egrep -c '(vmx|svm)' /proc/cpuinfo
# 결과가 0보다 크면 가상화 지원

# 중첩 가상화 활성화 (VMware에서)
echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel
```

## 멀티 노드 설치 실행

### 3.1 Controller 노드에서 설치 실행

```bash
# Controller 노드에서 Packstack 실행
sudo packstack --answer-file=packstack-answers-multinode.txt

# 설치 진행 상황 모니터링
tail -f /var/tmp/packstack/latest/openstack-setup.log
```

### 3.2 설치 후 확인

```bash
# OpenStack 환경 변수 로드
source /root/keystonerc_admin

# 컴퓨트 서비스 확인
openstack compute service list

# 하이퍼바이저 목록 확인
openstack hypervisor list

# 네트워크 에이전트 확인
openstack network agent list
```

**예상 출력:**
```
+----+----------------+---------------+----------+---------+-------+
| ID | Binary         | Host          | Zone     | Status  | State |
+----+----------------+---------------+----------+---------+-------+
|  1 | nova-compute   | compute-node-1| nova     | enabled | up    |
|  2 | nova-compute   | compute-node-2| nova     | enabled | up    |
|  3 | nova-conductor | controller    | internal | enabled | up    |
|  4 | nova-scheduler | controller    | internal | enabled | up    |
+----+----------------+---------------+----------+---------+-------+
```

## 로드 밸런싱 및 고가용성

### 4.1 인스턴스 배포 테스트

```bash
# 여러 인스턴스 생성하여 노드 분산 확인
for i in {1..4}; do
  openstack server create --flavor m1.small \
    --image cirros \
    --key-name openstack-key \
    --security-group default \
    --network internal \
    test-instance-$i
done

# 인스턴스가 어느 노드에 배포되었는지 확인
openstack server list --long
```

### 4.2 Compute 노드 장애 테스트

```bash
# Compute 노드 1 중지
ssh root@192.168.1.11 "sudo systemctl stop openstack-nova-compute"

# 서비스 상태 확인
openstack compute service list

# 새 인스턴스가 정상 노드에만 생성되는지 확인
openstack server create --flavor m1.small \
  --image cirros \
  --key-name openstack-key \
  --security-group default \
  --network internal \
  failover-test
```

## Magnum 멀티 노드 설정

### 5.1 모든 노드에 Docker 설치

```bash
# Controller 및 모든 Compute 노드에서 실행
sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl start docker
```

### 5.2 Magnum 설정 수정

```bash
# Controller 노드에서 Magnum 설정 파일 수정
sudo vim /etc/magnum/magnum.conf

# [DEFAULT] 섹션에 추가
[DEFAULT]
host = controller

# 클러스터 노드가 모든 Compute 노드에 분산되도록 설정
[cluster]
cluster_heat_template = /usr/lib/python3.9/site-packages/magnum/drivers/heat/template_def.py
```

## Octavia 멀티 노드 설정

### 5.1 Amphora 인스턴스 분산

```bash
# Octavia 설정에서 Amphora 인스턴스가 여러 노드에 분산되도록 설정
sudo vim /etc/octavia/octavia.conf

[controller_worker]
# 여러 가용 영역 설정
amp_availability_zone = nova

# 안티 어피니티 그룹 사용
amp_anti_affinity_policy = anti-affinity
```

## 모니터링 및 관리

### 6.1 노드 상태 모니터링

```bash
# 모든 노드의 리소스 사용량 확인
openstack hypervisor stats show

# 개별 노드 상태 확인
openstack hypervisor show compute-node-1
openstack hypervisor show compute-node-2
```

### 6.2 로그 중앙화

```bash
# Controller 노드에서 rsyslog 설정
sudo vim /etc/rsyslog.conf

# 다음 라인 추가
$ModLoad imudp
$UDPServerRun 514
$UDPServerAddress 192.168.1.10

# Compute 노드에서 로그 전송 설정
sudo vim /etc/rsyslog.conf
# 다음 라인 추가
*.* @192.168.1.10:514

# 서비스 재시작
sudo systemctl restart rsyslog
```

## 확장 및 축소

### 7.1 Compute 노드 추가

```bash
# 새 노드 준비 후 Packstack 응답 파일 수정
CONFIG_COMPUTE_HOSTS=192.168.1.11,192.168.1.12,192.168.1.13

# 증분 설치 실행
sudo packstack --answer-file=packstack-answers-multinode.txt
```

### 7.2 Compute 노드 제거

```bash
# 노드의 모든 인스턴스 마이그레이션
openstack server list --host compute-node-2
openstack server migrate <instance-id> --host compute-node-1

# 노드 비활성화
openstack compute service set compute-node-2 nova-compute --disable

# 노드 삭제
openstack compute service delete <service-id>
openstack hypervisor delete <hypervisor-id>
```

## 백업 및 복구

### 8.1 Controller 노드 백업

```bash
# 데이터베이스 백업
mysqldump -u root -p --all-databases > /backup/openstack-db-$(date +%Y%m%d).sql

# 설정 파일 백업
tar -czf /backup/openstack-configs-$(date +%Y%m%d).tar.gz /etc/keystone /etc/nova /etc/neutron /etc/glance /etc/cinder
```

### 8.2 Compute 노드 백업

```bash
# 각 Compute 노드에서 설정 백업
tar -czf /backup/compute-configs-$(date +%Y%m%d).tar.gz /etc/nova /etc/neutron
```

이제 멀티 노드 OpenStack 환경이 구성되어 더 나은 성능과 가용성을 제공할 수 있습니다!
