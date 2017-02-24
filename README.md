# confluent

## What does it do
Installs Kafka / Zookeeper instances on 3 servers

Installs Schema-Registry / REST Proxy / Connections on 2 servers

Installs Control-Centre on 1 server 

## Pre-req
Ensure terraform environment variables are set . .tf

### Step 1 Prepare kafka build

git clone https://github.com/mgis-architects/confluent

cp confluent-build.ini ~/confluent-build.ini

Modify ~/kafka-build.ini

Modify mediaStrorageAccountDetails ... these are not yet used, so can be removed


### Step 2 Execute the script using the Terraform repo 

git clone https://github.com/mgis-architects/terraform

cd azure/confluent

cp ~/confluent/confluent-azure.tfvars ~/confluent-azure.tfvars

Modify ~/confluent-azure.tfvars

Replace all instance of {userid} with a userid 

terraform apply -var-file=~/confluent-azure.tfvars

### Notes
Installation takes up to 15 minutes
