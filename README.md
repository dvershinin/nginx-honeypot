# nginx-honeypot

## Setup

* Copy the `honeypot` directory as `/etc/nginx/honeypot`

* Ensure `honey.conf` is "auto-loaded":

```bash
ln -s /etc/nginx/honeypot/honey.conf /etc/nginx/conf.d/honey.conf
```

* Configure NGINX `server {}` blocks with:

```nginx
include honeypot/server.conf;
```