# 2. Packstack을 이용한 OpenStack Zed 설치

## RDO 저장소 설정

### 2.1 RDO 저장소 추가

```bash
# CentOS 9용 RDO Zed 저장소 설치
sudo dnf install -y centos-release-openstack-zed

# EPEL 저장소 설치
sudo dnf install -y epel-release

# 저장소 업데이트
sudo dnf update -y
```

### 2.2 Packstack 설치

```bash
# Packstack 설치
sudo dnf install -y openstack-packstack

# 설치 확인
packstack --version
```

## Packstack 설정 파일 생성

### 3.1 기본 응답 파일 생성

```bash
# 응답 파일 생성
packstack --gen-answer-file=/home/$USER/packstack-answers.txt

# 백업 생성
cp /home/$USER/packstack-answers.txt /home/$USER/packstack-answers.txt.backup
```

### 3.2 응답 파일 수정

주요 설정 항목들을 수정합니다:

```bash
# 응답 파일 편집
vim /home/$USER/packstack-answers.txt
```

**주요 수정 사항:**

```ini
# 일반 설정
CONFIG_DEFAULT_PASSWORD=openstack123
CONFIG_KEYSTONE_ADMIN_PW=admin123

# 컴퓨트 노드 설정 (단일 노드 설치)
CONFIG_COMPUTE_HOSTS=192.168.1.10

# 네트워크 설정
CONFIG_NEUTRON_ML2_TYPE_DRIVERS=vxlan,flat,vlan
CONFIG_NEUTRON_ML2_TENANT_NETWORK_TYPES=vxlan
CONFIG_NEUTRON_ML2_MECHANISM_DRIVERS=openvswitch
CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=extnet:br-ex
CONFIG_NEUTRON_OVS_BRIDGE_IFACES=br-ex:enp0s8

# Horizon 설정
CONFIG_HORIZON_SSL=n

# 서비스 활성화/비활성화
CONFIG_CINDER_INSTALL=y
CONFIG_SWIFT_INSTALL=n
CONFIG_HEAT_INSTALL=y
CONFIG_MAGNUM_INSTALL=n  # 나중에 수동 설치
CONFIG_OCTAVIA_INSTALL=n  # 나중에 수동 설치

# 데모 프로젝트 생성
CONFIG_PROVISION_DEMO=y

# Telemetry 서비스 (선택사항)
CONFIG_CEILOMETER_INSTALL=y
CONFIG_AODH_INSTALL=y
```

## OpenStack 설치 실행

### 4.1 설치 시작

```bash
# Packstack 실행 (약 30-60분 소요)
sudo packstack --answer-file=/home/$USER/packstack-answers.txt

# 설치 로그 모니터링 (다른 터미널에서)
tail -f /var/tmp/packstack/latest/openstack-setup.log
```

### 4.2 설치 중 발생할 수 있는 문제들

**메모리 부족 오류:**
```bash
# 스왑 공간 추가
sudo fallocate -l 2G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
```

**네트워크 설정 오류:**
```bash
# 브리지 인터페이스 수동 생성
sudo ovs-vsctl add-br br-ex
sudo ovs-vsctl add-port br-ex enp0s8
```

## 설치 후 설정

### 5.1 환경 변수 설정

```bash
# OpenStack 클라이언트 환경 변수 로드
source /root/keystonerc_admin

# 사용자 홈 디렉토리에 복사
sudo cp /root/keystonerc_admin /home/$USER/
sudo chown $USER:$USER /home/$USER/keystonerc_admin

# .bashrc에 추가
echo "source /home/$USER/keystonerc_admin" >> ~/.bashrc
source ~/.bashrc
```

### 5.2 기본 서비스 확인

```bash
# OpenStack 서비스 상태 확인
sudo systemctl list-units --type=service | grep openstack

# 주요 서비스 상태 확인
sudo systemctl status openstack-nova-compute
sudo systemctl status neutron-openvswitch-agent
sudo systemctl status openstack-cinder-volume
```

### 5.3 OpenStack 클라이언트 설치

```bash
# OpenStack 클라이언트 설치
sudo dnf install -y python3-openstackclient

# 설치 확인
openstack --version
```

## 기본 네트워크 설정

### 6.1 External 네트워크 생성

```bash
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
```

### 6.2 Internal 네트워크 생성

```bash
# Internal 네트워크 생성
openstack network create internal

# Internal 서브넷 생성
openstack subnet create --network internal \
  --dns-nameserver 8.8.8.8 \
  --gateway 10.0.0.1 \
  --subnet-range 10.0.0.0/24 \
  internal-subnet
```

### 6.3 라우터 생성 및 설정

```bash
# 라우터 생성
openstack router create router1

# External 네트워크를 게이트웨이로 설정
openstack router set --external-gateway external router1

# Internal 서브넷을 라우터에 연결
openstack router add subnet router1 internal-subnet
```

## 보안 그룹 설정

### 7.1 기본 보안 그룹 규칙 추가

```bash
# SSH 접근 허용
openstack security group rule create --protocol tcp --dst-port 22 default

# ICMP 허용
openstack security group rule create --protocol icmp default

# HTTP/HTTPS 허용
openstack security group rule create --protocol tcp --dst-port 80 default
openstack security group rule create --protocol tcp --dst-port 443 default
```

## 키페어 생성

### 8.1 SSH 키페어 생성

```bash
# SSH 키페어 생성
ssh-keygen -t rsa -b 2048 -f ~/.ssh/openstack-key -N ""

# OpenStack에 키페어 등록
openstack keypair create --public-key ~/.ssh/openstack-key.pub openstack-key

# 키페어 확인
openstack keypair list
```

## 테스트 인스턴스 생성

### 9.1 이미지 다운로드

```bash
# CirrOS 테스트 이미지 다운로드
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img

# 이미지 등록
openstack image create "cirros" \
  --file cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

### 9.2 Flavor 생성

```bash
# 작은 크기의 flavor 생성
openstack flavor create --id 1 --vcpus 1 --ram 512 --disk 1 m1.tiny
openstack flavor create --id 2 --vcpus 1 --ram 2048 --disk 20 m1.small
```

### 9.3 테스트 인스턴스 생성

```bash
# 인스턴스 생성
openstack server create --flavor m1.tiny \
  --image cirros \
  --key-name openstack-key \
  --security-group default \
  --network internal \
  test-instance

# 인스턴스 상태 확인
openstack server list
```

### 9.4 Floating IP 할당

```bash
# Floating IP 생성
openstack floating ip create external

# Floating IP 할당
openstack server add floating ip test-instance <FLOATING_IP>

# 연결 테스트
ping <FLOATING_IP>
ssh cirros@<FLOATING_IP>
```

## Horizon 대시보드 접근

### 10.1 웹 인터페이스 접근

```bash
# Horizon 서비스 상태 확인
sudo systemctl status httpd

# 브라우저에서 접근
# URL: http://192.168.1.10/dashboard
# 사용자명: admin
# 패스워드: admin123 (설정한 패스워드)
```

## 설치 검증

### 11.1 서비스 상태 확인

```bash
# 모든 OpenStack 서비스 확인
openstack service list

# 컴퓨트 서비스 확인
openstack compute service list

# 네트워크 에이전트 확인
openstack network agent list

# 볼륨 서비스 확인
openstack volume service list
```

### 11.2 로그 확인

```bash
# 주요 로그 파일 위치
tail -f /var/log/nova/nova-compute.log
tail -f /var/log/neutron/openvswitch-agent.log
tail -f /var/log/keystone/keystone.log
```

## 다음 단계

OpenStack 기본 설치가 완료되면 다음 단계로 진행하세요:
- [Magnum 설치 및 구성](03-magnum-setup.md)
- [Octavia 설치 및 구성](04-octavia-setup.md)

## 문제 해결

### 일반적인 문제들

1. **설치 실패 시 재시도**
   ```bash
   # 설치 상태 초기화
   sudo packstack --answer-file=/home/$USER/packstack-answers.txt --os-debug
   ```

2. **서비스 시작 실패**
   ```bash
   # 서비스 재시작
   sudo systemctl restart openstack-nova-compute
   sudo systemctl restart neutron-openvswitch-agent
   ```

3. **네트워크 연결 문제**
   ```bash
   # 브리지 상태 확인
   sudo ovs-vsctl show
   
   # 네트워크 네임스페이스 확인
   sudo ip netns list
   ```
