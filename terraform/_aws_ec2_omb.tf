resource "aws_instance" "omb_instance" {
  count                       = var.instance_qty_omb  
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_omb
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.main.id]
  subnet_id                   = aws_subnet.main[0].id
  associate_public_ip_address = true

  user_data = <<-EOFOMBINSTANCE
#!/bin/bash

set -e

# 1. Define variables for OMB setup
MAVEN_VERSION="3.8.9"
INSTALL_DIR="${var.omb_install_dir}"
BUILD_DIR="${var.omb_build_dir}"

# 2. Create OMB directory structure
mkdir -p $INSTALL_DIR
mkdir -p $INSTALL_DIR/{driver-conf,workloads,results,payload}

# 3. Create Driver Configuration (driver-confluent.yaml)
#-------------------------------------------------------
cat > $INSTALL_DIR/driver-conf/driver-confluent.yaml <<EOFDRIVER
name: ConfluentCloud
driverClass: io.openmessaging.benchmark.driver.kafka.KafkaBenchmarkDriver
reset: false
replicationFactor: 3

commonConfig: |
  bootstrap.servers=${local.pni_bootstrap_endpoint}
  security.protocol=SASL_SSL
  sasl.mechanism=PLAIN
  sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${confluent_api_key.app-benchmark-kafka-api-key.id}' password='${confluent_api_key.app-benchmark-kafka-api-key.secret}';

producerConfig: |
  acks=all
  linger.ms=10
  batch.size=131072

consumerConfig: |
  auto.offset.reset=earliest
  enable.auto.commit=false
  session.timeout.ms=45000
  heartbeat.interval.ms=3000
  request.timeout.ms=60000
  max.poll.records=1000
  # Tune for 180MB/s Egress
  fetch.min.bytes=1048576
  fetch.max.bytes=104857600
  max.partition.fetch.bytes=10485760
  receive.buffer.bytes=10485760

topicConfig: |
  min.insync.replicas=2
EOFDRIVER
#-------------------------------------------------------

# 4. Create Workload Configuration (workload.yaml)
#-------------------------------------------------
cat > $INSTALL_DIR/workloads/workload.yaml <<EOFWORKLOAD
name: ConfluentCloud-60in-180out
topics: 10
partitionsPerTopic: 12

# Scaling for m6i.2xlarge (8 vCPU | 32 GB RAM | Up to 12.5 Gbps)
messageSize: 10240
payloadFile: "$INSTALL_DIR/payload/payload-10Kb.data"
# 60MB/s total (approx 6144 msg/s)
producerRate: 6144

# 180MB/s total egress (3 subscriptions x 60MB/s each)
subscriptionsPerTopic: 3
# Total 120 consumers (1 per partition)
consumerPerSubscription: 4
# Total 20 producer threads
producersPerTopic: 2

warmupDurationMinutes: 3
testDurationMinutes: 10
EOFWORKLOAD
#-------------------------------------------------

# 5. Update and install dependencies
dnf update -y
dnf install -y git java-17-amazon-corretto-devel

# 6. Install Maven 3.8.9 (Linux 2023 comes with maven 3.5.4 which is too old for OMB)
cd /tmp
dnf update -y ca-certificates
wget https://dlcdn.apache.org/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz
tar xzf apache-maven-$MAVEN_VERSION-bin.tar.gz -C /opt

# 7. Link into PATH
ln -sf /opt/apache-maven-$MAVEN_VERSION/bin/mvn /usr/local/bin/mvn
ln -sf /opt/apache-maven-$MAVEN_VERSION/bin/mvn /usr/bin/mvn

# 8. Setup Working Directory
mkdir -p $BUILD_DIR
chown $(whoami) $BUILD_DIR
cd $BUILD_DIR

# 9. Clone Official OMB Repository
if [ ! -d "benchmark" ]; then
  git clone https://github.com/openmessaging/benchmark.git .
fi

# 10. Build OMB using Maven (Using Java 17 as specified)
# Disabling checks to match your Dockerfile logic
mvn clean install -DskipTests -Dspotless.check.skip=true

# 11. Find the built package and extract it
# Using wildcard to match version-agnostic naming
PACKAGE_PATH=$(find package/target/ -name "openmessaging-benchmark-*-bin.tar.gz")
echo "Extracting $PACKAGE_PATH to $INSTALL_DIR..."
tar -xvf "$PACKAGE_PATH" -C $INSTALL_DIR --strip-components=1

# 12. Permissions
chmod +x $INSTALL_DIR/bin/*
echo "-----------------------------------------------"
echo "OMB Setup Complete!"
echo "Run 'bin/benchmark --help' to verify."
echo "-----------------------------------------------"

# 13. Generate payload files
dd if=/dev/urandom of=$INSTALL_DIR/payload/payload-1Kb.data bs=1024 count=1
dd if=/dev/urandom of=$INSTALL_DIR/payload/payload-10Kb.data bs=1024 count=10

# 14. Run OMB
cd $INSTALL_DIR
chown -R $(whoami) $INSTALL_DIR
./bin/benchmark --drivers driver-conf/driver-confluent.yaml workloads/workload.yaml | tee results/omb-run-$(date +%Y%m%d-%H%M%S).log
# To see results in real-time, you can use: ls -t results/ | head -n 1 | xargs -I {} tail -f "results/{}"
EOFOMBINSTANCE

  tags = {
    Name  = "${var.demo_prefix}-ec2_omb-${count.index}-${random_id.id.hex}"
    owner = var.owner
  }
}
