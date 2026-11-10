# External Secrets (SSM Parameter Store)

초안이다. 아직 클러스터에 적용한 적 없고, 매니페스트 repo 가 생기면 거기로 옮긴다.

## 데이터 흐름

```
Terraform 60-edge ──▶ SSM SecureString /reservation/edge/origin-verify-header
        │                         │
        │ (같은 값)                │ ESO 가 읽음 (Pod Identity)
        ▼                         ▼
   CloudFront               K8s Secret origin-verify ──env──▶ Spring 필터(OriginVerifyFilter)
   origin custom header
   X-Origin-Verify
```

## ESO 가 필요로 하는 AWS 권한 (Terraform 에서 Pod Identity 로 연결)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters"],
      "Resource": "arn:aws:ssm:ap-northeast-2:<ACCOUNT_ID>:parameter/reservation/*"
    }
  ]
}
```

SecureString 을 AWS 관리형 키(`aws/ssm`)로 암호화하는 지금은 이것으로 충분하다.
직접 만든 KMS 키로 바꾸면 해당 키에 대한 `kms:Decrypt` 를 추가해야 한다.

## 알아둘 점

- 헤더 이름은 Terraform(`custom_header.name`)과 앱(`app.origin-verify.header-name`)이 같아야 한다.
  지금은 둘 다 `X-Origin-Verify`.
- ESO 가 Secret 을 갱신해도 실행 중인 Pod 의 env 는 바뀌지 않는다. 재시작이 필요하며,
  자동화하려면 Reloader 같은 컨트롤러를 쓰는 방법이 있다(아직 도입 여부 미정).
- 무중단 로테이션은 지금 구조로는 안 된다. CloudFront 배포 반영(수 분)과 Pod 재시작 시점이 어긋나는 동안
  403 이 난다. 필요해지면 앱이 이전 값과 새 값 2개를 동시에 허용하도록 확장한다.
- 이 헤더는 "CloudFront 를 거쳤다"는 표시일 뿐 사용자 인증이 아니다. 값은 Terraform state 와
  CloudFront 설정에도 존재하므로 해당 권한이 있는 사람에게는 보인다.
