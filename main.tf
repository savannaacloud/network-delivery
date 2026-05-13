locals {
  prefix = var.prefix
}

# ── Network (VPC) ──────────────────────────────────────────────────────────
# Outer L2/L3 container. We explicitly set cidr = "" to skip the auto-
# subnet the platform creates by default — we'll attach per-tier subnets
# below.

resource "sws_network" "spoke" {
  name = "${local.prefix}-vpc"
  cidr = ""
}

# ── Subnets (one per tier) ─────────────────────────────────────────────────

resource "sws_subnet" "tiers" {
  for_each = var.subnet_cidrs

  name       = "${local.prefix}-${each.key}-subnet"
  network_id = sws_network.spoke.id
  cidr       = each.value
  ip_version = 4
}

# ── Router + Router Interface ──────────────────────────────────────────────
# One router per VPC; we attach every subnet to it so they can talk to each
# other and reach the public network.

resource "sws_router" "edge" {
  name = "${local.prefix}-router"
}

resource "sws_router_interface" "attach" {
  for_each = sws_subnet.tiers

  router_id = sws_router.edge.id
  subnet_id = each.value.id
}

# ── NAT Gateway ────────────────────────────────────────────────────────────
# NAT Gateway is **console-only** as of provider v0.4 (no sws_nat_gateway
# resource yet). The router above already has snat_enabled by default, so
# subnets get private→internet egress out-of-the-box. If you need a
# dedicated NAT with bandwidth quotas, separate metering, or HA pair —
# create it at https://savannaa.com/networking/nat-gateways and reference
# its id from your instances.

# ── Security Groups + Rules ────────────────────────────────────────────────

resource "sws_security_group" "tiers" {
  for_each    = var.subnet_cidrs
  name        = "${local.prefix}-${each.key}-sg"
  description = "${each.key}-tier security group"
}

# Allow SSH into every tier from the bastion CIDR (or var.bastion_allowed_cidr
# if no bastion).
resource "sws_security_group_rule" "ssh" {
  for_each = sws_security_group.tiers

  security_group_id = each.value.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.bastion_allowed_cidr
}

# Public web tier allows :80 / :443
resource "sws_security_group_rule" "web_http" {
  security_group_id = sws_security_group.tiers["web"].id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "sws_security_group_rule" "web_https" {
  security_group_id = sws_security_group.tiers["web"].id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

# ── Public IPs (Anycast Edge addresses) ────────────────────────────────────
# Allocate `edge_ip_count` static public IPs. Attach via for_each so output
# stays stable across plan/apply.

resource "sws_floating_ip" "edge" {
  count       = var.edge_ip_count
  description = "${local.prefix} edge IP #${count.index + 1}"
}

# ── Bastion ────────────────────────────────────────────────────────────────
# Public SSH-jump host. The provider's bastion resource has a key_name
# auto-fallback (PR #318): if you don't pass a keypair, it creates a
# default one for you. We pass an explicit keypair below for predictability.

resource "sws_keypair" "bastion" {
  count = var.enable_bastion ? 1 : 0
  name  = "${local.prefix}-bastion-key"
}

resource "sws_bastion" "jump" {
  count = var.enable_bastion ? 1 : 0

  name         = "${local.prefix}-bastion"
  network_id   = sws_network.spoke.id
  key_name     = sws_keypair.bastion[0].name
  allowed_cidr = var.bastion_allowed_cidr
  ssh_port     = 22
}

# ── Load Balancer + Listener + Pool ────────────────────────────────────────
# Public L7 LB in front of the web tier. Backend now waits for LB ACTIVE
# before attaching listener/pool (PR #318), so this just works in one apply.

resource "sws_load_balancer" "public" {
  count = var.enable_load_balancer ? 1 : 0

  name          = "${local.prefix}-lb"
  vip_subnet_id = sws_subnet.tiers["web"].id
}

resource "sws_lb_listener" "http" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_id = sws_load_balancer.public[0].id
  protocol         = "HTTP"
  protocol_port    = 80
  name             = "${local.prefix}-http"
}

resource "sws_lb_pool" "web" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_id = sws_load_balancer.public[0].id
  protocol         = "HTTP"
  lb_algorithm     = "ROUND_ROBIN"
  name             = "${local.prefix}-pool-web"
}

# ── CDN ────────────────────────────────────────────────────────────────────

resource "sws_cdn" "edge" {
  count = var.enable_cdn ? 1 : 0

  name = "${local.prefix}-cdn"
  config = jsonencode({
    origin_url   = "https://${var.domain_name}"
    cache_ttl_s  = 3600
    waf_enabled  = true
  })
}

# ── DNS — public Hosted Zone + recordset ───────────────────────────────────
# Public DNS zone the platform serves authoritatively. Subzones of
# savannaa.com / savannaa.ng auto-delegate via the admin-fallback (PR #319).

resource "sws_dns_zone" "public" {
  name        = "${var.domain_name}."   # zones end with a dot
  description = "${local.prefix} public hosted zone"
}

resource "sws_dns_record" "apex" {
  count = var.edge_ip_count > 0 ? 1 : 0

  zone_id  = sws_dns_zone.public.id
  name     = "${var.domain_name}."
  type     = "A"
  ttl      = 300
  records  = [sws_floating_ip.edge[0].address]
}

# ── Private DNS ────────────────────────────────────────────────────────────
# Private split-horizon DNS — resolves only inside the VPC. Used for
# service discovery between tiers without exposing names publicly.

resource "sws_private_dns_zone" "internal" {
  name        = "internal.${var.domain_name}"
  description = "${local.prefix} private split-horizon DNS"
}

# ── Network Peering ────────────────────────────────────────────────────────
# VPC ↔ VPC peering. Optional: set var.peer_network_id to your hub VPC id
# to peer this spoke into a hub. Leave empty to skip.

resource "sws_vpc_peering" "peer" {
  count = var.peer_network_id == "" ? 0 : 1

  name             = "${local.prefix}-peer"
  local_network_id = sws_network.spoke.id
  peer_network_id  = var.peer_network_id
}

# ── Service Discovery, Transit Hub, Private Endpoints, Express Link,
#    Workforce VPN, Site-to-Site VPN, Path Analyzer, Flow Logs, Network
#    Topology ─────────────────────────────────────────────────────────────
#
# These nine products do not yet have first-class terraform resources in
# provider v0.4 — they're console-only. The backend supports them; the
# missing piece is the schema wrapper inside terraform-provider-sws.
#
# Order / configure each from the console:
#
#   Service Discovery    https://savannaa.com/networking/service-discovery
#   Transit Hub          https://savannaa.com/networking/transit-hub
#   Private Endpoints    https://savannaa.com/networking/private-endpoints
#   Express Link         https://savannaa.com/networking/express-link
#   Workforce VPN        https://savannaa.com/networking/client-vpn
#   Site-to-Site VPN     https://savannaa.com/networking/site-to-site-vpn
#   Path Analyzer        https://savannaa.com/networking/reachability
#   Flow Logs            https://savannaa.com/networking/flow-logs
#   Network Topology     https://savannaa.com/networking/topology
#
# Each of those console paths emits a stable resource id you can later
# import into terraform once the corresponding `sws_*` resource ships.
