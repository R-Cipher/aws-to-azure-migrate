terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Fixed private IPs. The security group rules reference each other's IPs,
# so pinning them avoids a dependency loop and matches the lab exactly.
# ---------------------------------------------------------------------------
locals {
  ip = {
    app01 = "172.31.1.79"
    app02 = "172.31.9.42"
    ivm   = "172.31.11.59"
    rep   = "172.31.4.100"
  }

  source_servers = {
    "migration-app01" = local.ip.app01
    "migration-app02" = local.ip.app02
  }

  # Ports the replication appliance uses to reach the source servers
  source_mgmt_ports = {
    winrm-http  = 5985
    winrm-https = 5986
    smb         = 445
    rpc         = 135
  }

  # Minimums from Microsoft docs (memory in MiB, disk in GB)
  min = {
    source      = { memory_mib = 2048, os_disk_gb = 32 }             # Windows Server 2025
    discovery   = { vcpus = 8, memory_mib = 16384, os_disk_gb = 80 } # Azure Migrate appliance
    replication = { vcpus = 8, memory_mib = 16384 }                  # Replication appliance
  }

  # 443 and 9443 from each source server, as one rule per port per IP
  replication_rules = {
    for pair in setproduct([443, 9443], [local.ip.app01, local.ip.app02]) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = "${pair[1]}/32" }
  }
}

# ---------------------------------------------------------------------------
# Network: the region's default VPC (172.31.0.0/16) and its us-east-2a subnet.
# Terraform adopts and tags them; destroy only removes them from state.
# ---------------------------------------------------------------------------
resource "aws_default_vpc" "main" {
  tags = {
    Name = "vpc-migrate-romy"
  }
}

resource "aws_default_subnet" "main" {
  availability_zone = var.availability_zone

  tags = {
    Name = "snet-migrate-romy"
  }
}

# ---------------------------------------------------------------------------
# AMIs: latest Amazon-published Windows Server images
# ---------------------------------------------------------------------------
data "aws_ami" "windows_2025" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }
}

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# Instance type specs, used to check the sizing minimums
data "aws_ec2_instance_type" "source" {
  instance_type = var.source_instance_type
}

data "aws_ec2_instance_type" "discovery" {
  instance_type = var.discovery_instance_type
}

data "aws_ec2_instance_type" "replication" {
  instance_type = var.replication_instance_type
}

# ---------------------------------------------------------------------------
# Security groups: one per role. (AWS reserves the "sg-" name prefix.)
# ---------------------------------------------------------------------------
resource "aws_security_group" "sources" {
  name        = "migrate-sources-sg"
  description = "Source servers: management from the replication appliance, RDP from admin"
  vpc_id      = aws_default_vpc.main.id
  tags        = { Name = "migrate-sources-sg" }
}

resource "aws_security_group" "discovery" {
  name        = "migrate-discovery-sg"
  description = "Discovery appliance: 443/9443 from source servers, RDP from admin"
  vpc_id      = aws_default_vpc.main.id
  tags        = { Name = "migrate-discovery-sg" }
}

resource "aws_security_group" "replication" {
  name        = "migrate-replication-sg"
  description = "Replication appliance: 443/9443 from source servers, RDP from admin"
  vpc_id      = aws_default_vpc.main.id
  tags        = { Name = "migrate-replication-sg" }
}

# Source servers: WinRM, SMB, RPC only from the replication appliance
resource "aws_vpc_security_group_ingress_rule" "sources_mgmt" {
  for_each = local.source_mgmt_ports

  security_group_id = aws_security_group.sources.id
  description       = "${each.key} from replication appliance"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "${local.ip.rep}/32"
}

# Appliances: HTTPS (443) and replication data (9443) only from the two sources
resource "aws_vpc_security_group_ingress_rule" "discovery_replication" {
  for_each = local.replication_rules

  security_group_id = aws_security_group.discovery.id
  description       = "${each.value.port} from source server"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "replication_replication" {
  for_each = local.replication_rules

  security_group_id = aws_security_group.replication.id
  description       = "${each.value.port} from source server"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# RDP from the admin IP on every security group
resource "aws_vpc_security_group_ingress_rule" "rdp" {
  for_each = {
    sources     = aws_security_group.sources.id
    discovery   = aws_security_group.discovery.id
    replication = aws_security_group.replication.id
  }

  security_group_id = each.value
  description       = "RDP from admin"
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = var.admin_cidr
}

# All outbound (Terraform removes the default egress rule, so add it back).
# The appliances need outbound 443 to reach Azure.
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    sources     = aws_security_group.sources.id
    discovery   = aws_security_group.discovery.id
    replication = aws_security_group.replication.id
  }

  security_group_id = each.value
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Instances
# ---------------------------------------------------------------------------
resource "aws_instance" "source" {
  for_each = local.source_servers

  ami                         = data.aws_ami.windows_2025.id
  instance_type               = var.source_instance_type
  subnet_id                   = aws_default_subnet.main.id
  private_ip                  = each.value
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sources.id]
  key_name                    = var.appliance_key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = local.min.source.os_disk_gb
  }

  lifecycle {
    precondition {
      condition     = data.aws_ec2_instance_type.source.memory_size >= local.min.source.memory_mib
      error_message = "Source servers need at least 2 GB RAM (Windows Server 2025 minimum)."
    }
  }

  tags = { Name = each.key }
}

resource "aws_instance" "discovery" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = var.discovery_instance_type
  subnet_id                   = aws_default_subnet.main.id
  private_ip                  = local.ip.ivm
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.discovery.id]
  key_name                    = var.migration_key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = local.min.discovery.os_disk_gb
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_ec2_instance_type.discovery.default_vcpus >= local.min.discovery.vcpus &&
        data.aws_ec2_instance_type.discovery.memory_size >= local.min.discovery.memory_mib
      )
      error_message = "The discovery appliance needs at least 8 vCPUs and 16 GB RAM."
    }
  }

  tags = { Name = "migration-ivm" }
}

resource "aws_instance" "replication" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = var.replication_instance_type
  subnet_id                   = aws_default_subnet.main.id
  private_ip                  = local.ip.rep
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.replication.id]
  key_name                    = var.appliance_key_name

  # OS disk. 80 GB is headroom for a 32 GB-RAM server, not a documented minimum.
  root_block_device {
    volume_type = "gp3"
    volume_size = 80
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_ec2_instance_type.replication.default_vcpus >= local.min.replication.vcpus &&
        data.aws_ec2_instance_type.replication.memory_size >= local.min.replication.memory_mib
      )
      error_message = "The replication appliance needs at least 8 vCPUs and 16 GB RAM."
    }
  }

  tags = { Name = "migration-rep" }
}

# Second disk: the replication appliance needs an OS disk plus a cache/data disk
resource "aws_ebs_volume" "replication_cache" {
  availability_zone = var.availability_zone
  size              = var.replication_cache_disk_gb
  type              = "gp3"

  tags = { Name = "migration-rep-cache" }
}

resource "aws_volume_attachment" "replication_cache" {
  device_name = "xvdf"
  volume_id   = aws_ebs_volume.replication_cache.id
  instance_id = aws_instance.replication.id
}