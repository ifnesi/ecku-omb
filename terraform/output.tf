# terraform output instructions-pni
output "demo" {
  value = <<-EOFDEMO
----------------------------
1. CONFLUENT CLOUD RESOURCES
----------------------------
Environment ID.....: ${resource.confluent_environment.benchmark.id}
Kafka Cluster ID...: ${confluent_kafka_cluster.enterprise.id}
Kafka REST Endpoint: ${trimprefix(trimsuffix(local.pni_kafka_rest_endpoint, ":443"), "https://")}

-------------------------
2. SSH SETUP INSTRUCTIONS
-------------------------
2.1. Save your private key:
echo '${tls_private_key.main.private_key_pem}' > ~/.ssh/pni-test-key.pem

2.2. Set correct permissions on the private key:
chmod 600 ~/.ssh/pni-test-key.pem

2.3. Connect to your EC2 proxy instance (${aws_instance.proxy.private_ip}):
ssh -i ~/.ssh/pni-test-key.pem ec2-user@${aws_instance.proxy.public_ip}

2.4. Connect to your EC2 OMB instance(s):
${join("\n", [
   for i, instance in aws_instance.omb_instance :
      "OMB Instance #${i}:\nssh -i ~/.ssh/pni-test-key.pem ec2-user@${instance.public_ip}  # Public IP address\nssh -i ~/.ssh/pni-test-key.pem ec2-user@${instance.private_ip}  # Private IP address\n-- // --"
])}

2.5. For each EC2 proxy/OMB instances, test connectivity (port 443):
curl --request GET \
   --url ${local.pni_kafka_rest_endpoint}/kafka/v3/clusters/${confluent_kafka_cluster.enterprise.id}/topics \
   -u "${confluent_api_key.app-benchmark-kafka-api-key.id}:${confluent_api_key.app-benchmark-kafka-api-key.secret}"

2.6 To see results in real-time on each EC2 OMB instance, you can use:
ls -t ${var.omb_install_dir}/results/ | head -n 1 | xargs -I {} tail -f "${var.omb_install_dir}/results/{}"

2.7 Exit the EC2 SSH session(s)

----------------------------------------------
3. CONFLUENT CLOUD CONSOLE ACCESS INSTRUCTIONS
----------------------------------------------
3.1. Update the /etc/hosts file on your laptop (the NGINX proxy was set up via Terraform already):
echo "\n${aws_instance.proxy.public_ip} ${trimprefix(trimsuffix(local.pni_kafka_rest_endpoint, ":443"), "https://")}" | sudo tee -a /etc/hosts

3.2. (Optional) Alternatively, you can also send a direct cURL request from your laptop to verify the NGINX proxy was set up correctly:
curl --request GET \
   --url ${local.pni_kafka_rest_endpoint}/kafka/v3/clusters/${confluent_kafka_cluster.enterprise.id}/topics \
   -u "${confluent_api_key.app-benchmark-kafka-api-key.id}:${confluent_api_key.app-benchmark-kafka-api-key.secret}"

For more details: https://docs.confluent.io/cloud/current/networking/ccloud-console-access.html#configure-a-proxy

EOFDEMO

  sensitive = true
}

output cc_secrets {
     value = <<-EOFSECRETS
---------------------------
1. CONFLUENT CLOUD SECERETS
---------------------------
Environment ID.....: ${resource.confluent_environment.benchmark.id}
Kafka Cluster ID...: ${confluent_kafka_cluster.enterprise.id}
Kafka REST Endpoint: ${trimprefix(trimsuffix(local.pni_kafka_rest_endpoint, ":443"), "https://")}
Kafka API Key......: ${confluent_api_key.app-benchmark-kafka-api-key.id}
Kafka API Secret...: ${confluent_api_key.app-benchmark-kafka-api-key.secret}
      
EOFSECRETS
  sensitive = true
}
