# VPC/서브넷은 AWS 기본(default) 리소스를 그대로 쓰고 있어서 관리 대상으로
# "생성"하지 않고 데이터 소스로만 참조한다 — 여기서 만들지도, 지우지도 않음.
data "aws_vpc" "main" {
  id = "vpc-087307b75e29bc739"
}

data "aws_subnet" "main" {
  id = "subnet-0bb8f66c0591bed70"
}

resource "aws_security_group" "fowoco" {
  name        = "fowoco-sg"
  description = "FOWOCO demo server security group"
  vpc_id      = data.aws_vpc.main.id

  # SSH(22)는 없음 — kubectl은 GitHub Actions의 스코프 제한된 KUBE_CONFIG로,
  # k3s API(6443)는 CI 러너 IP가 계속 바뀌어서 0.0.0.0/0로 열어두고 TLS
  # 클라이언트 인증서로 방어함(네트워크 ACL이 아니라 인증이 진짜 방어선).
  # 규칙에 description을 새로 붙이면 AWS 프로바이더가 delete+recreate로
  # 처리해서 라이브 SG 규칙이 순간 흔들림 — import된 기존 규칙과 완전히
  # 동일하게 유지하려고 description 없이 둠(포트/프로토콜/CIDR로 충분히
  # 설명됨, 주석은 위에 남겨둠: 80/443 웹, 6443은 CI 배포용 k3s API).
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "fowoco_dev" {
  name        = "fowoco-dev-sg"
  description = "fowoco dev box - SSM only, no inbound ports"
  vpc_id      = data.aws_vpc.main.id

  # 인바운드 규칙 전부 없음 — SSM Session Manager만으로 접속(아웃바운드만 필요).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
