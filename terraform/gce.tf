# mesh expansion as code.

variable "meshconfig" {
  type = "map"
  default = {
    "project" = "istio-gce-perf"
    "gce_image" = "debian-cloud/debian-9"
  }
}

resource "google_compute_instance" "default" {
  name         = "tr-example-${format("%d", count.index + 1)}"
  project      = "${var.meshconfig["project"]}"
  machine_type = "n1-standard-1"
  zone         = "us-central1-a"
  count        = 2

  tags = ["foo", "bar"]

  boot_disk {
    initialize_params {
      image = "${var.meshconfig["gce_image"]}"
    }
  }

  // Local SSD disk
  scratch_disk {
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  metadata = {
    foo = "bar"
  }
  
  # script to modify the host of the gateway ip.
  metadata_startup_script = "echo hi > /test.txt"

  # service_account {
  #   scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  # }
}