ui = true
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1  # For dev; enable TLS in prod
}
storage "raft" {
  path = "/opt/vault/data"
  node_id = "oracle_node"
}
seal "transit" {
  address = "http://127.0.0.1:8200"
  disable_clustering = true
}
api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"
disable_mlock = true