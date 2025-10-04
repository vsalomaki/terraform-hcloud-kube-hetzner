locals {
  user_kustomization_templates             = try(fileset(var.extra_kustomize_folder, "**/*.yaml.tpl"), toset([]))
  user_kustomization_pre_install_templates = try(fileset(var.extra_kustomize_pre_install_folder, "**/*.yaml.tpl"), toset([]))
}

resource "null_resource" "kustomization_user_pre_install_templates" {
  for_each = local.user_kustomization_pre_install_templates

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p $(dirname /var/user_kustomize_preinstall/${each.key})"
    ]
  }

  provisioner "file" {
    content     = templatefile("${var.extra_kustomize_pre_install_folder}/${each.key}", var.extra_kustomize_parameters)
    destination = replace("/var/user_kustomize_preinstall/${each.key}", ".yaml.tpl", ".yaml")
  }

  triggers = {
    manifest_sha1 = "${sha1(templatefile("${var.extra_kustomize_pre_install_folder}/${each.key}", var.extra_kustomize_parameters))}"
  }

  depends_on = [
    null_resource.kustomization
  ]
}

resource "null_resource" "kustomization_user_pre_install_deploy" {
  count = length(local.user_kustomization_pre_install_templates) > 0 ? 1 : 0

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Remove templates after rendering, and apply changes.
  provisioner "remote-exec" {
    # Debugging: "sh -c 'for file in $(find /var/user_kustomize -type f -name \"*.yaml\" | sort -n); do echo \"\n### Template $${file}.tpl after rendering:\" && cat $${file}; done'",
    inline = compact([
      "rm -f /var/user_kustomize_preinstall/**/*.yaml.tpl",
      "echo 'Applying user pre-install kustomization...'",
      "kubectl apply -k /var/user_kustomize_preinstall/",
      var.extra_kustomize_pre_install_post_deploy_commands
    ])
  }

  lifecycle {
    replace_triggered_by = [
      null_resource.kustomization_user_pre_install_templates
    ]
  }

  depends_on = [
    null_resource.kustomization_user_pre_install_templates,
  ]
}

resource "null_resource" "kustomization_user" {
  for_each = local.user_kustomization_templates

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p $(dirname /var/user_kustomize/${each.key})"
    ]
  }

  provisioner "file" {
    content     = templatefile("${var.extra_kustomize_folder}/${each.key}", var.extra_kustomize_parameters)
    destination = replace("/var/user_kustomize/${each.key}", ".yaml.tpl", ".yaml")
  }

  triggers = {
    manifest_sha1 = "${sha1(templatefile("${var.extra_kustomize_folder}/${each.key}", var.extra_kustomize_parameters))}"
  }

  depends_on = [
    null_resource.kustomization,
    null_resource.kustomization_user_pre_install_deploy
  ]
}

resource "null_resource" "kustomization_user_deploy" {
  count = length(local.user_kustomization_templates) > 0 ? 1 : 0

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Remove templates after rendering, and apply changes.
  provisioner "remote-exec" {
    # Debugging: "sh -c 'for file in $(find /var/user_kustomize -type f -name \"*.yaml\" | sort -n); do echo \"\n### Template $${file}.tpl after rendering:\" && cat $${file}; done'",
    inline = compact([
      "rm -f /var/user_kustomize/**/*.yaml.tpl",
      "echo 'Applying user kustomization...'",
      "kubectl apply -k /var/user_kustomize/ --wait=true",
      var.extra_kustomize_deployment_commands
    ])
  }

  lifecycle {
    replace_triggered_by = [
      null_resource.kustomization_user
    ]
  }

  depends_on = [
    null_resource.kustomization_user,
    null_resource.kustomization_user_pre_install_deploy,
  ]
}
