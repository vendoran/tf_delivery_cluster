# Create the data bag to store our builder keys
resource "chef_role" "delivery-build-node" {
  name = "delivery-build-node"
  run_list = ["recipe[delivery_build]"]
}

# Setup chef-build-node
resource "aws_instance" "chef-build-node" {
  ami = "${var.ami}"
  count = "${var.count}"
  instance_type = "${var.instance_type}"
  subnet_id = "${var.subnet_id}"
  vpc_security_group_ids = ["${var.security_groups_ids}"]
  key_name = "${var.key_name}"
  tags {
    Name = "${format("chef-build-node-%02d", count.index + 1)}"
  }
  root_block_device = {
    delete_on_termination = true
  }
  connection {
    user = "${var.user}"
    key_fle = "${var.private_key_path}"
  }
  depends_on = ["chef_role.delivery-build-node"]

  # For now there is no way to delete the node from the chef-server
  # and also there is no way to customize your `destroy` actions
  # https://github.com/hashicorp/terraform/issues/649
  #
  # Workaround: Force-delete the node before hand
  provisioner "local-exec" {
    command = <<EOF
    knife client delete ${format("chef-build-node-%02d", count.index + 1)} -y
    knife node delete ${format("chef-build-node-%02d", count.index + 1)} -y
    echo 'ugly'
EOF
  }

  # Copies certificates
  provisioner "file" {
    source = ".chef/trusted_certs"
    destination = "/tmp"
  }

  # Configure certificates
  provisioner "remote-exec" {
    inline = [
      "sudo service iptables stop",
      "sudo chkconfig iptables off",
      "sudo mkdir -p /etc/chef",
      "sudo mv /tmp/trusted_certs /etc/chef/."
    ]
  }

  provisioner "chef"  {
    attributes {
      "delivery_build" {
        "delivery-cli" {
          "options" = "--nogpgcheck"
        }
        # "trusted_certs" {
        #   "Delivery-Server-Cert" = "/etc/chef/trusted_certs/.crt"
        #   "Supermarket-Server" = "/etc/chef/trusted_certs/supermarket_server_fqdn.crt"
        # }
      }
    }
    # Perhaps we want to install chefdk on the build-nodes
    # if so, we can skip the chef-client install
    # skip_install = true
    run_list = ["role[delivery-build-node]"]
    node_name = "${format("chef-build-node-%02d", count.index + 1)}"
    secret_key = "${file(".chef/encrypted_data_bag_secret")}"
    server_url = "${var.chef-server-url}"
    validation_client_name = "terraform-validator"
    validation_key = "${file(".chef/terraform-validator.pem")}"
  }
}
