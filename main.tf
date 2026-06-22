terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

variable "ssh_password" {
  sensitive = true
}

provider "aws" {
  region = "eu-north-1"
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key" {
  key_name   = "terraform-demo-key102"
  public_key = tls_private_key.key.public_key_openssh
}

resource "aws_security_group" "sg1" {
  name        = "terraform-demo-sg"
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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

resource "aws_instance" "vm" {
  ami                         = "ami-0aba19e56f3eaec05"
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.key.key_name
  vpc_security_group_ids      = [aws_security_group.sg1.id]
  associate_public_ip_address = true

  depends_on = [aws_key_pair.key, aws_security_group.sg1]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = tls_private_key.key.private_key_pem
    timeout     = "5m"
  }

provisioner "remote-exec" {
  inline = [
    # enable password auth
    "sudo sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",
    "sudo sed -i 's/^#\\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config",
    "echo 'ubuntu:${var.ssh_password}' | sudo chpasswd",
    "sudo systemctl restart ssh",

    "sudo apt install -y nginx",
    "sudo systemctl enable nginx",
    "sudo systemctl start nginx",
    
    "sudo tee /var/www/html/index.html > /dev/null <<'EOF'",
    "<!DOCTYPE html>",
    "<html>",
    "  <head><title>My Terraform Server</title></head>",
    "  <body>",
    "    <h1>Hello from Terraform!</h1>",
    "    <p>Hostname: $(hostname)</p>",
    "    <p>Date: $(date)</p>",
    "  </body>",
    "</html>",
    "EOF"
  ]
}

  tags = {
    Name = "terraform-demo"
  }
}

output "public_ip" {
  value = aws_instance.vm.public_ip
}
