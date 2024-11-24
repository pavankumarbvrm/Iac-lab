
provider "aws" {
  region  = "us-east-1"
  profile = "default"
}

# Variables
variable "instance_type" {
  default = "t2.micro"  # Specify instance type
}

variable "key_name" {
  description = "AWS Key Pair name"
  type        = string
  default     = "pavan_pem_key"
}

# AMI IDs for instances
variable "ubuntu_ami_id" {
  default = "ami-005fc0f236362e99f"  # Replace with a valid Ubuntu AMI ID for your region
}

variable "amazon_linux_ami_id" {
  default = "ami-06b21ccaeff8cd686"  # Replace with a valid Amazon Linux AMI ID for your region
}

# Security Group allowing SSH
resource "aws_security_group" "ansible_sg" {
  name        = "ansible-sg"
  description = "Allow SSH access"
  vpc_id      = "vpc-0e0791f0603d5077f"  # Replace with your VPC ID

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Update to restrict access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Ubuntu Ansible Control Node
resource "aws_instance" "ansible_control_node" {
  ami           = var.ubuntu_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.ansible_sg.name]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "Ansible-Control-Node"
  }
}

# Null Resource to Install Ansible and Update Hostname
resource "null_resource" "install_ansible_and_update_hostname" {
  depends_on = [aws_instance.ansible_control_node]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file("/workspaces/Iac-lab/Ansible/pavan_pem_key.pem")
      host        = aws_instance.ansible_control_node.public_ip
    }

    inline = [
      "sudo apt update",
      "sudo apt install -y software-properties-common",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt update",
      "sudo apt install -y ansible",
      
      # Set the hostname dynamically based on instance name
      "sudo hostnamectl set-hostname ${var.instance_type}-hostname",  # Replace this with your desired hostname logic

      # Verify the hostname has been updated
      "hostnamectl",
      
      # Restart the instance to apply the hostname change
      "sudo reboot"
    ]
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}


# Variables for SSH connection
variable "ssh_user" {
  default = "ubuntu"  # Default user for Ubuntu AMIs
}

variable "ssh_private_key_path" {
  description = "Path to your private key file"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# Ubuntu Managed Node
resource "aws_instance" "ubuntu_managed_node" {
  ami           = var.ubuntu_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.ansible_sg.name]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "Ubuntu-Managed-Node"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Set the hostname for Ubuntu node
              sudo hostnamectl set-hostname ubuntu_node
              echo "ubuntu_node" | sudo tee /etc/hostname
              sudo systemctl restart systemd-logind.service
              EOF
}

# Amazon Linux Managed Node
resource "aws_instance" "amazon_linux_managed_node" {
  ami           = var.amazon_linux_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.ansible_sg.name]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "Amazon-Linux-Managed-Node"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Set the hostname for AWS node
              sudo hostnamectl set-hostname aws_node
              echo "aws_node" | sudo tee /etc/hostname
              sudo systemctl restart systemd-logind.service
              EOF
}

output "ansible_control_node_ip" {
  description = "Public IP of the Ansible control node"
  value       = aws_instance.ansible_control_node.public_ip
}

output "ubuntu_managed_node_ip" {
  description = "Public IP of the Ubuntu managed node"
  value       = aws_instance.ubuntu_managed_node.public_ip
}

output "amazon_linux_managed_node_ip" {
  description = "Public IP of the Amazon Linux managed node"
  value       = aws_instance.amazon_linux_managed_node.public_ip
}

# Create IAM Role for SSM Access
resource "aws_iam_role" "ssm_role" {
  name = "SSMAccessRole"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

# Attach the AmazonSSMManagedInstanceCore Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "ssm_role_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile to Attach IAM Role to EC2 Instances
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}