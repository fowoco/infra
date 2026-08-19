output "node_public_ip" {
  value = aws_eip.fowoco_node.public_ip
}

output "node_instance_id" {
  value = aws_instance.fowoco_node.id
}

output "dev_instance_id" {
  value = aws_instance.fowoco_dev.id
}
