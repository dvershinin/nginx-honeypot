# nginx-honeypot

NGINX honeypot with lots of honey for "flies". Honey is at `honeypot/honey.conf`.

## What is honey?

The unwanted requests which are no good for a well-maintained LEMP stack website.
You [don't host phpMyAdmin](https://www.getpagespeed.com/server-setup/security/stop-installing-phpmyadmin) or other junk on your server.
All these requests come from bots, not from you, and allow early detection and very proactive blocking
in order to reduce server load and logs noise.

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

## TODO

* RPM package
* More honey