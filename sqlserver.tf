# =========================
# SQL Server on EC2 (POC - East VPC)
# =========================

# Get latest Windows Server 2022 base AMI (for initial install)
data "aws_ami" "windows_base" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
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
  sqlserver_ami = var.sqlserver_ami_id != "" ? var.sqlserver_ami_id : data.aws_ami.windows_base.id

  # User data for fresh install - downloads ISO directly (more reliable than SSEI)
  userdata_install = <<-EOF
    <powershell>
    # Log to file for debugging
    Start-Transcript -Path C:\sqlserver-install.log
    
    # Download SQL Server 2022 Developer Edition ISO directly
    $isoUrl = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso"
    $isoPath = "C:\SQL2022.iso"
    
    Write-Host "Downloading SQL Server 2022 Developer ISO (~1.5GB, takes 5-10 minutes)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath -UseBasicParsing
    
    Write-Host "ISO downloaded. Mounting..."
    $mount = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    $setupExe = "$($driveLetter):\setup.exe"
    
    Write-Host "Installing SQL Server 2022 Developer from $setupExe..."
    $installArgs = "/Q /ACTION=Install /FEATURES=SQLENGINE /INSTANCENAME=MSSQLSERVER /SQLSVCACCOUNT=`"NT AUTHORITY\SYSTEM`" /SQLSYSADMINACCOUNTS=`"BUILTIN\Administrators`" /SECURITYMODE=SQL /SAPWD=`"${var.sqlserver_password}`" /TCPENABLED=1 /IACCEPTSQLSERVERLICENSETERMS"
    
    Start-Process -FilePath $setupExe -ArgumentList $installArgs -Wait -NoNewWindow
    
    # Unmount ISO
    Dismount-DiskImage -ImagePath $isoPath
    
    # Wait for SQL Server service to start
    Write-Host "Waiting for SQL Server service..."
    Start-Sleep -Seconds 30
    Start-Service MSSQLSERVER -ErrorAction SilentlyContinue
    
    # Wait for service to be ready
    $maxWait = 60
    $waited = 0
    while ($waited -lt $maxWait) {
      $svc = Get-Service MSSQLSERVER -ErrorAction SilentlyContinue
      if ($svc.Status -eq 'Running') { break }
      Start-Sleep -Seconds 5
      $waited += 5
    }
    
    # Create admin login using sqlcmd
    Write-Host "Creating admin login..."
    $sqlcmd = "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\SQLCMD.EXE"
    if (-not (Test-Path $sqlcmd)) {
      $sqlcmd = (Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Recurse -Filter "sqlcmd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    
    if ($sqlcmd) {
      & $sqlcmd -S localhost -Q "CREATE LOGIN [${var.sqlserver_username}] WITH PASSWORD = '${var.sqlserver_password}'; ALTER SERVER ROLE sysadmin ADD MEMBER [${var.sqlserver_username}];"
    }
    
    # Open firewall
    New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    
    Write-Host "SQL Server 2022 Developer installation complete!"
    Stop-Transcript
    </powershell>
    EOF

  # User data for custom AMI (already has SQL Server)
  userdata_custom = <<-EOF
    <powershell>
    # Custom AMI - SQL Server already installed, just ensure firewall is open
    New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
    </powershell>
    EOF

  sqlserver_userdata = var.sqlserver_ami_id != "" ? local.userdata_custom : local.userdata_install
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
  ami                    = local.sqlserver_ami
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

# =========================
# Auto-create AMI after SQL Server install (only on first deploy)
# =========================

resource "null_resource" "wait_for_sqlserver_install" {
  count = var.sqlserver_ami_id == "" ? 1 : 0

  triggers = {
    instance_id = aws_instance.sqlserver.id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for SQL Server installation to complete (~15 min)..."
      
      # Wait for instance to be running
      aws ec2 wait instance-running --instance-ids ${aws_instance.sqlserver.id} --region ${var.aws_region}
      
      # Wait for instance status checks to pass
      aws ec2 wait instance-status-ok --instance-ids ${aws_instance.sqlserver.id} --region ${var.aws_region}
      
      # Additional wait for SQL Server install (user_data script)
      echo "Instance ready. Waiting 15 minutes for SQL Server installation..."
      sleep 900
      
      echo "SQL Server installation should be complete."
    EOF
  }

  depends_on = [aws_instance.sqlserver]
}

resource "aws_ami_from_instance" "sqlserver" {
  count              = var.sqlserver_ami_id == "" ? 1 : 0
  name               = "sqlserver-2022-developer-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  source_instance_id = aws_instance.sqlserver.id
  description        = "SQL Server 2022 Developer with CDC support"

  tags = {
    Name = "sqlserver-2022-developer"
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [null_resource.wait_for_sqlserver_install]
}

output "sqlserver_ami_id_created" {
  description = "AMI ID created from SQL Server instance (use this for future deploys)"
  value       = var.sqlserver_ami_id == "" ? aws_ami_from_instance.sqlserver[0].id : var.sqlserver_ami_id
}
