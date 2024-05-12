storage "raft" {
  path    = "/tmp/vault-data"
  node_id = "local-node"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = "true"
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui = true

// less secure, but mlock requires root
disable_mlock = true