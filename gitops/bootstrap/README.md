# Argo CD 부트스트랩과 세션 운영 절차

클러스터가 올라온 뒤(30-data → 40-eks → 50-platform 적용 후) 이 순서로 진행한다.
클러스터 API 가 프라이빗이라 아래 명령은 전부 **점프 호스트(SSM 세션) 안에서** 실행한다.

## 왜 Argo CD 만 손으로 설치하나

Argo CD 가 있어야 Argo CD 가 다른 것을 설치할 수 있다. 그래서 Argo CD 하나만 helm 으로 직접 설치하고,
루트 Application 하나를 적용한 뒤로는 모든 플랫폼 구성요소를 Git 에서 선언한다.
(Argo CD 자신을 Argo CD 가 관리하는 "자기 관리"는 설정 실수 시 스스로를 망가뜨릴 수 있어서 하지 않는다.)

## 0. 사전 조건

- 이 저장소의 `gitops/` 가 GitHub(main)에 push 되어 있어야 한다. Argo CD 가 거기서 읽는다.
- 점프 호스트에서 클러스터 접근 확인: `kubectl get nodes` (노드 2대 Ready)

```bash
aws eks update-kubeconfig --name reservation --region ap-northeast-2
kubectl get nodes
```

## 1. 점프 호스트에 helm 설치 (검증값 확인 포함)

점프 호스트는 t4g(arm64)다. 인터넷의 설치 스크립트를 바로 실행하지 않고, 버전을 고정하고 체크섬을 검증한다.
helm v4.3.1 (2026-10-15 릴리스).

```bash
HELM_VERSION=v4.3.1
cd /tmp
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz"
echo "8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88  helm-${HELM_VERSION}-linux-arm64.tar.gz" | sha256sum -c -
tar -xzf "helm-${HELM_VERSION}-linux-arm64.tar.gz"
sudo install -m 0755 linux-arm64/helm /usr/local/bin/helm
helm version
```

`sha256sum -c` 가 `OK` 를 출력해야 한다. 아니면 중단한다.

## 2. Argo CD 설치

차트 argo-cd 10.11.6 (앱 v3.5.6). 값 파일은 이 저장소의 `bootstrap/argocd-values.yaml`.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
curl -fsSLO https://raw.githubusercontent.com/jaehwan01101/EKS/main/gitops/bootstrap/argocd-values.yaml
helm install argocd argo/argo-cd --version 10.11.6 -n argocd --create-namespace -f argocd-values.yaml
kubectl -n argocd get pods
```

파드가 전부 Running 이 될 때까지 기다린다 (`kubectl -n argocd get pods -w`).

## 3. 루트 Application 적용

```bash
kubectl apply -f https://raw.githubusercontent.com/jaehwan01101/EKS/main/gitops/bootstrap/root-app.yaml
kubectl -n argocd get applications -w
```

기대하는 순서 (sync-wave):

| wave | Application |
|---|---|
| 0 | aws-load-balancer-controller, external-secrets, argo-rollouts, metrics-server, storage |
| 1 | external-secrets-config (ClusterSecretStore) |

모든 Application 이 `Synced` / `Healthy` 가 되어야 한다.

## 4. 확인할 것

```bash
kubectl top nodes                         # metrics-server 동작 + 노드 메모리 여유 실측 (기록해 둘 것)
kubectl get sc                            # gp3 가 default 인지. gp2 도 default 면 default 가 둘이다 (아래 참고)
kubectl -n kube-system get pods | grep -E "aws-load-balancer|ebs-csi"
kubectl get clustersecretstore            # aws-parameter-store 가 Ready 인지
```

- `gp2` 와 `gp3` 가 둘 다 default 로 표시되면 `gp2` 의 default 어노테이션을 제거한다:
  `kubectl patch sc gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'`
- LB 컨트롤러 파드가 `CrashLoopBackOff` 면 로그를 본다: `kubectl -n kube-system logs deploy/aws-load-balancer-controller`
  (흔한 원인: vpcId 불일치, 서비스 어카운트 이름 불일치로 AWS 권한 없음)

## 5. UI 접속 (프라이빗 클러스터라 2단 터널)

초기 관리자 비밀번호 (사용 후 삭제할 것):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

점프 호스트에서 포트 포워딩 (이 터미널은 열어 둔다):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

PC 에서 SSM 포트 포워딩 (점프 호스트 인스턴스 ID 는 `terraform output bastion_instance_id`):

```powershell
aws ssm start-session --target <인스턴스ID> --region ap-northeast-2 --profile eks --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'
```

브라우저에서 `https://localhost:8080` (자체 서명 인증서 경고는 정상). 사용자 `admin`.
Rollouts 대시보드와 Grafana 도 같은 방식으로 본다.

## 긴급 수정 절차 (selfHeal 과의 충돌)

장애 중에 누가 `kubectl` 로 직접 고치면 selfHeal 이 그 수정을 **되돌린다**.
긴급 수정이 필요하면 해당 Application 의 자동 동기화를 먼저 끈다:

```bash
kubectl -n argocd patch application <이름> --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

수습한 뒤에는 같은 변경을 Git 에 반영하고 자동 동기화를 다시 켠다. 이 절차와 그 이유는 포스트모템에 기록한다.

## 종료 절차 (비용 방지, 순서 중요)

**ALB 는 Terraform 이 만든 것이 아니라 LB 컨트롤러가 만든 것**이라, 클러스터를 지워도 ALB 가 남아서 과금되고
VPC 삭제도 막는다. 반드시 컨트롤러가 살아 있을 때 Ingress 를 먼저 지운다.

1. 앱 Ingress 삭제 (Argo CD 의 앱 Application 삭제 또는 `kubectl delete ingress`)
2. ALB 가 사라졌는지 확인: `aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn"` 이 `[]`
3. `50-platform` destroy → `40-eks` destroy → `30-data` destroy
4. NAT 끄기 (VPC 는 유지하고 NAT 와 EIP 만 지운다. VPC ID 가 유지되어 `vpcId` 를 Git 에서 고치지 않아도 된다):
   `cd infra/terraform/20-network` 에서 `terraform apply "-var-file=../common.tfvars" -var enable_nat_gateway=false`
   (다음 세션 시작 때는 `-var` 없이 apply 하면 다시 켜진다)
5. 확인: EKS 클러스터 없음, NAT 없음, RDS 없음, 크레딧 잔액 기록
