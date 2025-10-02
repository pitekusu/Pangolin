resource "aws_lightsail_instance" "pangolin" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  ip_address_type   = "ipv6"

  user_data = <<-CLOUDINIT
    #cloud-config
    package_update: true
    runcmd:
      - bash -lc 'mkdir -p /opt/pangolin && cd /opt/pangolin'
      - bash -lc 'command -v curl >/dev/null 2>&1 || (sudo dnf -y install curl)'
      - bash -lc 'curl -fsSL https://digpangolin.com/get-installer.sh | bash'
      - bash -lc 'chmod +x /opt/pangolin/installer'
      - bash -lc 'echo "Run: cd /opt/pangolin && sudo ./installer" | sudo tee /etc/motd'
  CLOUDINIT
}

resource "aws_lightsail_instance_public_ports" "pangolin_ports" {
  instance_name = aws_lightsail_instance.pangolin.name

  port_info {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    ipv6_cidrs = ["::/0"] 
    }

  port_info {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    ipv6_cidrs = ["::/0"]
    }

  port_info {
    from_port = 51820
    to_port = 51820
    protocol = "udp"
    ipv6_cidrs = ["::/0"]
    }
    
  port_info {
    from_port = 21820
    to_port = 21820
    protocol = "udp"
    ipv6_cidrs = ["::/0"]
    }
}
