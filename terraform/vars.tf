# required variables
variable "env" {
  description = "name of the environment to deploy to (dev,dr,blank for prod)"
  default     = "dev"
}

variable "product" {
  description = "name of the ResourceGroup/Product"
  default     = "Monitoring"
}

variable "product_prefix" {
  description = "unique part of the name to give to resources"
  default     = "monitoring"
}

variable "num_vms" {
  description = "The number of virtual machines you will provision. This variable is also used for NICs and PIPs."
  default     = "3"
}

variable "vm" {
  description = "administrator user name"
  type        = "map"

  default = {
    size            = "Standard_DS2_v2"
    drsize          = "Standard_D2S_v3"
    devsize         = "Standard_DS1_v2"
    image_publisher = "Canonical"
    image_offer     = "UbuntuServer"
    image_sku       = "16.04-LTS"
    image_version   = "latest"
    admin_username  = "elk"
    admin_password  = "CHANGEME"

    #ssh_public_key = ""
    #admin_password = "notused"
    disable_password_authentication = false
  }
}

variable "env_vars" {
  description = "address prefixes relevant to environment"
  type        = "map"

  default = {
    onprem = "10.0.0.0/8"

    #PROD
    location    = "northeurope"
    SubID       = ""
    vNetName    = "production"
    SubNetName  = "app"
    SubNetSpace = "10.20.30.0/23"

    #DR
    drlocation    = "westeurope"
    drSubID       = ""
    drvNetName    = "dr"
    drSubNetName  = "app"
    drSubNetSpace = "10.20.60.0/23"

    #DEV
    devlocation    = "northeurope"
    devSubID       = ""
    devvNetName    = "sdlc"
    devSubNetName  = "app"
    devSubNetSpace = "172.20.20.128/25"
  }
}
