# -----------------------------------------------------------------------------
# Availability Zones
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "rosa" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.demo_name}-rosa-vpc"
  }
}

# -----------------------------------------------------------------------------
# Private subnets (one per AZ - used by ROSA HCP worker nodes)
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.rosa.id
  cidr_block        = cidrsubnet(aws_vpc.rosa.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${var.demo_name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# -----------------------------------------------------------------------------
# Public subnets (one per AZ - used by NAT gateway and load balancers)
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.rosa.id
  cidr_block              = cidrsubnet(aws_vpc.rosa.cidr_block, 8, count.index + 128)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.demo_name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "rosa" {
  vpc_id = aws_vpc.rosa.id

  tags = {
    Name = "${var.demo_name}-igw"
  }
}

# -----------------------------------------------------------------------------
# NAT Gateway (single AZ for cost - sufficient for a demo)
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.demo_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "rosa" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.demo_name}-nat"
  }

  depends_on = [aws_internet_gateway.rosa]
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.rosa.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.rosa.id
  }

  tags = {
    Name = "${var.demo_name}-private-rt"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rosa.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rosa.id
  }

  tags = {
    Name = "${var.demo_name}-public-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
