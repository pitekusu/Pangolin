output "instance_ipv6_addresses" {
  value = aws_lightsail_instance.pangolin.ipv6_addresses
}

output "ssh_example" {
  value = "ssh ec2-user@[${aws_lightsail_instance.pangolin.ipv6_addresses[0]}]"
}

output "dashboard_setup_url" {
  value = "https://${var.dashboard_domain}/auth/initial-setup"
}
