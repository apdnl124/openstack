# 1. 환경 설정 가이드

## VMware 가상머신 생성

### 1.1 가상머신 사양 설정

```
- 이름: OpenStack-Controller
- 게스트 OS: Linux - Red Hat Enterprise Linux 9 64-bit
- 프로세서: 4 cores
- 메모리: 16GB (최소 8GB)
- 하드디스크: 100GB (Thin Provisioned)
- 네트워크 어댑터: 2개
  - 어댑터 1: NAT 또는 Bridged (Management)
  - 어댑터 2: Host-only 또는 Custom (Provider)
```

### 1.2 가상화 기능 활성화

VMware 설정에서 다음 옵션을 활성화:
```
- Processors & Memory > Virtualization engine
  ☑ Virtualize Intel VT-x/EPT or AMD-V/RVI
  ☑ Virtualize CPU performance counters
```

## CentOS 9 설치

### 2.1 CentOS 9 Stream ISO 다운로드

```bash
# CentOS 9 Stream 다운로드 링크
https://www.centos.org/download/
```

### 2.2 설치 과정

1. **언어 선택**: English (United States)
2. **키보드**: US
3. **시간대**: Asia/Seoul
4. **설치 대상**: 
   - 자동 파티셔닝 사용
   - 또는 수동 파티셔닝:
     ```
     /boot     : 1GB   (xfs)
     /         : 50GB  (xfs)
     /var      : 30GB  (xfs)
     /home     : 15GB  (xfs)
     swap      : 4GB
     ```

5. **네트워크 설정**:
   - enp0s3 (Management): DHCP 활성화
   - enp0s8 (Provider): 수동 설정 (나중에 구성)

6. **소프트웨어 선택**: Server with GUI
7. **사용자 생성**: 
   - root 패스워드 설정
   - 일반 사용자 생성 (sudo 권한 부여)

## 기본 시스템 설정

### 3.1 시스템 업데이트

```bash
# 시스템 패키지 업데이트
sudo dnf update -y

# 재부팅
sudo reboot
```

### 3.2 필수 패키지 설치

```bash
# 개발 도구 및 유틸리티 설치
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y vim wget curl git net-tools bind-utils

# SELinux 설정 확인 (Permissive 모드 권장)
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# 방화벽 비활성화 (테스트 환경)
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

### 3.3 네트워크 설정

#### Management 네트워크 (enp0s3)
```bash
# 현재 IP 확인
ip addr show enp0s3

# 고정 IP 설정 (선택사항)
sudo nmcli con mod enp0s3 ipv4.addresses 192.168.1.10/24
sudo nmcli con mod enp0s3 ipv4.gateway 192.168.1.1
sudo nmcli con mod enp0s3 ipv4.dns 8.8.8.8
sudo nmcli con mod enp0s3 ipv4.method manual
sudo nmcli con up enp0s3
```

#### Provider 네트워크 (enp0s8)
```bash
# Provider 네트워크 설정
sudo nmcli con add type ethernet con-name provider ifname enp0s8
sudo nmcli con mod provider ipv4.addresses 192.168.100.10/24
sudo nmcli con mod provider ipv4.method manual
sudo nmcli con up provider
```

### 3.4 호스트명 설정

```bash
# 호스트명 설정
sudo hostnamectl set-hostname openstack-controller

# /etc/hosts 파일 편집
sudo tee -a /etc/hosts << EOF
192.168.1.10    openstack-controller controller
192.168.100.10  openstack-controller-provider
EOF
```

### 3.5 시간 동기화 설정

```bash
# Chrony 설치 및 설정
sudo dnf install -y chrony
sudo systemctl enable chronyd
sudo systemctl start chronyd

# 시간 동기화 확인
chrony sources -v
```

### 3.6 스왑 설정 확인

```bash
# 스왑 상태 확인
free -h
swapon --show

# 스왑이 없다면 생성
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 영구 설정
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 시스템 검증

### 4.1 하드웨어 가상화 지원 확인

```bash
# CPU 가상화 기능 확인
egrep -c '(vmx|svm)' /proc/cpuinfo
# 결과가 0보다 크면 가상화 지원

# KVM 모듈 로드 확인
lsmod | grep kvm
```

### 4.2 네트워크 연결 테스트

```bash
# 인터넷 연결 확인
ping -c 4 8.8.8.8

# DNS 해석 확인
nslookup google.com

# 네트워크 인터페이스 확인
ip link show
```

### 4.3 디스크 공간 확인

```bash
# 디스크 사용량 확인
df -h

# 사용 가능한 공간이 충분한지 확인 (최소 50GB 여유 공간 필요)
```

## 다음 단계

환경 설정이 완료되면 [Packstack 설치](02-packstack-installation.md)로 진행하세요.

## 문제 해결

### 일반적인 문제들

1. **네트워크 연결 문제**
   ```bash
   # 네트워크 서비스 재시작
   sudo systemctl restart NetworkManager
   
   # 네트워크 설정 확인
   nmcli con show
   ```

2. **가상화 기능 미지원**
   - VMware 설정에서 가상화 엔진 옵션 확인
   - BIOS에서 Intel VT-x 또는 AMD-V 활성화

3. **디스크 공간 부족**
   ```bash
   # 불필요한 패키지 정리
   sudo dnf autoremove -y
   sudo dnf clean all
   ```
