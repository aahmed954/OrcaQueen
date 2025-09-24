vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id = "litellm_role_id"
      secret_id = "{{ with secret "approle/litellm" }}{{ .Data.secret_id }}{{ end }}"
    }
  }
}

cache {
  use_auto_auth_token = false
}

template {
  source = "/local/secrets.ctmpl"
  destination = "/secrets/secrets.env"
  command = "chmod 600 /secrets/secrets.env"
}

template_config {
  exit_on_retry_failure = true
}

pid_file = "/tmp/agent.pid"

auto_auth {
  sink {
    log_level = "info"
  }
}

log_level = "info"