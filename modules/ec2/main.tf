data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id = var.subnet_id

  vpc_security_group_ids = [
    var.security_group_id
  ]

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              for attempt in 1 2 3 4 5; do
                if apt-get update; then
                  break
                fi
                if [ "$attempt" -eq 5 ]; then
                  exit 1
                fi
                sleep 10
              done
              DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
              echo "<h1>Hello from Terraform AWS Infrastructure</h1>" > /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name = "${var.project_name}-web-server"
  }
}
