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
  key_name   = "terraform-demo-key"
  public_key = tls_private_key.key.public_key_openssh
}

resource "aws_security_group" "sg" {
  name        = "terraform-demo-sg"
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
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
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  depends_on = [aws_key_pair.key, aws_security_group.sg]

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
      # create the file
      "echo 'hello from terraform' > /home/ubuntu/hello.txt",
      "hostname >> /home/ubuntu/hello.txt",
      "date >> /home/ubuntu/hello.txt"
    ]
  }

  tags = {
    Name = "terraform-demo"
  }
}

output "public_ip" {
  value = aws_instance.vm.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_instance.vm.public_ip}"
}