provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "terraform-sveltekit"
    key    = "terraform-key"
    region = "us-east-1"
  }
}

data "external" "get_version" {
  program = ["node", "-e", "console.log(JSON.stringify({ version: require('./package.json').version }))"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

resource "aws_security_group" "sveltekit" {
  name = "sveltekit"

  ingress {
    description = "sveltekit"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "sveltekit"
  }
}

resource "aws_security_group" "sveltekit_lb" {
  name = "sveltekit_lb"

  ingress {
    description = "sveltekit_lb"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "sveltekit_lb"
  }
}

resource "aws_ecr_repository" "sveltekit" {
  name         = "sveltekit"
  force_delete = true
}

output "ecr_repository_url" {
  value = aws_ecr_repository.sveltekit.repository_url
}

resource "aws_lb" "sveltekit" {
  name               = "sveltekit"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.sveltekit_lb.id]

  tags = {
    Name = "sveltekit"
  }
}

resource "aws_lb_target_group" "sveltekit" {
  name        = "sveltekit"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_lb_listener" "sveltekit" {
  load_balancer_arn = aws_lb.sveltekit.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.sveltekit.arn
    type             = "forward"
  }
}

resource "aws_ecs_cluster" "sveltekit" {
  name               = "sveltekit"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_ecs_task_definition" "sveltekit" {
  family = "sveltekit"
  container_definitions = jsonencode([
    {
      name      = "sveltekit"
      image     = "${aws_ecr_repository.sveltekit.repository_url}:${data.external.get_version.result.version}"
      cpu       = 0
      essential = true
      portMappings = [
        {
          name          = "sveltekit-3000-tcp"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
    }
  ])
  cpu                      = 1024
  memory                   = 3072
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_ecs_service" "sveltekit" {
  name                = "sveltekit"
  cluster             = aws_ecs_cluster.sveltekit.id
  task_definition     = aws_ecs_task_definition.sveltekit.arn
  desired_count       = 1
  scheduling_strategy = "REPLICA"
  launch_type         = "FARGATE"
  deployment_controller {
    type = "ECS"
  }
  enable_ecs_managed_tags = true
  force_new_deployment    = true

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.sveltekit.id]
    subnets          = data.aws_subnet_ids.default.ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.sveltekit.arn
    container_name   = "sveltekit"
    container_port   = 3000
  }
}