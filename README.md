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

## Contributions

Contributions are welcome! Please open an issue or submit a pull request with your improvements.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE.md) file for details.

## TODO

* RPM package
* More honey
