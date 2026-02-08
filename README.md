# Open Messaging Benchmark (OMB) on Confluent Cloud

This demo is designed to test **Confluent Cloud Enterprise cluster auto‑scalability (eCKU)** using **Open Messaging Benchmark (OMB)** running from AWS EC2 instances over **Private Networking (AWS PNI)**.

It provisions:

- One **AWS EC2** instance to work as a proxy for local access to the PNI Kafka cluster.
- One or more **AWS EC2** instances running the [Open Messaging Benchmark (OMB)](https://openmessaging.cloud/docs/benchmarks/kafka/).
- A **Confluent Cloud Enterprise Kafka cluster** reachable **only via Private Networking (PNI)** from your AWS VPC.

You can then:

- Generate sustained load against the Enterprise cluster.
- Observe **throughput** and **automatic eCKU scaling** in Confluent Cloud.
- Validate **end‑to‑end private connectivity** and optional **proxy‑based Console access**.

## 1. Architecture Overview

At a high level, this demo deploys the following components in your AWS account and Confluent Cloud:

- **AWS VPC**
  - Subnets for:
    - **PNI proxy EC2 instance** (running NGINX for Console/API access).
    - **OMB worker EC2 instances** (OMB Kafka clients).
  - Security groups, route tables, Internet Gateway as needed for provisioning and outbound access.

- **Confluent Cloud**
  - **Environment** and **Enterprise Kafka cluster** created via Terraform.
  - Cluster networking configured as **AWS Private Networking (PNI)**.
  - **Client quota** and **API key/secret** for the cluster.

- **Connectivity**
  - The Enterprise cluster is reachable **privately** from the EC2 instances via PNI. No direct public internet access to the brokers.
  - An **NGINX proxy** on the EC2 proxy instance allows:
    - Console/API access from your laptop via a `/etc/hosts` override.
    - Direct REST calls to the Kafka REST endpoint through PNI.

PNI and Console access are documented in more detail here:

- **AWS Private Networking (PNI)**: https://docs.confluent.io/cloud/current/networking/aws-pni.html  
- **Console access via proxy**: https://docs.confluent.io/cloud/current/networking/ccloud-console-access.html#configure-a-proxy

### Network diagrams

#### Logical AWS PNI configuration

![aws-pni](docs/aws-pni.png)

#### End‑to‑end connectivity path

![aws-pni-connectivity](docs/aws-pni-connectivity.png)

## 2. What Gets Provisioned

After a successful `terraform apply` (details in the section **7. Quick Start**), you will have:

1. **Confluent Cloud resources**

   - **Environment ID** (e.g. `env-xxxxxx`)
   - **Enterprise Kafka cluster ID** (e.g. `lkc-xxxxxx`)
   - **Kafka REST endpoint** over PNI (e.g. `lkc-xxxxxx-apxxxxxx.eu-west-1.aws.accesspoint.glb.confluent.cloud`)

2. **AWS resources**

   - VPC, subnets, route tables, Internet Gateway and security groups.
   - **EC2 proxy instance** (for NGINX/proxy and SSH jump host).
     - Default instance type is **t3.nano** (see Terraform variable `instance_type_proxy`).
   - **`N` EC2 OMB worker instances** (default `N=3`, see Terraform variable `instance_qty_omb`).
     - Default instance type is **m6i.2xlarge** (see Terraform variable `instance_type_omb`).
   - TLS private key and associated configuration to allow SSH access from your laptop.

3. **Benchmark configuration**

   - OMB installed and configured on each OMB EC2 instance.
   - Local directories for OMB results (e.g. `/opt/omb/results/`).

## 3. Confluent Cloud Enterprise Cluster & eCKU Behaviour

This demo focuses on **Enterprise clusters** in Confluent Cloud that support **elastic scaling in units of eCKU**.

Key aspects:

- **Baseline throughput per OMB instance**

  Each OMB EC2 instance is configured to produce at around **one eCKU** of throughput:

  - **Write**: ~60 MB/s  
  - **Read**: ~180 MB/s  

With three OMB instances running, you should see approximately three eCKUs worth of load. In the sample run, the total throughput slightly exceeded this, causing the cluster to scale up to **four eCKUs**.

- **Scaling behaviour**
  - Cluster automatically scales **up** as throughput increases (subject to limits and quota).
  - Cluster can scale **down to zero eCKU** when there are **no topics and no access** (no traffic or credentials in use).
  - For more details, see **Cluster provisioning and scaling**:  
    https://docs.confluent.io/cloud/current/clusters/cluster-types.html#cluster-provisioning-and-scaling

During the demo, use the **Confluent Cloud Metrics** UI to monitor:

- **Throughput charts** (bytes in/out).
- **eCKU utilisation and scaling events**.
- Any back‑pressure or throttling surfaced via **client quota**.

## 4. Private Networking (PNI) Details

The Enterprise Kafka cluster is provisioned with **AWS PNI networking**:

- **Traffic path**
  - OMB workloads and the NGINX proxy reach the cluster via **private connectivity** from your AWS VPC.
  - The public Confluent endpoints are not used for data plane in this demo.

See the Confluent docs for proxy‑based Console access:  
https://docs.confluent.io/cloud/current/networking/ccloud-console-access.html#configure-a-proxy

## 5. Prerequisites

You need:

- [**Terraform CLI**(https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)] installed.
- An [**AWS**](https://aws.amazon.com/console/) account with permissions to create:
  - VPC, subnets, security groups
  - EC2 instances (Amazon Linux 2023)
  - TLS key pair
  - Internet Gateway and route tables
- A [**Confluent Cloud**](https://www.confluent.io/lp/tryfree/) account with **Cloud resource management** access to create:
  - An environment and Enterprise Kafka cluster
  - Cluster API key/secret
  - Client quota

Recommended:

- Access to the **Confluent Cloud Console** for viewing metrics and Stream Lineage.
- Permissions to create necessary VPC endpoints and networking artefacts as per PNI documentation.

## 6. Terraform Layout

The Terraform configuration is split across several files for clarity:

- `variables.tf` – Input variables (region, number of EC2 instances for proxy and OMB).
- `_aws_.tf` – AWS‑level networking configuration.
- `_aws_ec2_proxy.tf` – EC2 proxy instance (PNI NGINX and SSH entry point).
- `_aws_ec2_omb.tf` – EC2 instances running OMB workers.
- `_confluent.tf` – Confluent Cloud resources (environment, cluster, quota, API keys).
- `outputs.tf` – Useful outputs (instance IPs, REST endpoint, demo instructions).
- `providers.tf` – Terraform providers (AWS, Confluent Cloud).
- `locals.tf` – Local values and naming conventions.

Refer to `variables.tf` for the complete list of configurable inputs.

## 7. Quick Start

### 7.1. Clone the repository

```bash
git clone git@github.com:ifnesi/ecku-omb.git
cd ecku-omb
```

### 7.2. Configure environment variables

Copy the example environment file and then edit `.env` to match your environment:

```bash
cp .env_example .env
```

Required variables include:

- **AWS**
  - `TF_VAR_aws_account_id` – Your AWS account number.
  - `TF_VAR_owner` – Email address to be set as an owner tag on AWS resources.

- **Confluent Cloud**
  - `CONFLUENT_CLOUD_API_KEY` – Cloud resource management API key.
  - `CONFLUENT_CLOUD_API_SECRET` – Cloud resource management API secret.

Follow [these steps](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/manage-api-keys.html#add-an-api-key) to learn how to create the Cloud resource management API key/secret.

Check `.env` and `variables.tf` for any additional optional variables you may want to override (e.g. region, number of OMB instances).

### 7.3. Initialise and plan

```bash
terraform init
terraform plan
```

Review the plan to confirm the resources that will be created.

### 7.4. Apply

If the plan looks good:

```bash
terraform apply
```

When Terraform completes, capture the demo output:

```bash
terraform output demo
```

This will print:

- Confluent Cloud environment and cluster IDs.
- Kafka REST endpoint.
- SSH instructions for the proxy and OMB instances.
- cURL examples for validating connectivity and NGINX proxy.

See example below:

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

## 8. Running the Demo Step‑by‑Step

The `demo` output includes a complete set of commands. Below is the logical flow, using the same steps for clarity.

### 8.1. SSH setup

1. **Save your private key** (as printed in the output):

```bash
echo '-----BEGIN RSA PRIVATE KEY-----
...
...
-----END RSA PRIVATE KEY-----' > ~/.ssh/pni-test-key.pem
```

2. **Set permissions**:

```bash
chmod 600 ~/.ssh/pni-test-key.pem
```

3. **Connect to the proxy instance**:

```bash
ssh -i ~/.ssh/pni-test-key.pem ec2-user@<PROXY_PUBLIC_IP>
```

4. **From the proxy, connect to each OMB instance** (using public or private IPs, as printed):

```bash
# Example for OMB instance #0
ssh -i ~/.ssh/pni-test-key.pem ec2-user@<OMB0_PUBLIC_IP>   # Public

# ... repeat for OMB instance #1, #2, etc.
```

### 8.2. Validate PNI connectivity from each instance

- **From EC2 to Kafka REST**

For each EC2 proxy/OMB instance, you can verify connectivity to the REST endpoint on **port 443**:

- DNS for the Kafka REST endpoint resolves correctly inside the VPC.
- TLS and authentication work.
- Connectivity flows over PNI (no public internet path).

```bash
curl --request GET \
    --url https://<KAFKA_REST_ENDPOINT>:443/kafka/v3/clusters/<CLUSTER_ID>/topics \
    -u "<API_KEY>:<API_SECRET>"
```

- **From your laptop to Kafka REST / Console**

  After Terraform has configured the NGINX proxy, you can:

  1. Add a host mapping on your laptop (`/etc/hosts`):

```bash
echo "<PROXY_PUBLIC_IP> <KAFKA_REST_ENDPOINT>" | sudo tee -a /etc/hosts
```

  2. Send a direct cURL from your laptop via the proxy:

```bash
curl --request GET \
    --url https://<KAFKA_REST_ENDPOINT>:443/kafka/v3/clusters/<CLUSTER_ID>/topics \
    -u "<API_KEY>:<API_SECRET>"
```

### 8.3. Observe OMB results in real‑time

On each OMB instance, you can follow the latest OMB result file:

```bash
ls -t /opt/omb/results/ | head -n 1 | xargs -I {} tail -f "/opt/omb/results/{}"
```

This lets you see the benchmark progress and per‑run statistics.

### 8.4. Exit SSH sessions

Once you have finished inspecting the instances and results:

- Exit from OMB instances.
- Exit from the proxy instance.

## 9. Visualising Results in Confluent Cloud

The **Results** section in this repo is mapped to screenshots and key views:

### 9.1. AWS EC2 Instances

View the EC2 console to confirm the **proxy** and **OMB worker** instances are running.

![ec2-instances](docs/ec2-instances.png)

### 9.2. Confluent Cloud Enterprise Cluster

In the Confluent Cloud Console:

- Open the **Enterprise cluster**.
- Check **Cluster settings**, **Network** tab to confirm PNI networking.

![enterprise-cluster](docs/enterprise-cluster.png)

### 9.3. Enterprise Throughput and Scaling

In **Metrics** for the cluster:

- Monitor **bytes in/out** and **client throughput**.
- Watch for scale‑out events as OMB drives load.

![cluster-throughput](docs/cluster-throughput.png)

By default (three OMB instances at ~1 eCKU each), you should see approximately:

- **Write**: ~180 MB/s aggregate  
- **Read**: ~540 MB/s aggregate  

…and auto‑scale to 3–4 eCKUs depending on actual throughput.

### 9.4. Stream Lineage

If Stream Governance is enabled:

Open **Stream Lineage** in the Confluent Cloud Console to see producer/consumer relationships.

![stream-lineage](docs/stream-lineage.png)

More details: https://docs.confluent.io/cloud/current/stream-governance/stream-lineage.html

### 9.5. eCKU Scaling Over Time

Use the cluster metrics view to visualise **eCKU over time** and confirm **scale up** and **scale down to zero** once the test completes and topics are removed.

![ecku](docs/ecku.png)

![ecku-zero](docs/ecku-zero.png)

## 10. Cleanup

To destroy **all** resources created by this demo (AWS and Confluent Cloud), run:

```bash
terraform destroy
```

This will:

- Delete the Confluent Cloud environment, Enterprise cluster, and related resources.
- Tear down AWS networking, EC2 instances, and associated infrastructure.

## 11. Additional Resources

- **Confluent Developer Portal** – free courses, docs, articles, blogs, podcasts and more to help you get started with managed Apache Kafka:  
  https://developer.confluent.io/
- **PNI documentation** – architecture and supported regions:  
  https://docs.confluent.io/cloud/current/networking/aws-pni.html
- **Cluster types and scaling**:  
  https://docs.confluent.io/cloud/current/clusters/cluster-types.html#cluster-provisioning-and-scaling

Disclaimer: I work for Confluent :wink:
