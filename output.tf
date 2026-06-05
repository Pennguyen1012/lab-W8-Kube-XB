output "alb_dns_name" {
  description = "The DNS name of the load balancer. Open this in your browser."
  value       = "http://${aws_lb.k8s_alb.dns_name}"
}

output "ssh_command" {
  description = "Command to SSH into the EC2 instance"
  value       = "ssh -i k8s-challenge-key.pem ubuntu@${aws_instance.k8s_node.public_ip}"
}
