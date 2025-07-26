# OpenStack Zed with Magnum & Octavia on CentOS 9

이 저장소는 VMware 가상머신 환경에서 CentOS 9를 사용하여 OpenStack Zed 버전을 설치하고, Magnum(Container Orchestration)과 Octavia(Load Balancer) 서비스를 구현하는 완전한 가이드를 제공합니다.

## 📋 목차

1. [환경 구성](#환경-구성)
2. [설치 가이드](#설치-가이드)
3. [서비스 구성](#서비스-구성)
4. [문제 해결](#문제-해결)

## 🖥️ 환경 구성

### 시스템 요구사항
- **하이퍼바이저**: VMware Workstation/ESXi
- **운영체제**: CentOS 9 Stream
- **최소 하드웨어**:
  - CPU: 4 cores (가상화 지원)
  - RAM: 16GB 이상 권장
  - 디스크: 100GB 이상
  - 네트워크: 2개 이상의 네트워크 인터페이스

### 네트워크 구성
- **Management Network**: 192.168.1.0/24
- **Provider Network**: 192.168.100.0/24
- **Tunnel Network**: 10.0.0.0/24

## 📚 설치 가이드

### 단계별 설치 문서

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

## 🛠️ 자동화 스크립트

- `scripts/install-prerequisites.sh`: 사전 요구사항 설치
- `scripts/packstack-install.sh`: Packstack 자동 설치
- `scripts/magnum-setup.sh`: Magnum 서비스 구성
- `scripts/octavia-setup.sh`: Octavia 서비스 구성

## ⚙️ 설정 파일

- `configs/packstack-answers.txt`: Packstack 설치 응답 파일
- `configs/magnum.conf`: Magnum 서비스 설정
- `configs/octavia.conf`: Octavia 서비스 설정

## 🔧 문제 해결

일반적인 문제와 해결 방법은 [troubleshooting.md](docs/troubleshooting.md)를 참조하세요.

## 📞 지원

문제가 발생하거나 질문이 있으시면 Issues 탭에서 문의해주세요.

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

---

**주의사항**: 이 가이드는 학습 및 테스트 목적으로 작성되었습니다. 프로덕션 환경에서는 추가적인 보안 설정과 최적화가 필요합니다.
