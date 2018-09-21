resource "azurerm_resource_group" "rg" {
  name     = "${var.env}${var.product}"
  location = "${var.env_vars["${var.env}location"]}"

  tags {
    AutoShutdownSchedule = ""
    BusinessUnit         = "${var.bu}"
    ContactDetails       = ""
    CostCentre           = ""
    DataClassification   = ""
    ExpirationDate       = "TBC"
    ITEnvironment        = "IT"
    MaintenanceWindows   = "TBC"
    OperatingSystem      = "${var.vm["image_sku"]}"
    ProjectCode          = "${var.env}${var.product}"
    SecurityGrade        = "TBC"
    ServiceName          = "${var.env}${var.product}"
    ServiceTier          = "Platinum"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.env}${var.product_prefix}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  # INBOUND
  security_rule {
    name                       = "SSH-In"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_range     = 22
    source_address_prefix      = "${var.env_vars["onprem"]}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Logstash-In"
    priority                   = 105
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_range     = 5000
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NGINX-In"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Elasticsearch-replication1"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["9200", "9300"]
    source_address_prefix      = "${var.env_vars["${var.env}SubNetSpace"]}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Puppet-In"
    priority                   = 135
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = 8140
    destination_port_range     = 8140
    source_address_prefix      = "${var.env_vars["onprem"]}"
    destination_address_prefix = "*"
  }
}

#STORAGE ACCOUNT
resource "azurerm_storage_account" "sa" {
  name                     = "${var.env}elkmonitoring"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  account_tier             = "Standard"
  account_replication_type = "RAGRS"
}

resource "azurerm_storage_share" "sashare" {
  name                 = "backups"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  storage_account_name = "${azurerm_storage_account.sa.name}"
  quota                = 4096
}

#AVAILABILITY SET
resource "azurerm_availability_set" "av" {
  name                = "${var.env}${var.product_prefix}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  managed             = true
}

data "azurerm_subnet" "subnet" {
  name                 = "${var.env_vars["${var.env}SubNetName"]}"
  virtual_network_name = "${var.env_vars["${var.env}vNetName"]}"
  resource_group_name  = "${var.env_vars["${var.env}vNetName"]}"
}

#LOAD BALANCER
resource "azurerm_lb" "lb" {
  name                = "${var.env}${var.product_prefix}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  frontend_ip_configuration {
    name                          = "LoadBalancerFrontEnd"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = "${data.azurerm_subnet.subnet.subnet.id}"
  }

  depends_on = ["azurerm_availability_set.av"]
}

#LB POOL
resource "azurerm_lb_backend_address_pool" "pool" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  loadbalancer_id     = "${azurerm_lb.lb.id}"
  name                = "${var.env}MonitoringAddressPool"
  depends_on          = ["azurerm_lb.lb"]
}

resource "azurerm_lb_probe" "http" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  loadbalancer_id     = "${azurerm_lb.lb.id}"
  name                = "http"
  port                = 80
  interval_in_seconds = 30
  depends_on          = ["azurerm_lb.lb"]
}

#LB PROBES
resource "azurerm_lb_probe" "https" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  loadbalancer_id     = "${azurerm_lb.lb.id}"
  name                = "https"
  port                = 443
  interval_in_seconds = 30
  depends_on          = ["azurerm_lb.lb"]
}

resource "azurerm_lb_probe" "logstash" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  loadbalancer_id     = "${azurerm_lb.lb.id}"
  name                = "logstash"
  port                = 5000
  interval_in_seconds = 30
  depends_on          = ["azurerm_lb.lb"]
}

#LB RULES
resource "azurerm_lb_rule" "http" {
  resource_group_name            = "${azurerm_resource_group.rg.name}"
  loadbalancer_id                = "${azurerm_lb.lb.id}"
  name                           = "HTTP"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.pool.id}"
  probe_id                       = "${azurerm_lb_probe.http.id}"
  load_distribution              = "Default"
  depends_on                     = ["azurerm_lb.lb"]
}

resource "azurerm_lb_rule" "https" {
  resource_group_name            = "${azurerm_resource_group.rg.name}"
  loadbalancer_id                = "${azurerm_lb.lb.id}"
  name                           = "HTTPS"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.pool.id}"
  probe_id                       = "${azurerm_lb_probe.https.id}"
  load_distribution              = "Default"
  depends_on                     = ["azurerm_lb.lb"]
}

resource "azurerm_lb_rule" "logstash" {
  resource_group_name            = "${azurerm_resource_group.rg.name}"
  loadbalancer_id                = "${azurerm_lb.lb.id}"
  name                           = "logstash"
  protocol                       = "Tcp"
  frontend_port                  = 5000
  backend_port                   = 5000
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.pool.id}"
  probe_id                       = "${azurerm_lb_probe.logstash.id}"
  load_distribution              = "SourceIPProtocol"
  depends_on                     = ["azurerm_lb.lb"]
}

#VM NIC
resource "azurerm_network_interface" "nic" {
  name                      = "${var.env}${var.product_prefix}${count.index}"
  location                  = "${azurerm_resource_group.rg.location}"
  resource_group_name       = "${azurerm_resource_group.rg.name}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
  count                     = "${var.num_vms}"

  ip_configuration {
    name                          = "${var.env}${var.product_prefix}ipconfig${count.index}"
    subnet_id                     = "${data.azurerm_subnet.subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
  }

  depends_on = ["azurerm_availability_set.av"]
}

#VM
resource "azurerm_virtual_machine" "vm" {
  depends_on            = ["azurerm_network_interface.nic"]
  name                  = "${var.env}${var.product_prefix}svr${count.index}"
  location              = "${azurerm_resource_group.rg.location}"
  resource_group_name   = "${azurerm_resource_group.rg.name}"
  availability_set_id   = "${azurerm_availability_set.av.id}"
  network_interface_ids = ["${element(azurerm_network_interface.nic.*.id, count.index)}"]
  vm_size               = "${var.vm["${var.env}size"]}"
  count                 = "${var.num_vms}"

  storage_image_reference {
    publisher = "${var.vm["image_publisher"]}"
    offer     = "${var.vm["image_offer"]}"
    sku       = "${var.vm["image_sku"]}"
    version   = "${var.vm["image_version"]}"
  }

  storage_os_disk {
    name              = "${var.env}${var.product_prefix}svros${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "${var.env}${var.product_prefix}svrdata${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "100"
  }

  os_profile {
    computer_name  = "${var.env}${var.product_prefix}svr${count.index}"
    admin_username = "${var.vm["admin_username"]}"
    admin_password = "${var.vm["admin_password"]}"
  }

  os_profile_linux_config {
    disable_password_authentication = "${var.vm["disable_password_authentication"]}"

    /*
      ssh_keys = [{
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${var.vm["ssh_public_key"]}"
    }]*/
  }

  depends_on = ["azurerm_network_interface.nic"]
}

#TODO:
# Add cloudformation to install puppet manifests

output "ClusterIPs" {
  value = ["${azurerm_network_interface.nic.*.private_ip_address}"]
}

output "LoadBalancerIP" {
  value = ["${azurerm_lb.lb.private_ip_address}"]
}
