resource "aws_security_group" "app_sg" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2026-01-28T14:05:37.130Z"
  vpc_id      = "vpc-05e45cf5b3c3f60f8"
  tags = {}

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

resource "aws_instance" "inventory_app" {
  ami                    = "ami-073130f74f5ffb161"
  instance_type          = "t3.small"
  subnet_id              = "subnet-0007532b9109cdae0"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = "SS_KEY"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "Linux_Devops"
  }
}

resource "aws_eip" "inventory_eip" {
  instance = aws_instance.inventory_app.id
  domain   = "vpc"
}
