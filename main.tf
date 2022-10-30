terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "default" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "tf_test"
  }
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.1.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "sub1"
  }
}


resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "sub2"
  }
}

resource "aws_subnet" "sub3" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.1.2.0/24"
  #map_public_ip_on_launch = true

  tags = {
    Name = "sub3"
  }
}

resource "aws_subnet" "sub4" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.1.3.0/24"
  #map_public_ip_on_launch = true

  tags = {
    Name = "sub4"
  }
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "tf_test_ig"
  }
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "aws_route_table"
  }
}


# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "instance_sg"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our elb security group to access
# the ELB over HTTP
resource "aws_security_group" "elb" {
  name        = "elb_sg"
  description = "Used in the terraform"

  vpc_id = aws_vpc.default.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ensure the VPC has an Internet gateway or this step will fail
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_elb" "web" {
  name = "example-elb"

  # The same availability zone as our instance
  subnets = [aws_subnet.sub3.id]

  security_groups = [aws_security_group.elb.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  # The instance is registered automatically

  instances                   = [aws_instance.web.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}

resource "aws_lb_cookie_stickiness_policy" "default" {
  name                     = "lbpolicy"
  load_balancer            = aws_elb.web.id
  lb_port                  = 80
  cookie_expiration_period = 600
}

resource "aws_instance" "web" {
  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = var.aws_amis[var.aws_region]
   
  # The name of our SSH keypair you've created and downloaded
  # from the AWS console.
  #
  # https://console.aws.amazon.com/ec2/v2/home?region=us-west-2#KeyPairs:
  #
  key_name = var.key_name

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id              = aws_subnet.sub2.id
  user_data              = file("userdata.sh")

 root_block_device {
    volume_size = 20 
    volume_type = "gp3"
    encrypted   = true
  }
  #Instance tags

  tags = {
    Name = "elb-example"
  }
}


/*
 * Module: tf_aws_asg_elb
 *
 * This template creates the following resources
 *   - A launch configuration
 *   - A auto-scaling group
 *
 * It requires you create an ELB instance before you use it.
 */

resource "aws_launch_configuration" "launch_config" {
  image_id = var.aws_amis[var.aws_region]
  instance_type = "t2.micro"
  key_name = var.key_name
  security_groups = [aws_security_group.default.id]
  user_data = file("userdata.sh")
  
}

resource "aws_autoscaling_group" "main_asg" {
  # We want this to explicitly depend on the launch config above
  depends_on = ["aws_launch_configuration.launch_config"]

  name = "test_asg"

  vpc_zone_identifier = [aws_subnet.sub3.id, aws_subnet.sub4.id]

  # Uses the ID from the launch config created above
  launch_configuration = aws_launch_configuration.launch_config.id

  max_size = "6"
  min_size = "2"
  desired_capacity = "2"

  health_check_grace_period = 300
  health_check_type = "ELB"

  load_balancers = [aws_elb.web.id]
}


# Create S3 Bucket Resource
resource "aws_s3_bucket" "s3_bucket" {
  bucket = var.bucket_name
  acl    = "public-read"
  
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "PublicReadGetObject",
          "Effect": "Allow",
          "Principal": "*",
          "Action": [
              "s3:GetObject"
          ],
          "Resource": [
              "arn:aws:s3:::${var.bucket_name}/*"
          ]
      }
  ]
}  
EOF
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
 # tags          = var.tags
  force_destroy = true
}

resource "aws_s3_bucket_object" "image_folder" {
    bucket = aws_s3_bucket.s3_bucket.id
    acl    = "private"
    key    = "images/"

}

resource "aws_s3_bucket_object" "log_folders" {
    bucket = aws_s3_bucket.s3_bucket.id
    acl    = "private"
    key    = "logs/"

}

resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.s3_bucket.id

  rule {
    id = "rule-1"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 90
    }

    status = "Enabled"
  }

  rule {
    id = "rule-2"

    filter {
      prefix = "images/"
    }

    expiration {
      days = 90
    }

    status = "Enabled"
  }
}