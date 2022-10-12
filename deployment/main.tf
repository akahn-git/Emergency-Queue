# configures terraform to use the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# configures the AWS provider
provider "aws" {
  region = "us-east-1"
  access_key = ""
  secret_key = ""
}

# define an ECS cluster for emergencyqueue
resource "aws_ecs_cluster" "emergencyqueue_cluster" {
  name = "emergencyqueue_cluster"
}

# adopt the default role created by AWS to run the task under
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

# define a task for the frontend webserver
resource "aws_ecs_task_definition" "emergencyqueue_frontend_webserver" {
  family                   = "emergencyqueue_frontend_webserver"
  task_role_arn            = "${data.aws_iam_role.ecs_task_execution_role.arn}"
  execution_role_arn       = "${data.aws_iam_role.ecs_task_execution_role.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "emergencyqueue_webserver"
      image     = "609184045166.dkr.ecr.us-east-1.amazonaws.com/emergency-queue"
      essential = true
      command   = ["nginx", "-g", "daemon off;"]
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

# create a security group
#
# this is used to allow network traffic to reach our containers
resource "aws_security_group" "emergencyqueue_security_group" {
  name = "emergencyqueue_security_group"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# adopt the default AWS VPC as a resource in terraform. see:
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_vpc
resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name = "default VPC"
  }
}

# create subnets in two availability zones
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

resource "aws_subnet" "emergencyqueue_subnet" {
  count                   = "${length(var.availability_zones)}"
  vpc_id                  = aws_default_vpc.default_vpc.id
  cidr_block              = cidrsubnet(aws_default_vpc.default_vpc.cidr_block, 4, count.index + 1)
  availability_zone       = "${var.availability_zones[count.index]}"
  map_public_ip_on_launch = false
}

# create a load balancer to distribute traffic to the tasks described below
resource "aws_lb" "emergencyqueue_load_balancer" {
  name               = "emergencyqueue-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.emergencyqueue_security_group.id]
  subnets            = aws_subnet.emergencyqueue_subnet.*.id
}

# create a target group for the load balancer described above
resource "aws_lb_target_group" "emergencyqueue_target_group" {
  name        = "emergencyqueue-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
  depends_on  = [
    aws_lb.emergencyqueue_load_balancer
  ]
}

# load balancer endpoint
resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.emergencyqueue_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.emergencyqueue_target_group.arn
  }
}

# define a service, running 5 instances of the frontend webserver
resource "aws_ecs_service" "emergencyqueue_frontend_webserver_service" {
  name                   = "emerencyqueue_frontend_webserver_service"
  enable_execute_command = true
  launch_type            = "FARGATE"
  cluster                = aws_ecs_cluster.emergencyqueue_cluster.id
  task_definition        = aws_ecs_task_definition.emergencyqueue_frontend_webserver.id
  desired_count          = 5
  network_configuration {
    subnets          = aws_subnet.emergencyqueue_subnet.*.id
    security_groups  = [aws_security_group.emergencyqueue_security_group.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.emergencyqueue_target_group.arn
    container_name   = "frontend_webserver"
    container_port   = 80
  }
}