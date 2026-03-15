# devport Infrastructure as Code

DevPort 프로젝트의 Terraform 인프라 구성입니다.

## 아키텍처 개요

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                         VPC                             │
                                    │                                                         │
                                    │  Public Subnet              Private Subnet              │
┌──────────┐    ┌────────────┐      │  ┌───────────────┐         ┌─────────────────────────┐  │
│ Route 53 │───▶│ CloudFront │─────▶│  │  S3 (frontend)│         │      EC2 Instance       │  │
└──────────┘    └────────────┘      │  └───────────────┘         │   ┌─────────────────┐   │  │
      │                             │                            │   │  Docker Compose │   │  │
      │                             │  ┌───────────────┐         │   │  ┌─────┐ ┌────┐ │   │  │
      │         ┌───────┐           │  │  NAT Instance │◀────────│   │  │ App │ │ DB │ │   │  │
      └────────▶│  NLB  │──────────▶│  │  (t4g.nano)   │         │   │  └─────┘ └────┘ │   │  │
                └───────┘           │  └───────────────┘         │   └─────────────────┘   │  │
                (SSL termination)   │                            │                         │  │
                                    │                            │  ┌─────────────────────┐│  │
                                    │                            │  │   Lambda Crawler    ││  │
                                    │                            │  │   (VPC-attached)    ││  │
                                    │                            │  └─────────────────────┘│  │
                                    │                            └─────────────────────────┘  │
                                    └─────────────────────────────────────────────────────────┘

┌───────────────────┐    OIDC     ┌──────────┐    S3 Sync + CDN Invalidation
│  GitHub Actions   │────────────▶│ IAM Role │──────────────────────────────▶ S3 / CloudFront
│  (devport-web)    │  (keyless)  └──────────┘
└───────────────────┘

┌───────────────────┐    SSM      ┌──────────────────────────────────────────┐
│  GitHub Actions   │────────────▶│  EC2  (Blue-Green Deploy)                │
│  (devport-api)    │  RunShell   │                                          │
└───────────────────┘   Script    │  Nginx ──▶ Blue (상시 활성)                │
                                  │            Green (배포 중 임시 기동)         │
                                  └──────────────────────────────────────────┘
```

## 구성 요소

| 구성 요소                     | 목적                                              |
| ----------------------------- | ------------------------------------------------- |
| **Route 53**            | DNS 관리                                          |
| **CloudFront**          | CDN + 프론트엔드 HTTPS                            |
| **S3**                  | 정적 프론트엔드 호스팅                            |
| **NLB**                 | API 로드 밸런서 + SSL 터미네이션                  |
| **NAT Instance**        | 프라이빗 서브넷의 아웃바운드 인터넷               |
| **EC2**                 | Docker Compose (앱 + PostgreSQL), 프라이빗 서브넷 |
| **Lambda**              | VPC 연결 크롤러, DB 직접 접근                     |
| **EventBridge**         | 크롤러 크론 스케줄러                              |
| **GitHub Actions OIDC** | CI/CD 인증 (devport-web → S3/CloudFront 배포)    |
| **Nginx**               | 리버스 프록시, Blue-Green 트래픽 전환             |
| **Redis**               | 캐시 및 세션 저장소                               |

---

## API 배포 — Blue-Green (무중단)

`devport-kr/devport-api`의 `main` 브랜치에에서 trigger 후 Blue-Green 배포를 수행

### 컨테이너 구성

| 컨테이너                    | 역할                              | 실행 상태 |
| --------------------------- | --------------------------------- | --------- |
| `devport-nginx`           | 리버스 프록시, upstream 전환 담당 | 상시      |
| `devport-api-blue`        | 운영 슬롯 (항상 최신 이미지)      | 상시      |
| `devport-api-green`       | 배포 슬롯 (배포 중에만 임시 기동) | 배포 시   |
| `devport-postgres-native` | PostgreSQL (pgvector)             | 상시      |
| `devport-redis-native`    | Redis                             | 상시      |

- Green은 `profiles: ["green"]`으로 선언되어 `docker compose up`으로는 시작되지 않음
- 배포 스크립트만 Green을 `--profile green`으로 기동/중지

### 배포 흐름

```
  GitHub Actions (main push)
        │
        ▼
  AWS SSM RunShellScript ──▶ EC2
        │
        ▼
  ┌─────────────────────────────────────────────────────┐
  │  1. GHCR 로그인                                      │
  │  2. Green 이미지 pull & 컨테이너 시작                 │
  │  3. Green 헬스체크 (최대 30초)                        │
  │     └─ 실패 시: Green 제거, Blue 유지, 배포 중단      │
  │  4. Nginx upstream → Green 전환 (nginx -s reload)    │
  │     └─ 이 시점부터 트래픽은 Green으로                  │
  │  5. Blue 중지 → 새 이미지 pull → Blue 재시작          │
  │  6. Blue 헬스체크 (최대 30초)                         │
  │     └─ 실패 시: Green이 계속 서빙                     │
  │  7. Nginx upstream → Blue 전환 (nginx -s reload)     │
  │  8. Green 중지 & 제거                                 │
  │  9. 완료 — Blue가 최신 이미지로 서빙                   │
  └─────────────────────────────────────────────────────┘
```

### 핵심 포인트

- **무중단 배포**: Nginx의 `upstream.conf`를 덮어쓰고 `nginx -s reload`로 전환하므로 커넥션이 끊기지 않음
- **자동 롤백**: Green 헬스체크 실패 시 Blue가 그대로 유지되어 서비스에 영향 없음
- **최종 상태**: 배포 완료 후 항상 Blue가 활성, Green은 제거됨
- **이미지**: `ghcr.io/devport-kr/devport-api:latest-native-arm64` (GraalVM Native, ARM64)
- **헬스체크**: `/workspace/health-check` (Spring Boot Actuator liveness)

### Nginx upstream 전환 원리

배포 스크립트가 `/opt/devport/nginx/upstream.conf`를 직접 덮어씁니다:

```nginx
# Blue 활성 시 (기본 상태)
upstream devport_api {
    server devport-api-blue:8080;
    keepalive 32;
}

# Green 활성 시 (배포 중 임시)
upstream devport_api {
    server devport-api-green:8080;
    keepalive 32;
}
```

`docker exec devport-nginx nginx -s reload`로 무중단 전환합니다.

### 트리거

- **자동**: `devport-kr/devport-api` 리포의 `main` 브랜치 push
- **수동**: GitHub Actions에서 `workflow_dispatch`로 실행 가능

---

## Terraform Apply 전 체크리스트

`terraform apply` 실행 **전에** 아래 단계를 완료하세요:

### 1. 필수 도구 설치

- [ ] AWS CLI 설치 및 설정 (`aws configure`)
- [ ] Terraform >= 1.5.0 설치 (`terraform --version`)
- [ ] AWS 권한: VPC, EC2, S3, CloudFront, Lambda, Route 53, ACM, NLB, IAM, Secrets Manager

### 2. Route 53 설정 (택 1)

#### 옵션 A: AWS 콘솔에서 수동으로 Hosted Zone 생성

1. **AWS Console → Route 53 → Hosted zones** 이동
2. **"Create hosted zone"** 클릭
3. 도메인 이름 입력 (예: `devport.kr`)
4. **Public hosted zone** 선택
5. **"Create hosted zone"** 클릭
6. **Zone ID** 복사 (예: `Z1234567890ABC`)
7. 4개의 **NS 레코드** (네임서버) 확인

**도메인 등록기관에서 네임서버 변경:**

- 도메인 등록기관에 로그인 (가비아, GoDaddy, Namecheap 등)
- DNS/네임서버 설정 찾기
- 기본 네임서버를 AWS 네임서버 4개로 교체:
  ```
  ns-XXX.awsdns-XX.com
  ns-XXX.awsdns-XX.net
  ns-XXX.awsdns-XX.co.uk
  ns-XXX.awsdns-XX.org
  ```
- 저장 후 전파 대기 (15분 - 48시간)

**DNS 전파 확인:**

```bash
dig NS yourdomain.com
# AWS 네임서버가 반환되어야 합니다
```

`terraform.tfvars`에 설정:

```hcl
route53_zone_id     = "Z1234567890ABC"  # Zone ID
create_route53_zone = false
```

#### 옵션 B: Terraform으로 Zone 자동 생성

`terraform.tfvars`에 설정:

```hcl
create_route53_zone = true
# route53_zone_id 불필요
```

`terraform apply` 후 출력된 네임서버로 등록기관에서 업데이트:

```bash
terraform output route53_nameservers
```

### 3. 변수 설정

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`를 편집:

| 변수                   | 필수   | 설명                   | 예시                 |
| ---------------------- | ------ | ---------------------- | -------------------- |
| `domain_name`        | 예     | 도메인                 | `devport.kr`       |
| `route53_zone_id`    | 예*    | 기존 Zone ID           | `Z1234567890ABC`   |
| `ssh_allowed_cidr`   | 예     | SSH 허용 IP            | `203.0.113.50/32`  |
| `db_password`        | 예     | PostgreSQL 비밀번호    | 강력한 비밀번호 사용 |
| `alarm_email`        | 아니오 | CloudWatch 알림 이메일 | `you@example.com`  |
| `psycopg2_layer_arn` | 아니오 | Lambda DB 접속 레이어  | 아래 참고            |

> *`create_route53_zone = true`일 경우 `route53_zone_id` 불필요

> **psycopg2 레이어**: Lambda 크롤러가 PostgreSQL에 접속하려면 필요합니다. 직접 생성하거나 리전에 맞는 공개 레이어 ARN을 사용하세요.

### 4. (선택) 원격 State 설정

팀 환경이나 프로덕션 용도:

```bash
cd scripts
./setup-remote-state.sh
```

이후 `main.tf`에서 backend 설정의 주석을 해제하세요.

### 5. 초기화 및 검토

```bash
terraform init
terraform plan
```

플랜 출력을 꼼꼼히 검토한 후 진행하세요.

---

## Terraform Apply

```bash
terraform apply
```

프롬프트에서 `yes` 입력. 약 10-15분 소요됩니다.

---

## Terraform Apply 후 체크리스트

`terraform apply` 성공 **후** 아래 단계를 완료하세요:

### 1. 도메인 네임서버 업데이트 (새 Route 53 Zone 생성 시)

- [ ] Terraform 출력에서 네임서버 확인: `terraform output route53_nameservers`
- [ ] 도메인 등록기관에 로그인 (가비아, GoDaddy, Namecheap 등)
- [ ] AWS 네임서버 4개로 업데이트
- [ ] DNS 전파 대기 (보통 15분 - 48시간)

### 2. ACM 인증서 확인

- [ ] DNS 검증까지 5-30분 대기
- [ ] 상태 확인: AWS Console → ACM → Certificates → 상태가 **"Issued"**여야 함
- [ ] "Pending validation"에서 멈춘 경우 Route 53에 CNAME 레코드가 있는지 확인

### 3. SNS 이메일 구독 확인 (`alarm_email` 설정 시)

- [ ] 이메일 수신함에서 "AWS Notification - Subscription Confirmation" 확인
- [ ] **"Confirm subscription"** 링크 클릭

### 4. EC2 애플리케이션 설정

```bash
# Terraform 출력에서 인스턴스 ID 확인
terraform output ec2_instance_id

# SSM으로 접속 (EC2는 프라이빗 서브넷 — 직접 SSH 불가)
aws ssm start-session --target <instance-id>

# EC2 인스턴스에서:
cd /opt/devport
sudo cp .env.template .env
sudo vim .env  # POSTGRES_PASSWORD 설정 (tfvars의 db_password와 동일)

# 서비스 시작
sudo docker-compose up -d

# 컨테이너 동작 확인
sudo docker-compose ps
```

### 5. 프론트엔드 배포

```bash
cd scripts
./deploy-frontend.sh prod /path/to/your/frontend/build
```

### 6. Lambda 크롤러 테스트

```bash
# 수동 실행
aws lambda invoke --function-name devport-prod-crawler response.json
cat response.json

# 에러 확인
aws logs tail /aws/lambda/devport-prod-crawler --follow
```

### 7. 최종 확인

- [ ] 프론트엔드 로드: `https://yourdomain.com`
- [ ] API 응답: `https://api.yourdomain.com/health`
- [ ] WWW 리다이렉트: `https://www.yourdomain.com`
- [ ] EC2에서 DB 접근: `sudo docker-compose exec db psql -U devport -d devport_db`
- [ ] 크롤러 DB 기록 성공

---

## 주요 명령어

| 작업                | 명령어                                                                     |
| ------------------- | -------------------------------------------------------------------------- |
| EC2 접속            | `aws ssm start-session --target <instance-id>`                           |
| 앱 로그 확인        | `sudo docker-compose logs -f app`                                        |
| DB 로그 확인        | `sudo docker-compose logs -f db`                                         |
| 서비스 재시작       | `sudo docker-compose restart`                                            |
| 수동 DB 백업        | `sudo /opt/scripts/backup.sh`                                            |
| 크롤러 실행         | `aws lambda invoke --function-name devport-prod-crawler out.json`        |
| CDN 캐시 무효화     | `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"` |
| Terraform 출력 확인 | `terraform output`                                                       |

## 프로젝트 구조

```
devport-iac/
├── modules/
│   ├── networking/        # VPC, 서브넷, NAT 인스턴스, 보안 그룹
│   ├── ec2/               # EC2 인스턴스, IAM, CloudWatch
│   ├── s3-cloudfront/     # S3 버킷, CloudFront 배포
│   ├── nlb/               # Network Load Balancer
│   ├── lambda-crawler/    # Lambda 함수, EventBridge
│   └── acm/               # SSL 인증서
├── environments/
│   ├── dev/               # 개발 환경
│   └── prod/              # 운영 환경
├── scripts/
│   ├── deploy-frontend.sh     # 프론트엔드 배포
│   ├── invoke-crawler.sh      # 크롤러 수동 실행
│   ├── setup-ec2-nginx.sh     # EC2 Nginx 설정
│   └── setup-remote-state.sh  # 원격 State 설정
├── docs/                  # 아키텍처 문서 및 가이드
├── docker-compose.yml     # EC2용 Docker Compose (Blue-Green + DB + Redis)
├── github-actions.tf      # GitHub Actions OIDC (키 없는 CI/CD)
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
└── versions.tf
```

## 모듈 문서

### Networking 모듈

VPC, 퍼블릭/프라이빗 서브넷, NAT Instance를 생성합니다.

| 리소스         | 설명                                                                |
| -------------- | ------------------------------------------------------------------- |
| Public Subnet  | NLB, NAT Instance                                                   |
| Private Subnet | EC2, Lambda                                                         |
| NAT Instance   | 아웃바운드 트래픽용 t4g.nano (~$3/월, NAT Gateway $32/월 대비 절약) |

| 출력                         | 설명               |
| ---------------------------- | ------------------ |
| `vpc_id`                   | VPC ID             |
| `public_subnet_id`         | 퍼블릭 서브넷 ID   |
| `private_subnet_id`        | 프라이빗 서브넷 ID |
| `ec2_security_group_id`    | EC2 보안 그룹      |
| `lambda_security_group_id` | Lambda 보안 그룹   |

### EC2 모듈

프라이빗 서브넷에 EC2 인스턴스를 프로비저닝합니다:

- Amazon Linux 2023 (ARM/Graviton)
- Docker + Docker Compose 사전 설치
- CloudWatch, S3용 IAM 역할
- CloudWatch 알람

| 출력                       | 설명                       |
| -------------------------- | -------------------------- |
| `instance_id`            | EC2 인스턴스 ID            |
| `instance_private_ip`    | 프라이빗 IP 주소           |
| `private_key_secret_arn` | SSH 키 Secrets Manager ARN |

### Lambda Crawler 모듈

VPC에 연결된 Lambda를 생성하여 PostgreSQL에 직접 기록합니다:

- 프라이빗 서브넷에서 실행
- 외부 API 접근을 위해 NAT Instance 사용
- 프라이빗 IP로 EC2 PostgreSQL 연결
- psycopg2 Lambda 레이어 필요

| 출력              | 설명             |
| ----------------- | ---------------- |
| `function_name` | Lambda 함수 이름 |
| `function_arn`  | Lambda 함수 ARN  |

### GitHub Actions OIDC

GitHub Actions에서 AWS로의 키 없는(keyless) 인증을 설정합니다:

- `devport-kr/devport-web`의 `main` 브랜치만 IAM 역할을 assume 가능
- S3 프론트엔드 버킷에 빌드 결과 업로드
- CloudFront 캐시 무효화 수행
- 장기 AWS 액세스 키 불필요

## 환경 변수

### 필수 terraform.tfvars

| 변수                    | 설명                 | 예시                |
| ----------------------- | -------------------- | ------------------- |
| `domain_name`         | 기본 도메인          | `devport.kr`      |
| `route53_zone_id`     | Hosted Zone ID       | `Z1234567890`     |
| `ssh_allowed_cidr`    | SSH 허용 IP          | `1.2.3.4/32`      |
| `db_password`         | PostgreSQL 비밀번호  | `secure-password` |
| `private_subnet_cidr` | 프라이빗 서브넷 CIDR | `10.0.2.0/24`     |

### 선택

| 변수                   | 설명                     | 기본값 |
| ---------------------- | ------------------------ | ------ |
| `psycopg2_layer_arn` | Lambda PostgreSQL 레이어 | `""` |
| `alarm_email`        | CloudWatch 알림 이메일   | `""` |

## 유지보수

### 데이터베이스 백업

매일 오전 3시에 Docker를 통해 자동 백업됩니다:

```bash
# 수동 백업
sudo /opt/scripts/backup.sh
```

### Lambda 코드 업데이트

1. `modules/lambda-crawler/`의 코드 수정
2. `terraform apply` 실행

또는 수동 배포:

```bash
aws lambda update-function-code \
  --function-name devport-prod-crawler \
  --zip-file fileb://lambda.zip
```

## 트러블슈팅

### EC2에 SSH 접속이 안 되는 경우

EC2는 프라이빗 서브넷에 있습니다. SSM Session Manager를 사용하세요:

```bash
aws ssm start-session --target <instance-id>
```

### Lambda가 DB에 연결되지 않는 경우

1. 보안 그룹에서 Lambda → EC2 포트 5432 허용 확인
2. Lambda가 프라이빗 서브넷에 있는지 확인
3. Lambda 환경 변수의 DB 자격 증명 확인

### Lambda가 인터넷에 접근하지 못하는 경우

1. NAT Instance 실행 중인지 확인
2. 프라이빗 라우트 테이블에서 0.0.0.0/0 → NAT Instance 경로 확인

### CloudFront 403 에러

1. S3 버킷 정책 확인
2. OAC 설정 확인
3. `index.html` 존재 여부 확인

## 보안 참고사항

- EC2는 프라이빗 서브넷 (퍼블릭 IP 없음)
- PostgreSQL은 VPC 내부에서만 접근 가능
- Lambda는 프라이빗 IP로 DB 연결
- SSM Session Manager를 통한 SSH (인터넷에서 직접 SSH 불가)
- 모든 S3 버킷 퍼블릭 접근 차단
- EC2에 IMDSv2 필수
- EBS 볼륨 암호화
- DB 비밀번호는 Lambda 환경 변수로 전달
- GitHub Actions OIDC로 키 없는 CI/CD (장기 AWS 키 불필요)

## 라이선스

MIT
