###############################################################################
# VPC BASE MODULE
#
# Creates a VPC, Internet Gateway, any number of public and private subnets
# (driven by maps so tfvars decide how many and where), route tables and an
# optional single NAT Gateway for private subnets.
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

###############################################################################
# PUBLIC SUBNETS
###############################################################################

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = coalesce(each.value.availability_zone, var.default_availability_zone)
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  lifecycle {
    precondition {
      condition     = coalesce(each.value.availability_zone, var.default_availability_zone, "unset") != "unset"
      error_message = "Subnet '${each.key}' has no availability_zone and no default_availability_zone was supplied."
    }
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  count = length(var.public_subnets) > 0 && var.create_internet_gateway ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

###############################################################################
# PRIVATE SUBNETS (optional) + single NAT gateway (optional)
###############################################################################

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = coalesce(each.value.availability_zone, var.default_availability_zone)

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count = var.create_nat_gateway && length(var.private_subnets) > 0 ? 1 : 0

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count = var.create_nat_gateway && length(var.private_subnets) > 0 ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = merge(var.tags, { Name = "${var.name}-nat" })

  depends_on = [aws_internet_gateway.this]

  lifecycle {
    precondition {
      condition     = length(var.public_subnets) > 0
      error_message = "create_nat_gateway requires at least one public subnet to host the NAT Gateway."
    }
  }
}

resource "aws_route_table" "private" {
  count = length(var.private_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route" "private_nat" {
  count = var.create_nat_gateway && length(var.private_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[0].id
}
