# Copyright (c) 2019, 2023 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  boot_volume_size = tonumber(lookup(var.shape, "boot_volume_size", 50))
  memory           = tonumber(lookup(var.shape, "memory", 4))
  ocpus            = max(1, tonumber(lookup(var.shape, "ocpus", 1)))
  shape            = lookup(var.shape, "shape", "VM.Standard.E4.Flex")
}

output "id" {
  value = oci_core_instance.bastion.id
}

output "public_ip" {
  value = oci_core_instance.bastion.public_ip
}

resource "oci_core_instance" "bastion" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "bastion-${var.state_id}"
  defined_tags        = var.defined_tags
  freeform_tags       = var.freeform_tags
  shape               = lookup(var.shape, "shape")

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  create_vnic_details {
    assign_public_ip = coalesce(var.public_ip, "none") != "none" ? false : var.is_public
    display_name     = "bastion-${var.state_id}"
    hostname_label   = var.assign_dns ? "b-${var.state_id}" : null
    nsg_ids          = var.nsg_ids
    subnet_id        = var.subnet_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.bastion.rendered
  }

  dynamic "shape_config" {
    for_each = length(regexall("Flex", local.shape)) > 0 ? [1] : []
    content {
      ocpus         = local.ocpus
      memory_in_gbs = (local.memory / local.ocpus) > 64 ? (local.ocpus * 4) : local.memory
    }
  }

  source_details {
    boot_volume_size_in_gbs = local.boot_volume_size
    source_id               = var.image_id
    source_type             = "image"
  }

  lifecycle {
    ignore_changes = [availability_domain, defined_tags, freeform_tags, metadata, source_details, display_name]

    precondition {
      condition     = coalesce(var.image_id, "none") != "none"
      error_message = "Missing image_id for bastion. Check provided value for image_id if image_type is 'custom', or image_os/image_os_version if image_type is 'platform'."
    }
  }

  timeouts {
    create = "60m"
  }
}


###
# This section relates to the fact we cannot attach the
# reserved public ip to the bastion instance
#
# issue: https://github.com/oracle/terraform-provider-oci/issues/1802
###
data "oci_core_private_ips" "bastion" {
  ip_address = oci_core_instance.bastion.private_ip
  subnet_id  = var.subnet_id

  depends_on = [ 
    oci_core_instance.bastion
  ]
}

data "oci_core_public_ip" "bastion" {
  count = coalesce(var.public_ip, "none") != "none" ? 1 : 0
  ip_address = var.public_ip
}

resource "oci_core_public_ip" "bastion" {
  count = coalesce(var.public_ip, "none") != "none" ? 1 : 0

  compartment_id = data.oci_core_public_ip.bastion[0].compartment_id
  display_name   = data.oci_core_public_ip.bastion[0].display_name
  lifetime       = data.oci_core_public_ip.bastion[0].lifetime
  private_ip_id  = data.oci_core_private_ips.bastion.private_ips[0]["id"]

  depends_on = [ 
    data.oci_core_public_ip.bastion
  ]
  
  lifecycle {
    prevent_destroy = true
  }
}
