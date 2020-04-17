# Basic AWS configuration which will grab our keys from ENV
provider "aws" {
  region     = "eu-west-2"
  access_key = ""
  secret_key = ""
}

# Our AWS keypair
resource "aws_key_pair" "terraformkey" {
  key_name   = "${terraform.workspace}-terraform-lab"
  public_key = file(var.PATH_TO_PUBLIC_KEY)
}

# Our VPC definition, using a default IP range of 10.0.0.0/16
resource "aws_vpc" "lab-vpc" {
  cidr_block           = var.VPC_CIDR
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Default route required for the VPC to push traffic via gateway
resource "aws_route" "first-internet-route" {
  route_table_id         = aws_vpc.lab-vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab-vpc-gateway.id
}

# Gateway which allows outbound and inbound internet access to the VPC
resource "aws_internet_gateway" "lab-vpc-gateway" {
  vpc_id = aws_vpc.lab-vpc.id
}

# Create our first subnet (Defaults to 10.0.1.0/24)
resource "aws_subnet" "first-vpc-subnet" {
  vpc_id = aws_vpc.lab-vpc.id

  cidr_block        = var.FIRST_SUBNET_CIDR
  availability_zone = "eu-west-2a"

  tags = {
    Name = "First Subnet"
  }
}

# Create our second subnet (Defaults to 10.0.2.0/24)
resource "aws_subnet" "second-vpc-subnet" {
  vpc_id = aws_vpc.lab-vpc.id

  cidr_block        = var.SECOND_SUBNET_CIDR
  availability_zone = "eu-west-2a"

  tags = {
    Name = "Second Subnet"
  }
}

# Set DHCP options for delivering things like DNS servers
resource "aws_vpc_dhcp_options" "first-dhcp" {
  domain_name          = "first.local"
  domain_name_servers  = [var.FIRST_DC_IP, var.PUBLIC_DNS]
  ntp_servers          = [var.FIRST_DC_IP]
  netbios_name_servers = [var.FIRST_DC_IP]
  netbios_node_type    = 2

  tags = {
    Name = "First DHCP"
  }
}

# Associate our DHCP configuration with our VPC
resource "aws_vpc_dhcp_options_association" "first-dhcp-assoc" {
  vpc_id          = aws_vpc.lab-vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.first-dhcp.id
}

# Our first domain controller of the "first.local" domain
resource "aws_instance" "first-dc" {
  ami                         = var.ENVIRONMENT == "deploy" ? data.aws_ami.first-dc.0.image_id : data.aws_ami.latest-windows-server.image_id
  instance_type               = "t2.small"
  key_name                    = aws_key_pair.terraformkey.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.first-vpc-subnet.id
  private_ip                  = var.FIRST_DC_IP
  iam_instance_profile        = var.ENVIRONMENT == "deploy" ? null : aws_iam_instance_profile.ssm_instance_profile.0.name

  tags = {
    Workspace = "${terraform.workspace}"
    Name      = "${terraform.workspace}-First-DC"
  }

  vpc_security_group_ids = [
    aws_security_group.first-sg.id,
  ]
}

# Our second domain controller of the "second.local" domain
resource "aws_instance" "second-dc" {
  ami                         = var.ENVIRONMENT == "deploy" ? data.aws_ami.second-dc.0.image_id : data.aws_ami.latest-windows-server.image_id
  instance_type               = "t2.small"
  key_name                    = aws_key_pair.terraformkey.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.second-vpc-subnet.id
  private_ip                  = var.SECOND_DC_IP
  iam_instance_profile        = var.ENVIRONMENT == "deploy" ? null : aws_iam_instance_profile.ssm_instance_profile.0.name

  tags = {
    Workspace = "${terraform.workspace}"
    Name      = "${terraform.workspace}-Second-DC"
  }

  vpc_security_group_ids = [
    aws_security_group.second-sg.id,
  ]
}

# IAM Role required to access SSM from EC2
resource "aws_iam_role" "ssm_role" {
  name               = "${terraform.workspace}_ssm_role_default"
  count              = var.ENVIRONMENT == "deploy" ? 0 : 1
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ssm_role_policy" {
  role       = aws_iam_role.ssm_role.0.name
  count      = var.ENVIRONMENT == "deploy" ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name  = "${terraform.workspace}_ssm_instance_profile"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  role  = aws_iam_role.ssm_role.0.name
}

# Security group for first.local
resource "aws_security_group" "first-sg" {
  vpc_id = aws_vpc.lab-vpc.id

  # Allow second zone to first
  ingress {
    protocol    = "-1"
    cidr_blocks = [var.SECOND_SUBNET_CIDR]
    from_port   = 0
    to_port     = 0
  }

  ingress {
    protocol    = "-1"
    cidr_blocks = [var.FIRST_SUBNET_CIDR]
    from_port   = 0
    to_port     = 0
  }

  # Allow management from our IP
  ingress {
    protocol    = "-1"
    cidr_blocks = var.MANAGEMENT_IPS
    from_port   = 0
    to_port     = 0
  }

  # Allow global outbound
  egress {
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
  }
}

# Security group for second.local
resource "aws_security_group" "second-sg" {
  vpc_id = aws_vpc.lab-vpc.id

  # Allow secure zone to first
  ingress {
    protocol    = "-1"
    cidr_blocks = [var.FIRST_SUBNET_CIDR]
    from_port   = 0
    to_port     = 0
  }

  ingress {
    protocol    = "-1"
    cidr_blocks = [var.SECOND_SUBNET_CIDR]
    from_port   = 0
    to_port     = 0
  }

  # Allow management from Our IP
  ingress {
    protocol    = "-1"
    cidr_blocks = var.MANAGEMENT_IPS
    from_port   = 0
    to_port     = 0
  }

  # Allow global outbound
  egress {
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
  }
}

# Add first.local MOF's to S3
resource "aws_s3_bucket_object" "first-dc-mof" {
  bucket     = var.SSM_S3_BUCKET
  count      = var.ENVIRONMENT == "deploy" ? 0 : 1
  key        = "Lab/First.mof"
  source     = "../dsc/Lab/First.mof"
  etag       = filemd5("../dsc/Lab/First.mof")
}

# Add second.local MOF's to S3
resource "aws_s3_bucket_object" "second-dc-mof" {
  bucket     = var.SSM_S3_BUCKET
  count      = var.ENVIRONMENT == "deploy" ? 0 : 1
  key        = "Lab/Second.mof"
  source     = "../dsc/Lab/Second.mof"
  etag       = filemd5("../dsc/Lab/Second.mof")
}

# SSM parameters used by DSC
resource "aws_ssm_parameter" "admin-ssm-parameter" {
  name  = "admin"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  type  = "SecureString"
  value = "{\"Username\":\"admin\", \"Password\":\"Password@1\"}"
}

resource "aws_ssm_parameter" "first-admin-ssm-parameter" {
  name  = "first-admin"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  type  = "SecureString"
  value = "{\"Username\":\"first.local\\\\admin\", \"Password\":\"Password@1\"}"
}

resource "aws_ssm_parameter" "regular-user-ssm-parameter" {
  name  = "regular.user"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  type  = "SecureString"
  value = "{\"Username\":\"regular.user\", \"Password\":\"Password@3\"}"
}

resource "aws_ssm_parameter" "roast-user-ssm-parameter" {
  name  = "roast.user"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  type  = "SecureString"
  value = "{\"Username\":\"roast.user\", \"Password\":\"Password@4\"}"
}

resource "aws_ssm_parameter" "asrep-user-ssm-parameter" {
  name  = "asrep.user"
  count = var.ENVIRONMENT == "deploy" ? 0 : 1
  type  = "SecureString"
  value = "{\"Username\":\"asrep.user\", \"Password\":\"Password@5\"}"
}

output "first-dc_ip" {
  value       = "${aws_instance.first-dc.public_ip}"
  description = "Public IP of First-DC"
}

output "second-dc_ip" {
  value       = "${aws_instance.second-dc.public_ip}"
  description = "Public IP of Second-DC"
}

# Apply our DSC via SSM to first.local
resource "aws_ssm_association" "first-dc" {
  name             = "AWS-ApplyDSCMofs"
  association_name = "${terraform.workspace}-First-DC"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.first-dc.id]
  }

  parameters = {
    MofsToApply    = "s3:${var.SSM_S3_BUCKET}:Lab/First.mof"
    RebootBehavior = "Immediately"
  }

  count = var.ENVIRONMENT == "deploy" ? 0 : 1
}

# Apply our DSC via SSM to second.local
resource "aws_ssm_association" "second-dc" {
  name             = "AWS-ApplyDSCMofs"
  association_name = "${terraform.workspace}-Second-DC"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.second-dc.id]
  }

  parameters = {
    MofsToApply    = "s3:${var.SSM_S3_BUCKET}:Lab/Second.mof"
    RebootBehavior = "Immediately"
  }

  count = var.ENVIRONMENT == "deploy" ? 0 : 1
}