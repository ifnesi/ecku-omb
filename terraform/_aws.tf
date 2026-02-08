provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random CIDR block for VPC (equivalent to network_addr_prefix="10.$((RANDOM % 256)).$((RANDOM % 256))")
resource "random_integer" "network_prefix_1" {
  min = 0
  max = 255
}

resource "random_integer" "network_prefix_2" {
  min = 0
  max = 255
}

# Create VPC (equivalent to aws ec2 create-vpc)
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name  = "${var.demo_prefix}-vpc-${random_id.id.hex}"
    owner = var.owner
  }
}

# Create single security group for demo (both EC2 and ENIs)
resource "aws_security_group" "main" {
  name        = "${var.demo_prefix}-sg-${random_id.id.hex}"
  description = "Demo security group for PNI test (EC2 + ENIs)"
  vpc_id      = aws_vpc.main.id

  # SSH access for EC2
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.client_cidr_blocks
    description = "SSH access"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(var.client_cidr_blocks, [aws_vpc.main.cidr_block])
    description = "HTTPS access"
  }

  # Kafka broker access for ENIs
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = concat(var.client_cidr_blocks, [aws_vpc.main.cidr_block])
    description = "Kafka broker access"
  }

  # https://docs.confluent.io/cloud/current/networking/aws-pni.html#update-the-security-group-to-block-outbound-traffic
  # SECURITY WARNING: For production deployments, restrict egress to egress = [] to remove the default 0.0.0.0/0 egress rule.
  # This demo intentionally uses 0.0.0.0/0 to allow downloading Confluent CLI, Terraform provider, and related dependencies.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name  = "${var.demo_prefix}-sg-${random_id.id.hex}"
    owner = var.owner
  }
}

# Generate SSH key pair automatically
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create key pair for EC2 access
resource "aws_key_pair" "main" {
  key_name   = "${var.demo_prefix}-key-${random_id.id.hex}"
  public_key = tls_private_key.main.public_key_openssh
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name  = "${var.demo_prefix}-gtw-${random_id.id.hex}"
    owner = var.owner
  }
}

# Create route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name  = "${var.demo_prefix}-rt-${random_id.id.hex}"
    owner = var.owner
  }
}

# Create subnets (equivalent to aws ec2 create-subnet loop)
resource "aws_subnet" "main" {
  count = 3

  vpc_id               = aws_vpc.main.id
  cidr_block           = local.subnet_cidrs[count.index]
  availability_zone_id = local.availability_zone_ids[count.index]

  tags = {
    Name  = "${var.demo_prefix}-subnet-${random_id.id.hex}"
    owner = var.owner
  }
}

# Create ENIs (equivalent to enis_create.sh script)
# For each subnet (0, 1, 2), create num_eni_per_subnet ENIs
resource "aws_network_interface" "main" {
  count = 3 * var.num_eni_per_subnet

  subnet_id = aws_subnet.main[floor(count.index / var.num_eni_per_subnet)].id
  security_groups = [aws_security_group.main.id]

  # Calculate private IP: base_ip + (j+1) where j is the ENI number within subnet
  # floor(count.index / var.num_eni_per_subnet) gives subnet index (0, 1, 2)
  # count.index % var.num_eni_per_subnet gives ENI index within subnet (0, 1, ...)
  private_ips = [
    cidrhost(
      aws_subnet.main[floor(count.index / var.num_eni_per_subnet)].cidr_block,
      10 + (count.index % var.num_eni_per_subnet) + 1
    )
  ]

  description = "Confluent PNI-sub-${floor(count.index / var.num_eni_per_subnet)}-eni-${(count.index % var.num_eni_per_subnet) + 1}"

  tags = {
    Name  = "${var.demo_prefix}-sub-${floor(count.index / var.num_eni_per_subnet)}-eni-${(count.index % var.num_eni_per_subnet) + 1}"
    owner = var.owner
  }

  depends_on = [
    confluent_gateway.main
  ]
}

# Create network interface permissions (equivalent to aws ec2 create-network-interface-permission)
resource "aws_network_interface_permission" "main" {
  count = length(aws_network_interface.main)

  network_interface_id = aws_network_interface.main[count.index].id
  permission           = "INSTANCE-ATTACH"
  aws_account_id       = confluent_gateway.main.aws_private_network_interface_gateway[0].account
}

# Associate route table with first subnet (for EC2)
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main[0].id
  route_table_id = aws_route_table.public.id
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
