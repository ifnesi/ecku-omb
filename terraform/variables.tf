variable "demo_prefix" {
  type    = string
  default = "demo-omb"
}

variable "region" {
  description = "The region in which to create the AWS and Confluent resources."
  type        = string
  default     = "eu-west-1"
}

variable "instance_type_proxy" {
  description = "The EC2 instance type to use for the PNI Proxy."
  type        = string
  default     = "t3.nano"
}

variable "instance_type_omb" {
  description = "The EC2 instance type to use for the OMB client."
  type        = string
  default     = "m6i.2xlarge"
}

variable "instance_qty_omb" {
  description = "Number of EC2 instance(s) to use for the OMB client (Each instance will consume one eCKU ==> Write: ~60MB/s | Read: ~180MB/s)."
  type        = number
  default     = 3
}

variable "aws_account_id" {
  description = "The AWS Account ID (12 digits) in which to create the VPC."
  type        = string
}

variable "owner" {
  description = "The email address of the owner of the resources created by this Terraform configuration."
  type        = string
}

variable "omb_install_dir" {
  description = "The installation directory for OMB on the EC2 instance."
  type        = string
  default     = "/opt/omb"
}

variable "omb_build_dir" {
  description = "The build directory for OMB on the EC2 instance."
  type        = string
  default     = "/tmp/omb-build"
}

# ----------------------------------------
# Confluent Cloud Kafka cluster variables
# ----------------------------------------
variable "stream_governance" {
  type    = string
  default = "ESSENTIALS"
}

# --------------------------------------------------------
# This 'random_id_4' will make whatever you create (names, etc)
# unique in your account.
# --------------------------------------------------------
resource "random_id" "id" {
  byte_length = 4
}

variable "num_eni_per_subnet" {
  description = "Number of ENIs to create per subnet"
  type        = number
  default     = 17
}

variable "client_cidr_blocks" {
  description = "List of client CIDR blocks allowed to access EC2"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}