# =========================
# SQL Server on EC2 (POC - East VPC)
# Uses AWS SQL Server Standard AMI (licensed, pre-configured)
# =========================

# Get latest SQL Server 2022 Standard on Windows Server 2022
data "aws_ami" "sqlserver" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-SQL_2022_Standard-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # Simple user data - just configure firewall and create admin login
  sqlserver_userdata = <<-EOF
    <powershell>
    Start-Transcript -Path C:\sqlserver-setup.log
    
    # Open firewall for SQL Server
    New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    
    # Create admin login
    $sqlcmd = "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\SQLCMD.EXE"
    if (-not (Test-Path $sqlcmd)) {
      $sqlcmd = (Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Recurse -Filter "sqlcmd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    
    if ($sqlcmd) {
      Write-Host "Creating admin login..."
      & $sqlcmd -S localhost -E -Q "CREATE LOGIN [${var.sqlserver_username}] WITH PASSWORD = '${var.sqlserver_password}'; ALTER SERVER ROLE sysadmin ADD MEMBER [${var.sqlserver_username}];"
      Write-Host "Admin login created"
    } else {
      Write-Host "sqlcmd not found - use Windows Authentication or SA login"
    }
    
    Write-Host "SQL Server setup complete!"
    Stop-Transcript
    </powershell>
    EOF
}

# Security group for SQL Server
resource "aws_security_group" "sqlserver" {
  name_prefix = "${var.cluster_name}-sqlserver-"
  description = "Security group for SQL Server POC"
  vpc_id      = module.vpc_east.vpc_id

  # SQL Server port from VPC
  ingress {
    description = "SQL Server from VPC"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [module.vpc_east.vpc_cidr_block]
  }

  # RDP for management (restrict to your IP in production)
  ingress {
    description = "RDP access"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sqlserver"
  }
}

# IAM role for SSM access
resource "aws_iam_role" "sqlserver" {
  name_prefix = "${var.cluster_name}-sqlserver-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sqlserver_ssm" {
  role       = aws_iam_role.sqlserver.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "sqlserver" {
  name_prefix = "${var.cluster_name}-sqlserver-"
  role        = aws_iam_role.sqlserver.name
}

# SQL Server EC2 instance
resource "aws_instance" "sqlserver" {
  ami                    = data.aws_ami.sqlserver.id
  instance_type          = "t3.medium"
  subnet_id              = module.vpc_east.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.sqlserver.id]
  iam_instance_profile   = aws_iam_instance_profile.sqlserver.name

  # Enable public IP for RDP access
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  user_data = local.sqlserver_userdata

  tags = {
    Name = "${var.cluster_name}-sqlserver-poc"
  }

  depends_on = [module.vpc_east]
}

output "sqlserver_ami_used" {
  description = "SQL Server AMI used (AWS SQL Server 2022 Standard)"
  value       = data.aws_ami.sqlserver.id
}
