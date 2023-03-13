provider "aws" {
  region     = "eu-west-1"
  access_key = "AWSACCESSKEY"
  secret_key = "AWSSECRETKEY"
}

###########################################


# VPC Creation
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
}


# Internet Gateway for VPC
resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
}


# Subnet for each availability zone
resource "aws_subnet" "subnet_a" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "subnet_b" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1b"
  map_public_ip_on_launch = true
}


# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }
}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public.id
}



# Security group for the EC2 instances and ALB
resource "aws_security_group" "mysg" {
  name_prefix = "mysg"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
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


# Creating 2 EC2 Instances using count
variable "instance_count" {
  type    = number
  default = 2
}

resource "aws_instance" "ec2_instance" {
  count         = var.instance_count
  ami           = "ami-08fea9e08576c443b"
  instance_type = "t2.micro"
  subnet_id     = count.index % 2 == 0 ? aws_subnet.subnet_a.id : aws_subnet.subnet_b.id
  vpc_security_group_ids = [aws_security_group.mysg.id]
  availability_zone = count.index == 0 ? "eu-west-1a" : "eu-west-1b"

  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Current Web Server is $(hostname -f) <br> Keep refreshing to change EC2 Instances (Thanks to the Application Load Balancer)</h1><br>Terraform code wrote by Farhad Mahdavi" > /var/www/html/index.html
              EOF
}


############ ALB part


# Creating the load balancer
resource "aws_lb" "my_lb" {
  name               = "my-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
  security_groups    = [aws_security_group.mysg.id]

}


# Target Group for lb
resource "aws_lb_target_group" "my_tg" {
  name_prefix      = "my-tg"
  port             = 80
  protocol         = "HTTP"
  target_type      = "instance"
  vpc_id           = aws_vpc.vpc.id
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
  }
}


# Attaching EC2 Instances to the target group
resource "aws_lb_target_group_attachment" "tgattach" {
  count           = 2
  target_group_arn = aws_lb_target_group.my_tg.id
  target_id        = aws_instance.ec2_instance[count.index].id
  port             = 80
}

# Listener for the ALB
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg.arn
  }
}
