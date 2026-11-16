variable "location" {
  description = "Azure region for the landing zone."
  type        = string
  default     = "westus2"
}

variable "resource_group_name" {
  type    = string
  default = "rg-lab-06-romy"
}