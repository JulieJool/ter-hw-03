resource "yandex_vpc_network" "vpc_netology" {
  name        = var.vpc_name
}

resource "yandex_vpc_subnet" "public" {
  name           = var.subnet_a_name
  zone           = var.default_zone
  network_id     = yandex_vpc_network.vpc_netology.id
  v4_cidr_blocks = var.v4_cidr_blocks_a
}

resource "yandex_kms_symmetric_key" "key-a" {
  name              = "bucket-encryption-key"
  description       = "Ключ для шифрования бакета"
  default_algorithm = "AES_256"
  rotation_period   = "8760h" # 1 year
}

resource "yandex_kms_symmetric_key_iam_binding" "public_read" {
  symmetric_key_id = yandex_kms_symmetric_key.key-a.id
  role            = "viewer"
  members         = ["system:allUsers"]  # access for everyone
}

resource "yandex_storage_bucket" "bucket" {
  bucket     = "julie-teplovs-bucket-${random_string.suffix.result}"
  acl        = "public-read"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.key-a.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "yandex_storage_object" "image" {
  bucket = yandex_storage_bucket.bucket.bucket
  key    = "cat.jpg"
  source = "./cat.jpg"
  access_key = var.access_key
  secret_key = var.secret_key
  acl        = "public-read"
  content_type = "image/jpeg"
}

resource "yandex_compute_instance_group" "ig" {
  name                = "lamp-instance-group"
  folder_id           = var.folder_id
  service_account_id  = var.service_account_id
  deletion_protection = false

  instance_template {
    platform_id = "standard-v2"
    resources {
      memory = 2
      cores  = 2
    }
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"
      }
    }
    network_interface {
      network_id = yandex_vpc_network.vpc_netology.id
      subnet_ids = [yandex_vpc_subnet.public.id]
      nat        = true
    }
    metadata = {
      serial-port-enable = 1
      ssh-keys           = "ubuntu:${var.ssh_key_path}"
      bucket_name        = "julie-teplovs-bucket-${random_string.suffix.result}" 
      user-data          = "#cloud-config\n runcmd:\n  - 'export PUBLIC_IPV4=$(curl ifconfig.me)'\n  - 'echo Instance: $(hostname), IP Address: $PUBLIC_IPV4 \n http://julie-teplovs-bucket-${random_string.suffix.result}.storage.yandexcloud.net/cat.jpg | sudo tee /var/www/html/index.html > /dev/null'"
    }
  }

  scale_policy {
    fixed_scale {
      size = 3  
    }
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 2
  }

  allocation_policy {
    zones = [var.default_zone]
  }

  load_balancer {
    target_group_name = "lamp-target-group"
  }

  health_check {
    tcp_options {
      port = 80
    }
  }
}

resource "yandex_lb_network_load_balancer" "lb" {
  name = "lamp-load-balancer"

  listener {
    name = "http"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.ig.load_balancer.0.target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
