
#######################################################################################################
# Variables
#####################################################################################################
variable "subscriptionid" {}
variable "appid" {}
variable "apppassword" {}
variable "tenantid" {}
variable "location" {}
variable "rg_name" {}
#variable "vlan_name" {}
variable "vnet_rg_name" {}
variable "vnet_name" {}
variable "subnet_name" {}
variable "address_prefix" {}
variable "cluster_size" {}
variable "prox_cluster_size" {}
variable "cc_cluster_size" {}
variable "prefix" {}
variable "storage_acc" {}
variable "adminuser" {}
variable "vmsize" {}
variable "vmpublisher" {}
variable "vmoffer" {}
variable "vmsku"{} 
variable "vmversion" {}

#######################################################################################################
# Configure the Microsoft Azure Provider
#######################################################################################################
provider "azurerm" {
   subscription_id = "${var.subscriptionid}"
   client_id       = "${var.appid}"
   client_secret   = "${var.apppassword}"
   tenant_id       = "${var.tenantid}"
}

#######################################################################################################
# Resource group
#######################################################################################################
resource "azurerm_resource_group" "resource_group" {
    name     = "${var.rg_name}"
    location = "${var.location}"
    lifecycle { 
	prevent_destroy=true
    }
}
 
resource "azurerm_availability_set" "availability_group" {
    name = "${var.prefix}-ag"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resource_group.name}"
}


#######################################################################################################
# Network
#######################################################################################################
# # Create a virtual network in the web_servers resource group
# resource "azurerm_virtual_network" "network" {
#   name                = "${var.vlan_name}"
#   address_space       = ["10.135.0.0/16"]
#   location            = "${var.location}"
#   resource_group_name = "${azurerm_resource_group.resource_group.name}"
# }

resource "azurerm_subnet" "subnet" {
  name                 = "${var.subnet_name}"
  resource_group_name  = "${var.vnet_rg_name}"
  virtual_network_name = "${var.vnet_name}"
  address_prefix       = "${var.address_prefix}"
}

resource "azurerm_network_interface" "nic" {
  count		          = "${var.cluster_size}"
  name                = "${var.prefix}-ip-zk${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  ip_configuration {
    name                          = "${var.prefix}-ip-zk${count.index}"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.backend_pool.id}"]
  }
}

resource "azurerm_network_interface" "nic1" {
  count                   = "${var.prox_cluster_size}"
  name                = "${var.prefix}-ip-pr${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  ip_configuration {
    name                          = "${var.prefix}-ip-pr${count.index}"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.backend_pool.id}"]
  }
}

resource "azurerm_network_interface" "nic2" {
  count                   = "${var.cc_cluster_size}"
  name                = "${var.prefix}-ip-cc${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  ip_configuration {
    name                          = "${var.prefix}-ip-cc${count.index}"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.backend_pool.id}"]
  }
}


#######################################################################################################
# Public load balancer
# - Note the backend_address_pool is mapped to servers via the nic definition above
#######################################################################################################
resource "azurerm_public_ip" "pubip" {
    name = "${var.prefix}_pubip"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resource_group.name}"
    public_ip_address_allocation = "static"
    domain_name_label = "${azurerm_resource_group.resource_group.name}"
}

resource "azurerm_lb" "load_balancer" {
    name = "${var.prefix}_lb"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resource_group.name}"

    frontend_ip_configuration {
      name = "${var.prefix}_pubip-frontend"
      public_ip_address_id = "${azurerm_public_ip.pubip.id}"
    }
}

resource "azurerm_lb_backend_address_pool" "backend_pool" {
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.load_balancer.id}"
  name                = "${var.prefix}-backend_address_pool"
}

resource "azurerm_lb_rule" "load_balancer_http_rule" {
  location                       = "${var.location}"
  resource_group_name            = "${azurerm_resource_group.resource_group.name}"
  loadbalancer_id                = "${azurerm_lb.load_balancer.id}"
  name                           = "HTTPRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "${var.prefix}_pubip-frontend"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.backend_pool.id}"
  probe_id                       = "${azurerm_lb_probe.load_balancer_probe.id}"
  depends_on                     = ["azurerm_lb_probe.load_balancer_probe"]
}

resource "azurerm_lb_rule" "load_balancer_https_rule" {
  location                       = "${var.location}"
  resource_group_name            = "${azurerm_resource_group.resource_group.name}"
  loadbalancer_id                = "${azurerm_lb.load_balancer.id}"
  name                           = "HTTPSRule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "${var.prefix}_pubip-frontend"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.backend_pool.id}"
  probe_id                       = "${azurerm_lb_probe.load_balancer_probe.id}"
  depends_on                     = ["azurerm_lb_probe.load_balancer_probe"]
}

resource "azurerm_lb_probe" "load_balancer_probe" {
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.load_balancer.id}"
  name                = "HTTP"
  port                = 80
}  


#######################################################################################################
# Storage Account
#######################################################################################################
resource "azurerm_storage_account" "sa" {
  name                = "${var.storage_acc}"
  resource_group_name = "${azurerm_resource_group.resource_group.name}"
  location            = "${var.location}"
  account_type        = "Standard_LRS"

  tags {
    prefix = "staging"
  }
}

resource "azurerm_storage_container" "sc1" {
  count                 = "${var.cluster_size}"
  name                  = "${var.prefix}-container-${count.index}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  storage_account_name  = "${azurerm_storage_account.sa.name}"
  container_access_type = "private"
}

resource "azurerm_storage_container" "sc2" {
  count                 = "${var.prox_cluster_size}"
  name                  = "${var.prefix}-container-pr${count.index}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  storage_account_name  = "${azurerm_storage_account.sa.name}"
  container_access_type = "private"
}

resource "azurerm_storage_container" "sc3" {
  count                 = "${var.cc_cluster_size}"
  name                  = "${var.prefix}-container-cc${count.index}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  storage_account_name  = "${azurerm_storage_account.sa.name}"
  container_access_type = "private"
}

#Zookeeper / Kafka servers
resource "azurerm_virtual_machine" "zkvm" {
  count                 = "${var.cluster_size}"
  name                  = "${var.prefix}-vm-zk${count.index}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  network_interface_ids = ["${element(azurerm_network_interface.nic.*.id,count.index)}"]
  vm_size               = "${var.vmsize}"
  availability_set_id   = "${azurerm_availability_set.availability_group.id}"

  storage_image_reference {
    publisher = "${var.vmpublisher}"
    offer     = "${var.vmoffer}"
    sku       = "${var.vmsku}"
    version   = "${var.vmversion}"
  }

  storage_os_disk {
    name          = "${var.prefix}-vm-zk${count.index}-osdisk"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc1.*.name,count.index)}/${var.prefix}-vm-zk${count.index}-osdisk.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  storage_data_disk {
    name          = "${var.prefix}-vm-zk${count.index}-datadisk0"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc1.*.name,count.index)}/${var.prefix}-vm-zk${count.index}-datadisk0.vhd"
    disk_size_gb  = "100"
    create_option = "empty"
    lun           = 0
  }

  os_profile {
    computer_name  = "${var.prefix}-vm-zk${count.index}"
    admin_username = "${var.adminuser}"
    admin_password = "not@used@hopefully!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${var.adminuser}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/terra_key.pub")}"
    }
  }

#    host = "${azurerm_network_interface.nic.private_ip_address}"

  connection {
    user = "${var.adminuser}"
    host = "${azurerm_network_interface.nic.private_ip_address}"
    agent = false
    private_key = "${file("~/.ssh/id_rsa")}"
    # Failed to read key ... no key found
    timeout = "30s"
  }

   provisioner "file" { 
     source = "../../../confluent/kafka-build.sh" 
     destination = "/home/${var.adminuser}/kafka-build.sh"
   } 

}

# Proxy Servers
resource "azurerm_virtual_machine" "prvm" {
  count                 = "${var.prox_cluster_size}"
  name                  = "${var.prefix}-vm-pr${count.index}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  network_interface_ids = ["${element(azurerm_network_interface.nic1.*.id,count.index)}"]
  vm_size               = "${var.vmsize}"
  availability_set_id   = "${azurerm_availability_set.availability_group.id}"

  storage_image_reference {
    publisher = "${var.vmpublisher}"
    offer     = "${var.vmoffer}"
    sku       = "${var.vmsku}"
    version   = "${var.vmversion}"
  }

  storage_os_disk {
    name          = "${var.prefix}-vm-pr${count.index}-osdisk"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc2.*.name,count.index)}/${var.prefix}-vm-pr${count.index}-osdisk.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  storage_data_disk {
    name          = "${var.prefix}-vm-pr${count.index}-datadisk0"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc2.*.name,count.index)}/${var.prefix}-vm-pr${count.index}-datadisk0.vhd"
    disk_size_gb  = "100"
    create_option = "empty"
    lun           = 0
  }

  os_profile {
    computer_name  = "${var.prefix}-vm-pr${count.index}"
    admin_username = "${var.adminuser}"
    admin_password = "not@used@hopefully!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${var.adminuser}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/terra_key.pub")}"
    }
  }

#   tags {
#      prefix = "${var.prefix}"
#      nodetype    = "${count.index == 0 ? "master" : "managed"}"
#   }
}

# Control-Center Servers
resource "azurerm_virtual_machine" "ccvm" {
  count                 = "${var.cc_cluster_size}"
  name                  = "${var.prefix}-vm-cc${count.index}"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.resource_group.name}"
  network_interface_ids = ["${element(azurerm_network_interface.nic2.*.id,count.index)}"]
  vm_size               = "${var.vmsize}"
  availability_set_id   = "${azurerm_availability_set.availability_group.id}"

  storage_image_reference {
    publisher = "${var.vmpublisher}"
    offer     = "${var.vmoffer}"
    sku       = "${var.vmsku}"
    version   = "${var.vmversion}"
  }

  storage_os_disk {
    name          = "${var.prefix}-vm-cc${count.index}-osdisk"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc3.*.name,count.index)}/${var.prefix}-vm-cc${count.index}-osdisk.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  storage_data_disk {
    name          = "${var.prefix}-vm-cc${count.index}-datadisk0"
    vhd_uri       = "${azurerm_storage_account.sa.primary_blob_endpoint}${element(azurerm_storage_container.sc3.*.name,count.index)}/${var.prefix}-vm-cc${count.index}-datadisk0.vhd"
    disk_size_gb  = "100"
    create_option = "empty"
    lun           = 0
  }

  os_profile {
    computer_name  = "${var.prefix}-vm-cc${count.index}"
    admin_username = "${var.adminuser}"
    admin_password = "not@used@hopefully!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/${var.adminuser}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/terra_key.pub")}"
    }
  }

#   tags {
#      prefix = "${var.prefix}"
#      nodetype    = "${count.index == 0 ? "master" : "managed"}"
#   }
}

