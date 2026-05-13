terraform {
  required_providers {
    sws = { source = "savannaacloud/sws", version = "~> 0.4" }
  }
}

# Smallest networking footprint: 1 VPC + 1 subnet + 1 router. No bastion,
# no LB, no DNS. Apply this first to verify auth + region work.

resource "sws_network" "vpc" {
  name = "net-minimal-vpc"
  cidr = ""
}

resource "sws_subnet" "main" {
  name       = "net-minimal-subnet"
  network_id = sws_network.vpc.id
  cidr       = "10.99.0.0/24"
  ip_version = 4
}

resource "sws_router" "r" {
  name = "net-minimal-router"
}

resource "sws_router_interface" "attach" {
  router_id = sws_router.r.id
  subnet_id = sws_subnet.main.id
}

output "vpc_id" { value = sws_network.vpc.id }
