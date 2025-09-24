storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 0
  tls_cert_file = "/vault/tls/tls.crt"
  tls_key_file  = "/vault/tls/tls.key"
}

seal "transit" {
  address = "http://transit:8200"
  disable_clustering = true
}

ui = true

api_addr = "http://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"