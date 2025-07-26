# OpenStack Zed with Magnum & Octavia on CentOS 9

이 저장소는 VMware 가상머신 환경에서 CentOS 9를 사용하여 OpenStack Zed 버전을 설치하고, Magnum(Container Orchestration)과 Octavia(Load Balancer) 서비스를 구현하는 완전한 가이드를 제공합니다.

## 📋 목차

1. [환경 구성](#환경-구성)
2. [설치 가이드](#설치-가이드)
3. [서비스 구성](#서비스-구성)
4. [멀티 노드 구성](#멀티-노드-구성)
5. [문제 해결](#문제-해결)

## 🖥️ 환경 구성

### 단일 노드 (All-in-One) 구성
- **서버**: 1대
- **역할**: Controller + Compute + Network + Storage
- **최소 하드웨어**:
  - CPU: 4 cores (가상화 지원)
  - RAM: 16GB 이상 권장
  - 디스크: 100GB 이상
  - 네트워크: 2개 이상의 네트워크 인터페이스

### 멀티 노드 구성 (권장)
- **Controller 노드**: 1대 (192.168.1.10)
  - Keystone, Glance, Nova API, Neutron Server, Horizon 등
  - CPU: 4 cores, RAM: 8GB, 디스크: 50GB
- **Compute 노드**: 1대 이상 (192.168.1.11, 192.168.1.12, ...)
  - Nova Compute, Neutron Agent
  - CPU: 4 cores, RAM: 8GB, 디스크: 50GB

### 네트워크 구성
- **Management Network**: 192.168.1.0/24
- **Provider Network**: 192.168.100.0/24
- **Tunnel Network**: 10.0.0.0/24

## 📚 설치 가이드

### 단일 노드 설치

1. **[환경 설정](docs/01-environment-setup.md)**
   - VMware 가상머신 생성
   - CentOS 9 설치 및 기본 설정
   - 네트워크 구성

2. **[Packstack 설치](docs/02-packstack-installation.md)**
   - RDO 저장소 설정
   - Packstack을 이용한 OpenStack Zed 설치
   - 기본 서비스 확인

3. **[Magnum 구성](docs/03-magnum-setup.md)**
   - Magnum 서비스 설치
   - Kubernetes/Docker Swarm 클러스터 템플릿 생성
   - 컨테이너 클러스터 배포

4. **[Octavia 구성](docs/04-octavia-setup.md)**
   - Octavia 서비스 설치
   - Amphora 이미지 생성
   - 로드밸런서 생성 및 테스트

### 멀티 노드 설치

5. **[멀티 노드 구성](docs/05-multi-node-setup.md)**
   - Controller + Compute 노드 분리 구성
   - 고가용성 및 확장성 향상
   - 로드 분산 및 장애 복구

## 🛠️ 자동화 스크립트

### 단일 노드용
- `scripts/install-prerequisites.sh`: 사전 요구사항 설치
- `scripts/packstack-install.sh`: Packstack 자동 설치
- `scripts/magnum-setup.sh`: Magnum 서비스 구성
- `scripts/octavia-setup.sh`: Octavia 서비스 구성

### 멀티 노드용
- `scripts/prepare-compute-node.sh`: Compute 노드 준비 (각 Compute 노드에서 실행)
- `scripts/multinode-setup.sh`: 멀티 노드 자동 설치 (Controller 노드에서 실행)

## ⚙️ 설정 파일

- `configs/packstack-answers-template.txt`: Packstack 설치 응답 파일
- `configs/magnum.conf.template`: Magnum 서비스 설정
- `configs/octavia.conf.template`: Octavia 서비스 설정

## 🚀 빠른 시작

### 단일 노드 설치
```bash
# 1. 저장소 클론
git clone https://github.com/apdnl124/openstack.git
cd openstack

# 2. 사전 요구사항 설치
sudo ./scripts/install-prerequisites.sh
sudo reboot

# 3. OpenStack 설치
sudo ./scripts/packstack-install.sh

# 4. Magnum 설치
sudo ./scripts/magnum-setup.sh

# 5. Octavia 설치
sudo ./scripts/octavia-setup.sh
```

### 멀티 노드 설치
```bash
# 각 Compute 노드에서 실행
sudo ./scripts/prepare-compute-node.sh

# Controller 노드에서 실행
sudo ./scripts/multinode-setup.sh
```

## 🔧 멀티 노드 구성

### 장점
- **성능 향상**: 워크로드가 여러 노드에 분산
- **고가용성**: 단일 장애점 제거
- **확장성**: 필요에 따라 Compute 노드 추가/제거 가능
- **리소스 격리**: Controller와 Compute 기능 분리

### 구성 예시
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Controller     │    │  Compute-1      │    │  Compute-2      │
│  192.168.1.10   │    │  192.168.1.11   │    │  192.168.1.12   │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Keystone      │    │ • Nova Compute  │    │ • Nova Compute  │
│ • Glance        │    │ • Neutron Agent │    │ • Neutron Agent │
│ • Nova API      │    │ • OVS Agent     │    │ • OVS Agent     │
│ • Neutron Server│    │                 │    │                 │
│ • Horizon       │    │                 │    │                 │
│ • Cinder API    │    │                 │    │                 │
│ • Heat          │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📊 성능 비교

| 구성 | 단일 노드 | 멀티 노드 (1+2) |
|------|-----------|------------------|
| 동시 인스턴스 | ~10개 | ~30개 |
| CPU 활용률 | 높음 | 분산됨 |
| 메모리 사용량 | 집중됨 | 분산됨 |
| 장애 복구 | 불가능 | 가능 |
| 확장성 | 제한적 | 우수 |

## 🔧 문제 해결

일반적인 문제와 해결 방법은 [troubleshooting.md](docs/troubleshooting.md)를 참조하세요.

### 멀티 노드 관련 문제
- SSH 키 인증 실패
- 노드 간 네트워크 연결 문제
- 서비스 분산 설정 오류
- 로드 밸런싱 문제

## 📞 지원

문제가 발생하거나 질문이 있으시면 Issues 탭에서 문의해주세요.

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

---

**주의사항**: 이 가이드는 학습 및 테스트 목적으로 작성되었습니다. 프로덕션 환경에서는 추가적인 보안 설정과 최적화가 필요합니다.

## 🎯 다음 단계

1. **모니터링 시스템 구축**: Prometheus + Grafana
2. **백업 및 복구 시스템**: 자동화된 백업 스크립트
3. **CI/CD 파이프라인**: GitLab CI 또는 Jenkins 연동
4. **보안 강화**: SSL/TLS 인증서, 방화벽 규칙 최적화
