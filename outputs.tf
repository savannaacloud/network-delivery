output "vpc_id" {
  value = sws_network.spoke.id
}

output "subnet_ids" {
  value = { for k, v in sws_subnet.tiers : k => v.id }
}

output "router_id" {
  value = sws_router.edge.id
}

output "security_group_ids" {
  value = { for k, v in sws_security_group.tiers : k => v.id }
}

output "edge_public_ips" {
  value = [for f in sws_floating_ip.edge : f.address]
}

output "bastion_id" {
  value       = try(sws_bastion.jump[0].id, null)
  description = "Bastion VM id. null when enable_bastion = false."
}

output "bastion_private_key" {
  description = "Bastion SSH key (PEM). Returned once. `terraform output -raw bastion_private_key > ~/.ssh/<prefix>-bastion.pem`."
  value       = try(sws_keypair.bastion[0].private_key, null)
  sensitive   = true
}

output "load_balancer_id" {
  value = try(sws_load_balancer.public[0].id, null)
}

output "load_balancer_vip" {
  value = try(sws_load_balancer.public[0].vip_address, null)
}

output "cdn_id" {
  value = try(sws_cdn.edge[0].id, null)
}

output "public_dns_zone" {
  value = sws_dns_zone.public.name
}

output "private_dns_zone" {
  value = sws_private_dns_zone.internal.name
}

output "vpc_peering_id" {
  value = try(sws_vpc_peering.peer[0].id, null)
}
