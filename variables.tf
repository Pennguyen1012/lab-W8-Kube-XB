variable "aws_region" {
  description = "The region which the project will be deployed onto"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "The type of the EC2 instance"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Ubuntu 24.04 AMI ID"
  type        = string
  default     = "ami-002843b0a9e09324a"
}
