variable "key_name" {
  description = "Name of the SSH keypair to use in AWS."
  default = "web"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

# Redhat
variable "aws_amis" {
  default = {
    "us-east-1" = "ami-06640050dc3f556bb"
  }
}


variable "bucket_name" {
  description = "Name of the S3 bucket. Must be Unique across AWS"
  type        = string
  default = "test-bucket123-4"
}
