# --- 메인 k3s 노드 (client/server/ai/postgres 전부 이 한 대에서 동작) ---
resource "aws_instance" "fowoco_node" {
  ami                    = "ami-0195f90f654bc4d8e"
  instance_type          = "m7i-flex.large"
  subnet_id              = data.aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.fowoco.id]
  key_name               = "fowoco-key"

  root_block_device {
    volume_type = "gp3"
    volume_size = 100 # 30GB로 시작 → 디스크 프레셔 인시던트 이후 100GB로 증설(2026-08-13)
    iops        = 3000
    tags = {
      # DLM 정책(fowoco_backup 리소스)이 이 태그로 스냅샷 대상을 찾음 —
      # 여기서 빠지면 terraform apply가 조용히 일일 백업을 끊어버림.
      fowoco-backup = "daily"
    }
  }

  tags = {
    Name = "fowoco-node-1"
  }

  lifecycle {
    # AMI가 이후에 deprecated/교체돼도 이미 떠서 운영 중인 인스턴스를
    # terraform apply가 재생성하려 들면 안 됨 — 이미지·userdata는 최초
    # 부팅 시점 값으로 고정, 실제 변경은 항상 in-place(k3s 자체 업그레이드 등).
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "fowoco_node" {
  domain = "vpc"
  tags = {
    Name = "fowoco-node-1-eip"
  }
}

resource "aws_eip_association" "fowoco_node" {
  instance_id   = aws_instance.fowoco_node.id
  allocation_id = aws_eip.fowoco_node.id
}

# --- 로컬 개발용 EC2 (SSM 전용, 온디맨드 시작/정지) ---
resource "aws_instance" "fowoco_dev" {
  ami                    = "ami-0195f90f654bc4d8e"
  instance_type          = "m7i-flex.large"
  subnet_id              = data.aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.fowoco_dev.id]
  iam_instance_profile   = aws_iam_instance_profile.fowoco_dev_ssm.name
  associate_public_ip_address = true # SSM 에이전트 아웃바운드 등록용 (NAT 게이트웨이 없음)

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    tags = {
      Name = "fowoco-dev-root"
    }
  }

  tags = {
    Name = "fowoco-dev"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
