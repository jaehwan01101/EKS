# 엔지니어링 로그: 겪은 문제와 결정

이 문서는 구축하면서 **실제로 겪은 문제**와 **선택의 근거**를 날짜순으로 쌓는다.
포트폴리오의 "문제 해결" 항목과 면접 답변의 원재료다. 겪지 않은 것은 "예상"이라고 따로 표시한다.

각 항목은 같은 틀로 쓴다: 증상 → 원인 → 어떻게 찾았나 → 해결 → 배운 것.

---

## 겪은 문제 (검증됨)

### 1. 무료 플랜이 인스턴스 타입을 거부했다
- **증상**: 노드 그룹이 `CREATE_FAILED`, 점프 호스트 미생성. `InvalidParameterCombination ... not eligible for Free Tier`.
- **원인**: AWS Free Plan 계정은 무료 허용 타입만 만들 수 있다. 처음에 고른 `t4g.medium`(arm)이 대상이 아니었다.
- **놓친 점**: 선택 전에 AZ별 제공 여부는 확인했지만 **계정 플랜의 허용 여부**는 확인하지 않았다.
- **해결**: 허용 타입을 조회해 `m7i-flex.large`(x86) 2대로 변경. AMI 타입도 x86용으로 바꿈.
- **배운 것**: 리소스를 고를 때 "존재하는가"와 "내 계정에서 허용되는가"는 다른 질문이다.

### 2. GitHub OIDC: `Not authorized to perform sts:AssumeRoleWithWebIdentity`
- **증상**: 워크플로가 AWS 역할을 맡지 못하고 12번 재시도 후 실패.
- **핵심 어려움**: AWS는 어느 조건이 틀렸는지 알려주지 않는다(`aud`, `sub`, 공급자 누락이 모두 같은 메시지). 보안상 일부러 그렇다.
- **어떻게 찾았나**: 양쪽 값을 직접 꺼내 대조했다.
  - AWS 쪽: `aws iam get-role` 로 실제 적용된 신뢰 정책 조회 (`sub = repo:owner/repo:ref:refs/heads/main`)
  - GitHub 쪽: 워크플로 안에서 OIDC 토큰의 페이로드를 디코딩 (`sub = repo:owner@<계정ID>/repo@<저장소ID>:ref:refs/heads/main`)
- **원인**: GitHub 이 `sub` 에 불변 숫자 ID 를 포함한 형식으로 토큰을 발급했고, 신뢰 정책은 이름만 있는 옛 형식이었다. `StringEquals` 는 완전 일치라 거절.
- **디버깅 중 실수**: 첫 디코딩 스크립트가 base64url 패딩 때문에 실패했는데 `2>/dev/null` 이 에러를 숨겨 "출력 없음"으로 보였다. `jq` 의 `@base64d` 로 교체. **실패를 숨기면 "아무 일 없음"과 구분되지 않는다.**
- **해결**: 신뢰 정책 `sub` 를 ID 포함 형식으로 맞춤. 이름 재사용(계정/저장소를 지우고 같은 이름으로 재생성)을 통한 탈취도 막는 방향이라 보안상 더 낫다.
- **검증**: main 에서는 성공, 다른 브랜치(`test-oidc`)에서는 같은 에러로 **실패**하는 것을 둘 다 확인 (Actions 기록에 남음).
- **배운 것**: 거절한 쪽이 이유를 알려 주지 않으면 **양쪽 값을 직접 꺼내 대조**한다.

### 3. Docker 빌드: `groupadd ... exit code 4`
- **증상**: 이미지 빌드의 실행 단계에서 사용자 생성이 실패.
- **원인(추정)**: `groupadd` 종료 코드 4는 "GID 중복". 베이스 이미지(Ubuntu 계열)가 이미 uid/gid 1000 을 쓰는 것으로 보인다. 이미지를 직접 열어 확인하지는 않았다.
- **해결**: uid/gid 를 10001 로 변경. 베이스 이미지가 무엇을 갖든 충돌하지 않고, 컨테이너 사용자를 10000 이상으로 두는 보안 권장 사항에도 맞는다.
- **배운 것**: 빌드 단계(Gradle)가 성공하고 실행 단계에서 실패했다는 사실이 범위를 좁혀 줬다.

### 4. 비용: 아무것도 안 돌려도 크레딧이 줄었다
- **증상**: 크레딧이 113.87달러(11-11)에서 106.69달러(11-15)로 4일간 약 7달러 감소. 클러스터는 없던 시기.
- **원인**: NAT Gateway 가 켜진 채였다 (시간당 과금).
- **해결**: `20-network` 에 `enable_nat_gateway` 변수 추가. VPC 는 두고 NAT 만 지울 수 있다. VPC ID 가 유지되어 Git 에 적은 값을 매번 바꿀 필요도 없다.
- **배운 것**: 실제 청구 데이터를 보고 원인을 찾았다. 켜 두고 잊는 것이 가장 흔한 비용 사고다.

### 5. Argo CD: external-secrets 가 `OutOfSync` + `Degraded`, CRD 반영 실패
- **증상**: ESO 설치 Application 이 5번 재시도 후 실패. ESO 컨트롤러 파드는 `RESTARTS 7`, cert-controller 는 `0/1`. 다음 wave(ClusterSecretStore)는 `Missing` 에서 대기.
- **어떻게 찾았나**: Application 의 `operationState.message` 를 조회 → `CustomResourceDefinition "clustersecretstores.external-secrets.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes`. (이 문제는 ESO/Prometheus Operator 에서 널리 알려져 있어 후보로 미리 예상했고, 메시지로 확정)
- **원인**: Argo CD 의 기본 방식인 client-side apply 는 리소스 전체를 `last-applied-configuration` 어노테이션에 저장한다. ESO 의 CRD 는 스키마가 커서 이 어노테이션이 한도를 넘는다. CRD 가 없으니 컨트롤러가 기동 실패를 반복했다. **뿌리 하나가 세 가지 증상으로 보였다.**
- **해결**: 해당 Application 에 `ServerSideApply=true`. API 서버가 변경을 추적하므로 어노테이션 한도가 없다.
- **상태**: 수정 반영 후 `Healthy` 확인 대기 (확인되면 이 줄을 갱신).
- **배운 것**: 증상(Degraded)이 아니라 메시지(`operationState`)를 읽는다. 재시작 횟수 같은 2차 증상은 뿌리를 가리지 않게 주의.

---

## 설계 결정과 근거 (검증됨)

| 결정 | 근거 | 대가(한계) |
|---|---|---|
| Terraform 레이어 분리(상태 파일 분리) | 변경 영향 범위를 줄이고, 비용 큰 레이어만 내렸다 올릴 수 있음 | 레이어 간 값은 remote state 로 연결해야 함 |
| EKS API 프라이빗 + SSM 점프 호스트(인바운드 없음) | API 를 인터넷에 노출하지 않음 | PC 에서 직접 kubectl 불가, UI 접속이 2단 터널 |
| Pod Identity (키 없는 AWS 접근) | 파드에 장기 키를 넣지 않음. GitHub OIDC 와 같은 사상 | 서비스 어카운트 이름이 코드와 일치해야 함 |
| VPC CNI prefix delegation | 노드당 파드 수 110개 확인 (기본이면 수십 개) | |
| GitHub Actions + OIDC (장기 키 없음) | 키 유출/로테이션 부담 제거. `sub` 로 저장소·브랜치 한정 | PR 빌드는 AWS 접근 불가(의도) |
| Action 을 커밋 SHA 로 고정 + 2주 쿨다운 | 태그는 옮겨질 수 있음(2025년 tj-actions 사고). 막 나온 릴리스는 검증 기간이 짧음 | 업데이트가 수동(Dependabot 로 보완 예정) |
| ECR 태그 `커밋SHA7자리-실행번호` + IMMUTABLE | 태그 → 커밋 추적, 같은 태그 덮어쓰기 불가 | |
| 재실행 멱등성: 푸시 전 태그 존재 확인 | Re-run 은 run_number 가 같아 같은 태그를 다시 푸시 → immutable 이 거부. 있으면 건너뜀 | |
| Dockerfile 멀티스테이지, amd64 명시, 비root | 노드가 x86 이라 arm64 불필요. 빌드 도구를 최종 이미지에서 제외 | Jib 보다 캐시 설계 부담 |
| `provenance: false` | 증명 매니페스트가 ECR 에 별도 항목으로 붙는 것을 막음. 켜진 채/꺼진 채 모두 확인하지는 않음 | 공급망 증명 포기 |
| DB 비밀번호를 상태 파일에 남기지 않음 (ephemeral + write-only) | 일반 방식은 비밀번호가 상태에 평문 저장됨 | |
| RDS 보안 그룹 규칙을 40-eks 에서 붙임 | 30-data 가 40-eks 를 참조하면 레이어가 순환 | 규칙이 다른 레이어에 있어 찾기 어려움 |
| Argo CD pull 방식 + app of apps + sync wave | CI 에 클러스터 권한 불필요. CRD 순서 문제 해결 | 프라이빗이라 웹훅 불가, 폴링 지연(약 2~3분) |

---

## 알려진 한계 (솔직하게)

- 고가용성 포기: NAT 1개, RDS 단일 AZ, 컨트롤러 replicas 1
- 앱이 DB 마스터 계정을 그대로 사용 (운영이라면 권한 분리한 앱 전용 계정)
- Argo CD UI SSO 없음, 외부 노출 없음(터널로만 접속)
- 같은 저장소에 앱 코드와 배포 매니페스트 (운영 규모라면 분리)

---

## 진행 중 / 아직 겪지 않은 것 (예상, 겪으면 위로 옮긴다)

- Rollouts 와 Argo CD 의 diff 충돌 (`ignoreDifferences`)
- 카나리 분석에서 트래픽 부족 문제
- LB 컨트롤러의 VPC ID 조회 실패 가능성 (값 파일에 지정해 둠)
- gp2/gp3 기본 스토리지 클래스 중복
