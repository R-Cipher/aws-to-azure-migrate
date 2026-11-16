variable "aws_region" {
  description = "AWS region for the source environment."
  type        = string
  default     = "us-east-2"
}

variable "availability_zone" {
  description = "Availability Zone for the subnet and all instances."
  type        = string
  default     = "us-east-2a"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (for example 203.0.113.10/32). The only address allowed to RDP."
  type        = string
}

variable "migration_key_name" {
  description = "Existing EC2 key pair used by the discovery appliance."
  type        = string
  default     = "migrationKey"
}

variable "appliance_key_name" {
  description = "Existing EC2 key pair used by the source servers and the replication appliance."
  type        = string
  default     = "applianceKey"
}

# Instance sizes. Terraform checks each one against Microsoft's minimums
# (see "Sizing requirements") and stops at plan time if it's too small.
variable "source_instance_type" {
  description = "Source servers. Windows Server 2025 needs at least 2 GB RAM."
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB
}

variable "discovery_instance_type" {
  description = "Discovery appliance. Needs at least 8 vCPUs and 16 GB RAM."
  type        = string
  default     = "t3.2xlarge" # 8 vCPU, 32 GB
}

variable "replication_instance_type" {
  description = "Replication appliance. Needs at least 8 vCPUs and 16 GB RAM."
  type        = string
  default     = "m7a.2xlarge" # 8 vCPU, 32 GB
}

variable "replication_cache_disk_gb" {
  description = "Second (cache) disk for the replication appliance."
  type        = number
  default     = 600
}