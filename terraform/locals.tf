locals {
  network_addr_prefix = "10.${random_integer.network_prefix_1.result}.${random_integer.network_prefix_2.result}"
  vpc_cidr_block = "${local.network_addr_prefix}.0/24"

  # Calculate subnet CIDRs (equivalent to subnet_cidr="$network_addr_prefix.$((i * 64))/26")
  subnet_cidrs = [
    "${local.network_addr_prefix}.0/26", # i=0: 0/26
    "${local.network_addr_prefix}.64/26", # i=1: 64/26
    "${local.network_addr_prefix}.128/26" # i=2: 128/26
  ]

  # Calculate base IPs (equivalent to base_ips+=("$network_addr_prefix.$((i * 64 + 10))"))
  base_ips = [
    "${local.network_addr_prefix}.10", # i=0: 0 + 10 = 10
    "${local.network_addr_prefix}.74", # i=1: 64 + 10 = 74
    "${local.network_addr_prefix}.138" # i=2: 128 + 10 = 138
  ]
}

locals {
  # Take the first 3 AZ IDs in the selected region
  availability_zone_ids = slice(data.aws_availability_zones.available.zone_ids, 0, 3)
}

locals {
  pni_kafka_rest_endpoint = [for endpoint in confluent_kafka_cluster.enterprise.endpoints : endpoint.rest_endpoint if endpoint.access_point_id == confluent_access_point.aws.id][0]
  pni_bootstrap_endpoint = [for endpoint in confluent_kafka_cluster.enterprise.endpoints : endpoint.bootstrap_endpoint if endpoint.access_point_id == confluent_access_point.aws.id][0]
}
