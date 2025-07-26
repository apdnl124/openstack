# 문제 해결 가이드

이 문서는 OpenStack Zed 설치 및 Magnum, Octavia 구성 중 발생할 수 있는 일반적인 문제들과 해결 방법을 제공합니다.

## 일반적인 문제들

### 1. Packstack 설치 관련 문제

#### 1.1 메모리 부족 오류
**증상**: 설치 중 "Out of memory" 오류 발생

**해결 방법**:
```bash
# 추가 스왑 공간 생성
sudo fallocate -l 2G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2

# 영구 설정
echo '/swapfile2 none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 1.2 네트워크 브리지 생성 실패
**증상**: br-ex 브리지 생성 실패

**해결 방법**:
```bash
# 수동으로 브리지 생성
sudo ovs-vsctl add-br br-ex
sudo ovs-vsctl add-port br-ex enp0s8

# 브리지 상태 확인
sudo ovs-vsctl show
```

#### 1.3 Packstack 설치 중단
**증상**: 설치가 중간에 멈춤

**해결 방법**:
```bash
# 설치 로그 확인
tail -f /var/tmp/packstack/latest/openstack-setup.log

# 실패한 서비스 확인
sudo systemctl --failed

# 특정 서비스 재시작
sudo systemctl restart openstack-nova-compute
```

### 2. 네트워크 관련 문제

#### 2.1 인스턴스가 DHCP IP를 받지 못함
**증상**: 인스턴스가 부팅되지만 IP 주소를 받지 못함

**해결 방법**:
```bash
# DHCP 에이전트 상태 확인
openstack network agent list --agent-type dhcp

# DHCP 에이전트 재시작
sudo systemctl restart neutron-dhcp-agent

# 네트워크 네임스페이스 확인
sudo ip netns list
sudo ip netns exec qdhcp-<network-id> ip addr
```

#### 2.2 Floating IP 연결 실패
**증상**: Floating IP가 할당되지만 접근 불가

**해결 방법**:
```bash
# 라우터 상태 확인
openstack router show router1

# L3 에이전트 상태 확인
openstack network agent list --agent-type l3

# 라우터 네임스페이스 확인
sudo ip netns exec qrouter-<router-id> ip route
```

#### 2.3 보안 그룹 규칙 문제
**증상**: 인스턴스에 접근할 수 없음

**해결 방법**:
```bash
# 보안 그룹 규칙 확인
openstack security group rule list default

# 필요한 규칙 추가
openstack security group rule create --protocol tcp --dst-port 22 default
openstack security group rule create --protocol icmp default
```

### 3. Magnum 관련 문제

#### 3.1 클러스터 생성 실패
**증상**: 클러스터 생성이 CREATE_FAILED 상태

**해결 방법**:
```bash
# Heat 스택 이벤트 확인
openstack stack event list <cluster-stack-name>

# 실패한 리소스 확인
openstack stack resource list <cluster-stack-name> --filter status=CREATE_FAILED

# Heat 로그 확인
sudo tail -f /var/log/heat/heat-engine.log
```

#### 3.2 이미지 관련 문제
**증상**: "Image not found" 또는 이미지 부팅 실패

**해결 방법**:
```bash
# 이미지 속성 확인
openstack image show fedora-coreos-38

# 필요한 속성 추가
openstack image set --property os_distro=fedora-coreos fedora-coreos-38
openstack image set --property hw_rng_model=virtio fedora-coreos-38
```

#### 3.3 Kubernetes API 접근 불가
**증상**: kubectl 명령어 실행 시 연결 실패

**해결 방법**:
```bash
# 클러스터 설정 다시 다운로드
openstack coe cluster config <cluster-name> --dir ~/.kube --force

# 보안 그룹에 Kubernetes API 포트 추가
openstack security group rule create --protocol tcp --dst-port 6443 default

# 클러스터 노드 상태 확인
openstack server list | grep <cluster-name>
```

### 4. Octavia 관련 문제

#### 4.1 Amphora 인스턴스 생성 실패
**증상**: 로드밸런서 생성 시 Amphora 인스턴스가 생성되지 않음

**해결 방법**:
```bash
# Nova 로그 확인
sudo tail -f /var/log/nova/nova-compute.log

# Amphora 이미지 확인
openstack image list | grep amphora

# Management 네트워크 확인
openstack network show lb-mgmt-net
openstack subnet show lb-mgmt-subnet
```

#### 4.2 헬스 체크 실패
**증상**: 로드밸런서 멤버가 DOWN 상태

**해결 방법**:
```bash
# 멤버 서버 상태 확인
openstack loadbalancer member show <pool-id> <member-id>

# 백엔드 서버 접근성 확인
ping <member-ip>
telnet <member-ip> <member-port>

# 보안 그룹 규칙 확인
openstack security group rule list default
```

#### 4.3 SSL 인증서 문제
**증상**: HTTPS 리스너 생성 실패

**해결 방법**:
```bash
# Barbican 서비스 상태 확인
openstack secret list

# 인증서 내용 확인
openstack secret get --payload <secret-href>

# 새 인증서 생성 및 등록
openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes
openstack secret store --name='server-crt' --payload-content-type='text/plain' --payload="$(cat server.crt)"
```

### 5. 서비스 관련 문제

#### 5.1 서비스 시작 실패
**증상**: systemctl start 명령어 실행 시 실패

**해결 방법**:
```bash
# 서비스 상태 자세히 확인
sudo systemctl status <service-name> -l

# 서비스 로그 확인
sudo journalctl -u <service-name> -f

# 설정 파일 문법 확인
sudo <service-binary> --config-file /etc/<service>/<service>.conf --dry-run
```

#### 5.2 데이터베이스 연결 실패
**증상**: "Database connection failed" 오류

**해결 방법**:
```bash
# MariaDB 서비스 상태 확인
sudo systemctl status mariadb

# 데이터베이스 연결 테스트
mysql -u <username> -p<password> -h <host> <database>

# 데이터베이스 권한 확인
mysql -u root -p
SHOW GRANTS FOR '<username>'@'<host>';
```

### 6. 성능 관련 문제

#### 6.1 인스턴스 생성 속도 느림
**증상**: 인스턴스 생성에 오랜 시간 소요

**해결 방법**:
```bash
# 컴퓨트 노드 리소스 확인
openstack hypervisor stats show

# 이미지 캐싱 활성화
sudo vim /etc/nova/nova.conf
# [DEFAULT]
# cache_images = True

sudo systemctl restart openstack-nova-compute
```

#### 6.2 네트워크 성능 저하
**증상**: 인스턴스 간 네트워크 속도 느림

**해결 방법**:
```bash
# MTU 설정 확인
openstack network show <network-name>

# OVS 설정 최적화
sudo ovs-vsctl set Open_vSwitch . other_config:max-idle=10000
sudo ovs-vsctl set Open_vSwitch . other_config:flow-eviction-threshold=4000
```

## 로그 파일 위치

### OpenStack 서비스 로그
```bash
# Nova
/var/log/nova/nova-api.log
/var/log/nova/nova-compute.log
/var/log/nova/nova-conductor.log

# Neutron
/var/log/neutron/server.log
/var/log/neutron/openvswitch-agent.log
/var/log/neutron/dhcp-agent.log
/var/log/neutron/l3-agent.log

# Keystone
/var/log/keystone/keystone.log

# Glance
/var/log/glance/api.log
/var/log/glance/registry.log

# Cinder
/var/log/cinder/api.log
/var/log/cinder/volume.log

# Heat
/var/log/heat/heat-api.log
/var/log/heat/heat-engine.log

# Horizon
/var/log/httpd/error_log
/var/log/httpd/access_log
```

### Magnum 로그
```bash
/var/log/magnum/magnum-api.log
/var/log/magnum/magnum-conductor.log
```

### Octavia 로그
```bash
/var/log/octavia/octavia-api.log
/var/log/octavia/octavia-worker.log
/var/log/octavia/octavia-health-manager.log
/var/log/octavia/octavia-housekeeping.log
```

## 유용한 디버깅 명령어

### 일반적인 상태 확인
```bash
# 모든 OpenStack 서비스 상태
sudo systemctl list-units --type=service | grep openstack

# OpenStack 서비스 목록
openstack service list

# 컴퓨트 서비스 상태
openstack compute service list

# 네트워크 에이전트 상태
openstack network agent list

# 하이퍼바이저 상태
openstack hypervisor list
```

### 네트워크 디버깅
```bash
# 네트워크 네임스페이스 목록
sudo ip netns list

# 특정 네임스페이스에서 명령 실행
sudo ip netns exec <namespace> <command>

# OVS 브리지 상태
sudo ovs-vsctl show

# OVS 플로우 규칙
sudo ovs-ofctl dump-flows br-int
```

### 리소스 사용량 확인
```bash
# 시스템 리소스
htop
free -h
df -h

# OpenStack 리소스
openstack usage show
openstack quota show
openstack limits show --absolute
```

## 복구 절차

### 1. 서비스 전체 재시작
```bash
# OpenStack 서비스 재시작 순서
sudo systemctl restart mariadb
sudo systemctl restart rabbitmq-server
sudo systemctl restart memcached

sudo systemctl restart openstack-keystone
sudo systemctl restart openstack-glance-api
sudo systemctl restart openstack-nova-api
sudo systemctl restart openstack-nova-compute
sudo systemctl restart neutron-server
sudo systemctl restart neutron-openvswitch-agent
sudo systemctl restart openstack-cinder-api
sudo systemctl restart openstack-cinder-volume
```

### 2. 데이터베이스 복구
```bash
# 데이터베이스 백업
mysqldump -u root -p --all-databases > openstack_backup.sql

# 데이터베이스 복구
mysql -u root -p < openstack_backup.sql

# 데이터베이스 동기화
nova-manage db sync
neutron-db-manage upgrade head
cinder-manage db sync
```

### 3. 네트워크 재설정
```bash
# OVS 재시작
sudo systemctl restart openvswitch

# 브리지 재생성
sudo ovs-vsctl del-br br-ex
sudo ovs-vsctl add-br br-ex
sudo ovs-vsctl add-port br-ex enp0s8
```

이 가이드를 참조하여 문제를 해결할 수 있으며, 추가적인 도움이 필요한 경우 OpenStack 공식 문서나 커뮤니티를 참조하시기 바랍니다.
