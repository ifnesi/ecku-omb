# Open Messaging Benchmark (OMB) on Confluent Cloud

This demo designed for testing of Confluent Cloud Enterprise auto scalability.

It provisions AWS EC2 instance(s) running the [Open Messaging Benchmark (OMB)](https://github.com/openmessaging/benchmark) and a Confluent Cloud Enterprise Kafka cluster.

The Enterprise Kafka clusters will be provisioned with PNI networking:

![aws-pni](docs/aws-pni.png)

![aws-pni-connectivity](docs/aws-pni-connectivity.png)

For more details: https://docs.confluent.io/cloud/current/networking/aws-pni.html

## Prerequisites

- [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [AWS](https://aws.amazon.com/console/) account with permissions to create:
  - VPC
  - Subnets
  - Security groups
  - EC2 instances (amazon_linux_2023)
  - TLS private key
  - Internet gateway
  - Route table
- [Confluent Cloud](https://www.confluent.io/get-started/) account with Cloud resource management access as it will create:
  - Environment and Kafka cluster
  - API key/secret for the cluster
  - Client Quota

## Quick Start

### 1. Clone this repo:

```bash
git clone git@github.com:ifnesi/ecku-omb.git
cd ecku-omb
```

## 2. Terraform Directory Structure

- `variables.tf` – Input variables: region, EC2 instance to run the PNI proxy, EC2 instances to run OMB (default is 3)
- `_aws_.tf` – AWS Terraform configuration
- `_aws_ec2_proxy.tf` – AWS Terraform configuration for the EC2 proxy instance
- `_aws_ec2_omb.tf` – AWS Terraform configuration for the EC2 OMB instance(s)
- `_confluent.tf` – Confluent Terraform configuration
- `outputs.tf` – Useful outputs (instance IPs, instructions)
- `providers.tf` – Terraform providers
- `locals.tf` – Terraform local variables

### 3. Configure variables:

Copy the example env var file and set the corresponding values:
```bash
cp .env_example .env
```
- AWS
  - **TF_VAR_aws_account_id**: Your AWS account number
  - **TF_VAR_owner**: Email address to be set as owner on AWS (tag)
- CONFLUENT
  **- CONFLUENT_CLOUD_API_KEY**: Cloud resource management API key
  - **CONFLUENT_CLOUD_API_SECRET**: Cloud resource management API secret

### 4. Deploy:

```bash
terraform init
terraform plan
```

If everything is ok, apply:

```bash
terraform apply
```

Once completed, get output to continue the demo:

```bash
terraform output demo
```

Follow the instructions as per Terraform output (see example below):

```text
----------------------------
1. CONFLUENT CLOUD RESOURCES
----------------------------
Environment ID.....: env-xxxxxx
Kafka Cluster ID...: lkc-xxxxxx
Kafka REST Endpoint: lkc-xxxxxx-apxxxxxx.eu-west-1.aws.accesspoint.glb.confluent.cloud

-------------------------
2. SSH SETUP INSTRUCTIONS
-------------------------
2.1. Save your private key:
echo '-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEA5WYgeM64q2uSCsbOtM3w6b2G2DlXBIIDCtQ6JH9JN4Jy9xLX
...
...
...
U9i+EYc33w+8wvc4Oo/NAMQJQVH+memJUVadvuIMoyK4YIgBFjc=
-----END RSA PRIVATE KEY-----
' > ~/.ssh/pni-test-key.pem

2.2. Set correct permissions on the private key:
chmod 600 ~/.ssh/pni-test-key.pem

2.3. Connect to your EC2 proxy instance (10.188.141.10):
ssh -i ~/.ssh/pni-test-key.pem ec2-user@x.y.z.w

2.4. Connect to your EC2 OMB instance(s):
OMB Instance #0:
ssh -i ~/.ssh/pni-test-key.pem ec2-user@a.b.c.d  # Public IP address
ssh -i ~/.ssh/pni-test-key.pem ec2-user@10.188.141.55  # Private IP address
-- // --
OMB Instance #1:
ssh -i ~/.ssh/pni-test-key.pem ec2-user@e.f.g.h  # Public IP address
ssh -i ~/.ssh/pni-test-key.pem ec2-user@10.188.141.37  # Private IP address
-- // --
OMB Instance #2:
ssh -i ~/.ssh/pni-test-key.pem ec2-user@i.j.k.l  # Public IP address
ssh -i ~/.ssh/pni-test-key.pem ec2-user@10.188.141.38  # Private IP address
-- // --

2.5. For each EC2 proxy/OMB instances, test connectivity (port 443):
curl --request GET \
   --url https://lkc-xxxxxx-apxxxxxx.eu-west-1.aws.accesspoint.glb.confluent.cloud:443/kafka/v3/clusters/lkc-7vjxvw/topics \
   -u "XXXXXXXXXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

2.6 To see results in real-time on each EC2 OMB instance, you can use:
ls -t /opt/omb/results/ | head -n 1 | xargs -I {} tail -f "/opt/omb/results/{}"

2.7 Exit the EC2 SSH session(s)

----------------------------------------------
3. CONFLUENT CLOUD CONSOLE ACCESS INSTRUCTIONS
----------------------------------------------
3.1. Update the /etc/hosts file on your laptop (the NGINX proxy was set up via Terraform already):
echo "\nx.y.z.w lkc-xxxxxx-apxxxxxx.eu-west-1.aws.accesspoint.glb.confluent.cloud" | sudo tee -a /etc/hosts

3.2. (Optional) Alternatively, you can also send a direct cURL request from your laptop to verify the NGINX proxy was set up correctly:
curl --request GET \
   --url https://lkc-xxxxxx-apxxxxxx.eu-west-1.aws.accesspoint.glb.confluent.cloud:443/kafka/v3/clusters/lkc-7vjxvw/topics \
   -u "XXXXXXXXXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

For more details: https://docs.confluent.io/cloud/current/networking/ccloud-console-access.html#configure-a-proxy
```

## 5. Results

### 5.1 AWS EC2 Instances provisioned

![ec2-instances](docs/ec2-instances.png)

### 5.2 Confluent Cloud Enterprise Cluster

![enterprise-cluster](docs/enterprise-cluster.png)

### 5.3 Enterprise Cluster Throughput

By default there will be three EC2 instances running OMB and each producing at a rate of one eCKU:
- Write: ~60MB/s
- Read: ~180MB/s

![cluster-throughput](docs/cluster-throughput.png)

### 5.4 Confluent Cloud Stream Lineage

![stream-lineage](docs/stream-lineage.png)

For more details: https://docs.confluent.io/cloud/current/stream-governance/stream-lineage.html

### 5.5 fluent Cloud eCKU

During the tests, the Enterprise cluster will scale up to 3 (or possibly 4 eCKUs as each EC2 OMB instance will be producing/consuming data at the limit of one eCKU.

In this example it scaled up to four eCKUs as the total throughput was slighlty over 180 MB/s (write) and 540 MB/s (read).

![ecku](docs/ecku.png)

Confluent Cloud Enterprise clusters can scale back down to zero eCKU, as long as there is no topics and no access.

![ecku-zero](docs/ecku-zero.png)

For more details: https://docs.confluent.io/cloud/current/clusters/cluster-types.html#cluster-provisioning-and-scaling

## 6. Cleanup

To destroy all resources:

```bash
terraform destroy
```

This will delete all AWS and Confluent resources created during this demo.

Enjoy!

Check out Confluent's Developer portal (https://developer.confluent.io/), it has free courses, documents, articles, blogs, podcasts and so many more content to get you up and running with a fully managed Apache Kafka service

Disclaimer: I work for Confluent :wink:
