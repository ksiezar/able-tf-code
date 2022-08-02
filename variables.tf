variable "vpc_id" {
  type    = string
  default = "vpc-480bb82c"
}

variable "ami_id" {
  type    = string
  default = "ami-06640050dc3f556bb"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "key_name" {
  type    = string
  default = "able-ecs-ec2-key-pem"
}

variable "platform_private_subnet_ids" {
  type = list(string)
  default = ["subnet-f527b490"]
}

variable "aws_account_id" {
  type    = string
  default = "983808592101"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "image_name" {
  type    = string
}

variable "db_password" {
  type    = string
}

