# nginx-honeypot

NGINX honeypot with lots of honey for "flies". 

> [!IMPORTANT]
> This repository builds upon the popular article [NGINX honeypot – the easiest and fastest way to block bots!](https://www.getpagespeed.com/server-setup/security/nginx-honeypot-the-easiest-and-fastest-way-to-block-bots)
> and is compatible with the RHEL-based distributions.

## What is honey?

The unwanted requests which are no good for a well-maintained LEMP stack website.
You [don't host phpMyAdmin](https://www.getpagespeed.com/server-setup/security/stop-installing-phpmyadmin) or other junk on your server.
All these requests come from bots, not from you, and allow early detection and very proactive blocking
in order to reduce server load and logs noise.

Honey is at `honeypot/honey.conf`.

## Install

### From the GetPageSpeed repository (RPM)

On RHEL / CentOS / AlmaLinux / Rocky / Amazon Linux:

```bash
sudo dnf install nginx-honeypot   # yum on EL7
```

The package is **config-only** - it depends on nothing but `nginx`. It drops the honey
list and NGINX snippets into `/etc/nginx/honeypot/` and also ships the optional ban
tooling, which stays dormant unless you opt into the free fcgiwrap path below.

### Manual

Copy the `honeypot` directory to `/etc/nginx/honeypot`. For the free ban path, also
install `libexec/block-ip.cgi` and `sbin/block-ip.sh` (mode 0755).

## Wiring (detection only)

Out of the box the honeypot just **detects** bot-bait requests and returns `410 Gone` -
pure NGINX config, no firewall, no extra packages.

* Auto-load the honey map:

```bash
ln -s /etc/nginx/honeypot/honey.conf /etc/nginx/conf.d/honey.conf
```

* In each `server {}` block:

```nginx
include honeypot/server.conf;
```

That's it. Bots probing `/wp-includes/...`, `/.env`, phpMyAdmin and friends get a 410,
and your logs and app stay quiet.

## Optional: ban the offending IP

To go beyond detection and **ban** the source IP, include ONE of the ban variants in your
`server {}` block *instead of* `server.conf`. Pick the free path or the Pro path.

### Free: fcgiwrap + ipset

```nginx
include honeypot/server-ban-fcgiwrap.conf;
```

A 410 hit is handed to a fcgiwrap CGI that runs `block-ip.sh` (via `sudo`) to add the IP
to the `honeypot4` / `honeypot6` ipsets, so the kernel drops all further packets. One-time
setup:

```bash
# 1. ipsets + DROP rule, wrapped behind firewalld:
sudo /usr/libexec/nginx-honeypot/setup-firewalld.sh
# (raw iptables host with no firewalld? use init-firewall.sh instead.)

# 2. run fcgiwrap as the nginx user (socket: /run/fcgiwrap/fcgiwrap-nginx.sock)
sudo dnf install fcgiwrap ipset conntrack-tools nftables
sudo systemctl enable --now fcgiwrap@nginx.socket
```

`block-ip.sh` auto-detects the active firewall backend (legacy ipset / firewalld /
raw nftables) and dispatches accordingly, so the same script works on EL7-EL10 and on
hand-rolled iptables/nftables hosts. See **Which backend does my distro use?** below.

The CGI needs `sudo` rights for the ban script (the RPM ships this as
`/etc/sudoers.d/nginx-honeypot`):

```
Defaults!/usr/libexec/nginx-honeypot/block-ip.sh env_keep=REMOTE_ADDR
nginx ALL=(ALL) NOPASSWD: /usr/libexec/nginx-honeypot/block-ip.sh
```

Edit `/etc/nginx/honeypot/trusted-ips.conf` to whitelist IPs that must never be banned.

#### Which backend does my distro use?

| Distro                                 | firewalld default  | Recommended setup                     | `block-ip.sh` path           |
|----------------------------------------|--------------------|---------------------------------------|------------------------------|
| RHEL/CentOS/Rocky/Alma 7-9, Amazon 2/2023 | `iptables`     | `setup-firewalld.sh`                  | legacy ipset (~2 ms)         |
| RHEL/Rocky/Alma 10                     | `nftables`         | `setup-firewalld.sh`                  | firewall-cmd (~500 ms)       |
| Fedora 41+                             | `nftables`         | `setup-firewalld.sh`                  | firewall-cmd (~500 ms)       |
| Hand-rolled iptables (no firewalld)    | n/a                | `init-firewall.sh`                    | legacy ipset (~2 ms)         |
| Hand-rolled nftables (no firewalld)    | n/a                | `nft add table; nft add set ...`      | nft direct                   |

On EL10 (and any host where firewalld is on the `nftables` backend), the ipsets created
by `setup-firewalld.sh` live **inside firewalld's own nft table**, not as kernel ipsets -
so `block-ip.sh` routes through `firewall-cmd` to add entries. That path is correct but
~250x slower than the legacy ipset call. For high-traffic EL10 hosts, the **Pro
`nginx-module-nftset-access` path** below bypasses fcgiwrap entirely and is the
recommended production option.

### Pro: kernel-level ban with `nftset-access` (recommended)

```nginx
include honeypot/server-ban-nftset.conf;
```

With the
[`nginx-module-nftset-access`](https://nginx-extras.getpagespeed.com/modules/nftset-access/)
module (GetPageSpeed NGINX Extras, **Pro plan**) the whole fcgiwrap / CGI / `sudo` chain
collapses into a **single directive** - NGINX adds the offending IP straight into an
nftables set and returns 410:

```nginx
location @honeypot {
    nftset_autoadd filter:honeypot timeout=86400 status=410;
}
```

One-time nftables prep (IPv4 shown; mirror with the `ip6` table and `ipv6_addr` type for
IPv6):

```bash
dnf install nginx-module-nftset-access          # Pro plan
nft add table ip filter
nft add set ip filter honeypot '{ type ipv4_addr; flags timeout; }'
nft add chain ip filter input '{ type filter hook input priority 0; }'
nft add rule ip filter input ip saddr @honeypot drop
```

No fcgiwrap, no CGI, no `sudo`, no shell script; the ban is applied in microseconds from
inside NGINX, IPv4/IPv6 is auto-detected, and `timeout` expires bans automatically. The
module needs `CAP_NET_ADMIN` (its `selinux` subpackage grants this automatically) and
NGINX built `--with-compat` (GetPageSpeed NGINX is).

## Contributions

Contributions are welcome! Please open an issue or submit a pull request with your improvements.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE.md) file for details.

## TODO

* More honey
