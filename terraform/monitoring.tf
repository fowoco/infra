# --- EBS 스냅샷 자동화 (DLM) ---
resource "aws_dlm_lifecycle_policy" "fowoco_backup" {
  description        = "fowoco EC2 root volume daily snapshot 7 day retention"
  execution_role_arn = aws_iam_role.fowoco_dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      fowoco-backup = "daily"
    }

    schedule {
      name = "fowoco-daily-snapshot"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["18:00"]
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        created-by = "fowoco-dlm"
      }

      copy_tags = true
    }
  }
}

# --- 노드 자체 헬스 알람 (Prometheus는 노드가 죽으면 같이 죽어서 못 봄) ---
resource "aws_sns_topic" "fowoco_infra_alerts" {
  name = "fowoco-infra-alerts"
}

resource "aws_cloudwatch_metric_alarm" "fowoco_node_status_check_failed" {
  alarm_name          = "fowoco-node-status-check-failed"
  alarm_description   = "fowoco-node-1 EC2 status check 실패 (시스템/인스턴스 레벨) - 클러스터 내부 Prometheus는 노드 자체가 죽으면 같이 죽어서 이 알람이 그 사각지대를 커버함"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions = {
    InstanceId = aws_instance.fowoco_node.id
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.fowoco_infra_alerts.arn]
}

# --- 월 지출 예산 알림 ---
resource "aws_budgets_budget" "fowoco_monthly_cost" {
  name         = "fowoco-monthly-cost"
  budget_type  = "COST"
  limit_amount = "50.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["akkn920@naver.com"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["akkn920@naver.com"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["akkn920@naver.com"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_email_addresses = ["akkn920@naver.com"]
  }
}
