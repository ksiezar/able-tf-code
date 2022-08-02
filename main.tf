##### Security Group #######

resource "aws_security_group" "able-sg" {
  name        = "able-sg"
  description = "Security group for app solution devops"
  vpc_id      = var.vpc_id
  tags = {
    Name = "able-sg"
  }
}

###### Security Group Rules Ingress ######

resource "aws_security_group_rule" "app-web-ingress" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8081
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.able-sg.id
}

resource "aws_security_group_rule" "http-web-ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.able-sg.id
}

resource "aws_security_group_rule" "ssh-ingress" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.able-sg.id
}

resource "aws_security_group_rule" "able-db" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.able-sg.id
}

###### Security Group Rules Outbound ######

resource "aws_security_group_rule" "app-outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "All"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.able-sg.id
}

##### ECR image repository #######

resource "aws_ecr_repository" "able-ecr" {
  name = "able-ecr-repo"
  tags = {
    Name = "able-ecr"
  }
}

###### AWS RDS ########


resource "aws_db_instance" "able-db" {
  identifier             = "able-database"
  instance_class         = "db.m5.large"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "13.4"
  username               = "admin"
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.able-sg.id]
  skip_final_snapshot    = true
  backup_retention_period = 1
}

##### IAM ECS Agent policy #######

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}


resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

###### AWS Load Balancer ######
resource "aws_lb" "able-lb" {
  name               = "able-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.able-sg.id]
}

resource "aws_lb_target_group" "able-tg" {
  name     = "able-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.able-lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.able-tg.arn
  }
}

##### ECS Cluster #######

resource "aws_ecs_cluster" "able-ecs-cluster" {
  name = "able-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

####### AWS ECS EC2 instances ######

resource "tls_private_key" "able-ecs-ec2-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "able-ecs-ec2-key-pair" {
  key_name   = var.key_name
  public_key = tls_private_key.able-ecs-ec2-key.public_key_openssh
}

resource "aws_instance" "ec2_able_instance" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ecs_agent.arn
  vpc_security_group_ids = [aws_security_group.able-sg.id]
  key_name               = aws_key_pair.able-ecs-ec2-key-pair.id
  ebs_optimized          = "false"
  source_dest_check      = "false"
    user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=able-ecs >> /etc/ecs/ecs.config
EOF
}

resource "aws_ecs_task_definition" "able-task-definition" {
  family             = "able_task_definition"
  execution_role_arn = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  task_role_arn      = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  memory             = 1024
  cpu                = 512
  requires_compatibilities = ["EC2"]
  container_definitions = jsonencode([
    {
      name      = "able-app-ecs-container"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.image_name}:latest"
      cpu       = 512
      memory    = 1024
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "able-service" {
  name            = "able-service"
  cluster         = aws_ecs_cluster.able-ecs-cluster.id
  task_definition = aws_ecs_task_definition.able-task-definition.arn
  desired_count   = 2
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.able-tg.arn
    container_name   = "able-ecs-container"
    container_port   = 8080
  }
  network_configuration {
    security_groups       = [aws_security_group.able-sg.id]
    subnets               = var.platform_private_subnet_ids
    assign_public_ip      = "false"
  }
  depends_on              = ["aws_lb_listener.lb_listener"]
}