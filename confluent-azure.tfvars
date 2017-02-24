# Reference existing vnet
vnet_rg_name="{userid}-dev"
vnet_name="{userid}-dev-vnet"
subnet_name="{userid}-dev-subnet1"
address_prefix="10.9.3.0/24"
#
location="West Europe"
rg_name="{userid}-confluent-rg"
cluster_size=3
prox_cluster_size=2
cc_cluster_size=1
prefix="{userid}confluent"
storage_acc="{userid}confluentsa"
adminuser="{userid}"
vmsize="Standard_DS2"
vmpublisher = "RedHat"
vmoffer = "RHEL"
vmsku = "7.3"
vmversion = "latest"
