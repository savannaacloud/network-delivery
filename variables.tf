variable "prefix" {
  description = "Prefix for every resource name so multiple environments coexist."
  type        = string
  default     = "net-demo"
}

variable "region" {
  description = "Savannaa region: ng-abuja-1 or ng-lagos-1."
  type        = string
  default     = "ng-abuja-1"
}

variable "vpc_cidr" {
  description = "Outer network CIDR. The module carves three /24 subnets from it."
  type        = string
  default     = "10.50.0.0/16"
}

# Per-tier subnet CIDRs (must be inside vpc_cidr)
variable "subnet_cidrs" {
  description = "Map of tier-name → CIDR for each subnet."
  type        = map(string)
  default = {
    web    = "10.50.1.0/24"
    app    = "10.50.2.0/24"
    worker = "10.50.3.0/24"
  }
}

variable "domain_name" {
  description = "Top-level zone for both the public DNS hosted zone and the private DNS zone. Use one you control or a *.savannaa.com subzone (the platform auto-delegates *.savannaa.com)."
  type        = string
  default     = "net-demo.savannaa.com"
}

variable "ssh_public_key_file" {
  description = "Path to an existing SSH public key file (used by the bastion). BYO — provider doesn't generate keys."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "peer_network_id" {
  description = "Existing network ID to peer this VPC with. Empty disables the peering resource."
  type        = string
  default     = ""
}

# ── Toggles (heavy / opinionated resources) ────────────────────────────────

variable "enable_load_balancer" {
  description = "Spin up an L7 load balancer in front of the web subnet."
  type        = bool
  default     = true
}

variable "enable_cdn" {
  description = "Provision a CDN distribution that fronts the load balancer."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Provision a public bastion host for SSH-jump access."
  type        = bool
  default     = true
}

variable "bastion_allowed_cidr" {
  description = "CIDR allowed to reach the bastion's SSH port. Default 0/0 — tighten in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "edge_ip_count" {
  description = "How many static public IPs to allocate at the edge (separate from per-VM floating IPs)."
  type        = number
  default     = 2
}


variable "dns_admin_email" {
  description = "SOA admin email for the public DNS zone (Designate uses this in the SOA RNAME field with @ replaced by .)."
  type        = string
  default     = "hostmaster@savannaa.com"
}
