# -------------------------------------------------------
# Confluent Cloud Organization
# -------------------------------------------------------
data "confluent_organization" "cc_org" {
  # This data source fetches the organization details
  # Ensure you have the correct permissions to access the organization
}

# -------------------------------------------------------
# Confluent Cloud Environment
# -------------------------------------------------------
resource "confluent_environment" "benchmark" {
  display_name = "${var.demo_prefix}-${random_id.id.hex}"
  stream_governance {
    package = var.stream_governance
  }
}
output "benchmark" {
  description = "CC Environment"
  value       = resource.confluent_environment.benchmark.id
}

resource "confluent_gateway" "main" {
  display_name = "${var.demo_prefix}-gtw-${random_id.id.hex}"
  environment {
    id = resource.confluent_environment.benchmark.id
  }
  aws_private_network_interface_gateway {
    region = var.region
    zones  = local.availability_zone_ids
  }
}

resource "confluent_access_point" "aws" {
  display_name = "${var.demo_prefix}-ap-${random_id.id.hex}"
  environment {
    id = resource.confluent_environment.benchmark.id
  }
  gateway {
    id = confluent_gateway.main.id
  }
  aws_private_network_interface {
    network_interfaces = aws_network_interface.main[*].id
    account            = var.aws_account_id
  }

  depends_on = [
    aws_network_interface_permission.main
  ]
}

# Run on EC2 instance
# --------------------------------------------------------
# Apache Kafka Cluster
# --------------------------------------------------------
resource "confluent_kafka_cluster" "enterprise" {
  display_name = "${var.demo_prefix}-cluster-${random_id.id.hex}"
  availability = "HIGH"
  cloud        = "AWS"
  region       = var.region
  enterprise {}
  environment {
    id = resource.confluent_environment.benchmark.id
  }

  depends_on = [
    confluent_access_point.aws
  ]
}

resource "confluent_service_account" "app-benchmark" {
  display_name = "${var.demo_prefix}-app-${confluent_kafka_cluster.enterprise.id}"
  description  = "Service account to run benchmark tests"
}

resource "confluent_role_binding" "app-benchmark-kafka-cluster-admin" {
  principal = "User:${confluent_service_account.app-benchmark.id}"
  role_name = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.enterprise.rbac_crn
}

resource "confluent_api_key" "app-benchmark-kafka-api-key" {
  display_name           = "${confluent_service_account.app-benchmark.display_name}-kafka-api-key"
  description            = "Kafka API Key that is owned by 'app-benchmark' service account"
  disable_wait_for_ready = true
  owner {
    id          = confluent_service_account.app-benchmark.id
    api_version = confluent_service_account.app-benchmark.api_version
    kind        = confluent_service_account.app-benchmark.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.enterprise.id
    api_version = confluent_kafka_cluster.enterprise.api_version
    kind        = confluent_kafka_cluster.enterprise.kind

    environment {
      id = resource.confluent_environment.benchmark.id
    }
  }
  depends_on = [
    confluent_role_binding.app-benchmark-kafka-cluster-admin
  ]
}

# Client Quota for Producer and Consumer throughput
# Corrected Resource: Setting high throughput limits for the Service Account
resource "confluent_kafka_client_quota" "infinite-throughput" {
  display_name = "${var.demo_prefix}-inf-throughput-${random_id.id.hex}"
  description  = "High-limit quota for benchmark service account"

  # 1073741824 bytes = 1 GB/s 
  throughput {
    ingress_byte_rate = 1073741824
    egress_byte_rate  = 1073741824
  }

  # FIX: Pass only the ID, do not include "User:"
  principals = [
    confluent_service_account.app-benchmark.id
  ]

  kafka_cluster {
    id = confluent_kafka_cluster.enterprise.id
  }

  environment {
    id = confluent_environment.benchmark.id
  }
}