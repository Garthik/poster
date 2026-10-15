global
    maxconn 300
    log stdout format raw local0

defaults
    mode tcp
    timeout connect 5s
    timeout client 5m
    timeout server 5m

frontend postgres_tls_passthrough
    bind *:5432
    default_backend current_primary

backend current_primary
    option tcp-check
    server current_primary @TARGET@:5432 check inter 2s fall 2 rise 2
