# --- fowoco-dev EC2용 SSM 접속 역할 (SSH 없이 Session Manager로만 접속) ---
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fowoco_dev_ssm" {
  name               = "fowoco-dev-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fowoco_dev_ssm" {
  role       = aws_iam_role.fowoco_dev_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "fowoco_dev_ssm" {
  name = "fowoco-dev-ssm-profile"
  role = aws_iam_role.fowoco_dev_ssm.name
}

# --- DLM(Data Lifecycle Manager) EBS 스냅샷 자동화용 역할 ---
data "aws_iam_policy_document" "dlm_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fowoco_dlm" {
  name               = "fowoco-dlm-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fowoco_dlm" {
  role       = aws_iam_role.fowoco_dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}
