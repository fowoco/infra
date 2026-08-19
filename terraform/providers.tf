terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # 로컬 state 사용 — 1인 운영 데모 프로젝트라 S3+DynamoDB 원격 백엔드까지는
  # 오버스펙으로 판단함. 팀 협업으로 확장되면 그때 backend "s3" 블록 추가.
  # *.tfstate는 실제 리소스 속성(가끔 민감값 포함)을 평문으로 담고 있어서
  # .gitignore로 git에서 제외함 — state 파일 자체가 이 프로젝트의 유일한
  # 진실 공급원이니 로컬에서 백업해둘 것.
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project   = "fowoco"
      ManagedBy = "terraform"
    }
  }
}
