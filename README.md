# Network & Delivery — Savannaa Terraform Module

End-to-end terraform that deploys every **Network & Delivery** product on Savannaa from one root module. 12 are first-class terraform resources today; 9 are console-only with the pages linked from the apply.

## Products covered

### Provider-native resources (terraform creates these directly)

| Product | Resource | Notes |
|---|---|---|
| **Networks** | `sws_network` | The outer VPC. `cidr=""` skips the auto-subnet so you attach your own. |
| **Subnets** | `sws_subnet` | Per-tier CIDRs (web / app / worker by default). |
| **Routers** | `sws_router` + `sws_router_interface` | One router per VPC; attaches every subnet. |
| **Security Groups** | `sws_security_group` + `sws_security_group_rule` | Tier-scoped; module ships SSH + HTTP/HTTPS rules. |
| **Public IPs** | `sws_floating_ip` | Static public addresses you can attach to instances or LBs. Variable controls how many. |
| **Bastions** | `sws_bastion` | Public SSH-jump host. Auto-creates a keypair if you skip `key_name` (PR #318). |
| **Private DNS** | `sws_private_dns_zone` | Split-horizon zone resolving only inside the VPC. |
| **Network Peering** | `sws_vpc_peering` | VPC ↔ VPC peering. Set `peer_network_id` to enable. |
| **Load Balancers** | `sws_load_balancer` + `sws_lb_listener` + `sws_lb_pool` | L7 LB with HTTP listener + round-robin pool. Backend now waits for ACTIVE before attaching dependents (PR #318). |
| **CDN** | `sws_cdn` | Edge caching in front of the LB. Off by default. |
| **DNS · Hosted Zones** | `sws_dns_zone` + `sws_dns_record` | Public authoritative zone. Subzones of `savannaa.com` / `savannaa.ng` auto-delegate (PR #319). |
| **Anycast Edge** | `sws_floating_ip` (multiple) | Anycast addresses are exposed today as `sws_floating_ip` with `edge_ip_count`. A first-class `sws_anycast_endpoint` resource is on the provider roadmap. |

### Console-only products (terraform-import coming)

The platform supports these via the API + console, but the schema wrapper inside `terraform-provider-sws` v0.4 hasn't shipped yet. Order/configure each from the console — every page emits a stable resource id you can later `terraform import` once the matching `sws_*` resource lands.

| Product | Console URL |
|---|---|
| **NAT Gateway** | https://savannaa.com/networking/nat-gateways |
| **Service Discovery** | https://savannaa.com/networking/service-discovery |
| **Transit Hub** | https://savannaa.com/networking/transit-hub |
| **Private Endpoints** | https://savannaa.com/networking/private-endpoints |
| **Express Link** | https://savannaa.com/networking/express-link |
| **Workforce VPN** | https://savannaa.com/networking/client-vpn |
| **Site-to-Site VPN** | https://savannaa.com/networking/site-to-site-vpn |
| **Path Analyzer** | https://savannaa.com/networking/reachability |
| **Flow Logs** | https://savannaa.com/networking/flow-logs |
| **Network Topology** | https://savannaa.com/networking/topology |

> The router this module creates already has SNAT for private→internet egress, so you don't need NAT Gateway unless you want bandwidth quotas / separate metering / HA pair.

---

## Prerequisites

1. A Savannaa account → **API key** from https://savannaa.com/account/api-keys.
2. **terraform** ≥ 1.5 ([install](https://developer.hashicorp.com/terraform/install)).
3. A DNS domain to use for the public/private zone (a free `*.savannaa.com` subzone auto-delegates).

---

## Step-by-step

### 1. Clone

```bash
git clone https://github.com/savannaacloud/network-delivery.git
cd network-delivery
```

### 2. Set credentials

```bash
export SWS_API_URL="https://savannaa.com"
export SWS_API_KEY="sws_..."           # https://savannaa.com/account/api-keys
```

### 3. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars               # set domain_name + tighten bastion_allowed_cidr
```

### 4. Initialise

```bash
terraform init
```

### 5. Preview

```bash
terraform plan
```

With defaults you'll see roughly **20 resources**:

* 1 × VPC, 3 × subnets, 1 × router + 3 × router_interface
* 3 × security_group + 5 × security_group_rule
* 2 × floating_ip
* 1 × bastion + 1 × keypair
* 1 × load_balancer + 1 × listener + 1 × pool
* 1 × public DNS zone + 1 × A record
* 1 × private DNS zone

### 6. Apply

```bash
terraform apply
```

Takes ~3-5 min cold (load balancer amphora boot is the long pole), ~90 s when subsequent applies don't have to rebuild the LB.

### 7. Capture the bastion key

```bash
terraform output -raw bastion_private_key > ~/.ssh/net-demo-bastion.pem
chmod 600 ~/.ssh/net-demo-bastion.pem
ssh -i ~/.ssh/net-demo-bastion.pem ubuntu@$(terraform output -raw bastion_id)   # use public IP from console
```

### 8. Verify the LB is serving

```bash
# Get the VIP
curl -I http://$(terraform output -raw load_balancer_vip)
# You'll get 503 until you attach pool members (sws_lb_member resources, separate apply).
```

### 9. Verify DNS

```bash
# Public hosted zone
dig +short @ns1.savannaa.com $(terraform output -raw public_dns_zone)
# Private split-horizon (works from inside the VPC only)
dig +short @169.254.169.254 some-name.internal.$(terraform output -raw public_dns_zone)
```

### 10. Tear down

```bash
terraform destroy
```

~2 min. Backend auto-handles the awkward bits: LB stuck in PENDING (PR #322), router_interface blocked by FIPs (PR #321), subnet with orphan ports (PR #323), DNS subzone owned by admin (PR #319/320). You should not see any 409s.

---

## Layout

```
network-delivery/
├── README.md                    ← you are here
├── versions.tf                  ← provider pin (sws ~> 0.4)
├── variables.tf                 ← 11 vars (CIDRs, toggles, domain, peering)
├── main.tf                      ← every Network & Delivery resource
├── outputs.tf                   ← VPC/subnet/SG ids, edge IPs, LB VIP, DNS zones
├── terraform.tfvars.example     ← copy → terraform.tfvars and edit
├── .gitignore                   ← keeps state out of the repo
└── examples/
    └── minimal/                 ← 1 VPC + 1 subnet + 1 router; smoke test
```

---

## Hub-and-spoke pattern

Set `peer_network_id` to the network id of a hub VPC and this spoke peers in automatically. The hub VPC isn't created by this module — it's a one-time setup. Reuse this module per spoke:

```hcl
module "spoke_dev" {
  source          = "github.com/savannaacloud/network-delivery"
  prefix          = "dev"
  vpc_cidr        = "10.10.0.0/16"
  peer_network_id = data.terraform_remote_state.hub.outputs.vpc_id
}

module "spoke_prod" {
  source          = "github.com/savannaacloud/network-delivery"
  prefix          = "prod"
  vpc_cidr        = "10.20.0.0/16"
  peer_network_id = data.terraform_remote_state.hub.outputs.vpc_id
}
```

---

## Common gotchas

* **`Unable to create subzone in another tenants zone`** — using `domain_name` like `*.savannaa.com` triggers the admin-fallback (PR #319). It happens automatically; you don't need to do anything. If you see the error, your backend is older than #319 — ask support.
* **Load balancer stuck in PENDING_CREATE** — Octavia amphora boot needs ~30-90 s; backend's listener/pool create now waits up to 120 s (PR #318). If it's longer than that, your region's lb-mgmt-net auto-healer (PR #312) should fire; check `/var/log/savannaa-watchdog-octavia.log`.
* **`router_interface ... required by floating IPs`** — backend auto-disassociates FIPs on destroy (PR #321). If you see the error on apply, you're creating a new subnet in an old router-state — recreate the router.
* **CDN apply succeeds, but origin returns 503** — the CDN config points at `https://${domain_name}`; you need to attach LB pool members + a backend service before the CDN can fetch from origin. Use the Compute module to spin up backend VMs then add `sws_lb_member` resources.

---

## Region toggle

```hcl
region = "ng-lagos-1"     # was "ng-abuja-1"
```

Both regions support every resource in this module.

---

## Support

* Console: https://savannaa.com/networking
* Docs: https://savannaa.com/docs
* Issues with this module: https://github.com/savannaacloud/network-delivery/issues
