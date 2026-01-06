# =========================
# VPC Peering: us-east-1 <-> us-west-2
# =========================

# Create peering connection (requester in us-east-1)
resource "aws_vpc_peering_connection" "east_west" {
  vpc_id      = module.vpc_east.vpc_id
  peer_vpc_id = module.vpc_west.vpc_id
  peer_region = "us-west-2"
  auto_accept = false

  tags = {
    Name = "${var.cluster_name}-east-west-peering"
    Side = "Requester"
  }
}

# Accept peering connection in us-west-2
resource "aws_vpc_peering_connection_accepter" "west_accept" {
  provider                  = aws.west
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id
  auto_accept               = true

  tags = {
    Name = "${var.cluster_name}-east-west-peering"
    Side = "Accepter"
  }
}

# Enable DNS resolution for peering (requester side)
resource "aws_vpc_peering_connection_options" "east_options" {
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# Enable DNS resolution for peering (accepter side)
resource "aws_vpc_peering_connection_options" "west_options" {
  provider                  = aws.west
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# -----------------------
# Route tables: East -> West
# -----------------------

# Route from East private subnets to West VPC
resource "aws_route" "east_private_to_west" {
  count                     = length(module.vpc_east.private_route_table_ids)
  route_table_id            = module.vpc_east.private_route_table_ids[count.index]
  destination_cidr_block    = module.vpc_west.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# Route from East public subnets to West VPC
resource "aws_route" "east_public_to_west" {
  count                     = length(module.vpc_east.public_route_table_ids)
  route_table_id            = module.vpc_east.public_route_table_ids[count.index]
  destination_cidr_block    = module.vpc_west.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# -----------------------
# Route tables: West -> East
# -----------------------

# Route from West private subnets to East VPC
resource "aws_route" "west_private_to_east" {
  provider                  = aws.west
  count                     = length(module.vpc_west.private_route_table_ids)
  route_table_id            = module.vpc_west.private_route_table_ids[count.index]
  destination_cidr_block    = module.vpc_east.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# Route from West public subnets to East VPC
resource "aws_route" "west_public_to_east" {
  provider                  = aws.west
  count                     = length(module.vpc_west.public_route_table_ids)
  route_table_id            = module.vpc_west.public_route_table_ids[count.index]
  destination_cidr_block    = module.vpc_east.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.east_west.id

  depends_on = [aws_vpc_peering_connection_accepter.west_accept]
}

# -----------------------
# Security Group Rules for VPC Peering
# Allow GridGain traffic between clusters
# -----------------------

# Allow West VPC to reach East cluster nodes on GridGain ports
resource "aws_security_group_rule" "east_allow_west_gridgain" {
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_west.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
  description       = "Allow GridGain client port from West VPC"
}

resource "aws_security_group_rule" "east_allow_west_cluster" {
  type              = "ingress"
  from_port         = 3344
  to_port           = 3344
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_west.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
  description       = "Allow GridGain cluster port from West VPC"
}

# Allow East VPC to reach West cluster nodes on GridGain ports
resource "aws_security_group_rule" "west_allow_east_gridgain" {
  provider          = aws.west
  type              = "ingress"
  from_port         = 10800
  to_port           = 10800
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_east.vpc_cidr_block]
  security_group_id = module.eks_west.node_security_group_id
  description       = "Allow GridGain client port from East VPC"
}

resource "aws_security_group_rule" "west_allow_east_cluster" {
  provider          = aws.west
  type              = "ingress"
  from_port         = 3344
  to_port           = 3344
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_east.vpc_cidr_block]
  security_group_id = module.eks_west.node_security_group_id
  description       = "Allow GridGain cluster port from East VPC"
}
